-- =============================================================================
-- drobie · 0400 · Closet: items, item media, embeddings, history, wears, beauty
-- PLATFORM_ARCHITECTURE §3.3, FRS 3.2–3.4
-- =============================================================================

create or replace function private.immutable_array_to_string(text[], text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$ select array_to_string($1, $2) $$;
-- used by the items.search generated column, so writers need EXECUTE
grant execute on function private.immutable_array_to_string(text[], text) to authenticated, service_role;

create table public.items (
  id               uuid primary key default private.uuid_v7(),
  owner_user_id    uuid not null references public.profiles (id) on delete cascade,
  household_id     uuid not null references public.households (id) on delete restrict,
  visibility       public.item_visibility not null default 'private',
  kind             text not null default 'apparel' check (kind in
                     ('apparel', 'footwear', 'accessory', 'jewellery', 'bag', 'beauty', 'document', 'gadget', 'home', 'other')),
  category_id      uuid references public.categories (id) on delete set null,
  product_id       uuid references public.products (id) on delete set null,
  brand_id         uuid references public.brands (id) on delete set null,

  name             text not null check (char_length(name) between 1 and 120),
  brand            text check (char_length(brand) <= 80),
  size             text check (char_length(size) <= 30),
  colours          text[] not null default '{}' check (cardinality(colours) <= 6),
  pattern          text check (char_length(pattern) <= 30),
  fabric           text check (char_length(fabric) <= 40),
  seasons          text[] not null default '{}' check (seasons <@ array['summer', 'monsoon', 'winter', 'all']),
  occasions        text[] not null default '{}' check (cardinality(occasions) <= 12),
  own_tags         text[] not null default '{}' check (cardinality(own_tags) <= 20),
  notes            text check (char_length(notes) <= 1000),
  attributes       jsonb not null default '{}'::jsonb check (jsonb_typeof(attributes) = 'object'),

  price_minor      bigint check (price_minor >= 0),
  currency         public.currency_code not null default 'INR',
  purchased_on     date,
  return_by        date,
  warranty_until   date,

  place_id         uuid references public.places (id) on delete set null,
  state            public.item_state not null default 'clean',
  state_changed_at timestamptz not null default now(),
  holder_name      text check (char_length(holder_name) <= 80),   -- "lent to …" (free text until connections exist)
  holder_user_id   uuid references public.profiles (id) on delete set null,
  due_back_on      date,

  wear_count       int not null default 0 check (wear_count >= 0),
  wears_since_wash int not null default 0 check (wears_since_wash >= 0),
  last_worn_at     timestamptz,

  confidence       numeric(4,3) check (confidence between 0 and 1),
  tag_source       text not null default 'user' check (tag_source in ('phone', 'template', 'link', 'barcode', 'embedder', 'ai', 'user')),
  source           text not null default 'manual' check (source in
                     ('camera', 'gallery', 'section_photo', 'email', 'link', 'barcode', 'voice', 'manual', 'bulk', 'import')),
  is_stub          boolean not null default false,
  user_confirmed   boolean not null default false,

  search           tsvector generated always as (
                     to_tsvector('simple',
                       coalesce(name, '') || ' ' || coalesce(brand, '') || ' ' || coalesce(size, '') || ' ' ||
                       coalesce(pattern, '') || ' ' || coalesce(fabric, '') || ' ' ||
                       private.immutable_array_to_string(colours, ' ') || ' ' ||
                       private.immutable_array_to_string(occasions, ' ') || ' ' ||
                       private.immutable_array_to_string(own_tags, ' '))
                   ) stored,

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,

  constraint items_holder_only_when_lent check (state = 'lent' or (holder_name is null and holder_user_id is null and due_back_on is null)),
  constraint items_return_after_purchase check (return_by is null or purchased_on is null or return_by >= purchased_on)
);
comment on table public.items is 'Everything a user owns. Typed core columns + attributes validated against the category attribute_schema. Soft delete via deleted_at (synced to devices).';

-- hot paths: closet sync, where-is, filters, household reads
create index items_owner_sync_idx     on public.items (owner_user_id, updated_at, id);
create index items_owner_state_idx    on public.items (owner_user_id, state) where deleted_at is null;
create index items_owner_category_idx on public.items (owner_user_id, category_id) where deleted_at is null;
create index items_owner_place_idx    on public.items (owner_user_id, place_id) where deleted_at is null;
create index items_household_idx      on public.items (household_id, visibility) where deleted_at is null;
create index items_place_idx          on public.items (place_id);
create index items_category_idx       on public.items (category_id);
create index items_product_idx        on public.items (product_id);
create index items_brand_idx          on public.items (brand_id);
create index items_holder_user_idx    on public.items (holder_user_id);
create index items_return_by_idx      on public.items (return_by) where return_by is not null and deleted_at is null;
create index items_search_idx         on public.items using gin (search);
create index items_name_trgm          on public.items using gin (lower(name) extensions.gin_trgm_ops);
create index items_brand_trgm         on public.items using gin (lower(brand) extensions.gin_trgm_ops);

create trigger items_updated_at before update on public.items
  for each row execute function private.tg_set_updated_at();
create trigger items_immutable before update on public.items
  for each row execute function private.tg_immutable_columns('owner_user_id', 'created_at');

-- Integrity: household membership, place in same household, attribute schema,
-- state bookkeeping. SECURITY DEFINER because it reads other tables the caller
-- may not see directly; it never widens what the caller can write.
create or replace function private.tg_items_before()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schema jsonb;
  v_errors text[];
begin
  if new.household_id is null then
    select h.id into new.household_id from public.households h
    where h.owner_user_id = new.owner_user_id and h.kind = 'personal';
  end if;

  if (tg_op = 'INSERT' or new.household_id is distinct from old.household_id)
     and not exists (select 1 from public.household_members m
                     where m.household_id = new.household_id and m.user_id = new.owner_user_id
                       and m.role >= 'member') then
    raise exception 'owner is not a member of this household' using errcode = '42501';
  end if;

  if new.place_id is not null
     and (tg_op = 'INSERT' or new.place_id is distinct from old.place_id or new.household_id is distinct from old.household_id)
     and not exists (select 1 from public.places p
                     where p.id = new.place_id and p.household_id = new.household_id and p.deleted_at is null) then
    raise exception 'place must belong to the item''s household' using errcode = '23514';
  end if;

  if new.category_id is not null
     and (tg_op = 'INSERT' or new.attributes is distinct from old.attributes or new.category_id is distinct from old.category_id) then
    select c.attribute_schema into v_schema from public.categories c where c.id = new.category_id;
    v_errors := private.jsonschema_errors(v_schema, new.attributes);
    if cardinality(v_errors) > 0 then
      raise exception 'invalid attributes: %', array_to_string(v_errors, '; ') using errcode = '23514';
    end if;
  end if;

  if tg_op = 'UPDATE' and new.state is distinct from old.state then
    new.state_changed_at := now();
    if new.state = 'clean' and old.state in ('in_wash', 'at_dhobi') then
      new.wears_since_wash := 0;
    end if;
    if new.state <> 'lent' then
      new.holder_name := null;
      new.holder_user_id := null;
      new.due_back_on := null;
    end if;
  end if;
  return new;
end $$;
create trigger items_before before insert or update on public.items
  for each row execute function private.tg_items_before();

-- ---------------------------------------------------------------------------
-- item_events: append-only history ("where is it", "who has it")
-- ---------------------------------------------------------------------------
create table public.item_events (
  id            uuid primary key default private.uuid_v7(),
  item_id       uuid not null references public.items (id) on delete cascade,
  owner_user_id uuid not null references public.profiles (id) on delete cascade,
  actor_user_id uuid references public.profiles (id) on delete set null,
  type          text not null check (type in
                  ('created', 'state_changed', 'place_changed', 'holder_changed', 'edited', 'deleted', 'restored', 'owner_changed')),
  from_state    public.item_state,
  to_state      public.item_state,
  from_place_id uuid references public.places (id) on delete set null,
  to_place_id   uuid references public.places (id) on delete set null,
  holder_name   text,
  payload       jsonb not null default '{}'::jsonb,
  occurred_at   timestamptz not null default now()
);
create index item_events_item_idx  on public.item_events (item_id, occurred_at desc);
create index item_events_owner_idx on public.item_events (owner_user_id, occurred_at desc);
create index item_events_actor_idx on public.item_events (actor_user_id);
create index item_events_from_place_idx on public.item_events (from_place_id);
create index item_events_to_place_idx on public.item_events (to_place_id);
create trigger item_events_append_only before update or delete on public.item_events
  for each row when (current_setting('drobie.purging', true) is distinct from 'on')
  execute function private.tg_append_only();

create or replace function private.tg_items_after()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    insert into public.item_events (item_id, owner_user_id, actor_user_id, type, to_state, to_place_id)
    values (new.id, new.owner_user_id, v_actor, 'created', new.state, new.place_id);
    perform private.emit('item.created', 'item', new.id, jsonb_build_object('owner_user_id', new.owner_user_id));
    return null;
  end if;

  if new.state is distinct from old.state then
    insert into public.item_events (item_id, owner_user_id, actor_user_id, type, from_state, to_state, holder_name)
    values (new.id, new.owner_user_id, v_actor, 'state_changed', old.state, new.state, new.holder_name);
  end if;
  if new.place_id is distinct from old.place_id then
    insert into public.item_events (item_id, owner_user_id, actor_user_id, type, from_place_id, to_place_id)
    values (new.id, new.owner_user_id, v_actor, 'place_changed', old.place_id, new.place_id);
  end if;
  if new.state = old.state and new.state = 'lent'
     and (new.holder_name is distinct from old.holder_name or new.holder_user_id is distinct from old.holder_user_id) then
    insert into public.item_events (item_id, owner_user_id, actor_user_id, type, holder_name)
    values (new.id, new.owner_user_id, v_actor, 'holder_changed', new.holder_name);
  end if;
  if new.deleted_at is not null and old.deleted_at is null then
    insert into public.item_events (item_id, owner_user_id, actor_user_id, type)
    values (new.id, new.owner_user_id, v_actor, 'deleted');
    perform private.emit('item.deleted', 'item', new.id, jsonb_build_object('owner_user_id', new.owner_user_id));
  elsif new.deleted_at is null and old.deleted_at is not null then
    insert into public.item_events (item_id, owner_user_id, actor_user_id, type)
    values (new.id, new.owner_user_id, v_actor, 'restored');
  end if;

  if (new.name, new.brand, new.colours, new.category_id, new.occasions, new.own_tags, new.state, new.place_id)
     is distinct from (old.name, old.brand, old.colours, old.category_id, old.occasions, old.own_tags, old.state, old.place_id)
     and new.deleted_at is null then
    perform private.emit('item.updated', 'item', new.id, jsonb_build_object('owner_user_id', new.owner_user_id));
  end if;
  return null;
end $$;
create trigger items_after after insert or update on public.items
  for each row execute function private.tg_items_after();

-- ---------------------------------------------------------------------------
-- item_media: item ↔ media_assets (master, cutout, label, receipt, extra)
-- ---------------------------------------------------------------------------
create table public.item_media (
  id         uuid primary key default private.uuid_v7(),
  item_id    uuid not null references public.items (id) on delete cascade,
  asset_id   uuid not null references public.media_assets (id) on delete cascade,
  role       text not null check (role in ('master', 'cutout', 'label', 'receipt', 'extra')),
  position   smallint not null default 0 check (position between 0 and 50),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (item_id, asset_id)
);
create unique index item_media_one_master on public.item_media (item_id) where role = 'master';
create unique index item_media_one_cutout on public.item_media (item_id) where role = 'cutout';
create index item_media_asset_idx on public.item_media (asset_id);
create trigger item_media_updated_at before update on public.item_media
  for each row execute function private.tg_set_updated_at();

create or replace function private.tg_item_media_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.items i join public.media_assets a on a.id = new.asset_id
    where i.id = new.item_id and a.owner_user_id = i.owner_user_id
      and a.purpose in ('item_photo', 'receipt')
  ) then
    raise exception 'media must belong to the item owner and be an item photo or receipt' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger item_media_owner before insert or update on public.item_media
  for each row execute function private.tg_item_media_owner();

