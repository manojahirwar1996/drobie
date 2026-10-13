-- =============================================================================
-- drobie · 0300 · Media, taxonomy, catalog
-- PLATFORM_ARCHITECTURE §3.3 (categories), §3.4 (media), §3.5 (catalog)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Minimal JSON Schema validator (subset) for category attribute schemas and
-- config values. Supports: type (string | array of types), enum, const,
-- minimum, maximum, minLength, maxLength, pattern, properties, required,
-- additionalProperties (boolean), items, minItems, maxItems, uniqueItems.
-- If the project enables pg_jsonschema, this can be replaced by
-- jsonb_matches_schema() without changing callers.
-- ---------------------------------------------------------------------------
create or replace function private.jsonschema_errors(p_schema jsonb, p_data jsonb, p_path text default '$')
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  errs text[] := '{}';
  t text := jsonb_typeof(p_data);
  allowed jsonb;
  ok boolean;
  k text;
  v jsonb;
  i int;
begin
  if p_schema is null or jsonb_typeof(p_schema) <> 'object' then
    return errs;
  end if;

  -- type
  if p_schema ? 'type' then
    allowed := case when jsonb_typeof(p_schema -> 'type') = 'array' then p_schema -> 'type'
                    else jsonb_build_array(p_schema -> 'type') end;
    ok := false;
    for v in select * from jsonb_array_elements(allowed) loop
      if (v #>> '{}') = t
         or ((v #>> '{}') = 'integer' and t = 'number' and (p_data #>> '{}')::numeric = trunc((p_data #>> '{}')::numeric))
      then
        ok := true;
      end if;
    end loop;
    if not ok then
      return array[format('%s: expected %s, got %s', p_path, allowed, t)];
    end if;
  end if;

  if p_schema ? 'enum' and not (p_schema -> 'enum') @> jsonb_build_array(p_data) then
    errs := errs || format('%s: %s is not one of %s', p_path, p_data, p_schema -> 'enum');
  end if;
  if p_schema ? 'const' and p_data <> p_schema -> 'const' then
    errs := errs || format('%s: must equal %s', p_path, p_schema -> 'const');
  end if;

  if t = 'number' then
    if p_schema ? 'minimum' and (p_data #>> '{}')::numeric < (p_schema ->> 'minimum')::numeric then
      errs := errs || format('%s: below minimum %s', p_path, p_schema ->> 'minimum');
    end if;
    if p_schema ? 'maximum' and (p_data #>> '{}')::numeric > (p_schema ->> 'maximum')::numeric then
      errs := errs || format('%s: above maximum %s', p_path, p_schema ->> 'maximum');
    end if;
  elsif t = 'string' then
    if p_schema ? 'minLength' and char_length(p_data #>> '{}') < (p_schema ->> 'minLength')::int then
      errs := errs || format('%s: shorter than %s', p_path, p_schema ->> 'minLength');
    end if;
    if p_schema ? 'maxLength' and char_length(p_data #>> '{}') > (p_schema ->> 'maxLength')::int then
      errs := errs || format('%s: longer than %s', p_path, p_schema ->> 'maxLength');
    end if;
    if p_schema ? 'pattern' and (p_data #>> '{}') !~ (p_schema ->> 'pattern') then
      errs := errs || format('%s: does not match pattern', p_path);
    end if;
  elsif t = 'array' then
    if p_schema ? 'minItems' and jsonb_array_length(p_data) < (p_schema ->> 'minItems')::int then
      errs := errs || format('%s: fewer than %s items', p_path, p_schema ->> 'minItems');
    end if;
    if p_schema ? 'maxItems' and jsonb_array_length(p_data) > (p_schema ->> 'maxItems')::int then
      errs := errs || format('%s: more than %s items', p_path, p_schema ->> 'maxItems');
    end if;
    if coalesce((p_schema ->> 'uniqueItems')::boolean, false)
       and (select count(*) from jsonb_array_elements(p_data)) <> (select count(distinct e) from jsonb_array_elements(p_data) e) then
      errs := errs || format('%s: items must be unique', p_path);
    end if;
    if p_schema ? 'items' then
      i := 0;
      for v in select * from jsonb_array_elements(p_data) loop
        errs := errs || private.jsonschema_errors(p_schema -> 'items', v, format('%s[%s]', p_path, i));
        i := i + 1;
      end loop;
    end if;
  elsif t = 'object' then
    if p_schema ? 'required' then
      for k in select jsonb_array_elements_text(p_schema -> 'required') loop
        if not p_data ? k then
          errs := errs || format('%s.%s: is required', p_path, k);
        end if;
      end loop;
    end if;
    for k, v in select * from jsonb_each(p_data) loop
      if p_schema -> 'properties' ? k then
        errs := errs || private.jsonschema_errors(p_schema -> 'properties' -> k, v, p_path || '.' || k);
      elsif p_schema -> 'additionalProperties' = 'false'::jsonb then
        errs := errs || format('%s.%s: unknown attribute', p_path, k);
      elsif jsonb_typeof(p_schema -> 'additionalProperties') = 'object' then
        errs := errs || private.jsonschema_errors(p_schema -> 'additionalProperties', v, p_path || '.' || k);
      end if;
    end loop;
  end if;
  return errs;
end $$;
grant execute on function private.jsonschema_errors(jsonb, jsonb, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- media_assets: one system for every file in R2
-- ---------------------------------------------------------------------------
create table public.media_assets (
  id            uuid primary key default private.uuid_v7(),
  owner_user_id uuid references public.profiles (id) on delete cascade,
  owner_org_id  uuid,   -- FK when organizations arrive (v1.2)
  purpose       text not null check (purpose in (
                  'item_photo', 'wear_log', 'avatar_source', 'profile_photo', 'generated_look', 'post',
                  'portfolio', 'receipt', 'document', 'email_raw', 'export', 'place_photo')),
  r2_key        text not null unique check (r2_key ~ '^(u|o)/[0-9a-f-]{36}/[a-z_]+/[0-9a-f-]{36}/'),
  mime_type     text not null check (mime_type ~ '^[a-z]+/[a-z0-9.+-]+$'),
  bytes         bigint not null check (bytes > 0 and bytes <= 104857600),
  sha256        text check (sha256 ~ '^[0-9a-f]{64}$'),
  phash         text check (phash ~ '^[0-9a-f]{16}$'),
  width         int check (width > 0),
  height        int check (height > 0),
  status        public.media_status not null default 'pending',
  sensitivity   public.sensitivity not null default 'personal',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  constraint media_assets_one_owner check (num_nonnulls(owner_user_id, owner_org_id) = 1)
);
comment on table public.media_assets is 'Every stored file. Rows are created by media-upload-url (service role); clients read through RLS and get signed URLs from a function.';
create index media_assets_owner_idx on public.media_assets (owner_user_id, purpose, created_at desc);
create index media_assets_pending_idx on public.media_assets (created_at) where status = 'pending';
create index media_assets_phash_idx on public.media_assets (owner_user_id, phash) where phash is not null;
create trigger media_assets_updated_at before update on public.media_assets
  for each row execute function private.tg_set_updated_at();
create trigger media_assets_immutable before update on public.media_assets
  for each row execute function private.tg_immutable_columns('owner_user_id', 'owner_org_id', 'purpose', 'r2_key');

create or replace function private.tg_media_sensitivity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.purpose in ('avatar_source', 'document', 'email_raw') then
    new.sensitivity := 'sensitive';
  end if;
  return new;
end $$;
create trigger media_assets_sensitivity before insert or update of sensitivity on public.media_assets
  for each row execute function private.tg_media_sensitivity();

create table public.media_variants (
  id         uuid primary key default private.uuid_v7(),
  asset_id   uuid not null references public.media_assets (id) on delete cascade,
  variant    text not null check (variant in ('master', 'display', 'thumb', 'cutout')),
  r2_key     text not null unique,
  mime_type  text not null,
  bytes      bigint not null check (bytes > 0),
  width      int check (width > 0),
  height     int check (height > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (asset_id, variant)
);
create trigger media_variants_updated_at before update on public.media_variants
  for each row execute function private.tg_set_updated_at();

alter table public.profiles
  add constraint profiles_avatar_media_fk foreign key (avatar_media_id) references public.media_assets (id) on delete set null;
create index profiles_avatar_media_idx on public.profiles (avatar_media_id);

-- ---------------------------------------------------------------------------
-- categories: global taxonomy tree with per-category attribute schema
-- ---------------------------------------------------------------------------
create table public.categories (
  id                       uuid primary key default private.uuid_v7(),
  parent_id                uuid references public.categories (id) on delete restrict,
  slug                     text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name                     text not null,
  kind                     text not null check (kind in
                             ('apparel', 'footwear', 'accessory', 'jewellery', 'bag', 'beauty', 'document', 'gadget', 'home', 'other')),
  icon                     text,
  attribute_schema         jsonb not null default '{"type": "object"}'::jsonb
                             check (attribute_schema ->> 'type' = 'object'),
  default_wash_after_wears smallint check (default_wash_after_wears between 1 and 100),
  care                     jsonb not null default '{}'::jsonb,
  audience                 text[] not null default '{}' check (audience <@ array['women', 'men', 'unisex', 'kids']),
  sort_order               int not null default 0,
  active                   boolean not null default true,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
create index categories_parent_idx on public.categories (parent_id);
create trigger categories_updated_at before update on public.categories
  for each row execute function private.tg_set_updated_at();

create table public.category_translations (
  category_id uuid not null references public.categories (id) on delete cascade,
  locale      text not null check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  name        text not null,
  updated_at  timestamptz not null default now(),
  primary key (category_id, locale)
);
create trigger category_translations_updated_at before update on public.category_translations
  for each row execute function private.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- Catalog: brands, retailers (seam) and the shared products cache
-- ---------------------------------------------------------------------------
create table public.brands (
  id         uuid primary key default private.uuid_v7(),
  name       text not null,
  slug       text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  aliases    text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index brands_name_trgm on public.brands using gin (lower(name) extensions.gin_trgm_ops);
create index brands_aliases_idx on public.brands using gin (aliases);
create trigger brands_updated_at before update on public.brands
  for each row execute function private.tg_set_updated_at();

create table public.retailers (
  id                 uuid primary key default private.uuid_v7(),
  name               text not null,
  slug               text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  hosts              text[] not null default '{}',
  email_domains      text[] not null default '{}',
  aliases            text[] not null default '{}',
  return_window_days smallint check (return_window_days between 0 and 365),
  country            public.country_code not null default 'IN' references public.countries (code),
  active             boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index retailers_hosts_idx on public.retailers using gin (hosts);
create index retailers_email_domains_idx on public.retailers using gin (email_domains);
create index retailers_country_idx on public.retailers (country);
create trigger retailers_updated_at before update on public.retailers
  for each row execute function private.tg_set_updated_at();

create table public.products (
  id           uuid primary key default private.uuid_v7(),
  source_key   text not null unique check (char_length(source_key) between 3 and 300),
  source_type  text not null check (source_type in ('barcode', 'url', 'email', 'manual')),
  brand_id     uuid references public.brands (id) on delete set null,
  retailer_id  uuid references public.retailers (id) on delete set null,
  category_id  uuid references public.categories (id) on delete set null,
  name         text not null,
  colours      text[] not null default '{}',
  image_url    text check (image_url ~ '^https://'),
  image_phash  text check (image_phash ~ '^[0-9a-f]{16}$'),
  gtin         text check (gtin ~ '^[0-9]{8,14}$'),
  price_minor  bigint check (price_minor >= 0),
  currency     public.currency_code not null default 'INR',
  attributes   jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on table public.products is 'Shared product cache from barcodes, product pages and order emails. Never stores who bought a product.';
create index products_brand_idx on public.products (brand_id);
create index products_retailer_idx on public.products (retailer_id);
create index products_category_idx on public.products (category_id);
create index products_gtin_idx on public.products (gtin) where gtin is not null;
create index products_name_trgm on public.products using gin (lower(name) extensions.gin_trgm_ops);
create trigger products_updated_at before update on public.products
  for each row execute function private.tg_set_updated_at();
