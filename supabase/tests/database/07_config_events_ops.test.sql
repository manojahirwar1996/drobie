begin;
select plan(22);

select tests.create_user('admin1@c.test') as admin1 \gset
select tests.create_user('admin2@c.test') as admin2 \gset
select tests.create_user('user@c.test') as u \gset
insert into public.admin_users (user_id, role) values (:'admin1', 'admin'), (:'admin2', 'admin');

-- admin role helper requires MFA
select tests.authenticate_as(:'admin1', 'aal1');
select is(private.has_admin_role('admin'), false, 'admin role needs MFA (aal2)');
select tests.authenticate_as(:'admin1', 'aal2');
select is(private.has_admin_role('support'), true, 'admin with MFA covers support');
select is(private.has_admin_role('finance'), false, 'admin does not imply finance');
select tests.authenticate_as(:'u', 'aal2');
select is(private.has_admin_role('support'), false, 'non-staff has no admin role');
select tests.clear_authentication();

-- config: schema validation, four-eyes approval, publish, rollback
select throws_ok($$insert into public.config_versions (namespace, key, value) values ('app', 'ai.daily_spend_cap_minor', '"lots"')$$,
  '23514', null, 'config values are validated against their schema');

insert into public.config_versions (namespace, key, value, author_id, reason)
values ('app', 'ai.daily_spend_cap_minor', '80000', :'admin1', 'raise cap for launch');
select id as v1 from public.config_versions where key = 'ai.daily_spend_cap_minor' and version = 1 \gset

select tests.authenticate_as(:'admin1', 'aal2');
select throws_ok(format($$select private.config_publish(%L)$$, :'v1'), '42501', null,
  'approval-required config cannot be published unapproved');
select throws_ok(format($$select private.config_approve(%L)$$, :'v1'), '42501', null, 'the author cannot approve their own change');
select tests.authenticate_as(:'admin2', 'aal2');
select lives_ok(format($$select private.config_approve(%L)$$, :'v1'), 'a second admin approves');
select tests.authenticate_as(:'admin1', 'aal2');
select lives_ok(format($$select private.config_publish(%L)$$, :'v1'), 'approved config publishes');
select tests.clear_authentication();
select is(private.config_value('app', 'ai.daily_spend_cap_minor'), '80000'::jsonb, 'published value is in force');
select throws_ok(format($$update public.config_versions set value = '1' where id = %L$$, :'v1'), '42501', null,
  'published versions are immutable');

insert into public.config_versions (namespace, key, value, author_id) values ('copy', 'paywall.title', '"Go Pro with dro"', :'admin1');
select private.config_publish(id) from public.config_versions where key = 'paywall.title' and version = 1;
insert into public.config_versions (namespace, key, value, author_id) values ('copy', 'paywall.title', '"Try Ultimate dro"', :'admin1');
select private.config_publish(id) from public.config_versions where key = 'paywall.title' and version = 2;
select is(private.config_value('copy', 'paywall.title'), '"Try Ultimate dro"'::jsonb, 'newest publish wins');
select private.config_rollback('copy', 'paywall.title');
select is(private.config_value('copy', 'paywall.title'), '"Go Pro with dro"'::jsonb, 'rollback restores the previous version');

insert into public.config_versions (namespace, key, value, author_id, starts_at, ends_at)
values ('copy', 'paywall.title', '"Diwali offer!"', :'admin1', now() + interval '1 day', now() + interval '5 days');
select private.config_publish(id) from public.config_versions where key = 'paywall.title' and version = 3;
select is(private.config_value('copy', 'paywall.title'), '"Go Pro with dro"'::jsonb, 'a scheduled change waits for its start');

select ok(private.config_bundle('en-IN') -> 'values' ? 'copy:paywall.title', 'bundle includes client-visible keys');
select ok(not (private.config_bundle('en-IN') -> 'values' ? 'app:ai.daily_spend_cap_minor'), 'bundle excludes server-only keys');
select ok((select count(*) from audit.log where table_name = 'public.config_versions') >= 5, 'config changes are audited');
select throws_ok($$delete from audit.log$$, '42501', null, 'audit log is append-only');

-- outbox → queues
select tests.authenticate_as(:'u');
insert into public.items (name) values ('Event test kurta');
select tests.clear_authentication();
select ok(exists (select 1 from private.domain_events where type = 'item.created' and actor_user_id = :'u'),
  'item writes emit domain events in the same transaction');
select ok(private.dispatch_events(1000) > 0, 'dispatcher moves events to queues');
select ok(exists (select 1 from pgmq.read('search', 0, 100) m where m.message ->> 'type' = 'item.created'),
  'item events reach the search queue');

-- rate limiter
select is(array[private.rate_limit_take('t:1', 2, 0), private.rate_limit_take('t:1', 2, 0), private.rate_limit_take('t:1', 2, 0)],
  array[true, true, false], 'token bucket allows capacity then refuses');

select * from finish();
rollback;
