begin;
select plan(12);

select tests.create_user('new@drobie.test', false) as uid \gset

select is((select country::text || '/' || locale || '/' || timezone || '/' || currency from public.profiles where id = :'uid'),
          'IN/en-IN/Asia/Kolkata/INR', 'signup creates a profile with India defaults');
select is((select display_name from public.profiles where id = :'uid'), 'new', 'display name taken from auth metadata');
select ok((select inbound_email_token ~ '^[0-9a-f]{20}$' from public.profiles where id = :'uid'), 'inbound email token generated');
select is((select count(*)::int from public.households where owner_user_id = :'uid' and kind = 'personal'), 1,
          'one personal household');
select is((select role::text from public.household_members where user_id = :'uid'), 'owner', 'user owns their household');
select is((select array_agg(name order by sort_order) from public.places where household_id = tests.household_of(:'uid')),
          array['Home', 'Wardrobe', 'Drawer', 'Shoe rack'], 'starter places created');
select is((select p.code from public.entitlement_grants g join public.plans p on p.id = g.plan_id where g.user_id = :'uid'),
          'free', 'default plan granted at signup');
select ok(exists (select 1 from private.domain_events where type = 'account.created' and aggregate_id = :'uid'),
          'account.created event emitted');

-- not yet 18+ confirmed: closet writes are refused
select tests.authenticate_as(:'uid');
select throws_ok(
  format($$insert into public.items (name) values ('Kurta')$$),
  '42501', null, 'users who have not confirmed 18+ cannot add items');
select isnt(public.confirm_adult(), null, 'confirm_adult records the confirmation');
select lives_ok($$insert into public.items (name) values ('Kurta')$$, 'after confirming, items can be added');
select is((select household_id from public.items where name = 'Kurta'), tests.household_of(:'uid'),
          'items default to the personal household');

select * from finish();
rollback;
