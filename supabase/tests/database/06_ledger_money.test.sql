begin;
select plan(18);

select tests.create_user('payer@l.test') as u \gset

-- a subscription payment: gross 399 incl. GST, store fee 59.85, net
select lives_ok($$
  select private.post_ledger_transaction('subscription_payment', '[
    {"account": "receivable:play",       "amount_minor":  39900, "currency": "INR"},
    {"account": "liability:gst_payable", "amount_minor":  -6086, "currency": "INR"},
    {"account": "revenue:subscriptions", "amount_minor": -33814, "currency": "INR"}
  ]'::jsonb, 'test:play:1')
$$, 'a balanced transaction posts');

select is(
  private.post_ledger_transaction('subscription_payment', '[
    {"account": "receivable:play", "amount_minor": 39900, "currency": "INR"},
    {"account": "revenue:subscriptions", "amount_minor": -39900, "currency": "INR"}]'::jsonb, 'test:play:1'),
  (select id from private.ledger_transactions where idempotency_key = 'test:play:1'),
  'posting is idempotent by key');
select is((select balance_minor from private.account_balances where code = 'revenue:subscriptions'), 33814::bigint,
  'revenue balance derived from entries (credit-normal shown positive)');

set constraints private.ledger_entries_balanced immediate;
select throws_ok($$
  select private.post_ledger_transaction('broken', '[
    {"account": "receivable:play", "amount_minor": 100, "currency": "INR"},
    {"account": "revenue:subscriptions", "amount_minor": -90, "currency": "INR"}]'::jsonb)
$$, '23514', null, 'an unbalanced transaction is rejected');
select throws_ok($$
  select private.post_ledger_transaction('mixed', '[
    {"account": "receivable:play", "amount_minor": 100, "currency": "INR"},
    {"account": "credits:consumed", "amount_minor": -100, "currency": "INR"}]'::jsonb)
$$, '23514', null, 'an entry must use its account''s currency (credits never mix with money)');
set constraints private.ledger_entries_balanced deferred;

select throws_ok($$update private.ledger_entries set amount_minor = 1$$, '42501', null, 'ledger entries are immutable');
select throws_ok($$delete from private.ledger_transactions$$, '42501', null, 'ledger transactions cannot be deleted');

-- credits wallet
select private.grant_credits(:'u', 10, 'pack', 'test:grant:1');
select private.spend_credits(:'u', 4, 'look', 'test:spend:1');
select is((select balance from private.wallets where user_id = :'u'), 6::bigint, 'wallet balance = granted - spent');
select throws_ok(format($$select private.spend_credits(%L, 7, 'look', 'test:spend:2')$$, :'u'), 'P0001', null,
  'a wallet can never go negative');
select is((select balance from private.wallets where user_id = :'u'), 6::bigint, 'failed spend leaves the balance unchanged');
select tests.authenticate_as(:'u');
select is((select balance from public.my_wallets() where credit_type = 'studio_credits'), 6::bigint, 'user sees own wallet');
select tests.clear_authentication();

-- every transaction in the ledger balances to zero per currency
select is((select count(*)::int from (select transaction_id, currency from private.ledger_entries
                                       group by 1, 2 having sum(amount_minor) <> 0) t), 0,
  'the whole ledger balances');

-- orders and invoices
insert into public.orders (id, buyer_user_id, channel, currency) values ('55555555-5555-7555-8555-555555555555', :'u', 'web', 'INR');
insert into public.order_lines (order_id, line_type, description, unit_amount_minor, amount_minor, tax_rate_pct, tax_minor)
values ('55555555-5555-7555-8555-555555555555', 'credit_pack', '50 credits', 25000, 25000, 18, 4500),
       ('55555555-5555-7555-8555-555555555555', 'tip', 'thanks', 1000, 1000, 0, 0);
select is((select total_minor from public.orders where id = '55555555-5555-7555-8555-555555555555'), 30500::bigint,
  'order totals follow their lines (subtotal + tax)');
select throws_ok($$select private.issue_invoice('55555555-5555-7555-8555-555555555555')$$, '22023', null,
  'unpaid orders get no invoice');
update public.orders set status = 'paid', paid_at = now() where id = '55555555-5555-7555-8555-555555555555';
select private.issue_invoice('55555555-5555-7555-8555-555555555555') as inv \gset
select matches((select invoice_number from public.invoices where id = :'inv'),
  '^DL/[0-9]{4}-[0-9]{2}/000001$', 'invoice numbers are sequential per financial year');
select is(private.issue_invoice('55555555-5555-7555-8555-555555555555'), :'inv'::uuid, 'issuing again returns the same invoice');
select is(private.financial_year('2027-02-01 10:00+05:30'), '2026-27', 'Indian FY: Feb 2027 is FY 2026-27');
select is(private.financial_year('2026-04-01 10:00+05:30'), '2026-27', 'Indian FY starts 1 April');

select * from finish();
rollback;
