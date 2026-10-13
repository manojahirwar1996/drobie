-- =============================================================================
-- drobie · 0200 · Identity, households, places, sharing grants, RLS helpers
-- PLATFORM_ARCHITECTURE §3.1, §3.2, §3.9, §4
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Reference: countries (FK target for profiles, prices, tax). Launch: IN only.
-- ---------------------------------------------------------------------------
create table public.countries (
  code             public.country_code primary key,
  name             text not null,
  currency         public.currency_code not null,
  default_locale   text not null,
  default_timezone text not null,
  active           boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create trigger countries_updated_at before update on public.countries
  for each row execute function private.tg_set_updated_at();

insert into public.countries (code, name, currency, default_locale, default_timezone, active)
values ('IN', 'India', 'INR', 'en-IN', 'Asia/Kolkata', true);

-- ---------------------------------------------------------------------------
-- profiles: one per auth user. No plan column (plans come from entitlements).
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  display_name        text check (char_length(display_name) between 1 and 60),
  handle              text check (handle ~ '^[a-z0-9_.]{3,30}$'),
  country             public.country_code not null default 'IN' references public.countries (code),
  city                text check (char_length(city) <= 80),
  locale              text not null default 'en-IN' check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  timezone            text not null default 'Asia/Kolkata',
  currency            public.currency_code not null default 'INR',
  morning_time        time not null default '07:30',
  vibe                text check (char_length(vibe) <= 40),
  settings            jsonb not null default '{}'::jsonb check (jsonb_typeof(settings) = 'object'),
  avatar_media_id     uuid,  -- FK added in 0300 (media_assets)
  adult_confirmed_at  timestamptz,
  status              text not null default 'active' check (status in ('active', 'suspended', 'banned', 'deleted')),
  status_reason       text,
  inbound_email_token text not null unique default lower(encode(extensions.gen_random_bytes(10), 'hex')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz
);
comment on table public.profiles is 'One row per auth user. Protected columns (status, adult_confirmed_at, inbound_email_token) are writable only by server functions.';
create unique index profiles_handle_key on public.profiles (lower(handle)) where handle is not null;
create index profiles_country_idx on public.profiles (country);

create trigger profiles_updated_at before update on public.profiles
  for each row execute function private.tg_set_updated_at();
create trigger profiles_immutable before update on public.profiles
  for each row execute function private.tg_immutable_columns('id', 'created_at');

create or replace function private.tg_validate_timezone()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise exception 'unknown timezone %', new.timezone using errcode = '22023';
  end if;
  return new;
end $$;
create trigger profiles_timezone before insert or update of timezone on public.profiles
  for each row execute function private.tg_validate_timezone();

-- ---------------------------------------------------------------------------
-- consents: versioned, append-only history
-- ---------------------------------------------------------------------------
create table public.consents (
  id           uuid primary key default private.uuid_v7(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  consent_type text not null check (consent_type in
                 ('terms', 'privacy', 'email_import', 'gallery', 'calendar', 'measurements', 'marketing', 'avatar', 'location')),
  version      text not null check (char_length(version) between 1 and 20),
  granted      boolean not null,
  source       text not null default 'app' check (source in ('app', 'web', 'support', 'system')),
  recorded_at  timestamptz not null default now()
);
create index consents_user_type_idx on public.consents (user_id, consent_type, recorded_at desc);
create trigger consents_append_only before update or delete on public.consents
  for each row when (current_setting('drobie.purging', true) is distinct from 'on')
  execute function private.tg_append_only();

create or replace function private.has_consent(p_user uuid, p_type text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select c.granted from public.consents c
    where c.user_id = p_user and c.consent_type = p_type
    order by c.recorded_at desc, c.id desc
    limit 1), false)
$$;

-- ---------------------------------------------------------------------------
-- device_tokens
-- ---------------------------------------------------------------------------
create table public.device_tokens (
  id           uuid primary key default private.uuid_v7(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  token        text not null unique check (char_length(token) between 10 and 400),
  platform     text not null check (platform in ('ios', 'android', 'web')),
  app_version  text,
  last_seen_at timestamptz not null default now(),
  disabled_at  timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);
create trigger device_tokens_updated_at before update on public.device_tokens
  for each row execute function private.tg_set_updated_at();
create trigger device_tokens_immutable before update on public.device_tokens
  for each row execute function private.tg_immutable_columns('user_id');

-- ---------------------------------------------------------------------------
-- admin_users: staff roles (MFA enforced in has_admin_role)
-- ---------------------------------------------------------------------------
create table public.admin_users (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role       public.admin_role not null,
  active     boolean not null default true,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, role)
);
create index admin_users_created_by_idx on public.admin_users (created_by);
create trigger admin_users_updated_at before update on public.admin_users
  for each row execute function private.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- households (replace "homes"): every user gets a personal one at signup.
-- A user's several homes (flat, parents', hostel, suitcase) are top-level
-- places of kind 'home' inside their household (DECISIONS D-005).
-- ---------------------------------------------------------------------------
create table public.households (
  id            uuid primary key default private.uuid_v7(),
  name          text not null check (char_length(name) between 1 and 60),
  kind          text not null default 'personal' check (kind in ('personal', 'shared')),
  owner_user_id uuid not null references public.profiles (id) on delete cascade,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index households_owner_idx on public.households (owner_user_id);
create unique index households_one_personal on public.households (owner_user_id) where kind = 'personal';
create trigger households_updated_at before update on public.households
  for each row execute function private.tg_set_updated_at();
create trigger households_immutable before update on public.households
  for each row execute function private.tg_immutable_columns('owner_user_id', 'kind');

create table public.household_members (
  household_id uuid not null references public.households (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  role         public.household_role not null default 'member',
  invited_by   uuid references public.profiles (id) on delete set null,
  joined_at    timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (household_id, user_id)
);
create index household_members_user_idx on public.household_members (user_id, household_id);
create index household_members_invited_by_idx on public.household_members (invited_by);
create trigger household_members_updated_at before update on public.household_members
  for each row execute function private.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- places: nested locations (home → room → wardrobe → shelf → box), depth ≤ 6
-- ---------------------------------------------------------------------------
create table public.places (
  id           uuid primary key default private.uuid_v7(),
  household_id uuid not null references public.households (id) on delete cascade,
  parent_id    uuid references public.places (id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 60),
  kind         text not null default 'storage' check (kind in
                 ('home', 'room', 'storage', 'shelf', 'box', 'suitcase', 'bag', 'vehicle', 'other')),
  icon         text,
  sort_order   int not null default 0,
  depth        smallint not null default 1 check (depth between 1 and 6),
  created_by   uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index places_household_idx on public.places (household_id, updated_at);
create index places_parent_idx on public.places (parent_id);
create index places_created_by_idx on public.places (created_by);
create unique index places_unique_name_per_parent on public.places
  (household_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name))
  where deleted_at is null;

create trigger places_updated_at before update on public.places
  for each row execute function private.tg_set_updated_at();
create trigger places_immutable before update on public.places
  for each row execute function private.tg_immutable_columns('household_id', 'created_by');

create or replace function private.tg_places_tree()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  p_household uuid;
  p_depth smallint;
  max_child_depth int;
begin
  if new.parent_id is null then
    new.depth := 1;
  else
    if new.parent_id = new.id then
      raise exception 'a place cannot be its own parent' using errcode = '23514';
    end if;
    select household_id, depth into p_household, p_depth from public.places where id = new.parent_id;
    if p_household is distinct from new.household_id then
      raise exception 'parent place must be in the same household' using errcode = '23514';
    end if;
    if tg_op = 'UPDATE' and exists (
      with recursive anc as (
        select id, parent_id from public.places where id = new.parent_id
        union all
        select p.id, p.parent_id from public.places p join anc on p.id = anc.parent_id
      )
      select 1 from anc where anc.id = new.id
    ) then
      raise exception 'moving this place would create a cycle' using errcode = '23514';
    end if;
    new.depth := p_depth + 1;
  end if;
  if new.depth > 6 then
    raise exception 'places can be nested at most 6 levels deep' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and new.depth <> old.depth then
    -- re-depth the subtree; deepest descendant must still fit
    with recursive sub as (
      select id, 0 as rel from public.places where parent_id = new.id
      union all
      select p.id, sub.rel + 1 from public.places p join sub on p.parent_id = sub.id
    ) select coalesce(max(rel) + 1, 0) into max_child_depth from sub;
    if new.depth + max_child_depth > 6 then
      raise exception 'places can be nested at most 6 levels deep' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
create trigger places_tree before insert or update of parent_id on public.places
  for each row execute function private.tg_places_tree();

create or replace function private.tg_places_redepth_children()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.depth is distinct from old.depth then
    update public.places set parent_id = parent_id where parent_id = new.id;  -- re-fires places_tree
  end if;
  return null;
end $$;
create trigger places_redepth after update on public.places
  for each row when (old.depth is distinct from new.depth)
  execute function private.tg_places_redepth_children();

-- ---------------------------------------------------------------------------
-- tags (seam): physical QR/NFC labels bound to a place or an item
-- ---------------------------------------------------------------------------
create table public.tags (
  id           uuid primary key default private.uuid_v7(),
  code         text not null unique check (code ~ '^[A-Z2-9]{8,16}$'),
  kind         text not null check (kind in ('qr', 'nfc')),
  batch_id     uuid,           -- FK to tag_batches when that table arrives (Later)
  household_id uuid references public.households (id) on delete set null,
  place_id     uuid references public.places (id) on delete set null,
  item_id      uuid,           -- FK added in 0400 (items)
  claimed_by   uuid references public.profiles (id) on delete set null,
  claimed_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (num_nonnulls(place_id, item_id) <= 1),
  check ((claimed_by is null) = (claimed_at is null))
);
create index tags_household_idx on public.tags (household_id);
create index tags_place_idx on public.tags (place_id);
create index tags_item_idx on public.tags (item_id);
create index tags_claimed_by_idx on public.tags (claimed_by);
create trigger tags_updated_at before update on public.tags
  for each row execute function private.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- access_grants: the one sharing model (support now; friends, family,
-- stylists later). Sharing is a grant, never a copy.
-- ---------------------------------------------------------------------------
create table public.access_grants (
  id                   uuid primary key default private.uuid_v7(),
  grantor_user_id      uuid not null references public.profiles (id) on delete cascade,
  grantee_user_id      uuid references public.profiles (id) on delete cascade,
  grantee_circle_id    uuid,   -- FK when circles arrive (v1.1)
  grantee_org_id       uuid,   -- FK when organizations arrive (v1.2)
  grantee_household_id uuid references public.households (id) on delete cascade,
  scope                public.grant_scope not null,
  resource_item_id     uuid,   -- FK added in 0400
  resource_category_id uuid,   -- FK added in 0400
  resource_place_id    uuid references public.places (id) on delete cascade,
  purpose              public.grant_purpose not null,
  booking_id           uuid,   -- FK when bookings arrive (v1.2)
  note                 text check (char_length(note) <= 200),
  created_at           timestamptz not null default now(),
  expires_at           timestamptz,
  revoked_at           timestamptz,
  revoked_by           uuid references public.profiles (id) on delete set null,
  updated_at           timestamptz not null default now(),
  constraint access_grants_one_grantee
    check (num_nonnulls(grantee_user_id, grantee_circle_id, grantee_org_id, grantee_household_id) = 1),
  constraint access_grants_one_resource
    check (num_nonnulls(resource_item_id, resource_category_id, resource_place_id) <= 1),
  constraint access_grants_not_self check (grantee_user_id is distinct from grantor_user_id),
  constraint access_grants_expiry_after_start check (expires_at is null or expires_at > created_at),
  constraint access_grants_timeboxed
    check (purpose not in ('support', 'consultation') or expires_at is not null),
  constraint access_grants_support_scope
    check ((scope = 'support_view') = (purpose = 'support'))
);
comment on table public.access_grants is 'Time-limited, revocable access to a user''s data for another user, household, circle or organisation.';
create index access_grants_grantee_user_idx on public.access_grants (grantee_user_id, grantor_user_id) where revoked_at is null;
create index access_grants_grantee_household_idx on public.access_grants (grantee_household_id) where revoked_at is null;
create index access_grants_grantor_idx on public.access_grants (grantor_user_id, created_at desc);
create index access_grants_expires_idx on public.access_grants (expires_at) where revoked_at is null;
create index access_grants_resource_place_idx on public.access_grants (resource_place_id);
create index access_grants_revoked_by_idx on public.access_grants (revoked_by);
create trigger access_grants_updated_at before update on public.access_grants
  for each row execute function private.tg_set_updated_at();
create trigger access_grants_immutable before update on public.access_grants
  for each row execute function private.tg_immutable_columns(
    'grantor_user_id', 'grantee_user_id', 'grantee_circle_id', 'grantee_org_id', 'grantee_household_id',
    'scope', 'resource_item_id', 'resource_category_id', 'resource_place_id', 'purpose', 'created_at');

-- Grants can be shortened or revoked, never extended or un-revoked by a client.
create or replace function private.tg_access_grants_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin') then
    return new;
  end if;
  if old.revoked_at is not null and new.revoked_at is distinct from old.revoked_at then
    raise exception 'a revoked grant cannot be changed' using errcode = '42501';
  end if;
  if new.expires_at is distinct from old.expires_at
     and (new.expires_at is null or (old.expires_at is not null and new.expires_at > old.expires_at)) then
    raise exception 'a grant can only be shortened, not extended' using errcode = '42501';
  end if;
  if new.revoked_at is not null and old.revoked_at is null then
    new.revoked_by := auth.uid();
  end if;
  return new;
end $$;
create trigger access_grants_guard before update on public.access_grants
  for each row execute function private.tg_access_grants_guard();

-- ---------------------------------------------------------------------------
-- body_profiles (seam, SENSITIVE): owner only, consent required
-- ---------------------------------------------------------------------------
create table public.body_profiles (
  user_id         uuid primary key references public.profiles (id) on delete cascade,
  height_cm       numeric(5,1) check (height_cm between 50 and 250),
  measurements    jsonb not null default '{}'::jsonb check (jsonb_typeof(measurements) = 'object'),
  size_passport   jsonb not null default '{}'::jsonb check (jsonb_typeof(size_passport) = 'object'),
  fit_preferences jsonb not null default '{}'::jsonb check (jsonb_typeof(fit_preferences) = 'object'),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
comment on table public.body_profiles is 'SENSITIVE. Requires the measurements consent. Never included in a grant unless the scope is measurements_read.';
create trigger body_profiles_updated_at before update on public.body_profiles
  for each row execute function private.tg_set_updated_at();

-- =============================================================================
-- RLS helper functions (PLATFORM_ARCHITECTURE §4)
-- SECURITY DEFINER so they can read membership/grant tables regardless of the
-- caller's own policies; search_path = '' and fully-qualified names.
-- =============================================================================
create or replace function private.uid()
returns uuid
language sql
stable
set search_path = ''
as $$ select auth.uid() $$;

create or replace function private.is_household_member(
  p_household uuid,
  p_min_role public.household_role default 'viewer'
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.household_members m
    where m.household_id = p_household
      and m.user_id = auth.uid()
      and m.role >= p_min_role
  )
$$;

-- Owner of a household (used to apply user-level grants to household data).
create or replace function private.household_owner(p_household uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$ select owner_user_id from public.households where id = p_household $$;

create or replace function private.has_admin_role(p_role public.admin_role)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
     and exists (
       select 1 from public.admin_users a
       where a.user_id = auth.uid()
         and a.active
         and (
           a.role = p_role
           or a.role = 'super_admin'
           or (a.role = 'admin' and p_role in ('moderator', 'support', 'analyst'))
         )
     )
$$;

-- Blocking arrives with social (v1.1). The seam exists so every policy that
-- must respect blocks already calls it.
create or replace function private.is_blocked(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select false $$;

create or replace function private.has_access(
  p_owner    uuid,
  p_scope    public.grant_scope,
  p_item     uuid default null,
  p_category uuid default null,
  p_place    uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_scopes public.grant_scope[];
begin
  if v_caller is null or p_owner is null then
    return false;
  end if;
  if v_caller = p_owner then
    return true;
  end if;
  if private.is_blocked(p_owner, v_caller) then
    return false;
  end if;

  -- scope implication: a broader grant satisfies a narrower check
  v_scopes := case p_scope
    when 'item_read'   then array['item_read', 'closet_read', 'item_borrow', 'support_view']::public.grant_scope[]
    when 'places_read' then array['places_read', 'closet_read', 'support_view']::public.grant_scope[]
    when 'closet_read' then array['closet_read', 'support_view']::public.grant_scope[]
    else array[p_scope]
  end;

  return exists (
    select 1
    from public.access_grants g
    where g.grantor_user_id = p_owner
      and g.revoked_at is null
      and (g.expires_at is null or g.expires_at > now())
      and g.scope = any (v_scopes)
      and (
        g.grantee_user_id = v_caller
        or (g.grantee_household_id is not null and exists (
              select 1 from public.household_members m
              where m.household_id = g.grantee_household_id and m.user_id = v_caller))
        -- grantee_circle_id: v1.1, grantee_org_id: v1.2 (not matched yet)
      )
      and (g.scope <> 'support_view' or private.has_admin_role('support'))
      and (g.resource_item_id is null or g.resource_item_id = p_item)
      and (g.resource_category_id is null or g.resource_category_id = p_category)
      and (g.resource_place_id is null or (p_place is not null and exists (
            with recursive anc as (
              select pl.id, pl.parent_id from public.places pl where pl.id = p_place
              union all
              select pl.id, pl.parent_id from public.places pl join anc on pl.id = anc.parent_id
            )
            select 1 from anc where anc.id = g.resource_place_id)))
  );
end $$;
comment on function private.has_access is
  'True if the caller is the owner, or holds an active, unexpired, unrevoked grant from the owner whose scope (or a broader one) and resource filter match.';

grant execute on function
  private.uid(),
  private.is_household_member(uuid, public.household_role),
  private.household_owner(uuid),
  private.has_admin_role(public.admin_role),
  private.is_blocked(uuid, uuid),
  private.has_access(uuid, public.grant_scope, uuid, uuid, uuid),
  private.has_consent(uuid, text)
to authenticated, service_role;
