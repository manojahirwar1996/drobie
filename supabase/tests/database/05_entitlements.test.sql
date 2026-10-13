begin;
select plan(20);

select tests.create_user('free@e.test') as u \gset
select tests.create_user('other@e.test') as other \gset

select tests.authenticate_as(:'u');
select is((public.entitlement('closet.max_items') ->> 'limit')::int, 40, 'free plan: item limit from plan_features');
select is(public.entitlement('dro.chats') ->> 'plan', 'free', 'effective plan is free');
select is((public.entitlement('dro.think_harder') ->> 'enabled')::boolean, false, 'flag off on free');
select is((select count(*)::int from public.user_entitlements), 5, 'user_entitlements lists the caller''s features');
select throws_ok(format($$select private.entitlement(%L, 'dro.chats')$$, :'other'), '42501', null,
  'cannot read another user''s entitlements');
select throws_ok(format($$select private.consume_quota(%L, 'dro.chats')$$, :'u'), '42501', null,
  'clients cannot consume quota directly');

-- quotas (as the server)
select tests.authenticate_as_service();
select is((select count(*)::int from generate_series(1, 5) g
           where (private.consume_quota(:'u', 'dro.chats') ->> 'ok')::boolean), 5, 'five chats fit the free daily quota');
select is(private.consume_quota(:'u', 'dro.chats') ->> 'reason', 'quota_exceeded', 'the sixth is refused cleanly');
select is((private.entitlement(:'u', 'dro.chats') ->> 'remaining')::int, 0, 'remaining is zero');
select private.release_quota(:'u', 'dro.chats', 1);
select is((private.entitlement(:'u', 'dro.chats') ->> 'remaining')::int, 1, 'release gives quota back');
select tests.clear_authentication();
insert into public.usage_counters (user_id, feature_id, period_start, used)
select :'u', id, current_date - 1, 99 from public.features where key = 'dro.chats';
select is((private.entitlement(:'u', 'dro.chats') ->> 'used')::int, 4, 'yesterday''s usage does not count today');

-- booster adds to the plan limit
insert into public.entitlement_grants (user_id, feature_id, feature_value, source)
select :'u', id, 10, 'booster' from public.features where key = 'dro.chats';
select is((private.entitlement(:'u', 'dro.chats') ->> 'limit')::int, 15, 'boosters add to the plan quota');

-- higher-ranked plan wins; expired and revoked grants are ignored
insert into public.entitlement_grants (user_id, plan_id, source, starts_at, ends_at)
select :'u', id, 'trial', now() - interval '10 days', now() - interval '3 days' from public.plans where code = 'ultimate';
insert into public.entitlement_grants (user_id, plan_id, source, revoked_at)
select :'u', id, 'promo', now() from public.plans where code = 'ultimate';
select is(private.effective_plan(:'u'), 'free', 'expired and revoked grants do not count');
insert into public.entitlement_grants (user_id, plan_id, source)
select :'u', id, 'subscription' from public.plans where code = 'pro';
select is(private.effective_plan(:'u'), 'pro', 'an active subscription grant wins over free');
select is((private.entitlement(:'u', 'closet.max_items') ->> 'limit')::int, 300, 'pro item limit applies');
select is((private.entitlement(:'u', 'dro.think_harder') ->> 'enabled')::boolean, true, 'pro flag on');

insert into public.entitlement_grants (user_id, plan_id, source)
select :'u', id, 'admin' from public.plans where code = 'ultimate';
select is(private.entitlement(:'u', 'dro.chats') ->> 'limit', null, 'ultimate is unlimited');
select is((private.consume_quota(:'u', 'dro.chats', 1000) ->> 'ok')::boolean, true, 'unlimited quota always succeeds');

-- item limit is enforced in the database (other user: free, 40 items)
insert into public.items (owner_user_id, name) select :'other', 'item ' || g from generate_series(1, 40) g;
select throws_ok(format($$insert into public.items (owner_user_id, name) values (%L, 'one too many')$$, :'other'),
  'P0001', null, 'the 41st item on free is refused');
update public.items set deleted_at = now() where owner_user_id = :'other' and name = 'item 1';
select lives_ok(format($$insert into public.items (owner_user_id, name) values (%L, 'after delete')$$, :'other'),
  'deleting an item frees a slot');

select * from finish();
rollback;
