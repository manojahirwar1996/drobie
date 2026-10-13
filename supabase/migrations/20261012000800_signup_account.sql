-- =============================================================================
-- drobie · 0800 · Signup bootstrap and account RPCs
-- On every new auth user: profile, personal household (owner), a starter set
-- of places, and the default plan's entitlement grant. FRS 3.1, Step 3.
-- =============================================================================

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_household uuid;
  v_home uuid;
  v_name text := left(nullif(trim(coalesce(new.raw_user_meta_data ->> 'name',
                                           new.raw_user_meta_data ->> 'full_name', '')), ''), 60);
  v_country text := 'IN';
  c record;
begin
  select * into c from public.countries where code = v_country;

  insert into public.profiles (id, display_name, country, locale, timezone, currency)
  values (new.id, v_name, c.code, c.default_locale, c.default_timezone, c.currency);

  insert into public.households (name, kind, owner_user_id)
  values ('My home', 'personal', new.id)
  returning id into v_household;

  insert into public.household_members (household_id, user_id, role)
  values (v_household, new.id, 'owner');

  insert into public.places (household_id, name, kind, created_by, sort_order)
  values (v_household, 'Home', 'home', new.id, 0)
  returning id into v_home;

  insert into public.places (household_id, parent_id, name, kind, created_by, sort_order)
  values (v_household, v_home, 'Wardrobe', 'storage', new.id, 1),
         (v_household, v_home, 'Drawer', 'storage', new.id, 2),
         (v_household, v_home, 'Shoe rack', 'storage', new.id, 3);

  insert into public.entitlement_grants (user_id, plan_id, source, note)
  select new.id, p.id, 'signup', 'default plan at signup'
  from public.plans p where p.is_default;

  perform private.emit('account.created', 'profile', new.id, '{}'::jsonb);
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- 18+ confirmation (BRD guardrail). Idempotent.
create or replace function public.confirm_adult()
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  update public.profiles set adult_confirmed_at = coalesce(adult_confirmed_at, now())
  where id = auth.uid()
  returning adult_confirmed_at into v_at;
  return v_at;
end $$;

-- Used by the shared function middleware and by RPCs that need an adult user.
create or replace function private.is_active_adult(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.profiles
                 where id = p_user and status = 'active' and adult_confirmed_at is not null and deleted_at is null)
$$;

grant execute on function public.confirm_adult() to authenticated;
grant execute on function private.is_active_adult(uuid) to authenticated, service_role;
