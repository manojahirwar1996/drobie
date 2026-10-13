begin;
select plan(15);

select has_extension('vector', 'pgvector installed');
select has_extension('pgmq', 'pgmq installed');
select has_extension('pg_cron', 'pg_cron installed');

select is(
  (select array_agg(c.relname order by c.relname) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity),
  null,
  'every public table has RLS enabled');

select is(
  (select array_agg(distinct table_name::text order by table_name::text) from information_schema.role_table_grants
    where grantee = 'anon' and table_schema = 'public'
      and table_name not in ('countries', 'categories', 'category_translations', 'plans', 'features', 'plan_features')),
  null,
  'anon can read only reference tables');

select is(
  (select array_agg(distinct table_schema || '.' || table_name) from information_schema.role_table_grants
    where grantee in ('anon', 'authenticated') and table_schema in ('private', 'audit')),
  null,
  'no client role has any privilege on private or audit tables');

-- every foreign key is covered by an index whose leading columns match it
select is(
  (select array_agg(format('%s(%s)', c.conrelid::regclass, c.conname) order by 1)
     from pg_constraint c
     join pg_namespace n on n.oid = (select relnamespace from pg_class where oid = c.conrelid)
    where c.contype = 'f' and n.nspname in ('public', 'private', 'audit')
      and not exists (
        select 1 from pg_index i
        where i.indrelid = c.conrelid
          and (i.indkey::int2[])[0:cardinality(c.conkey) - 1] @> c.conkey
          and (i.indkey::int2[])[0:cardinality(c.conkey) - 1] <@ c.conkey)),
  null,
  'every foreign key has a supporting index');

select is(
  (select array_agg(p.oid::regprocedure::text order by 1) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private', 'audit') and p.prosecdef
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%')),
  null,
  'every SECURITY DEFINER function pins search_path');

select is(
  (select array_agg(c.table_name::text order by 1) from information_schema.columns c
    where c.table_schema = 'public' and c.column_name = 'updated_at'
      and c.table_name not in (select table_name from information_schema.views where table_schema = 'public')
      and c.table_name not in ('usage_counters')   -- maintained by consume_quota
      and not exists (select 1 from information_schema.triggers t
                      where t.event_object_schema = 'public' and t.event_object_table = c.table_name
                        and t.action_statement like '%tg_set_updated_at%')),
  null,
  'every table with updated_at has the trigger');

select is(
  (select array_agg(p.oid::regprocedure::text order by 1) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private', 'audit') and has_function_privilege('anon', p.oid, 'execute')),
  null,
  'anon cannot execute any of our functions');

-- the complete list of functions a signed-in client may execute (RLS helpers + RPCs)
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private', 'audit') and p.prokind = 'f'
      and has_function_privilege('authenticated', p.oid, 'execute')),
  array['active_grants', 'active_plan_ids', 'can_read_item', 'can_read_media', 'can_read_user', 'config_approve', 'config_publish',
        'config_rollback', 'confirm_adult', 'effective_features', 'effective_plan', 'entitlement', 'entitlement',
        'granted_household_ids', 'granted_places', 'has_access', 'has_admin_role', 'has_consent', 'household_owner', 'immutable_array_to_string',
        'is_active_adult', 'is_blocked', 'is_household_member', 'jsonschema_errors', 'my_household_ids', 'my_wallets', 'owns_item',
        'owns_order', 'uid', 'uuid_v7'],
  'authenticated can execute only the allow-listed functions');

select is(substr(private.uuid_v7()::text, 15, 1), '7', 'uuid_v7 sets the version nibble');
select ok(
  (select bool_and(substr(id::text, 20, 1) in ('8', '9', 'a', 'b')) from (select private.uuid_v7() as id from generate_series(1, 50)) t),
  'uuid_v7 sets the RFC 9562 variant bits');

create temporary table ids as select private.uuid_v7() as id;
select pg_sleep(0.003);
insert into ids select private.uuid_v7();
select ok((select (array_agg(id order by ctid))[1] < (array_agg(id order by ctid))[2] from ids), 'uuid_v7 is time-ordered');

select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where (n.nspname, c.relname) in (('private', 'domain_events_p' || to_char(now(), 'YYYYMM')),
                                    ('audit', 'log_p' || to_char(now(), 'YYYYMM')),
                                    ('private', 'ai_usage_p' || to_char(now(), 'YYYYMM')),
                                    ('public', 'notifications_p' || to_char(now(), 'YYYYMM')))),
  4,
  'current-month partitions exist for all partitioned tables');

select * from finish();
rollback;
