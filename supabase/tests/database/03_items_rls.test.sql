-- Allow/deny for the closet across every relationship: owner, stranger,
-- household viewer, valid / expired / revoked / item-scoped grant, support
-- staff with and without MFA, anon.
begin;
select plan(32);

select tests.create_user('owner@t.test') as owner \gset
select tests.create_user('stranger@t.test') as stranger \gset
select tests.create_user('family@t.test') as family \gset
select tests.create_user('friend@t.test') as friend \gset
select tests.create_user('expired@t.test') as expired \gset
select tests.create_user('revoked@t.test') as revoked \gset
select tests.create_user('one-item@t.test') as oneitem \gset
select tests.create_user('staff@t.test') as staff \gset
select tests.create_user('cat@t.test') as catg \gset
select tests.create_user('place@t.test') as placeg \gset

insert into public.household_members (household_id, user_id, role) values (tests.household_of(:'owner'), :'family', 'viewer');
insert into public.admin_users (user_id, role) values (:'staff', 'support');

-- owner adds a private and a household-visible item
select tests.authenticate_as(:'owner');
insert into public.items (id, name, visibility, place_id, category_id)
values ('11111111-1111-7111-8111-111111111111', 'Private kurta', 'private', tests.place_of(:'owner'),
        (select id from public.categories where slug = 'kurtas')),
       ('22222222-2222-7222-8222-222222222222', 'Shared saree', 'household', tests.place_of(:'owner', 'Drawer'), null);
insert into public.access_grants (grantee_user_id, scope, purpose, resource_category_id)
values (:'catg', 'item_read', 'friend', (select id from public.categories where slug = 'kurtas'));
insert into public.access_grants (grantee_user_id, scope, purpose, resource_place_id)
values (:'placeg', 'item_read', 'friend', tests.place_of(:'owner', 'Home'));
insert into public.access_grants (grantee_user_id, scope, purpose) values (:'friend', 'closet_read', 'friend');
insert into public.access_grants (grantee_user_id, scope, purpose, resource_item_id)
values (:'oneitem', 'item_read', 'friend', '11111111-1111-7111-8111-111111111111');
insert into public.access_grants (grantee_user_id, scope, purpose, expires_at)
values (:'staff', 'support_view', 'support', now() + interval '1 day');
select tests.clear_authentication();

-- grants in the past / revoked (inserted directly: clients cannot create them this way)
insert into public.access_grants (grantor_user_id, grantee_user_id, scope, purpose, created_at, expires_at)
values (:'owner', :'expired', 'closet_read', 'friend', now() - interval '2 days', now() - interval '1 day');
insert into public.access_grants (grantor_user_id, grantee_user_id, scope, purpose, revoked_at)
values (:'owner', :'revoked', 'closet_read', 'friend', now());

select tests.authenticate_as(:'owner');
select is((select count(*)::int from public.items), 2, 'owner sees own items');
select is((select count(*)::int from public.places where household_id = tests.household_of(:'owner')), 4, 'owner sees own places');
select is((select count(*)::int from public.item_events), 2, 'owner sees item history');

select tests.authenticate_as(:'stranger');
select is((select count(*)::int from public.items), 0, 'stranger sees no items');
select is((select count(*)::int from public.places where household_id = tests.household_of(:'owner')), 0, 'stranger sees no places');
select is((select count(*)::int from public.item_events where owner_user_id = :'owner'), 0, 'stranger sees no history');
select is((select count(*)::int from public.households where owner_user_id = :'owner'), 0, 'stranger cannot see the household');
with u as (update public.items set name = 'hacked' where id = '11111111-1111-7111-8111-111111111111' returning 1)
select is((select count(*)::int from u), 0, 'stranger cannot update the owner''s item');
select throws_ok(
  format($$insert into public.items (owner_user_id, name) values (%L, 'planted')$$, :'owner'),
  '42501', null, 'stranger cannot insert an item into someone else''s closet');
