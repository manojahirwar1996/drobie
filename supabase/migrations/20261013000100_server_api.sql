-- =============================================================================
-- drobie · 1000 · Server API schema for Edge Functions
-- `private` is never exposed by the Data API, so Edge Functions reach the
-- internal functions through thin wrappers in `server`. The schema is exposed
-- to PostgREST (supabase/config.toml), but ONLY service_role may use it:
-- anon/authenticated get no USAGE and no EXECUTE (tested in 08_server_api).
-- =============================================================================

create schema if not exists server;
revoke all on schema server from public, anon, authenticated;
grant usage on schema server to service_role;

-- ---------------------------------------------------------------------------
-- Account state (auth middleware)
-- ---------------------------------------------------------------------------
create or replace function server.account_state(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select jsonb_build_object(
       'exists', true,
       'status', p.status,
       'adult_confirmed', p.adult_confirmed_at is not null,
       'deleted', p.deleted_at is not null,
       'country', p.country,
       'locale', p.locale,
       'timezone', p.timezone,
       'plan', private.effective_plan(p.id))
     from public.profiles p where p.id = p_user),
    jsonb_build_object('exists', false))
$$;

create or replace function server.admin_roles(p_user uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(role::text order by role), '{}') from public.admin_users where user_id = p_user and active
$$;

-- ---------------------------------------------------------------------------
-- Entitlements and quotas
-- ---------------------------------------------------------------------------
create or replace function server.entitlement(p_user uuid, p_feature_key text)
returns jsonb language sql stable security definer set search_path = ''
as $$ select private.entitlement(p_user, p_feature_key) $$;

create or replace function server.entitlements(p_user uuid)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'plan', private.effective_plan(p_user),
    'features', coalesce(jsonb_object_agg(ef.feature_key, jsonb_build_object(
      'type', ef.feature_type, 'period', ef.period, 'enabled', ef.enabled, 'limit', ef.limit_value)), '{}'::jsonb))
  from private.effective_features(p_user) ef
$$;

create or replace function server.consume_quota(p_user uuid, p_feature_key text, p_amount bigint default 1)
returns jsonb language sql volatile security definer set search_path = ''
as $$ select private.consume_quota(p_user, p_feature_key, p_amount) $$;

create or replace function server.release_quota(p_user uuid, p_feature_key text, p_amount bigint default 1)
returns void language sql volatile security definer set search_path = ''
as $$ select private.release_quota(p_user, p_feature_key, p_amount) $$;

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------
create or replace function server.config_version()
returns bigint language sql stable security definer set search_path = ''
as $$ select version from private.config_state $$;

create or replace function server.config_bundle(p_locale text default 'en-IN')
returns jsonb language sql stable security definer set search_path = ''
as $$ select private.config_bundle(p_locale) $$;

-- Every key (server-side cache in _shared/config.ts), not only client-visible ones.
create or replace function server.config_snapshot(p_locale text default 'en-IN')
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'version', (select version from private.config_state),
    'values', coalesce(jsonb_object_agg(ck.namespace || ':' || ck.key, jsonb_build_object(
        'value', private.config_value(ck.namespace, ck.key, p_locale),
        'targeting', coalesce((
          select cv.targeting from public.config_versions cv
          where cv.namespace = ck.namespace and cv.key = ck.key and cv.locale in (p_locale, '*')
            and cv.status = 'live' order by (cv.locale = p_locale) desc limit 1), '[]'::jsonb),
        'client_visible', ck.client_visible)),
      '{}'::jsonb))
  from public.config_keys ck
$$;

-- ---------------------------------------------------------------------------
-- Consents (versions must match the texts currently in force)
-- ---------------------------------------------------------------------------
create or replace function server.set_consents(p_user uuid, p_consents jsonb, p_source text default 'app')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_current jsonb := private.config_value('app', 'consent_versions');
  c jsonb;
  v_changed int := 0;
  v_prev boolean;
