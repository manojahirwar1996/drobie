-- =============================================================================
-- drobie · 0700 · Notifications, versioned config, audit, ops internals, jobs
-- PLATFORM_ARCHITECTURE §3.13, §3.14, §5, §6, §8
-- =============================================================================

-- ---------------------------------------------------------------------------
-- audit.log: append-only, partitioned monthly
-- ---------------------------------------------------------------------------
create table audit.log (
  id            uuid not null default private.uuid_v7(),
  occurred_at   timestamptz not null default now(),
  actor_user_id uuid,
  actor_db_role text not null default current_user,
  action        text not null,
  table_name    text,
  record_id     text,
  before        jsonb,
  after         jsonb,
  reason        text,
  request_id    text,
  primary key (id, occurred_at)
) partition by range (occurred_at);
comment on table audit.log is 'Every staff action and every sensitive change. Append-only. Kept at least 24 months.';
select private.ensure_monthly_partitions('audit.log', 3);
create index audit_log_actor_idx on audit.log (actor_user_id, occurred_at desc);
create index audit_log_record_idx on audit.log (table_name, record_id, occurred_at desc);

create trigger audit_log_append_only before update or delete on audit.log
  for each row execute function private.tg_append_only();

create or replace function audit.record(
  p_action text, p_table text, p_record_id text, p_before jsonb, p_after jsonb, p_reason text default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into audit.log (actor_user_id, action, table_name, record_id, before, after, reason, request_id)
  values (auth.uid(), p_action, p_table, p_record_id, p_before, p_after,
          coalesce(p_reason, nullif(current_setting('drobie.audit_reason', true), '')),
          nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-request-id')
$$;

-- Generic row-change capture. TG_ARGV[0] = 'redact' stores only changed keys.
create or replace function audit.tg_capture()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_after  jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_id     text  := coalesce(v_after ->> 'id', v_before ->> 'id', v_after ->> 'user_id', v_before ->> 'user_id');
begin
  if coalesce(tg_argv[0], '') = 'redact' then
    v_before := case when v_before is null then null else jsonb_build_object('redacted', true) end;
    v_after  := case when v_after  is null then null else jsonb_build_object('redacted', true) end;
  end if;
  perform audit.record(lower(tg_op), tg_table_schema || '.' || tg_table_name, v_id, v_before, v_after);
  return null;
end $$;

-- ---------------------------------------------------------------------------
-- notifications (in-app inbox; push is a delivery channel). Partitioned.
-- ---------------------------------------------------------------------------
create table public.notifications (
  id         uuid not null default private.uuid_v7(),
  created_at timestamptz not null default now(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  type       text not null check (type ~ '^[a-z][a-z0-9_.]*$'),
  title      text not null check (char_length(title) <= 120),
  body       text check (char_length(body) <= 500),
  payload    jsonb not null default '{}'::jsonb,
  deliveries jsonb not null default '{}'::jsonb,   -- {"push": "sent", "email": "skipped"}
  read_at    timestamptz,
  primary key (id, created_at)
) partition by range (created_at);
select private.ensure_monthly_partitions('public.notifications', 3);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_unread_idx on public.notifications (user_id, created_at desc) where read_at is null;

create table public.notification_preferences (
  user_id           uuid not null references public.profiles (id) on delete cascade,
  channel           text not null check (channel in ('push', 'email', 'in_app')),
  notification_type text not null default '*',
  enabled           boolean not null default true,
  quiet_start       time,
  quiet_end         time,
  updated_at        timestamptz not null default now(),
  primary key (user_id, channel, notification_type),
  check ((quiet_start is null) = (quiet_end is null))
);
create trigger notification_preferences_updated_at before update on public.notification_preferences
  for each row execute function private.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- Versioned config (PLATFORM_ARCHITECTURE §8.2). One generic store serves
-- app_config, feature flags, copy, message templates, UI layouts, rule sets,
-- AI prompts and routes, notification types, blocklists and limits, so draft
-- → approve → publish → rollback works the same everywhere (DECISIONS D-007).
-- ---------------------------------------------------------------------------
create table public.config_keys (
  namespace         text not null check (namespace in (
                      'app', 'flag', 'copy', 'message_template', 'ui_layout', 'rule_set',
                      'ai_prompt', 'ai_route', 'notification_type', 'blocklist', 'limit', 'retailer_rule')),
  key               text not null check (key ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$'),
  description       text not null,
  value_schema      jsonb not null check (jsonb_typeof(value_schema) = 'object'),
  default_value     jsonb not null,
  owner             text not null,
  requires_approval boolean not null default false,  -- four-eyes: prices, payouts, AI budgets, kill switches
  client_visible    boolean not null default false,  -- included in the app config bundle
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (namespace, key)
);
create trigger config_keys_updated_at before update on public.config_keys
  for each row execute function private.tg_set_updated_at();

create or replace function private.tg_config_keys_validate()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_errors text[] := private.jsonschema_errors(new.value_schema, new.default_value);
begin
  if cardinality(v_errors) > 0 then
    raise exception 'default for %.% is invalid: %', new.namespace, new.key, array_to_string(v_errors, '; ')
      using errcode = '23514';
  end if;
  return new;
end $$;
create trigger config_keys_validate before insert or update on public.config_keys
  for each row execute function private.tg_config_keys_validate();

create table public.config_versions (
  id          uuid primary key default private.uuid_v7(),
  namespace   text not null,
  key         text not null,
  locale      text not null default '*' check (locale = '*' or locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  version     int not null,
  status      text not null default 'draft' check (status in ('draft', 'scheduled', 'live', 'archived')),
  value       jsonb not null,
  targeting   jsonb not null default '[]'::jsonb check (jsonb_typeof(targeting) = 'array'),
  starts_at   timestamptz,
  ends_at     timestamptz,
  author_id   uuid references public.profiles (id) on delete set null,
  approved_by uuid references public.profiles (id) on delete set null,
  approved_at timestamptz,
  reason      text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  foreign key (namespace, key) references public.config_keys (namespace, key) on delete cascade,
  unique (namespace, key, locale, version),
  check (ends_at is null or starts_at is null or ends_at > starts_at),
  check (status <> 'scheduled' or starts_at is not null),
  check (approved_by is null or approved_by is distinct from author_id)
);
create unique index config_versions_one_live on public.config_versions (namespace, key, locale) where status = 'live';
create index config_versions_scheduled_idx on public.config_versions (starts_at) where status = 'scheduled';
create index config_versions_author_idx on public.config_versions (author_id);
create index config_versions_approved_by_idx on public.config_versions (approved_by);
create trigger config_versions_updated_at before update on public.config_versions
  for each row execute function private.tg_set_updated_at();

create table private.config_state (
  id         boolean primary key default true check (id),
  version    bigint not null default 1,
  updated_at timestamptz not null default now()
);
insert into private.config_state default values;

create or replace function private.tg_config_versions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_schema jsonb;
  v_errors text[];
begin
  if tg_op = 'INSERT' then
    select coalesce(max(version), 0) + 1 into new.version from public.config_versions
    where namespace = new.namespace and key = new.key and locale = new.locale;
    if new.status not in ('draft') then
      raise exception 'new config versions start as draft' using errcode = '23514';
    end if;
  else
    if old.status <> 'draft' and (new.value is distinct from old.value or new.targeting is distinct from old.targeting
                                  or new.locale is distinct from old.locale or new.key is distinct from old.key) then
      raise exception 'only drafts can be edited; create a new version instead' using errcode = '42501';
    end if;
    if new.value is distinct from old.value then
      new.approved_by := null;
      new.approved_at := null;
    end if;
  end if;
  select value_schema into v_schema from public.config_keys where namespace = new.namespace and key = new.key;
  v_errors := private.jsonschema_errors(v_schema, new.value);
  if cardinality(v_errors) > 0 then
    raise exception 'config %.% value is invalid: %', new.namespace, new.key, array_to_string(v_errors, '; ')
      using errcode = '23514';
  end if;
  return new;
end $$;
create trigger config_versions_guard before insert or update on public.config_versions
  for each row execute function private.tg_config_versions_guard();

create or replace function private.config_approve(p_version_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v record;
begin
  select * into v from public.config_versions where id = p_version_id for update;
  if not found then
    raise exception 'config version not found' using errcode = '22023';
  end if;
  if auth.uid() is null or not private.has_admin_role('admin') then
    raise exception 'only an admin with MFA can approve config' using errcode = '42501';
  end if;
  if v.author_id = auth.uid() then
    raise exception 'the author cannot approve their own change (four-eyes rule)' using errcode = '42501';
  end if;
  update public.config_versions set approved_by = auth.uid(), approved_at = now() where id = p_version_id;
end $$;

-- Publish now (draft/archived → live) or schedule (draft → scheduled when
-- starts_at is in the future). Rollback = publish an archived version again.
create or replace function private.config_publish(p_version_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v record;
  k record;
begin
  select * into v from public.config_versions where id = p_version_id for update;
  if not found then
    raise exception 'config version not found' using errcode = '22023';
  end if;
  if auth.uid() is not null and not private.has_admin_role('admin') then
    raise exception 'only an admin with MFA can publish config' using errcode = '42501';
  end if;
  select * into k from public.config_keys where namespace = v.namespace and key = v.key;
  if k.requires_approval and v.approved_by is null then
    raise exception 'config %.% needs a second admin''s approval before publishing', v.namespace, v.key
      using errcode = '42501';
  end if;
  perform set_config('drobie.audit_reason', coalesce(p_reason, v.reason, ''), true);

  if v.starts_at is not null and v.starts_at > now() then
    update public.config_versions set status = 'scheduled' where id = v.id;
  else
    update public.config_versions set status = 'archived'
    where namespace = v.namespace and key = v.key and locale = v.locale and status = 'live' and id <> v.id;
    update public.config_versions set status = 'live' where id = v.id;
  end if;
  update private.config_state set version = version + 1, updated_at = now();
  perform private.emit('config.published', 'config_version', v.id,
                       jsonb_build_object('namespace', v.namespace, 'key', v.key, 'version', v.version));
end $$;

create or replace function private.config_rollback(p_namespace text, p_key text, p_locale text default '*', p_reason text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev uuid;
begin
  select id into v_prev from public.config_versions
  where namespace = p_namespace and key = p_key and locale = p_locale and status = 'archived'
  order by version desc limit 1;
  if v_prev is null then
    raise exception 'no earlier version to roll back to' using errcode = '22023';
  end if;
  perform private.config_publish(v_prev, coalesce(p_reason, 'rollback'));
  return v_prev;
end $$;

-- Value in force now: an active scheduled window beats live; then default.
create or replace function private.config_value(p_namespace text, p_key text, p_locale text default '*')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select cv.value from public.config_versions cv
      where cv.namespace = p_namespace and cv.key = p_key and cv.locale in (p_locale, '*')
        and cv.status in ('live', 'scheduled')
        and (cv.starts_at is null or cv.starts_at <= now())
        and (cv.ends_at is null or cv.ends_at > now())
      order by (cv.locale = p_locale) desc, (cv.status = 'scheduled') desc, cv.version desc
      limit 1),
    (select ck.default_value from public.config_keys ck where ck.namespace = p_namespace and ck.key = p_key)
  )
$$;

-- Client bundle (served by the config-bundle function with an ETag = version).
create or replace function private.config_bundle(p_locale text default 'en-IN')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'version', (select version from private.config_state),
    'locale', p_locale,
    'values', coalesce(jsonb_object_agg(ck.namespace || ':' || ck.key, jsonb_build_object(
        'value', private.config_value(ck.namespace, ck.key, p_locale),
        'targeting', coalesce((
          select cv.targeting from public.config_versions cv
          where cv.namespace = ck.namespace and cv.key = ck.key and cv.locale in (p_locale, '*')
            and cv.status = 'live' order by (cv.locale = p_locale) desc limit 1), '[]'::jsonb))),
      '{}'::jsonb))
  from public.config_keys ck
  where ck.client_visible
$$;

-- Readable names for the config areas in §8.1 (server-side use only).
create view private.app_config as
  select key, private.config_value('app', key) as value from public.config_keys where namespace = 'app';
create view private.feature_flags as
  select key, private.config_value('flag', key) as value from public.config_keys where namespace = 'flag';

-- Scheduled versions whose window has ended fall back automatically (they
-- stop matching in config_value); this job tidies them to archived.
create or replace function private.config_tick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.config_versions set status = 'archived'
  where status = 'scheduled' and ends_at is not null and ends_at <= now();
  update private.config_state set version = version + 1, updated_at = now()
  where exists (select 1 from public.config_versions
                where status = 'scheduled' and starts_at between now() - interval '1 minute' and now());
end $$;

-- ---------------------------------------------------------------------------
-- Ops internals (private)
-- ---------------------------------------------------------------------------
create table private.webhook_events (
  id           uuid primary key default private.uuid_v7(),
  provider     text not null check (provider in ('revenuecat', 'razorpay', 'play', 'app_store', 'resend', 'email_worker')),
  event_id     text not null,
  event_type   text,
  payload      jsonb not null,
  signature_ok boolean not null,
  status       text not null default 'received' check (status in ('received', 'processed', 'failed', 'ignored')),
  attempts     int not null default 0,
  error        text,
  received_at  timestamptz not null default now(),
  processed_at timestamptz,
  unique (provider, event_id)
);
create index webhook_events_status_idx on private.webhook_events (status, received_at) where status in ('received', 'failed');

create table private.idempotency_keys (
  user_id         uuid not null,
  key             text not null check (char_length(key) between 8 and 128),
  endpoint        text not null,
  request_hash    text not null,
  status          text not null default 'in_progress' check (status in ('in_progress', 'completed')),
  response_status int,
  response        jsonb,
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null default now() + interval '24 hours',
  primary key (user_id, key)
);
create index idempotency_keys_expires_idx on private.idempotency_keys (expires_at);

create table private.rate_limits (
  bucket     text primary key,
  tokens     numeric not null,
  updated_at timestamptz not null default now()
);

-- Token bucket: true if `cost` tokens were taken. Atomic per bucket.
create or replace function private.rate_limit_take(
  p_bucket text, p_capacity numeric, p_refill_per_sec numeric, p_cost numeric default 1
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tokens numeric;
begin
  insert into private.rate_limits as rl (bucket, tokens, updated_at)
  values (p_bucket, p_capacity, now())
  on conflict (bucket) do update
     set tokens = least(p_capacity,
                        rl.tokens + extract(epoch from (now() - rl.updated_at)) * p_refill_per_sec),
         updated_at = now()
  returning tokens into v_tokens;
  if v_tokens < p_cost then
    return false;
  end if;
  update private.rate_limits set tokens = tokens - p_cost where bucket = p_bucket;
  return true;
end $$;

create table private.ai_usage (
  id                 uuid not null default private.uuid_v7(),
  occurred_at        timestamptz not null default now(),
  user_id            uuid,
  feature            text not null,
  step               text not null check (step in ('rules', 'cache', 'device', 'template', 'embedder', 'ai')),
  provider           text,
  model              text,
  input_tokens       int not null default 0 check (input_tokens >= 0),
  output_tokens      int not null default 0 check (output_tokens >= 0),
  cache_read_tokens  int not null default 0 check (cache_read_tokens >= 0),
  cache_write_tokens int not null default 0 check (cache_write_tokens >= 0),
  images             int not null default 0 check (images >= 0),
  cost_minor         bigint not null default 0 check (cost_minor >= 0),   -- paise (INR)
  currency           public.currency_code not null default 'INR',
  latency_ms         int,
  ok                 boolean not null default true,
  request_id         text,
  primary key (id, occurred_at)
) partition by range (occurred_at);
select private.ensure_monthly_partitions('private.ai_usage', 3);
create index ai_usage_user_idx on private.ai_usage (user_id, occurred_at desc);
create index ai_usage_feature_idx on private.ai_usage (feature, step, occurred_at desc);

-- Today's paid AI spend (user's local day) for budget checks in ai-provider.
create or replace function private.ai_spend_today(p_user uuid default null)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(cost_minor), 0)::bigint from private.ai_usage
  where step = 'ai'
    and occurred_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'
    and (p_user is null or user_id = p_user)
$$;

-- ---------------------------------------------------------------------------
-- DPDP data rights
-- ---------------------------------------------------------------------------
create table public.deletion_requests (
  id           uuid primary key default private.uuid_v7(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'cancelled', 'purging', 'completed')),
  reason       text,
  requested_at timestamptz not null default now(),
  purge_after  timestamptz not null default now() + interval '30 days',
  completed_at timestamptz,
  updated_at   timestamptz not null default now()
);
create unique index deletion_requests_one_open on public.deletion_requests (user_id) where status in ('pending', 'purging');
create index deletion_requests_due_idx on public.deletion_requests (purge_after) where status = 'pending';
create trigger deletion_requests_updated_at before update on public.deletion_requests
  for each row execute function private.tg_set_updated_at();

create table public.data_exports (
  id             uuid primary key default private.uuid_v7(),
  user_id        uuid not null references public.profiles (id) on delete cascade,
  status         text not null default 'queued' check (status in ('queued', 'building', 'ready', 'expired', 'failed')),
  media_asset_id uuid references public.media_assets (id) on delete set null,
  requested_at   timestamptz not null default now(),
  ready_at       timestamptz,
  expires_at     timestamptz,
  updated_at     timestamptz not null default now()
);
create index data_exports_user_idx on public.data_exports (user_id, requested_at desc);
create index data_exports_media_idx on public.data_exports (media_asset_id);
create trigger data_exports_updated_at before update on public.data_exports
  for each row execute function private.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- Dictionary for voice and search
-- ---------------------------------------------------------------------------
create table public.synonyms (
  id            uuid primary key default private.uuid_v7(),
  term          text not null check (char_length(term) between 1 and 60),
  lang          text not null check (lang in ('en', 'hi', 'hinglish')),
  maps_to_type  text not null check (maps_to_type in
                  ('category', 'colour', 'place', 'state', 'occasion', 'season', 'action', 'pattern', 'fabric', 'brand')),
  maps_to_value text not null,
  weight        numeric(3,2) not null default 1 check (weight between 0 and 1),
  source        text not null default 'seed' check (source in ('seed', 'admin', 'learned')),
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index synonyms_unique on public.synonyms (lower(term), lang, maps_to_type, maps_to_value);
create index synonyms_term_trgm on public.synonyms using gin (lower(term) extensions.gin_trgm_ops);
create trigger synonyms_updated_at before update on public.synonyms
  for each row execute function private.tg_set_updated_at();

create table private.unmapped_terms (
  term       text primary key,
  count      int not null default 1,
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now(),
  resolved   boolean not null default false
);

create or replace function private.log_unmapped_term(p_term text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.unmapped_terms (term) values (lower(trim(p_term)))
  on conflict (term) do update set count = private.unmapped_terms.count + 1, last_seen = now()
$$;

-- ---------------------------------------------------------------------------
-- Audit capture on sensitive and staff-managed tables
-- ---------------------------------------------------------------------------
create trigger audit_plans          after insert or update or delete on public.plans          for each row execute function audit.tg_capture();
create trigger audit_plan_prices    after insert or update or delete on public.plan_prices    for each row execute function audit.tg_capture();
create trigger audit_features       after insert or update or delete on public.features       for each row execute function audit.tg_capture();
create trigger audit_plan_features  after insert or update or delete on public.plan_features  for each row execute function audit.tg_capture();
create trigger audit_entitlements   after insert or update or delete on public.entitlement_grants for each row execute function audit.tg_capture();
create trigger audit_admin_users    after insert or update or delete on public.admin_users    for each row execute function audit.tg_capture();
create trigger audit_access_grants  after insert or update or delete on public.access_grants  for each row execute function audit.tg_capture();
create trigger audit_categories     after insert or update or delete on public.categories     for each row execute function audit.tg_capture();
create trigger audit_config_keys    after insert or update or delete on public.config_keys    for each row execute function audit.tg_capture();
create trigger audit_config_versions after insert or update or delete on public.config_versions for each row execute function audit.tg_capture();
create trigger audit_offers         after insert or update or delete on public.offers         for each row execute function audit.tg_capture();
create trigger audit_promo_codes    after insert or update or delete on public.promo_codes    for each row execute function audit.tg_capture();
create trigger audit_experiments    after insert or update or delete on public.experiments    for each row execute function audit.tg_capture();
create trigger audit_tax_rates      after insert or update or delete on public.tax_rates      for each row execute function audit.tg_capture();
create trigger audit_countries      after insert or update or delete on public.countries      for each row execute function audit.tg_capture();
create trigger audit_retailers      after insert or update or delete on public.retailers      for each row execute function audit.tg_capture();
create trigger audit_profile_status after update on public.profiles
  for each row when (old.status is distinct from new.status) execute function audit.tg_capture();
create trigger audit_body_profiles  after insert or update or delete on public.body_profiles
  for each row execute function audit.tg_capture('redact');

-- ---------------------------------------------------------------------------
-- Scheduled jobs (pg_cron). Idempotent by job name.
-- ---------------------------------------------------------------------------
create or replace function private.maintain_partitions()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.ensure_monthly_partitions('private.domain_events', 3);
  perform private.ensure_monthly_partitions('audit.log', 3);
  perform private.ensure_monthly_partitions('private.ai_usage', 3);
  perform private.ensure_monthly_partitions('public.notifications', 3);
  -- retention by dropping whole months
  perform private.drop_old_partitions('private.domain_events', 3);
  perform private.drop_old_partitions('public.notifications', 3);   -- SRS §7: 90 days
  perform private.drop_old_partitions('private.ai_usage', 13);
  perform private.drop_old_partitions('audit.log', 24);
end $$;

create or replace function private.cleanup_ephemeral()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.idempotency_keys where expires_at < now();
  delete from private.webhook_events where received_at < now() - interval '180 days' and status in ('processed', 'ignored');
  delete from private.rate_limits where updated_at < now() - interval '1 day';
$$;

select cron.schedule('drobie-dispatch-events', '10 seconds', $$select private.dispatch_events(1000)$$);
select cron.schedule('drobie-config-tick', '* * * * *', $$select private.config_tick()$$);
select cron.schedule('drobie-partitions', '15 2 1,15 * *', $$select private.maintain_partitions()$$);
select cron.schedule('drobie-cleanup', '40 3 * * *', $$select private.cleanup_ephemeral()$$);

grant execute on function
  private.config_value(text, text, text),
  private.config_bundle(text),
  private.config_publish(uuid, text),
  private.config_rollback(text, text, text, text),
  private.config_approve(uuid),
  private.rate_limit_take(text, numeric, numeric, numeric),
  private.ai_spend_today(uuid),
  private.log_unmapped_term(text),
  private.dispatch_events(int),
  audit.record(text, text, text, jsonb, jsonb, text)
to service_role;
-- Admins call approve/publish with their own JWT (role + MFA checked inside).
grant execute on function private.config_approve(uuid), private.config_publish(uuid, text),
  private.config_rollback(text, text, text, text) to authenticated;
