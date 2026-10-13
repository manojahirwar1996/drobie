-- =============================================================================
-- drobie · 0600 · Money: orders, payments, refunds, invoices, tax rates, and a
-- double-entry ledger with wallets (Studio credits are a wallet).
-- PLATFORM_ARCHITECTURE §3.8, §9. Ledger rules are code, never config.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- tax_rates: versioned by validity window (a change = a new row)
-- ---------------------------------------------------------------------------
create table public.tax_rates (
  id         uuid primary key default private.uuid_v7(),
  country    public.country_code not null references public.countries (code),
  tax_code   text not null check (tax_code ~ '^[A-Z0-9_]{2,30}$'),
  rate_pct   numeric(6,3) not null check (rate_pct between 0 and 100),
  hsn_sac    text check (hsn_sac ~ '^[0-9]{4,8}$'),
  applies_to text[] not null default '{}',   -- order line types
  valid_from date not null,
  valid_to   date,
  created_at timestamptz not null default now(),
  check (valid_to is null or valid_to > valid_from)
);
create index tax_rates_lookup_idx on public.tax_rates (country, tax_code, valid_from desc);

-- ---------------------------------------------------------------------------
-- orders and lines
-- ---------------------------------------------------------------------------
create table public.orders (
  id              uuid primary key default private.uuid_v7(),
  human_ref       text not null unique default ('DRB-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 10))),
  buyer_user_id   uuid not null references public.profiles (id) on delete restrict,
  seller_type     text not null default 'platform' check (seller_type in ('platform', 'org', 'user')),
  seller_org_id   uuid,   -- FK when organizations arrive
  seller_user_id  uuid references public.profiles (id) on delete restrict,
  channel         text not null check (channel in ('play', 'app_store', 'web', 'app_gateway', 'admin')),
  currency        public.currency_code not null,
  subtotal_minor  bigint not null default 0 check (subtotal_minor >= 0),
  tax_minor       bigint not null default 0 check (tax_minor >= 0),
  discount_minor  bigint not null default 0 check (discount_minor >= 0),
  total_minor     bigint not null default 0 check (total_minor >= 0),
  status          text not null default 'created' check (status in
                    ('created', 'pending', 'paid', 'failed', 'cancelled', 'refunded', 'partially_refunded')),
  country         public.country_code not null default 'IN' references public.countries (code),
  buyer_gstin     text check (buyer_gstin ~ '^[0-9]{2}[A-Z0-9]{13}$'),
  idempotency_key text unique,
  paid_at         timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint orders_total_math check (total_minor = subtotal_minor + tax_minor - discount_minor),
  constraint orders_seller check (
    (seller_type = 'platform' and seller_org_id is null and seller_user_id is null) or
    (seller_type = 'org' and seller_org_id is not null and seller_user_id is null) or
    (seller_type = 'user' and seller_user_id is not null and seller_org_id is null))
);
create index orders_buyer_idx on public.orders (buyer_user_id, created_at desc);
create index orders_seller_user_idx on public.orders (seller_user_id);
create index orders_country_idx on public.orders (country);
create index orders_status_idx on public.orders (status, created_at) where status in ('created', 'pending');
create trigger orders_updated_at before update on public.orders
  for each row execute function private.tg_set_updated_at();
create trigger orders_immutable before update on public.orders
  for each row execute function private.tg_immutable_columns('buyer_user_id', 'currency', 'human_ref');

create table public.order_lines (
  id                uuid primary key default private.uuid_v7(),
  order_id          uuid not null references public.orders (id) on delete cascade,
  line_type         text not null check (line_type in
                      ('subscription', 'credit_pack', 'booking', 'kit', 'rental_fee', 'deposit', 'product', 'tip', 'service_fee')),
  description       text not null,
  plan_price_id     uuid references public.plan_prices (id) on delete restrict,
  quantity          int not null default 1 check (quantity > 0),
  unit_amount_minor bigint not null check (unit_amount_minor >= 0),
  amount_minor      bigint not null check (amount_minor >= 0),
  tax_rate_pct      numeric(6,3) not null default 0 check (tax_rate_pct between 0 and 100),
  tax_minor         bigint not null default 0 check (tax_minor >= 0),
  hsn_sac           text check (hsn_sac ~ '^[0-9]{4,8}$'),
  credits           bigint check (credits > 0),  -- credit packs: credits delivered
  ref_type          text,
  ref_id            uuid,
  created_at        timestamptz not null default now(),
  constraint order_lines_amount_math check (amount_minor = unit_amount_minor * quantity)
);
create index order_lines_order_idx on public.order_lines (order_id);
create index order_lines_plan_price_idx on public.order_lines (plan_price_id);

-- Keep order totals in step with their lines.
create or replace function private.tg_order_lines_totals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order uuid := coalesce(new.order_id, old.order_id);
begin
  update public.orders o
     set subtotal_minor = t.sub, tax_minor = t.tax, total_minor = t.sub + t.tax - o.discount_minor
    from (select coalesce(sum(amount_minor), 0) as sub, coalesce(sum(tax_minor), 0) as tax
            from public.order_lines where order_id = v_order) t
   where o.id = v_order;
  return null;
end $$;
create trigger order_lines_totals after insert or update or delete on public.order_lines
  for each row execute function private.tg_order_lines_totals();

alter table public.promo_redemptions
  add constraint promo_redemptions_order_fk foreign key (order_id) references public.orders (id) on delete set null;
create index promo_redemptions_order_idx on public.promo_redemptions (order_id);

-- ---------------------------------------------------------------------------
-- payments and refunds (raw provider payloads stay in private.webhook_events)
-- ---------------------------------------------------------------------------
create table public.payments (
  id                  uuid primary key default private.uuid_v7(),
  order_id            uuid not null references public.orders (id) on delete restrict,
  provider            text not null check (provider in ('razorpay', 'play', 'app_store')),
  provider_payment_id text not null,
  amount_minor        bigint not null check (amount_minor >= 0),
  currency            public.currency_code not null,
  status              text not null check (status in ('created', 'authorized', 'captured', 'failed', 'refunded', 'partially_refunded')),
  method              text,
  fee_minor           bigint check (fee_minor >= 0),
  tax_on_fee_minor    bigint check (tax_on_fee_minor >= 0),
  captured_at         timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (provider, provider_payment_id)
);
create index payments_order_idx on public.payments (order_id);
create trigger payments_updated_at before update on public.payments
  for each row execute function private.tg_set_updated_at();

create table public.refunds (
  id                 uuid primary key default private.uuid_v7(),
  payment_id         uuid not null references public.payments (id) on delete restrict,
  provider_refund_id text,
  amount_minor       bigint not null check (amount_minor > 0),
  currency           public.currency_code not null,
  status             text not null check (status in ('pending', 'processed', 'failed')),
  reason             text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index refunds_payment_idx on public.refunds (payment_id);
create unique index refunds_provider_key on public.refunds (provider_refund_id) where provider_refund_id is not null;
create trigger refunds_updated_at before update on public.refunds
  for each row execute function private.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- invoices (seam): GST invoices, sequential per financial year
-- ---------------------------------------------------------------------------
create table private.invoice_sequences (
  financial_year text primary key check (financial_year ~ '^[0-9]{4}-[0-9]{2}$'),
  last_number    int not null default 0
);

create table public.invoices (
  id             uuid primary key default private.uuid_v7(),
  order_id       uuid not null unique references public.orders (id) on delete restrict,
  invoice_number text not null unique,
  financial_year text not null,
  seq            int not null,
  issued_at      timestamptz not null default now(),
  buyer_name     text,
  buyer_gstin    text,
  place_of_supply text,
  currency       public.currency_code not null,
  subtotal_minor bigint not null,
  tax_minor      bigint not null,
  total_minor    bigint not null,
  media_asset_id uuid references public.media_assets (id) on delete set null,
  created_at     timestamptz not null default now(),
  unique (financial_year, seq)
);
create index invoices_media_idx on public.invoices (media_asset_id);

-- Indian FY runs April–March: 2026-10-12 → '2026-27'.
create or replace function private.financial_year(p_at timestamptz default now())
returns text
language sql
stable
set search_path = ''
as $$
  select case when extract(month from p_at at time zone 'Asia/Kolkata') >= 4
              then to_char(p_at at time zone 'Asia/Kolkata', 'YYYY') || '-' ||
                   lpad(((extract(year from p_at at time zone 'Asia/Kolkata')::int + 1) % 100)::text, 2, '0')
              else (extract(year from p_at at time zone 'Asia/Kolkata')::int - 1)::text || '-' ||
                   lpad((extract(year from p_at at time zone 'Asia/Kolkata')::int % 100)::text, 2, '0')
         end
$$;

create or replace function private.issue_invoice(p_order uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  o record;
  v_fy text := private.financial_year(now());
  v_seq int;
  v_id uuid;
begin
  select * into o from public.orders where id = p_order and status = 'paid' for update;
  if not found then
    raise exception 'order % is not paid', p_order using errcode = '22023';
  end if;
  select id into v_id from public.invoices where order_id = p_order;
  if v_id is not null then
    return v_id;
  end if;
  insert into private.invoice_sequences (financial_year, last_number) values (v_fy, 1)
  on conflict (financial_year) do update set last_number = private.invoice_sequences.last_number + 1
  returning last_number into v_seq;
  insert into public.invoices (order_id, invoice_number, financial_year, seq, buyer_gstin, currency,
                               subtotal_minor, tax_minor, total_minor)
  values (p_order, format('DL/%s/%s', v_fy, lpad(v_seq::text, 6, '0')), v_fy, v_seq, o.buyer_gstin, o.currency,
          o.subtotal_minor, o.tax_minor, o.total_minor)
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Double-entry ledger (private). Convention: amount_minor > 0 is a debit,
-- < 0 is a credit. Every transaction sums to zero per currency (checked at
-- COMMIT by a deferred constraint trigger). Entries are immutable.
-- Credits use the pseudo-currency 'CRD' and never mix with money.
-- ---------------------------------------------------------------------------
create table private.ledger_accounts (
  id            uuid primary key default private.uuid_v7(),
  code          text not null unique,
  name          text not null,
  type          text not null check (type in ('asset', 'liability', 'equity', 'revenue', 'expense')),
  currency      public.currency_code not null,
  owner_user_id uuid references public.profiles (id) on delete restrict,
  credit_type   text check (credit_type in ('studio_credits', 'store_credit', 'referral_credit')),
  allow_negative boolean not null default true,   -- wallets: false
  created_at    timestamptz not null default now(),
  check ((owner_user_id is null) = (credit_type is null))
);
create unique index ledger_accounts_wallet_key on private.ledger_accounts (owner_user_id, credit_type, currency)
  where owner_user_id is not null;

create table private.ledger_transactions (
  id              uuid primary key default private.uuid_v7(),
  kind            text not null check (kind ~ '^[a-z][a-z0-9_]*$'),
  description     text,
  order_id        uuid references public.orders (id) on delete restrict,
  payment_id      uuid references public.payments (id) on delete restrict,
  refund_id       uuid references public.refunds (id) on delete restrict,
  idempotency_key text unique,
  reverses_id     uuid references private.ledger_transactions (id) on delete restrict,
  created_by      uuid,
  created_at      timestamptz not null default now()
);
create index ledger_transactions_order_idx on private.ledger_transactions (order_id);
create index ledger_transactions_payment_idx on private.ledger_transactions (payment_id);
create index ledger_transactions_refund_idx on private.ledger_transactions (refund_id);
create index ledger_transactions_reverses_idx on private.ledger_transactions (reverses_id);

create table private.ledger_entries (
  id             uuid primary key default private.uuid_v7(),
  transaction_id uuid not null references private.ledger_transactions (id) on delete restrict,
  account_id     uuid not null references private.ledger_accounts (id) on delete restrict,
  amount_minor   bigint not null check (amount_minor <> 0),
  currency       public.currency_code not null,
  created_at     timestamptz not null default now()
);
create index ledger_entries_tx_idx on private.ledger_entries (transaction_id);
create index ledger_entries_account_idx on private.ledger_entries (account_id, created_at);

create trigger ledger_entries_append_only before update or delete on private.ledger_entries
  for each row execute function private.tg_append_only();
create trigger ledger_transactions_append_only before update or delete on private.ledger_transactions
  for each row execute function private.tg_append_only();

create or replace function private.tg_ledger_entry_currency()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.currency is distinct from (select currency from private.ledger_accounts where id = new.account_id) then
    raise exception 'entry currency % does not match account currency', new.currency using errcode = '23514';
  end if;
  return new;
end $$;
create trigger ledger_entries_currency before insert on private.ledger_entries
  for each row execute function private.tg_ledger_entry_currency();

create or replace function private.tg_ledger_balanced()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  bad record;
begin
  select currency, sum(amount_minor) as s into bad
  from private.ledger_entries
  where transaction_id = new.transaction_id
  group by currency
  having sum(amount_minor) <> 0
  limit 1;
  if found then
    raise exception 'ledger transaction % does not balance in % (off by %)', new.transaction_id, bad.currency, bad.s
      using errcode = '23514';
  end if;
  if (select count(*) from private.ledger_entries where transaction_id = new.transaction_id) < 2 then
    raise exception 'ledger transaction % needs at least two entries', new.transaction_id using errcode = '23514';
  end if;
  return null;
end $$;
create constraint trigger ledger_entries_balanced
  after insert on private.ledger_entries
  deferrable initially deferred
  for each row execute function private.tg_ledger_balanced();

-- Balance as the account holder sees it: debit-normal accounts (asset,
-- expense) = sum; credit-normal accounts (liability, equity, revenue) = -sum.
create or replace view private.account_balances as
select a.id as account_id, a.code, a.type, a.currency, a.owner_user_id, a.credit_type,
       (case when a.type in ('asset', 'expense') then coalesce(sum(e.amount_minor), 0)
             else -coalesce(sum(e.amount_minor), 0) end)::bigint as balance_minor
from private.ledger_accounts a
left join private.ledger_entries e on e.account_id = a.id
group by a.id;

-- Wallet account for a user (created on first use).
create or replace function private.wallet_account(p_user uuid, p_credit_type text, p_currency text default 'CRD')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select id into v_id from private.ledger_accounts
  where owner_user_id = p_user and credit_type = p_credit_type and currency = p_currency;
  if v_id is null then
    insert into private.ledger_accounts (code, name, type, currency, owner_user_id, credit_type, allow_negative)
    values (format('wallet:%s:%s:%s', p_credit_type, p_currency, p_user), format('%s wallet', p_credit_type),
            'liability', p_currency, p_user, p_credit_type, false)
    on conflict do nothing;
    select id into v_id from private.ledger_accounts
    where owner_user_id = p_user and credit_type = p_credit_type and currency = p_currency;
  end if;
  return v_id;
end $$;

-- The only way to write the ledger. p_entries: [{"account": "<code or uuid>", "amount_minor": n, "currency": "INR"}]
-- Idempotent on p_idempotency_key. Wallets cannot go negative (checked under a
-- row lock on the wallet account, so concurrent spends serialise).
create or replace function private.post_ledger_transaction(
  p_kind text,
  p_entries jsonb,
  p_idempotency_key text default null,
  p_description text default null,
  p_order uuid default null,
  p_payment uuid default null,
  p_refund uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tx uuid;
  e jsonb;
  v_account uuid;
  a record;
  v_balance bigint;
begin
  if p_idempotency_key is not null then
    select id into v_tx from private.ledger_transactions where idempotency_key = p_idempotency_key;
    if v_tx is not null then
      return v_tx;
    end if;
  end if;
  if jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) < 2 then
    raise exception 'a ledger transaction needs at least two entries' using errcode = '22023';
  end if;

  insert into private.ledger_transactions (kind, description, order_id, payment_id, refund_id, idempotency_key, created_by)
  values (p_kind, p_description, p_order, p_payment, p_refund, p_idempotency_key, auth.uid())
  returning id into v_tx;

  -- lock touched non-negative accounts in a stable order to avoid deadlocks
  for a in
    select la.id from private.ledger_accounts la
    where not la.allow_negative
      and la.id in (
        select coalesce(
                 (select id from private.ledger_accounts where code = x ->> 'account'),
                 case when (x ->> 'account') ~ '^[0-9a-f-]{36}$' then (x ->> 'account')::uuid end)
        from jsonb_array_elements(p_entries) x)
    order by la.id
    for update
  loop
    null;
  end loop;

  for e in select * from jsonb_array_elements(p_entries) loop
    select id into v_account from private.ledger_accounts where code = e ->> 'account';
    if v_account is null and (e ->> 'account') ~ '^[0-9a-f-]{36}$' then
      select id into v_account from private.ledger_accounts where id = (e ->> 'account')::uuid;
    end if;
    if v_account is null then
      raise exception 'unknown ledger account %', e ->> 'account' using errcode = '22023';
    end if;
    insert into private.ledger_entries (transaction_id, account_id, amount_minor, currency)
    values (v_tx, v_account, (e ->> 'amount_minor')::bigint, e ->> 'currency');
  end loop;

  for a in
    select distinct la.id, la.code from private.ledger_entries le
    join private.ledger_accounts la on la.id = le.account_id
    where le.transaction_id = v_tx and not la.allow_negative
  loop
    select balance_minor into v_balance from private.account_balances where account_id = a.id;
    if v_balance < 0 then
      raise exception 'insufficient balance in %', a.code using errcode = 'P0001', hint = 'insufficient_balance';
    end if;
  end loop;

  perform private.emit('ledger.posted', 'ledger_transaction', v_tx, jsonb_build_object('kind', p_kind));
  return v_tx;
end $$;

-- Credits helpers built on the ledger.
create or replace function private.grant_credits(
  p_user uuid, p_amount bigint, p_reason text, p_idempotency_key text, p_credit_type text default 'studio_credits'
)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select private.post_ledger_transaction(
    'credit_grant_' || p_reason,
    jsonb_build_array(
      jsonb_build_object('account', 'credits:issued', 'amount_minor', p_amount, 'currency', 'CRD'),
      jsonb_build_object('account', private.wallet_account(p_user, p_credit_type)::text, 'amount_minor', -p_amount, 'currency', 'CRD')),
    p_idempotency_key, p_reason)
$$;

create or replace function private.spend_credits(
  p_user uuid, p_amount bigint, p_reason text, p_idempotency_key text, p_credit_type text default 'studio_credits'
)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select private.post_ledger_transaction(
    'credit_spend_' || p_reason,
    jsonb_build_array(
      jsonb_build_object('account', private.wallet_account(p_user, p_credit_type)::text, 'amount_minor', p_amount, 'currency', 'CRD'),
      jsonb_build_object('account', 'credits:consumed', 'amount_minor', -p_amount, 'currency', 'CRD')),
    p_idempotency_key, p_reason)
$$;

-- Wallet balances (derived from the ledger, never edited).
create or replace view private.wallets as
select owner_user_id as user_id, credit_type, currency, balance_minor as balance
from private.account_balances
where owner_user_id is not null;

create or replace function public.my_wallets()
returns table (credit_type text, currency text, balance bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select w.credit_type, w.currency::text, w.balance from private.wallets w where w.user_id = auth.uid()
$$;

grant execute on function public.my_wallets() to authenticated, service_role;
grant execute on function
  private.post_ledger_transaction(text, jsonb, text, text, uuid, uuid, uuid),
  private.grant_credits(uuid, bigint, text, text, text),
  private.spend_credits(uuid, bigint, text, text, text),
  private.wallet_account(uuid, text, text),
  private.issue_invoice(uuid),
  private.financial_year(timestamptz)
to service_role;