begin
  if p_source not in ('app', 'web') then
    raise exception 'invalid consent source' using errcode = '22023';
  end if;
  if jsonb_typeof(p_consents) <> 'array' or jsonb_array_length(p_consents) = 0 then
    raise exception 'no consents given' using errcode = '22023';
  end if;
  for c in select * from jsonb_array_elements(p_consents) loop
    if v_current ? (c ->> 'consent_type') and (v_current ->> (c ->> 'consent_type')) <> (c ->> 'version') then
      raise exception 'consent % version % is not the current version %',
        c ->> 'consent_type', c ->> 'version', v_current ->> (c ->> 'consent_type')
        using errcode = '22023', hint = 'stale_consent_version';
    end if;
    v_prev := private.has_consent(p_user, c ->> 'consent_type');
    insert into public.consents (user_id, consent_type, version, granted, source)
    values (p_user, c ->> 'consent_type', c ->> 'version', (c ->> 'granted')::boolean, p_source);
    if v_prev is distinct from (c ->> 'granted')::boolean then
      v_changed := v_changed + 1;
      -- DPDP: withdrawing the measurements consent deletes the measurements
      if c ->> 'consent_type' = 'measurements' and not (c ->> 'granted')::boolean then
        delete from public.body_profiles where user_id = p_user;
      end if;
      perform private.emit('account.consent_changed', 'profile', p_user,
        jsonb_build_object('consent_type', c ->> 'consent_type', 'granted', (c ->> 'granted')::boolean));
    end if;
  end loop;
  return jsonb_build_object('recorded', jsonb_array_length(p_consents), 'changed', v_changed);
end $$;

create or replace function server.current_consents(p_user uuid)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_object_agg(t.consent_type, jsonb_build_object('granted', t.granted, 'version', t.version,
                                                                      'recorded_at', t.recorded_at)), '{}'::jsonb)
  from (select distinct on (consent_type) consent_type, granted, version, recorded_at
        from public.consents where user_id = p_user order by consent_type, recorded_at desc, id desc) t
$$;

-- ---------------------------------------------------------------------------
-- Rate limits, idempotency, webhooks
-- ---------------------------------------------------------------------------
create or replace function server.rate_limit_take(p_bucket text, p_capacity numeric, p_refill_per_sec numeric, p_cost numeric default 1)
returns boolean language sql volatile security definer set search_path = ''
as $$ select private.rate_limit_take(p_bucket, p_capacity, p_refill_per_sec, p_cost) $$;