-- ---------------------------------------------------------------------------
-- item_embeddings: model + version so a new model can run side by side
-- ---------------------------------------------------------------------------
create table public.item_embeddings (
  item_id       uuid not null references public.items (id) on delete cascade,
  owner_user_id uuid not null references public.profiles (id) on delete cascade,
  model         text not null,
  model_version text not null,
  embedding     extensions.vector(768) not null,
  created_at    timestamptz not null default now(),
  primary key (item_id, model, model_version)
);
comment on table public.item_embeddings is 'FashionSigLIP (768-d) today. A model with a different dimension gets its own table or column (additive).';
create index item_embeddings_owner_idx on public.item_embeddings (owner_user_id, model, model_version);
create index item_embeddings_hnsw on public.item_embeddings using hnsw (embedding extensions.vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- wear_logs, wear_log_items: what was worn when; counters by trigger
-- ---------------------------------------------------------------------------
create table public.wear_logs (
  id             uuid primary key default private.uuid_v7(),
  owner_user_id  uuid not null references public.profiles (id) on delete cascade,
  worn_on        date not null,
  occasion       text check (char_length(occasion) <= 40),
  event_name     text check (char_length(event_name) <= 80),
  with_people    text[] not null default '{}' check (cardinality(with_people) <= 20),
  notes          text check (char_length(notes) <= 500),
  look_id        uuid,   -- FK added with looks (Step 9)
  weather        jsonb,
  media_asset_id uuid references public.media_assets (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);
create index wear_logs_owner_idx on public.wear_logs (owner_user_id, worn_on desc);
create index wear_logs_owner_sync_idx on public.wear_logs (owner_user_id, updated_at, id);
create index wear_logs_media_idx on public.wear_logs (media_asset_id);
create trigger wear_logs_updated_at before update on public.wear_logs
  for each row execute function private.tg_set_updated_at();
create trigger wear_logs_immutable before update on public.wear_logs
  for each row execute function private.tg_immutable_columns('owner_user_id');

create table public.wear_log_items (
  wear_log_id uuid not null references public.wear_logs (id) on delete cascade,
  item_id     uuid not null references public.items (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (wear_log_id, item_id)
);
create index wear_log_items_item_idx on public.wear_log_items (item_id);

create or replace function private.tg_wear_log_items_counters()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_worn date;
begin
  if tg_op = 'INSERT' then
    select owner_user_id, worn_on into v_owner, v_worn from public.wear_logs where id = new.wear_log_id;
    if not exists (select 1 from public.items where id = new.item_id and owner_user_id = v_owner) then
      raise exception 'item does not belong to the wear log owner' using errcode = '42501';
    end if;
    update public.items
       set wear_count = wear_count + 1,
           wears_since_wash = wears_since_wash + 1,
           last_worn_at = greatest(last_worn_at, v_worn::timestamptz)
     where id = new.item_id;
    return new;
  else
    update public.items i
       set wear_count = greatest(i.wear_count - 1, 0),
           wears_since_wash = greatest(i.wears_since_wash - 1, 0),
           last_worn_at = (select max(w.worn_on)::timestamptz
                             from public.wear_log_items wi join public.wear_logs w on w.id = wi.wear_log_id
                            where wi.item_id = old.item_id and w.deleted_at is null)
     where i.id = old.item_id;
    return old;
  end if;
end $$;
create trigger wear_log_items_counters_ins before insert on public.wear_log_items
  for each row execute function private.tg_wear_log_items_counters();
create trigger wear_log_items_counters_del after delete on public.wear_log_items
  for each row execute function private.tg_wear_log_items_counters();

-- Soft-deleting (or restoring) a wear log adjusts the counters of its items.
create or replace function private.tg_wear_logs_soft_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delta int := case when new.deleted_at is not null then -1 else 1 end;
begin
  update public.items i
     set wear_count = greatest(i.wear_count + v_delta, 0),
         wears_since_wash = greatest(i.wears_since_wash + v_delta, 0),
         last_worn_at = (select max(w.worn_on)::timestamptz
                           from public.wear_log_items wi join public.wear_logs w on w.id = wi.wear_log_id
                          where wi.item_id = i.id and w.deleted_at is null)
   where i.id in (select item_id from public.wear_log_items where wear_log_id = new.id);
  return null;
end $$;
create trigger wear_logs_soft_delete after update on public.wear_logs
  for each row when ((old.deleted_at is null) <> (new.deleted_at is null))
  execute function private.tg_wear_logs_soft_delete();

-- ---------------------------------------------------------------------------
-- beauty_details
-- ---------------------------------------------------------------------------
create table public.beauty_details (
  item_id      uuid primary key references public.items (id) on delete cascade,
  opened_on    date,
  pao_months   smallint check (pao_months between 1 and 60),
  expires_on   date,
  barcode      text check (barcode ~ '^[0-9]{8,14}$'),
  shade        text check (char_length(shade) <= 40),
  spf          smallint check (spf between 0 and 100),
  skin_types   text[] not null default '{}',
  effective_expiry date generated always as (
    least(expires_on, (opened_on + make_interval(months => pao_months::int))::date)
  ) stored,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index beauty_details_expiry_idx on public.beauty_details (effective_expiry) where effective_expiry is not null;
create trigger beauty_details_updated_at before update on public.beauty_details
  for each row execute function private.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- Deferred foreign keys from 0200
-- ---------------------------------------------------------------------------
alter table public.tags
  add constraint tags_item_fk foreign key (item_id) references public.items (id) on delete set null;
alter table public.access_grants
  add constraint access_grants_resource_item_fk foreign key (resource_item_id) references public.items (id) on delete cascade,
  add constraint access_grants_resource_category_fk foreign key (resource_category_id) references public.categories (id) on delete cascade;
create index access_grants_resource_item_idx on public.access_grants (resource_item_id);
create index access_grants_resource_category_idx on public.access_grants (resource_category_id);
