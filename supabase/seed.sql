-- =============================================================================
-- drobie · seed.sql — LOCAL ONLY (runs on `supabase db reset`, never in production)
-- Reference data (taxonomy, plans, config keys…) lives in migration
-- 20261013000200_reference_data.sql.
-- =============================================================================

-- =============================================================================
-- LOCAL-ONLY test data. Password for every test user: drobie-local-123
--   alice@drobie.test : Ultimate (admin grant), 200 items, owner of her household
--   bob@drobie.test   : Free, 10 items
--   carol@drobie.test : viewer member of Alice's household (family sharing test)
-- =============================================================================
do $$
declare
  u record;
begin
  for u in select * from (values
    ('00000000-0000-4000-a000-00000000a11c'::uuid, 'alice@drobie.test', 'Alice'),
    ('00000000-0000-4000-a000-000000000b0b'::uuid, 'bob@drobie.test', 'Bob'),
    ('00000000-0000-4000-a000-00000000ca01'::uuid, 'carol@drobie.test', 'Carol')) t(id, email, name)
  loop
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
            extensions.crypt('drobie-local-123', extensions.gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}', jsonb_build_object('name', u.name), now(), now(), '', '', '', '');
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (u.id::text, u.id, jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
            'email', now(), now(), now());
  end loop;
end $$;

update public.profiles set adult_confirmed_at = now(), city = 'Bengaluru'
where id in ('00000000-0000-4000-a000-00000000a11c', '00000000-0000-4000-a000-000000000b0b', '00000000-0000-4000-a000-00000000ca01');

insert into public.consents (user_id, consent_type, version, granted, source)
select p.id, t.c, '1.0', true, 'system'
from public.profiles p cross join (values ('terms'), ('privacy')) t(c)
where p.id in ('00000000-0000-4000-a000-00000000a11c', '00000000-0000-4000-a000-000000000b0b', '00000000-0000-4000-a000-00000000ca01');

insert into public.entitlement_grants (user_id, plan_id, source, note)
select '00000000-0000-4000-a000-00000000a11c', id, 'admin', 'local test user on Ultimate' from public.plans where code = 'ultimate';

insert into public.household_members (household_id, user_id, role)
select h.id, '00000000-0000-4000-a000-00000000ca01', 'viewer'
from public.households h where h.owner_user_id = '00000000-0000-4000-a000-00000000a11c' and h.kind = 'personal';

-- Alice: a second home with rooms and storage, then 200 items spread across them
do $$
declare
  v_alice uuid := '00000000-0000-4000-a000-00000000a11c';
  v_hh uuid;
  v_home2 uuid;
  v_room uuid;
begin
  select id into v_hh from public.households where owner_user_id = v_alice and kind = 'personal';
  insert into public.places (household_id, name, kind, created_by) values (v_hh, 'Parents'' home', 'home', v_alice)
  returning id into v_home2;
  insert into public.places (household_id, parent_id, name, kind, created_by) values (v_hh, v_home2, 'My old room', 'room', v_alice)
  returning id into v_room;
  insert into public.places (household_id, parent_id, name, kind, created_by)
  values (v_hh, v_room, 'Almari', 'storage', v_alice), (v_hh, v_room, 'Trunk', 'box', v_alice);
end $$;

with leaf as (
  select c.id, c.slug, c.kind, row_number() over (order by c.slug) - 1 as n, count(*) over () as total
  from public.categories c where c.parent_id is not null and c.kind in ('apparel', 'footwear', 'accessory', 'jewellery', 'bag')
),
pl as (
  select p.id, row_number() over (order by p.name) - 1 as n, count(*) over () as total
  from public.places p join public.households h on h.id = p.household_id
  where h.owner_user_id = '00000000-0000-4000-a000-00000000a11c' and p.kind <> 'home'
),
gen as (select g from generate_series(1, 200) g)
insert into public.items (owner_user_id, kind, category_id, name, brand, colours, state, place_id, price_minor,
                          purchased_on, occasions, seasons, tag_source, source, confidence, user_confirmed, visibility)
select '00000000-0000-4000-a000-00000000a11c', leaf.kind, leaf.id,
       initcap(replace(leaf.slug, '-', ' ')) || ' #' || g,
       (array['Levi''s', 'Fabindia', 'H&M', 'Zara', 'Biba', 'Nike', null])[1 + g % 7],
       array[(array['black', 'white', 'blue', 'red', 'green', 'yellow', 'pink', 'beige', 'grey', 'maroon'])[1 + g % 10]],
       (array['clean', 'clean', 'clean', 'worn', 'in_wash', 'at_dhobi', 'clean', 'packed'])[1 + g % 8]::public.item_state,
       pl.id,
       (500 + (g * 137) % 4500) * 100,
       current_date - (g * 3 % 900),
       string_to_array((array['casual', 'office', 'festive', 'wedding,festive', 'casual,college'])[1 + g % 5], ','),
       array[(array['all', 'summer', 'winter', 'monsoon'])[1 + g % 4]],
       (array['phone', 'template', 'user', 'link'])[1 + g % 4],
       (array['camera', 'email', 'gallery', 'link', 'voice'])[1 + g % 5],
       0.55 + (g % 45) / 100.0,
       g % 3 = 0,
       case when g % 10 = 0 then 'household'::public.item_visibility else 'private' end
from gen
join leaf on leaf.n = g % leaf.total
join pl on pl.n = g % pl.total;

-- a few wears for Alice
insert into public.wear_logs (id, owner_user_id, worn_on, occasion)
select private.uuid_v7(), '00000000-0000-4000-a000-00000000a11c', current_date - d, 'casual'
from generate_series(1, 10) d;
insert into public.wear_log_items (wear_log_id, item_id)
select w.id, i.id
from (select id, row_number() over (order by worn_on) as n from public.wear_logs
      where owner_user_id = '00000000-0000-4000-a000-00000000a11c') w
join lateral (select id from public.items where owner_user_id = '00000000-0000-4000-a000-00000000a11c'
              order by id offset (w.n * 3) limit 3) i on true;

-- Bob: 10 items on the free plan
insert into public.items (owner_user_id, kind, category_id, name, colours, place_id)
select '00000000-0000-4000-a000-000000000b0b', 'apparel', (select id from public.categories where slug = 't-shirts'),
       'Bob tee #' || g, array['black'],
       (select p.id from public.places p join public.households h on h.id = p.household_id
         where h.owner_user_id = '00000000-0000-4000-a000-000000000b0b' and p.name = 'Wardrobe')
from generate_series(1, 10) g;

-- Studio credits for Alice through the ledger
select private.grant_credits('00000000-0000-4000-a000-00000000a11c', 25, 'seed', 'seed:alice:credits');

analyze;