-- Begin an idempotent request. Returns state:
--   new          → caller proceeds, then calls idempotency_complete
--   in_progress  → a concurrent duplicate; caller answers 409
--   completed    → replay the stored response
--   mismatch     → same key, different body; caller answers 422
create or replace function server.idempotency_begin(p_user uuid, p_key text, p_endpoint text, p_request_hash text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r record;
begin
  delete from private.idempotency_keys where user_id = p_user and key = p_key and expires_at < now();
  insert into private.idempotency_keys (user_id, key, endpoint, request_hash)
  values (p_user, p_key, p_endpoint, p_request_hash)
  on conflict (user_id, key) do nothing;
  if found then
    return jsonb_build_object('state', 'new');
  end if;
  select * into r from private.idempotency_keys where user_id = p_user and key = p_key;
  if r.endpoint <> p_endpoint or r.request_hash <> p_request_hash then
    return jsonb_build_object('state', 'mismatch');
  end if;
  if r.status = 'completed' then
    return jsonb_build_object('state', 'completed', 'response_status', r.response_status, 'response', r.response);
  end if;
  return jsonb_build_object('state', 'in_progress');
end $$;

create or replace function server.idempotency_complete(p_user uuid, p_key text, p_status int, p_response jsonb)
returns void language sql volatile security definer set search_path = ''
as $$
  update private.idempotency_keys set status = 'completed', response_status = p_status, response = p_response
  where user_id = p_user and key = p_key
$$;

-- A failed request releases its key so the client can retry.
create or replace function server.idempotency_release(p_user uuid, p_key text)
returns void language sql volatile security definer set search_path = ''
as $$ delete from private.idempotency_keys where user_id = p_user and key = p_key and status = 'in_progress' $$;

create or replace function server.webhook_receive(
  p_provider text, p_event_id text, p_event_type text, p_payload jsonb, p_signature_ok boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_status text;
begin
  insert into private.webhook_events (provider, event_id, event_type, payload, signature_ok,
                                      status)
  values (p_provider, p_event_id, p_event_type, p_payload, p_signature_ok,
          case when p_signature_ok then 'received' else 'ignored' end)
  on conflict (provider, event_id) do nothing
  returning id into v_id;
  if v_id is not null then
    return jsonb_build_object('id', v_id, 'duplicate', false);
  end if;
  select id, status into v_id, v_status from private.webhook_events where provider = p_provider and event_id = p_event_id;
  update private.webhook_events set attempts = attempts + 1 where id = v_id;
  return jsonb_build_object('id', v_id, 'duplicate', true, 'status', v_status);
end $$;

create or replace function server.webhook_mark(p_id uuid, p_status text, p_error text default null)
returns void language sql volatile security definer set search_path = ''
as $$
  update private.webhook_events
     set status = p_status, error = p_error, processed_at = case when p_status = 'processed' then now() end
   where id = p_id
$$;

-- ---------------------------------------------------------------------------
-- Events and queues
-- ---------------------------------------------------------------------------
create or replace function server.emit(p_type text, p_aggregate text, p_aggregate_id uuid, p_payload jsonb default '{}'::jsonb,
                                       p_actor uuid default null)
returns uuid
language sql
volatile
security definer
set search_path = ''
as $$
  insert into private.domain_events (type, aggregate, aggregate_id, actor_user_id, payload)
  values (p_type, p_aggregate, p_aggregate_id, p_actor, coalesce(p_payload, '{}'::jsonb))
  returning id
$$;

create or replace function server.queue_read(p_queue text, p_visibility_seconds int default 60, p_qty int default 10)
returns table (msg_id bigint, read_ct int, enqueued_at timestamptz, message jsonb)
language sql volatile security definer set search_path = ''
as $$ select r.msg_id, r.read_ct, r.enqueued_at, r.message from pgmq.read(p_queue, p_visibility_seconds, p_qty) r $$;

create or replace function server.queue_send(p_queue text, p_message jsonb, p_delay_seconds int default 0)
returns bigint language sql volatile security definer set search_path = ''
as $$ select pgmq.send(p_queue, p_message, p_delay_seconds) $$;

create or replace function server.queue_delete(p_queue text, p_msg_id bigint)
returns boolean language sql volatile security definer set search_path = ''
as $$ select pgmq.delete(p_queue, p_msg_id) $$;

create or replace function server.queue_archive(p_queue text, p_msg_id bigint)
returns boolean language sql volatile security definer set search_path = ''
as $$ select pgmq.archive(p_queue, p_msg_id) $$;

-- Dead-letter queue for messages that keep failing
select pgmq.create('dead_letter');

-- ---------------------------------------------------------------------------
-- AI usage and budgets
-- ---------------------------------------------------------------------------
create or replace function server.log_ai_usage(p jsonb)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into private.ai_usage (user_id, feature, step, provider, model, input_tokens, output_tokens,
                                cache_read_tokens, cache_write_tokens, images, cost_minor, latency_ms, ok, request_id)
  values ((p ->> 'user_id')::uuid, p ->> 'feature', p ->> 'step', p ->> 'provider', p ->> 'model',
          coalesce((p ->> 'input_tokens')::int, 0), coalesce((p ->> 'output_tokens')::int, 0),
          coalesce((p ->> 'cache_read_tokens')::int, 0), coalesce((p ->> 'cache_write_tokens')::int, 0),
          coalesce((p ->> 'images')::int, 0), coalesce((p ->> 'cost_minor')::bigint, 0),
          (p ->> 'latency_ms')::int, coalesce((p ->> 'ok')::boolean, true), p ->> 'request_id')
$$;

create or replace function server.ai_spend_today(p_user uuid default null)
returns bigint language sql stable security definer set search_path = ''
as $$ select private.ai_spend_today(p_user) $$;

-- ---------------------------------------------------------------------------
-- Privileges: service_role only
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema server from public, anon, authenticated;
grant execute on all functions in schema server to service_role;
alter default privileges in schema server revoke execute on functions from anon, authenticated;

-- AI price table and server-side limits live in config (no prices in code)
insert into public.config_keys (namespace, key, description, value_schema, default_value, owner, requires_approval, client_visible)
values
('app', 'ai.model_prices', 'Price per million tokens per model, in paise (input, output, cache read, cache write)',
  '{"type":"object","additionalProperties":{"type":"object","required":["input","output"],"properties":{"input":{"type":"number","minimum":0},"output":{"type":"number","minimum":0},"cache_read":{"type":"number","minimum":0},"cache_write":{"type":"number","minimum":0}}}}',
  '{}', 'founder', true, false),
('app', 'cors.allowed_origins', 'Browser origins allowed to call Edge Functions',
  '{"type":"array","items":{"type":"string","pattern":"^https?://"}}',
  '["https://drobie.app","https://admin.drobie.app","http://localhost:3000"]', 'eng', false, false),
('limit', 'rate.default', 'Default per-user token bucket for Edge Functions',
  '{"type":"object","required":["capacity","refill_per_sec"],"properties":{"capacity":{"type":"number","minimum":1},"refill_per_sec":{"type":"number","exclusiveMinimum":0}}}',
  '{"capacity":60,"refill_per_sec":1}', 'eng', false, false)
on conflict do nothing;
