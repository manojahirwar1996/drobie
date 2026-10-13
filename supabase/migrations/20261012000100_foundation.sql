-- =============================================================================
-- drobie · 0100 · Foundation
-- Extensions, schemas, ids, shared enums, shared triggers, outbox helper.
-- PLATFORM_ARCHITECTURE §2. Every later migration builds on these.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Extensions (Supabase convention: extension objects live in `extensions`)
-- ---------------------------------------------------------------------------
create schema if not exists extensions;
create extension if not exists pgcrypto  with schema extensions;
create extension if not exists citext    with schema extensions;
create extension if not exists pg_trgm   with schema extensions;
create extension if not exists vector    with schema extensions;
create extension if not exists pgmq;
create extension if not exists pg_cron;

-- ---------------------------------------------------------------------------
-- Schemas by exposure
--   public  : client-facing, every table under RLS
--   private : internals, never exposed through the Data API
--   audit   : append-only audit trail
-- `authenticated` gets USAGE on private only so RLS policies can call the
-- helper functions there; no private table is granted to it.
-- ---------------------------------------------------------------------------
create schema if not exists private;
create schema if not exists audit;

revoke all on schema private from public, anon, authenticated;
revoke all on schema audit   from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;
grant usage on schema audit   to service_role;

-- Functions are executable by PUBLIC by default in Postgres, and a per-schema
-- ALTER DEFAULT PRIVILEGES cannot remove that global default. Revoke it
-- globally for the migration role so every function we create starts locked;
-- EXECUTE is then granted explicitly per function. (0900 also strips the
-- grants Supabase adds to anon/authenticated for functions in `public`.)
alter default privileges revoke execute on functions from public;

-- Tables in public are NOT auto-granted to anon/authenticated (Supabase does
-- this by default). Each table grants exactly what the app needs (0900_grants).
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public  grant all on tables    to service_role;
alter default privileges in schema private grant all on tables    to service_role;
alter default privileges in schema audit   grant all on tables    to service_role;
alter default privileges in schema public  grant all on sequences to service_role;
alter default privileges in schema private grant all on sequences to service_role;

-- ---------------------------------------------------------------------------
-- UUID v7: time-ordered ids (better B-tree locality than v4). Postgres 18 has
-- a native uuidv7(); swap the body for it when the platform upgrades.
-- ---------------------------------------------------------------------------
create or replace function private.uuid_v7()
returns uuid
language sql
volatile
parallel safe
set search_path = ''
as $$
  select encode(
    set_bit(
      set_bit(
        overlay(
          uuid_send(gen_random_uuid())
          placing substring(int8send((extract(epoch from clock_timestamp()) * 1000)::bigint) from 3)
          from 1 for 6
        ),
        52, 1),
      53, 1),
    'hex')::uuid
$$;
comment on function private.uuid_v7() is 'RFC 9562 UUID version 7 (48-bit ms timestamp + random). Default for every primary key.';
grant execute on function private.uuid_v7() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Shared enums. Postgres enums can gain values additively (ALTER TYPE ... ADD
-- VALUE), which fits expand → migrate → contract. Sets that the business may
-- change often are text + CHECK or config instead.
-- ---------------------------------------------------------------------------
create type public.item_state as enum (
  'clean', 'worn', 'in_wash', 'at_dhobi', 'at_tailor', 'lent', 'packed'
);
create type public.item_visibility as enum ('private', 'household', 'friends', 'circle', 'public');
create type public.household_role  as enum ('viewer', 'member', 'adult', 'owner');
create type public.grant_scope     as enum (
  'closet_read', 'item_read', 'item_borrow', 'looks_write', 'places_read', 'measurements_read', 'support_view'
);
create type public.grant_purpose   as enum ('friend', 'family', 'consultation', 'support');
create type public.admin_role      as enum ('super_admin', 'admin', 'moderator', 'support', 'analyst', 'finance');
create type public.media_status    as enum ('pending', 'ready', 'quarantined', 'deleted');
create type public.sensitivity     as enum ('public', 'personal', 'sensitive');
create type public.feature_type    as enum ('flag', 'limit', 'quota');
create type public.quota_period    as enum ('day', 'month');

-- ---------------------------------------------------------------------------
-- Domain checks reused across tables
-- ---------------------------------------------------------------------------
create domain public.currency_code as char(3)
  check (value ~ '^[A-Z]{3}$');
comment on domain public.currency_code is 'ISO 4217 code, or CRD for drobie credits (non-money unit).';

create domain public.country_code as char(2)
  check (value ~ '^[A-Z]{2}$');

-- ---------------------------------------------------------------------------
-- Shared triggers
-- ---------------------------------------------------------------------------
create or replace function private.tg_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Columns named in TG_ARGV can never change after insert (owner columns, ids).
-- The service role may change them only inside an explicit maintenance session
-- that sets drobie.allow_owner_change = 'on' (account merges, support fixes).
create or replace function private.tg_immutable_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  col text;
  old_v text;
  new_v text;
begin
  if coalesce(current_setting('drobie.allow_owner_change', true), '') = 'on'
     and current_user in ('postgres', 'service_role', 'supabase_admin') then
    return new;
  end if;
  foreach col in array tg_argv loop
    execute format('select ($1).%1$I::text, ($2).%1$I::text', col)
      into old_v, new_v using old, new;
    if old_v is distinct from new_v then
      raise exception 'column %.% is immutable', tg_table_name, col
        using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;

