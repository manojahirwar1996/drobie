-- =============================================================================
-- drobie · 0500 · Plans, prices, features, entitlements, quotas, subscriptions,
-- experiments, offers. Pricing is data: nothing here names a price in code.
-- PLATFORM_ARCHITECTURE §3.7
-- =============================================================================

create table public.plans (
  id          uuid primary key default private.uuid_v7(),
  code        text not null unique check (code ~ '^[a-z][a-z0-9_]{1,30}$'),
  name        text not null,
  description text,
  rank        int not null default 0,       -- higher wins when a user has several active grants
  is_default  boolean not null default false,
  active      boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index plans_one_default on public.plans (is_default) where is_default;
create trigger plans_updated_at before update on public.plans
  for each row execute function private.tg_set_updated_at();

create table public.plan_prices (
  id               uuid primary key default private.uuid_v7(),
  plan_id          uuid not null references public.plans (id) on delete restrict,
  channel          text not null check (channel in ('play', 'app_store', 'web')),
  country          public.country_code not null default 'IN' references public.countries (code),
  billing_interval text not null check (billing_interval in ('week', 'month', 'year', 'once', 'lifetime')),
  interval_count   smallint not null default 1 check (interval_count between 1 and 12),
  currency         public.currency_code not null,
  amount_minor     bigint not null check (amount_minor >= 0),
  store_product_id text,
  trial_days       smallint not null default 0 check (trial_days between 0 and 90),
  experiment_key   text,
  variant          text,
  is_placeholder   boolean not null default false,  -- TRUE until real prices are decided
  active_from      timestamptz not null default now(),
  active_to        timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (active_to is null or active_to > active_from),
  check ((experiment_key is null) = (variant is null))
);
comment on table public.plan_prices is 'Price per plan × channel × country × interval (× experiment variant). Read by plans-catalog only; never sent to a client for another channel.';
create index plan_prices_lookup_idx on public.plan_prices (plan_id, channel, country, active_from desc);
create index plan_prices_country_idx on public.plan_prices (country);
create unique index plan_prices_store_product_key on public.plan_prices (channel, store_product_id) where store_product_id is not null;
create trigger plan_prices_updated_at before update on public.plan_prices
  for each row execute function private.tg_set_updated_at();

create table public.features (
  id             uuid primary key default private.uuid_v7(),
  key            text not null unique check (key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  type           public.feature_type not null,
  period         public.quota_period,
  unit           text,
  description    text,
  client_visible boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check ((type = 'quota') = (period is not null))
);
create trigger features_updated_at before update on public.features
  for each row execute function private.tg_set_updated_at();

create table public.plan_features (
  plan_id     uuid not null references public.plans (id) on delete cascade,
  feature_id  uuid not null references public.features (id) on delete cascade,
  enabled     boolean not null default true,
  limit_value bigint check (limit_value >= 0),  -- NULL = unlimited (limits and quotas); ignored for flags
  updated_at  timestamptz not null default now(),
  primary key (plan_id, feature_id)
);
create index plan_features_feature_idx on public.plan_features (feature_id);
create trigger plan_features_updated_at before update on public.plan_features
  for each row execute function private.tg_set_updated_at();

-- Why a user has access. Either a whole plan, or a single-feature booster.
create table public.entitlement_grants (
  id            uuid primary key default private.uuid_v7(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  plan_id       uuid references public.plans (id) on delete restrict,
  feature_id    uuid references public.features (id) on delete restrict,
  feature_value bigint check (feature_value >= 0),  -- booster: added to the plan limit/quota
  source        text not null check (source in
                  ('signup', 'subscription', 'trial', 'promo', 'referral', 'admin', 'household', 'org', 'booster')),
  source_ref    uuid,
  starts_at     timestamptz not null default now(),
  ends_at       timestamptz,
  revoked_at    timestamptz,
  created_by    uuid references public.profiles (id) on delete set null,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (num_nonnulls(plan_id, feature_id) = 1),
  check (feature_id is null or feature_value is not null),
  check (ends_at is null or ends_at > starts_at)
);
create index entitlement_grants_user_idx on public.entitlement_grants (user_id, starts_at) where revoked_at is null;
create index entitlement_grants_plan_idx on public.entitlement_grants (plan_id);
create index entitlement_grants_feature_idx on public.entitlement_grants (feature_id);
create index entitlement_grants_source_idx on public.entitlement_grants (source, source_ref);
create index entitlement_grants_created_by_idx on public.entitlement_grants (created_by);
create trigger entitlement_grants_updated_at before update on public.entitlement_grants
  for each row execute function private.tg_set_updated_at();

create table public.usage_counters (
  user_id      uuid not null references public.profiles (id) on delete cascade,
  feature_id   uuid not null references public.features (id) on delete cascade,
  period_start date not null,
  used         bigint not null default 0 check (used >= 0),
  updated_at   timestamptz not null default now(),
  primary key (user_id, feature_id, period_start)
);
create index usage_counters_feature_idx on public.usage_counters (feature_id);

-- ---------------------------------------------------------------------------
-- Effective entitlements
-- ---------------------------------------------------------------------------
-- A caller may compute entitlements only for themself (server functions run
-- with no JWT subject; support staff with MFA may look up a user).
create or replace function private.can_read_user(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select auth.uid() is null or auth.uid() = p_user or private.has_admin_role('support') $$;

create or replace function private.active_plan_ids(p_user uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  with active as (
    select g.plan_id from public.entitlement_grants g
    where g.user_id = p_user and g.plan_id is not null and g.revoked_at is null
      and g.starts_at <= now() and (g.ends_at is null or g.ends_at > now())
      and private.can_read_user(p_user)
  )
  select plan_id from active
  union
  select p.id from public.plans p where p.is_default and not exists (select 1 from active)
$$;

create or replace function private.effective_plan(p_user uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.code from public.plans p
  where p.id in (select private.active_plan_ids(p_user))
  order by p.rank desc, p.code
  limit 1
$$;

create or replace function private.effective_features(p_user uuid)
returns table (
  feature_key text,
  feature_type public.feature_type,
  period public.quota_period,
  enabled boolean,
  limit_value bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with plan_rows as (
    select pf.feature_id, pf.enabled, pf.limit_value
    from public.plan_features pf
    where pf.plan_id in (select private.active_plan_ids(p_user))
  ),
  per_feature as (
    select f.id, f.key, f.type, f.period,
           coalesce(bool_or(pr.enabled), false) as enabled,
           -- unlimited (NULL) wins over any number among enabled plan rows
           case when bool_or(pr.enabled and pr.limit_value is null) then null
                else max(pr.limit_value) filter (where pr.enabled) end as plan_limit,
           bool_or(pr.enabled and pr.limit_value is null) as unlimited
    from public.features f
    left join plan_rows pr on pr.feature_id = f.id
    group by f.id, f.key, f.type, f.period
  ),
  boosters as (
    select g.feature_id, sum(g.feature_value) as extra
    from public.entitlement_grants g
    where g.user_id = p_user and g.feature_id is not null and g.revoked_at is null
      and g.starts_at <= now() and (g.ends_at is null or g.ends_at > now())
      and private.can_read_user(p_user)
    group by g.feature_id
  )
  select pf.key, pf.type, pf.period,
         pf.enabled or b.extra is not null,
         case
           when pf.type = 'flag' then null
           when coalesce(pf.unlimited, false) then null
           else coalesce(pf.plan_limit, 0) + coalesce(b.extra, 0)
         end
  from per_feature pf
  left join boosters b on b.feature_id = pf.id
$$;

create or replace function private.quota_period_start(p_user uuid, p_period public.quota_period)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select case p_period
           when 'day'   then (now() at time zone coalesce(pr.timezone, 'Asia/Kolkata'))::date
           when 'month' then date_trunc('month', now() at time zone coalesce(pr.timezone, 'Asia/Kolkata'))::date
         end
  from (select 1) one
  left join public.profiles pr on pr.id = p_user
$$;

-- The single check every server function uses (via _shared/entitlements.ts).
create or replace function private.entitlement(p_user uuid, p_feature_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  f record;
  v_used bigint := 0;
  v_feature_id uuid;
begin
  if auth.uid() is not null and auth.uid() <> p_user and not private.has_admin_role('support') then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  select * into f from private.effective_features(p_user) ef where ef.feature_key = p_feature_key;
  if not found then
    raise exception 'unknown feature %', p_feature_key using errcode = '22023';
  end if;

  if f.feature_type = 'quota' then
    select id into v_feature_id from public.features where key = p_feature_key;
    select coalesce(uc.used, 0) into v_used from public.usage_counters uc
    where uc.user_id = p_user and uc.feature_id = v_feature_id
      and uc.period_start = private.quota_period_start(p_user, f.period);
    v_used := coalesce(v_used, 0);
  end if;

  return jsonb_build_object(
    'feature', p_feature_key,
    'type', f.feature_type,
    'enabled', f.enabled,
    'limit', f.limit_value,
    'period', f.period,
    'used', case when f.feature_type = 'quota' then v_used end,
    'remaining', case when f.feature_type = 'quota' and f.enabled
                      then case when f.limit_value is null then null else greatest(f.limit_value - v_used, 0) end end,
    'plan', private.effective_plan(p_user)
  );
end $$;

-- Client-facing: the caller's own entitlement for one feature.
create or replace function public.entitlement(p_feature_key text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select private.entitlement(auth.uid(), p_feature_key) $$;

-- Atomic quota consumption. Never over-consumes under concurrency: the
-- conditional upsert re-checks the limit after acquiring the row lock.
create or replace function private.consume_quota(p_user uuid, p_feature_key text, p_amount bigint default 1)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  f record;
  v_feature_id uuid;
  v_period date;
  v_used bigint;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'amount must be positive' using errcode = '22023';
  end if;
  if auth.uid() is not null and auth.uid() <> p_user then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  select * into f from private.effective_features(p_user) ef where ef.feature_key = p_feature_key;
  if not found or f.feature_type <> 'quota' then
    raise exception 'feature % is not a quota', p_feature_key using errcode = '22023';
  end if;
  if not f.enabled then
    return jsonb_build_object('ok', false, 'reason', 'not_enabled', 'limit', 0, 'used', 0, 'remaining', 0);
  end if;

  select id into v_feature_id from public.features where key = p_feature_key;
  v_period := private.quota_period_start(p_user, f.period);

  insert into public.usage_counters as uc (user_id, feature_id, period_start, used)
  select p_user, v_feature_id, v_period, p_amount
  where f.limit_value is null or p_amount <= f.limit_value
  on conflict (user_id, feature_id, period_start) do update
     set used = uc.used + excluded.used, updated_at = now()
   where f.limit_value is null or uc.used + excluded.used <= f.limit_value
  returning uc.used into v_used;

  if v_used is null then
    select coalesce(max(used), 0) into v_used from public.usage_counters
    where user_id = p_user and feature_id = v_feature_id and period_start = v_period;
    return jsonb_build_object('ok', false, 'reason', 'quota_exceeded', 'limit', f.limit_value,
                              'used', v_used, 'remaining', greatest(f.limit_value - v_used, 0));
  end if;
  return jsonb_build_object('ok', true, 'limit', f.limit_value, 'used', v_used,
                            'remaining', case when f.limit_value is null then null else f.limit_value - v_used end);
end $$;

-- Give quota back when the paid step failed (e.g. generation refund).
create or replace function private.release_quota(p_user uuid, p_feature_key text, p_amount bigint default 1)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  f record;
begin
  select ef.* into f from private.effective_features(p_user) ef where ef.feature_key = p_feature_key;
  update public.usage_counters uc
     set used = greatest(uc.used - p_amount, 0), updated_at = now()
   where uc.user_id = p_user
     and uc.feature_id = (select id from public.features where key = p_feature_key)
     and uc.period_start = private.quota_period_start(p_user, f.period);
end $$;

-- Effective entitlements for the caller (paywall, limits UI).
create view public.user_entitlements
with (security_barrier = true)
as
select ef.feature_key, ef.feature_type, ef.period, ef.enabled, ef.limit_value,
       private.effective_plan(auth.uid()) as plan_code
from private.effective_features(auth.uid()) ef
join public.features f on f.key = ef.feature_key and f.client_visible;
comment on view public.user_entitlements is 'The caller''s effective features, computed from active entitlement grants. The only entitlement surface the app reads.';

-- ---------------------------------------------------------------------------
-- Item limit is a server truth: enforced on insert from the plan's limit.
-- ---------------------------------------------------------------------------
create or replace function private.tg_items_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit bigint;
  v_enabled boolean;
  v_count bigint;
begin
  select ef.limit_value, ef.enabled into v_limit, v_enabled
  from private.effective_features(new.owner_user_id) ef where ef.feature_key = 'closet.max_items';
  if not found or v_limit is null then
    return new;   -- feature not configured, or unlimited
  end if;
  -- serialise concurrent inserts for the same owner
  perform pg_advisory_xact_lock(hashtextextended('items_limit:' || new.owner_user_id::text, 0));
  select count(*) into v_count from public.items
  where owner_user_id = new.owner_user_id and deleted_at is null;
  if v_count >= v_limit then
    raise exception 'item limit reached (%)', v_limit using errcode = 'P0001', hint = 'limit_reached:closet.max_items';
  end if;
  return new;
end $$;
create trigger items_limit before insert on public.items
  for each row execute function private.tg_items_limit();

-- ---------------------------------------------------------------------------
-- subscriptions (RevenueCat for stores, Razorpay for web)
-- ---------------------------------------------------------------------------
create table public.subscriptions (
  id                       uuid primary key default private.uuid_v7(),
  user_id                  uuid not null references public.profiles (id) on delete cascade,
  provider                 text not null check (provider in ('play', 'app_store', 'razorpay')),
  provider_customer_id     text,
  provider_subscription_id text not null,
  plan_id                  uuid not null references public.plans (id) on delete restrict,
  plan_price_id            uuid references public.plan_prices (id) on delete set null,
  status                   text not null check (status in
                             ('pending', 'trialing', 'active', 'grace', 'on_hold', 'paused', 'cancelled', 'expired')),
  current_period_start     timestamptz,
  current_period_end       timestamptz,
  trial_ends_at            timestamptz,
  grace_until              timestamptz,
  cancel_at_period_end     boolean not null default false,
  cancelled_at             timestamptz,
  mandate_status           text check (mandate_status in ('pending', 'active', 'paused', 'revoked', 'failed')),
  latest_event_at          timestamptz,   -- ignore out-of-order webhooks older than this
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  unique (provider, provider_subscription_id)
);
create index subscriptions_user_idx on public.subscriptions (user_id, status);
create index subscriptions_plan_idx on public.subscriptions (plan_id);
create index subscriptions_plan_price_idx on public.subscriptions (plan_price_id);
create trigger subscriptions_updated_at before update on public.subscriptions
  for each row execute function private.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- experiments (seam): sticky assignment
-- ---------------------------------------------------------------------------
create table public.experiments (
  id          uuid primary key default private.uuid_v7(),
  key         text not null unique check (key ~ '^[a-z][a-z0-9_.]{2,60}$'),
  description text,
  status      text not null default 'draft' check (status in ('draft', 'running', 'paused', 'ended')),
  variants    jsonb not null check (jsonb_typeof(variants) = 'array' and jsonb_array_length(variants) >= 2),
  targeting   jsonb not null default '{}'::jsonb,
  starts_at   timestamptz,
  ends_at     timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger experiments_updated_at before update on public.experiments
  for each row execute function private.tg_set_updated_at();

create table public.experiment_assignments (
  experiment_id uuid not null references public.experiments (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  variant       text not null,
  assigned_at   timestamptz not null default now(),
  primary key (experiment_id, user_id)
);
create index experiment_assignments_user_idx on public.experiment_assignments (user_id);

-- Deterministic weighted bucket by hash(experiment, user); first assignment sticks.
create or replace function private.assign_variant(p_experiment_key text, p_user uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  e record;
  v_existing text;
  v_bucket numeric;
  v_total numeric;
  v_acc numeric := 0;
  v jsonb;
begin
  select * into e from public.experiments where key = p_experiment_key;
  if not found then
    return null;
  end if;
  select variant into v_existing from public.experiment_assignments where experiment_id = e.id and user_id = p_user;
  if v_existing is not null then
    return v_existing;
  end if;
  if e.status <> 'running' then
    return null;
  end if;
  select sum(coalesce((x ->> 'weight')::numeric, 1)) into v_total from jsonb_array_elements(e.variants) x;
  v_bucket := (abs(hashtextextended(e.key || ':' || p_user::text, 0)) % 10000) / 10000.0 * v_total;
  for v in select * from jsonb_array_elements(e.variants) loop
    v_acc := v_acc + coalesce((v ->> 'weight')::numeric, 1);
    if v_bucket < v_acc then
      v_existing := v ->> 'key';
      exit;
    end if;
  end loop;
  insert into public.experiment_assignments (experiment_id, user_id, variant)
  values (e.id, p_user, v_existing)
  on conflict (experiment_id, user_id) do nothing;
  select variant into v_existing from public.experiment_assignments where experiment_id = e.id and user_id = p_user;
  return v_existing;
end $$;

-- ---------------------------------------------------------------------------
-- offers, promo codes, referrals (seam)
-- ---------------------------------------------------------------------------
create table public.offers (
  id              uuid primary key default private.uuid_v7(),
  code            text not null unique check (code ~ '^[a-z][a-z0-9_]{2,40}$'),
  kind            text not null check (kind in ('price_override', 'discount_pct', 'credit_grant', 'entitlement_grant')),
  plan_id         uuid references public.plans (id) on delete restrict,
  plan_price_id   uuid references public.plan_prices (id) on delete restrict,
  params          jsonb not null default '{}'::jsonb,
  max_redemptions int check (max_redemptions > 0),
  starts_at       timestamptz,
  ends_at         timestamptz,
  active          boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create index offers_plan_idx on public.offers (plan_id);
create index offers_plan_price_idx on public.offers (plan_price_id);
create trigger offers_updated_at before update on public.offers
  for each row execute function private.tg_set_updated_at();

create table public.promo_codes (
  id              uuid primary key default private.uuid_v7(),
  code            text not null check (code ~ '^[A-Z0-9]{4,20}$'),
  offer_id        uuid not null references public.offers (id) on delete cascade,
  max_redemptions int check (max_redemptions > 0),
  redeemed_count  int not null default 0 check (redeemed_count >= 0),
  per_user_limit  smallint not null default 1 check (per_user_limit > 0),
  starts_at       timestamptz,
  expires_at      timestamptz,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (max_redemptions is null or redeemed_count <= max_redemptions)
);
create unique index promo_codes_code_key on public.promo_codes (upper(code));
create index promo_codes_offer_idx on public.promo_codes (offer_id);
create trigger promo_codes_updated_at before update on public.promo_codes
  for each row execute function private.tg_set_updated_at();

create table public.promo_redemptions (
  id            uuid primary key default private.uuid_v7(),
  promo_code_id uuid not null references public.promo_codes (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  order_id      uuid,   -- FK added in 0600
  redeemed_at   timestamptz not null default now()
);
create index promo_redemptions_code_user_idx on public.promo_redemptions (promo_code_id, user_id);
create index promo_redemptions_user_idx on public.promo_redemptions (user_id);

create table public.referrals (
  id               uuid primary key default private.uuid_v7(),
  referrer_user_id uuid not null references public.profiles (id) on delete cascade,
  referred_user_id uuid not null unique references public.profiles (id) on delete cascade,
  code             text not null,
  status           text not null default 'pending' check (status in ('pending', 'qualified', 'rewarded', 'rejected')),
  qualified_at     timestamptz,
  rewarded_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (referrer_user_id <> referred_user_id)
);
create index referrals_referrer_idx on public.referrals (referrer_user_id, status);
create trigger referrals_updated_at before update on public.referrals
  for each row execute function private.tg_set_updated_at();

grant execute on function
  private.can_read_user(uuid),
  private.effective_features(uuid),
  private.effective_plan(uuid),
  private.active_plan_ids(uuid),
  private.entitlement(uuid, text)
to authenticated, service_role;
grant execute on function public.entitlement(text) to authenticated, service_role;
grant execute on function
  private.consume_quota(uuid, text, bigint),
  private.release_quota(uuid, text, bigint),
  private.assign_variant(text, uuid),
  private.quota_period_start(uuid, public.quota_period)
to service_role;
