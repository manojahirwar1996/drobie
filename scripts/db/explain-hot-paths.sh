#!/usr/bin/env bash
# Load ~100k items across 100 users, then print EXPLAIN ANALYZE for the hot
# paths as a signed-in user (through RLS). Run after test-local.sh.
set -euo pipefail
DB="${1:-drobie}"
psql -X -q -v ON_ERROR_STOP=1 -d "$DB" >/dev/null <<'SQL'
do $$
declare u uuid;
begin
  if (select count(*) from public.items) > 50000 then return; end if;
  for i in 1..100 loop
    u := tests.create_user('load' || i || '@load.test');
    insert into public.entitlement_grants (user_id, plan_id, source) select u, id, 'admin' from public.plans where code = 'ultimate';
  end loop;
end $$;
alter table public.items disable trigger items_after;
insert into public.items (owner_user_id, name, brand, colours, state, category_id, household_id, place_id)
select p.id, 'Load item ' || g, (array['Zara','H&M','Biba'])[1 + g % 3], array[(array['black','red','blue'])[1 + g % 3]],
       (array['clean','worn','in_wash'])[1 + g % 3]::public.item_state,
       (select id from public.categories where slug = (array['jeans','kurtas','sarees','t-shirts'])[1 + g % 4]),
       h.id, (select id from public.places where household_id = h.id and name = 'Wardrobe')
from public.profiles p join public.households h on h.owner_user_id = p.id
cross join generate_series(1, 1000) g
where p.display_name like 'load%' and (select count(*) from public.items) < 50000;
alter table public.items enable trigger items_after;
analyze;
SQL
psql -X -q -d "$DB" <<'SQL' | grep -E "^===|Execution Time|Scan using|Seq Scan on items"
begin;
select tests.authenticate_as('00000000-0000-4000-a000-00000000a11c') \gset
\echo '=== total items in database'
select count(*) from public.items where true;  -- RLS: only Alice's visible rows counted
\echo '=== 1. closet delta sync (keyset, 100 rows)'
explain (analyze, costs off) select id, name, state, place_id, updated_at from public.items
 where owner_user_id = '00000000-0000-4000-a000-00000000a11c' and (updated_at, id) > ('2000-01-01', '00000000-0000-0000-0000-000000000000')
 order by updated_at, id limit 100;
\echo '=== 2. where is "black kurta" (FTS over own closet)'
explain (analyze, costs off) select i.id, i.name, p.name from public.items i left join public.places p on p.id = i.place_id
 where i.owner_user_id = '00000000-0000-4000-a000-00000000a11c' and i.deleted_at is null
   and i.search @@ plainto_tsquery('simple', 'black kurtas') limit 20;
\echo '=== 3. laundry hub counts by state'
explain (analyze, costs off) select state, count(*) from public.items
 where owner_user_id = '00000000-0000-4000-a000-00000000a11c' and deleted_at is null group by state;
\echo '=== 4. unfiltered read (worst case: client forgot the owner filter)'
explain (analyze, costs off) select count(*) from public.items;
\echo '=== 5. entitlement check'
explain (analyze, costs off) select public.entitlement('dro.chats');
rollback;
SQL
