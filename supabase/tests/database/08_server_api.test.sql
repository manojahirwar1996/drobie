begin;
select plan(17);

select tests.create_user('srv@s.test') as u \gset

-- only the service role may touch the server schema
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'server' and (has_function_privilege('anon', p.oid, 'execute')
                                    or has_function_privilege('authenticated', p.oid, 'execute'))),
  null, 'no server function is executable by anon or authenticated');
select ok(not has_schema_privilege('authenticated', 'server', 'usage'), 'authenticated has no usage on the server schema');
select tests.authenticate_as(:'u');
select throws_ok(format($$select server.consume_quota(%L, 'dro.chats')$$, :'u'), '42501', null,
  'a signed-in client cannot call server functions');
select tests.clear_authentication();

-- account state
select is(server.account_state(:'u') ->> 'plan', 'free', 'account_state reports the effective plan');
select is((server.account_state(:'u') ->> 'adult_confirmed')::boolean, true, 'account_state reports adult confirmation');
select is((server.account_state(gen_random_uuid()) ->> 'exists')::boolean, false, 'unknown users do not exist');

-- consents: versions must match config; withdrawal of measurements deletes them
select is((server.set_consents(:'u', '[{"consent_type":"measurements","granted":true,"version":"1.0"}]') ->> 'changed')::int, 1,
  'granting a consent is recorded');
insert into public.body_profiles (user_id, height_cm) values (:'u', 170);
select throws_ok(format($$select server.set_consents(%L, '[{"consent_type":"gallery","granted":true,"version":"0.9"}]')$$, :'u'),
  '22023', null, 'a stale consent version is refused');
select server.set_consents(:'u', '[{"consent_type":"measurements","granted":false,"version":"1.0"}]');
select is((select count(*)::int from public.body_profiles where user_id = :'u'), 0,
  'withdrawing the measurements consent deletes the measurements');
select is(server.current_consents(:'u') -> 'measurements' ->> 'granted', 'false', 'current consents show the latest choice');

-- idempotency keys
select is(server.idempotency_begin(:'u', 'key-0001', '/v1/items', 'h1') ->> 'state', 'new', 'first use of a key is new');
select is(server.idempotency_begin(:'u', 'key-0001', '/v1/items', 'h1') ->> 'state', 'in_progress', 'a concurrent duplicate is in progress');
select is(server.idempotency_begin(:'u', 'key-0001', '/v1/items', 'h2') ->> 'state', 'mismatch', 'same key, different body is a mismatch');
select server.idempotency_complete(:'u', 'key-0001', 201, '{"data":{"ok":true}}');
select is(server.idempotency_begin(:'u', 'key-0001', '/v1/items', 'h1') -> 'response', '{"data":{"ok":true}}'::jsonb,
  'a completed key replays the stored response');

-- webhooks are deduplicated by provider event id
select is((server.webhook_receive('razorpay', 'evt_1', 'payment.captured', '{}', true) ->> 'duplicate')::boolean, false, 'first delivery is new');
select is((server.webhook_receive('razorpay', 'evt_1', 'payment.captured', '{}', true) ->> 'duplicate')::boolean, true, 'redelivery is a duplicate');

-- config snapshot includes server-only keys
select ok(server.config_snapshot('en-IN') -> 'values' ? 'app:ai.daily_spend_cap_minor', 'server snapshot includes server-only keys');

select * from finish();
rollback;