-- Append-only tables: block UPDATE and DELETE outright.
create or replace function private.tg_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end $$;

-- ---------------------------------------------------------------------------
-- Outbox: private.domain_events (partitioned monthly) + private.emit().
-- Partition helpers are defined here because several migrations use them.
-- ---------------------------------------------------------------------------
create or replace function private.ensure_monthly_partitions(
  p_table regclass,
  p_months_ahead int default 3,
  p_from date default date_trunc('month', now())::date
)
returns int
language plpgsql
set search_path = ''
as $$
declare
  parent_schema text;
  parent_name text;
  m date;
  part_name text;
  created int := 0;
begin
  select n.nspname, c.relname into parent_schema, parent_name
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where c.oid = p_table;

  for i in 0 .. p_months_ahead loop
    m := (date_trunc('month', p_from) + make_interval(months => i))::date;
    part_name := format('%s_p%s', parent_name, to_char(m, 'YYYYMM'));
    if not exists (
      select 1 from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = parent_schema and c.relname = part_name
    ) then
      execute format(
        'create table %I.%I partition of %I.%I for values from (%L) to (%L)',
        parent_schema, part_name, parent_schema, parent_name,
        m, (m + interval '1 month')::date
      );
      created := created + 1;
    end if;
  end loop;

  part_name := parent_name || '_default';
  if not exists (
    select 1 from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = parent_schema and c.relname = part_name
  ) then
    execute format('create table %I.%I partition of %I.%I default',
      parent_schema, part_name, parent_schema, parent_name);
  end if;
  return created;
end $$;
comment on function private.ensure_monthly_partitions is
  'Creates monthly range partitions (current month + N ahead) and a default partition. Run monthly by pg_cron; the default partition should stay empty (monitored).';

-- Drops whole monthly partitions older than the retention window (no big DELETEs).
create or replace function private.drop_old_partitions(p_table regclass, p_keep_months int)
returns int
language plpgsql
set search_path = ''
as $$
declare
  r record;
  cutoff date := (date_trunc('month', now()) - make_interval(months => p_keep_months))::date;
  dropped int := 0;
begin
  for r in
    select n.nspname as s, c.relname as t
    from pg_catalog.pg_inherits i
    join pg_catalog.pg_class c on c.oid = i.inhrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where i.inhparent = p_table
      and c.relname ~ '_p[0-9]{6}$'
      and to_date(right(c.relname, 6), 'YYYYMM') < cutoff
  loop
    execute format('drop table %I.%I', r.s, r.t);
    dropped := dropped + 1;
  end loop;
  return dropped;
end $$;

create table private.domain_events (
  id            uuid not null default private.uuid_v7(),
  occurred_at   timestamptz not null default now(),
  type          text not null check (type ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  aggregate     text not null,
  aggregate_id  uuid,
  actor_user_id uuid,
  payload       jsonb not null default '{}'::jsonb,
  dispatched_at timestamptz,
  primary key (id, occurred_at)
) partition by range (occurred_at);
comment on table private.domain_events is
  'Transactional outbox. Written in the same transaction as the change; a dispatcher moves rows to pgmq queues by topic.';

select private.ensure_monthly_partitions('private.domain_events', 3);
create index domain_events_undispatched_idx on private.domain_events (occurred_at) where dispatched_at is null;
create index domain_events_aggregate_idx on private.domain_events (aggregate, aggregate_id, occurred_at);

create or replace function private.emit(
  p_type text,
  p_aggregate text,
  p_aggregate_id uuid,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into private.domain_events (type, aggregate, aggregate_id, actor_user_id, payload)
  values (p_type, p_aggregate, p_aggregate_id, auth.uid(), coalesce(p_payload, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;
comment on function private.emit is 'Insert a domain event into the outbox (same transaction as the caller).';
grant execute on function private.emit(text, text, uuid, jsonb) to service_role;

-- Topic routing: event type prefix → pgmq queue. Data, not code.
create table private.event_routes (
  type_prefix text not null,
  queue       text not null,
  active      boolean not null default true,
  primary key (type_prefix, queue)
);

select pgmq.create('notifications');
select pgmq.create('embeddings');
select pgmq.create('search');
select pgmq.create('analytics');

insert into private.event_routes (type_prefix, queue) values
  ('item.', 'search'),
  ('item.', 'analytics'),
  ('media.', 'embeddings'),
  ('reminder.', 'notifications'),
  ('notification.', 'notifications'),
  ('account.', 'analytics'),
  ('subscription.', 'analytics'),
  ('subscription.', 'notifications'),
  ('ledger.', 'analytics');

create or replace function private.dispatch_events(p_batch int default 500)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  q record;
  n int := 0;
begin
  for r in
    select id, occurred_at, type, aggregate, aggregate_id, actor_user_id, payload
    from private.domain_events
    where dispatched_at is null
    order by occurred_at
    limit p_batch
    for update skip locked
  loop
    for q in
      select distinct er.queue from private.event_routes er
      where er.active and r.type like er.type_prefix || '%'
    loop
      perform pgmq.send(q.queue, jsonb_build_object(
        'event_id', r.id, 'type', r.type, 'aggregate', r.aggregate,
        'aggregate_id', r.aggregate_id, 'actor_user_id', r.actor_user_id,
        'occurred_at', r.occurred_at, 'payload', r.payload));
    end loop;
    update private.domain_events set dispatched_at = now()
    where id = r.id and occurred_at = r.occurred_at;
    n := n + 1;
  end loop;
  return n;
end $$;