select throws_ok(
  format($$insert into public.places (household_id, name) values (%L, 'Planted shelf')$$, tests.household_of(:'owner')),
  '42501', null, 'stranger cannot add places to someone else''s household');

select tests.authenticate_as(:'family');
select is((select array_agg(name) from public.items), array['Shared saree'], 'household viewer sees only household-visible items');
select is((select count(*)::int from public.places where household_id = tests.household_of(:'owner')), 4, 'household viewer sees places');
select throws_ok(
  format($$insert into public.places (household_id, name) values (%L, 'Viewer shelf')$$, tests.household_of(:'owner')),
  '42501', null, 'a viewer cannot add places (needs adult role)');
with u as (update public.items set state = 'worn' where id = '22222222-2222-7222-8222-222222222222' returning 1)
select is((select count(*)::int from u), 0, 'household viewer cannot change items');

select tests.authenticate_as(:'friend');
select is((select count(*)::int from public.items), 2, 'closet_read grant sees the closet');
select is((select count(*)::int from public.places where household_id = tests.household_of(:'owner')), 4, 'closet_read implies places_read');

select tests.authenticate_as(:'oneitem');
select is((select array_agg(name) from public.items), array['Private kurta'], 'item-scoped grant sees only that item');

select tests.authenticate_as(:'catg');
select is((select array_agg(name) from public.items), array['Private kurta'], 'category-scoped grant sees only that category');
select tests.authenticate_as(:'placeg');
select is((select count(*)::int from public.items), 2, 'place-scoped grant covers items in sub-places (Home → Wardrobe, Drawer)');
select is((select count(*)::int from public.places where household_id = tests.household_of(:'owner')), 0,
  'an item_read grant does not expose the place tree');

select tests.authenticate_as(:'expired');
select is((select count(*)::int from public.items), 0, 'expired grant sees nothing');

select tests.authenticate_as(:'revoked');
select is((select count(*)::int from public.items), 0, 'revoked grant sees nothing');

select tests.authenticate_as(:'staff', 'aal1');
select is((select count(*)::int from public.items), 0, 'support grant without MFA sees nothing');
select tests.authenticate_as(:'staff', 'aal2');
select is((select count(*)::int from public.items), 2, 'support staff with MFA and a user-approved grant can view');

-- revoking takes effect immediately
select tests.authenticate_as(:'owner');
update public.access_grants set revoked_at = now() where grantee_user_id = :'friend';
select tests.authenticate_as(:'friend');
select is((select count(*)::int from public.items), 0, 'revoked grant stops access immediately');

-- soft delete hides from others but syncs to the owner
select tests.authenticate_as(:'owner');
update public.items set deleted_at = now() where id = '22222222-2222-7222-8222-222222222222';
select is((select count(*)::int from public.items where deleted_at is not null), 1, 'owner still syncs soft-deleted rows');
select tests.authenticate_as(:'family');
select is((select count(*)::int from public.items), 0, 'soft-deleted items disappear for the household');

-- grants cannot be extended or un-revoked by the grantor
select tests.authenticate_as(:'owner');
select throws_ok(
  format($$update public.access_grants set expires_at = now() + interval '30 days' where grantee_user_id = %L$$, :'staff'),
  '42501', null, 'a grant cannot be extended');
select throws_ok(
  format($$update public.access_grants set revoked_at = null where grantee_user_id = %L$$, :'friend'),
  '42501', null, 'a revoked grant cannot be restored');
select throws_ok(
  format($$insert into public.access_grants (grantee_user_id, scope, purpose) values (%L, 'support_view', 'support')$$, :'staff'),
  '23514', null, 'support grants must expire');

select tests.authenticate_as_anon();
select throws_ok($$select count(*) from public.items$$, '42501', null, 'anon cannot read items');
select lives_ok($$select count(*) from public.categories$$, 'anon can read the taxonomy');

select * from finish();
rollback;
