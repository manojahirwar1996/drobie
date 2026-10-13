-- Test helpers (committed, so later test files can use them). Mirrors the
-- usual Supabase pattern: impersonate a user by setting the role and JWT claims.
create extension if not exists pgtap with schema extensions;
-- migrations revoke PUBLIC EXECUTE on new functions globally; pgTAP's
-- assertions must stay callable while a test impersonates a client role
grant execute on all functions in schema extensions to anon, authenticated, service_role;

create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

create or replace function tests.create_user(p_email text, p_adult boolean default true)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', p_email,
          '{"provider":"email"}', jsonb_build_object('name', split_part(p_email, '@', 1)), now(), now());
  if p_adult then
    update public.profiles set adult_confirmed_at = now() where id = v_id;
  end if;
  return v_id;
end $$;

create or replace function tests.authenticate_as(p_user uuid, p_aal text default 'aal1')
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated', 'aal', p_aal)::text, true);
end $$;

create or replace function tests.authenticate_as_anon()
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end $$;

create or replace function tests.authenticate_as_service()
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
end $$;

create or replace function tests.clear_authentication()
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Personal household / a named place of a user (setup convenience)
create or replace function tests.household_of(p_user uuid)
returns uuid
language sql
security definer
set search_path = ''
as $$ select id from public.households where owner_user_id = p_user and kind = 'personal' $$;

create or replace function tests.place_of(p_user uuid, p_name text default 'Wardrobe')
returns uuid
language sql
security definer
set search_path = ''
as $$
  select p.id from public.places p join public.households h on h.id = p.household_id
  where h.owner_user_id = p_user and p.name = p_name limit 1
$$;

grant execute on all functions in schema tests to anon, authenticated, service_role;

select plan(1);
select ok(true, 'test helpers installed');
select * from finish();
