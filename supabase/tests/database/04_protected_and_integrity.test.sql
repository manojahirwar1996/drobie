-- Protected columns, server-only tables, sensitive data, data integrity rules.
begin;
select plan(30);

select tests.create_user('a@p.test') as a \gset
select tests.create_user('b@p.test') as b \gset
select tests.create_user('stylist@p.test') as stylist \gset

select tests.authenticate_as(:'a');
insert into public.items (id, name, category_id)
values ('33333333-3333-7333-8333-333333333333', 'Blue jeans', (select id from public.categories where slug = 'jeans'));

-- protected columns on own rows
select throws_ok($$update public.profiles set status = 'active'$$, '42501', null, 'cannot change own account status');
select throws_ok($$update public.profiles set adult_confirmed_at = null$$, '42501', null, 'cannot unset/forge adult confirmation');
select throws_ok($$update public.profiles set inbound_email_token = 'x'$$, '42501', null, 'cannot change inbound email token');
select throws_ok($$update public.items set wear_count = 99$$, '42501', null, 'wear counters are server-maintained');
select throws_ok(format($$update public.items set owner_user_id = %L$$, :'b'), '42501', null, 'cannot change item owner');
select lives_ok($$update public.profiles set display_name = 'Aanya', morning_time = '08:00'$$, 'can edit own profile fields');
select throws_ok($$update public.profiles set timezone = 'Mars/Olympus'$$, '22023', null, 'timezone must be valid');

-- money, plans and limits are server truths
select throws_ok(format($$insert into public.entitlement_grants (user_id, plan_id, source) select %L, id, 'admin' from public.plans where code = 'ultimate'$$, :'a'),
  '42501', null, 'clients cannot grant themselves a plan');
select throws_ok($$update public.usage_counters set used = 0$$, '42501', null, 'clients cannot reset quota usage');
select throws_ok($$select * from public.plan_prices$$, '42501', null, 'raw price table is not client-readable (served per channel)');
select throws_ok($$select * from private.ledger_entries$$, '42501', null, 'ledger is not client-readable');
select throws_ok($$insert into public.orders (buyer_user_id, channel, currency) values (auth.uid(), 'web', 'INR')$$,
  '42501', null, 'clients cannot create orders directly');
select throws_ok($$select * from public.config_versions$$, '42501', null, 'config store is server-only');
select is((select count(*)::int from public.my_wallets()), 0, 'my_wallets returns only the caller''s wallets');

-- consents are append-only
insert into public.consents (consent_type, version, granted) values ('marketing', '1.0', true);
select throws_ok($$update public.consents set granted = false$$, '42501', null, 'consent history cannot be edited');
select throws_ok($$insert into public.consents (consent_type, version, granted, source) values ('marketing', '1.0', false, 'support')$$,
  '42501', null, 'clients can only record consents from app or web');

-- SENSITIVE body profile: consent required; grants must name it
select throws_ok($$insert into public.body_profiles (height_cm) values (165)$$, '42501', null,
  'measurements need the measurements consent');
insert into public.consents (consent_type, version, granted) values ('measurements', '1.0', true);
select lives_ok($$insert into public.body_profiles (height_cm, measurements) values (165, '{"bust_cm": 86}')$$,
  'with consent, measurements can be saved');
insert into public.access_grants (grantee_user_id, scope, purpose, expires_at)
values (:'b', 'closet_read', 'consultation', now() + interval '7 days');

select tests.authenticate_as(:'b');
select is((select count(*)::int from public.body_profiles), 0, 'a closet_read grant does not expose measurements');
select tests.authenticate_as(:'a');
insert into public.access_grants (grantee_user_id, scope, purpose, expires_at)
values (:'stylist', 'measurements_read', 'consultation', now() + interval '7 days');
select tests.authenticate_as(:'stylist');
select is((select count(*)::int from public.body_profiles), 1, 'an explicit measurements_read grant can read them');
select tests.clear_authentication();
select ok(exists (select 1 from audit.log where table_name = 'public.body_profiles' and after = '{"redacted": true}'),
  'sensitive changes are audited without values');

-- attribute schema validation per category
select tests.authenticate_as(:'a');
select throws_ok($$update public.items set attributes = '{"fit": "baggy-ish"}' where id = '33333333-3333-7333-8333-333333333333'$$,
  '23514', null, 'attributes must match the category schema (enum)');
select throws_ok($$update public.items set attributes = '{"colourway": "x"}' where id = '33333333-3333-7333-8333-333333333333'$$,
  '23514', null, 'unknown attributes are rejected when the schema is closed');
select lives_ok($$update public.items set attributes = '{"fit": "straight", "waist_in": 30, "rise": "high"}' where id = '33333333-3333-7333-8333-333333333333'$$,
  'valid attributes are accepted');

-- places tree rules
insert into public.places (id, household_id, name) values ('44444444-4444-7444-8444-444444444441', tests.household_of(:'a'), 'L1');
insert into public.places (id, household_id, parent_id, name) values
  ('44444444-4444-7444-8444-444444444442', tests.household_of(:'a'), '44444444-4444-7444-8444-444444444441', 'L2'),
  ('44444444-4444-7444-8444-444444444443', tests.household_of(:'a'), '44444444-4444-7444-8444-444444444442', 'L3'),
  ('44444444-4444-7444-8444-444444444444', tests.household_of(:'a'), '44444444-4444-7444-8444-444444444443', 'L4'),
  ('44444444-4444-7444-8444-444444444445', tests.household_of(:'a'), '44444444-4444-7444-8444-444444444444', 'L5'),
  ('44444444-4444-7444-8444-444444444446', tests.household_of(:'a'), '44444444-4444-7444-8444-444444444445', 'L6');
select throws_ok(format($$insert into public.places (household_id, parent_id, name) values (%L, '44444444-4444-7444-8444-444444444446', 'L7')$$, tests.household_of(:'a')),
  '23514', null, 'places nest at most 6 deep');
select throws_ok($$update public.places set parent_id = '44444444-4444-7444-8444-444444444443' where id = '44444444-4444-7444-8444-444444444441'$$,
  '23514', null, 'a place cannot be moved under its own descendant');
select throws_ok(format($$insert into public.places (household_id, name) values (%L, 'l1')$$, tests.household_of(:'a')),
  '23505', null, 'place names are unique per parent (case-insensitive)');
select throws_ok(format($$update public.items set place_id = %L where id = '33333333-3333-7333-8333-333333333333'$$, tests.place_of(:'b')),
  '23514', null, 'an item cannot be placed in another household');

-- state bookkeeping and history
update public.items set state = 'lent', holder_name = 'Riya', due_back_on = current_date + 7
where id = '33333333-3333-7333-8333-333333333333';
update public.items set state = 'clean' where id = '33333333-3333-7333-8333-333333333333';
select is((select holder_name from public.items where id = '33333333-3333-7333-8333-333333333333'), null,
  'returning a lent item clears the holder');
select is((select array_agg(to_state::text order by occurred_at, id) from public.item_events
           where item_id = '33333333-3333-7333-8333-333333333333' and type = 'state_changed'),
          array['lent', 'clean'], 'state changes are logged in item history');

select * from finish();
rollback;
