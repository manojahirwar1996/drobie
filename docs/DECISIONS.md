# drobie: decision log

Format: ID · date · decision · reason. Decisions already fixed in the specs (stack, Mumbai region, R2, in-house-first AI ladder, no phone sign-in, 18+ only, pricing as data, Studio credits on a ledger, the PLATFORM_ARCHITECTURE seams) are taken as given and not repeated here.

## Database foundation (Step 2), 2026-10-12

| ID | Decision | Reason |
| --- | --- | --- |
| D-001 | Native monthly range partitioning managed by `private.ensure_monthly_partitions` + pg_cron (no pg_partman). Default partition kept as a safety net. | pg_partman isn't guaranteed on Supabase; native partitioning is enough at our scale. |
| D-002 | UUID v7 from a SQL function `private.uuid_v7()`. Swap for native `uuidv7()` on Postgres 18. | Time-ordered keys, better index locality, no sequential ids exposed. |
| D-003 | **No function is executable by PUBLIC.** Global `alter default privileges revoke execute on functions from public` in 0100, plus an explicit revoke of Supabase's auto-grants on `public` functions in 0900. A test pins the allow-list. | Found by tests: a per-schema revoke can't remove the global default, which left SECURITY DEFINER internals (ledger writer, quota) callable by any signed-in user. |
| D-004 | List-read policies use set-based helpers (`my_household_ids`, `active_grants`, `granted_places`) evaluated once per statement. Per-row `has_access()` is only used for single-object checks. App code must always filter by owner/household. | A per-row grant check made closet sync a 2.4 s sequential scan at 100k items; set-based checks run in 0.3 ms via the index. |
| D-005 | A user's several homes (flat, parents', hostel, suitcase; FR-LOC-01) are top-level `places` of kind `home` inside their personal household. Households are the sharing unit. | Keeps households = "who shares", places = "where things are". No extra table. |
| D-006 | `item_events` (PLATFORM_ARCHITECTURE) replaces `item_state_events` (TECH_DESIGN/SRS). It is written automatically by a trigger on `items`. | PLATFORM wins on the data model; history can't be forgotten by a code path. |
| D-007 | One generic versioned config store, `config_keys` (schema, default, owner, approval, client visibility) + `config_versions` (draft → scheduled/live → archived, targeting, approver), instead of separate content_strings / ui_layouts / rule_sets / ai_prompts / ai_routes / notification_types / blocklists / app_config / feature_flags tables. Namespaces separate them; `private.app_config` and `private.feature_flags` are views. | One publish/approve/rollback/audit path for everything in §8.1, much less code, same capabilities. |
| D-008 | `countries` and `tax_rates` are real reference tables (FK targets), versioned by validity dates, not in the config store. | They are referenced by profiles, prices, orders and invoices. |
| D-009 | Ledger convention: debit = positive, credit = negative; every transaction sums to zero per currency (deferred constraint trigger). Credits use the pseudo-currency `CRD` and wallets are liability accounts that cannot go negative (row-locked check). | Standard double entry; money and credits can never mix; concurrent spends are safe (tested with 30 parallel spends). |
| D-010 | A plpgsql JSON-Schema subset validator (`private.jsonschema_errors`) checks category attributes and config values. | `pg_jsonschema` may not be enabled; callers don't change if we switch. |
| D-011 | The item limit (`closet.max_items`) is enforced by a database trigger with a per-owner advisory lock. | "Limits are server truths": no code path can skip it; tested under 30 parallel inserts. |
| D-012 | `plan_prices` is not client-readable; the `plans-catalog` function serves prices per channel. | SRS CE-42: iOS must never receive web prices. |
| D-013 | Seeded prices are FRS §6 numbers with `is_placeholder = true`. | Pricing is still undecided; changing it is a data edit, not a release. |
| D-014 | Retention: notifications 3 months (SRS §7: 90 days), domain events 3 months, ai_usage detail 13 months, audit log 24 months, by dropping partitions. | No large DELETEs; meets "audit ≥ 1 year". |
| D-015 | Admin role hierarchy in `has_admin_role`: super_admin covers everything; admin covers moderator, support and analyst, but not finance. MFA (`aal2`) is always required. | Finance data stays with finance. |
| D-016 | Kill-switch flags (e.g. `flag:dro_ai`) are marked `requires_approval`, per §8.2 (four-eyes on kill switches). | Follows the spec. Revisit if one-person emergency shut-off is needed. |
| D-017 | Supabase target Postgres 17. The suite also runs on Postgres 16 locally. | Supabase's current default; nothing used is version-specific. |
| D-018 | Document categories never store ID numbers (closed schema: type, expiry tracked, original). | DPDP data minimisation. |

## Open questions (need a founder decision)

1. **Free plan item limit:** the FRS says "Up to 100 items" (§2 users table) and also "Free 40" (§6 limits table). The seed uses 40. It's one row in `plan_features`.
2. **Ledger on account deletion:** tax law requires keeping financial records, but wallet accounts reference the user. Proposal for Step 13: keep the ledger and detach or anonymise the wallet owner on purge.
3. **Kill switches and four-eyes:** keep approval on `dro_ai` and similar, or allow one admin to switch *off* (never on) instantly?
4. **GST SAC codes** for subscriptions and credit packs: confirm with the CA before the first web invoice.
5. **Retailer return windows** in the seed are starting values; verify against each retailer's current policy.
