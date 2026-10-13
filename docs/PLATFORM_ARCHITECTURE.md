# drobie — Platform architecture and future-ready data model

Version 1.0 for development · Drobie Labs · Confidential

This document extends TECH_DESIGN sections 6–9. **Where it differs from TECH_DESIGN on the data model, this document wins.** It exists so the database we build for the MVP never has to be redone when drobie grows into the full platform.

## 1. The end goal the backend must support

drobie starts as a personal wardrobe and "where is it" app and grows into a platform:

| Stage | What gets added | Who acts on the platform |
| --- | --- | --- |
| MVP | Closet, effortless adding, places, dro, daily picks, care, plans and credits | Users |
| v1.1 | Friends, circles, family/household sharing, lend and swap, Try it on, QR/NFC box labels, subscription boosters | Users, their friends and family |
| v1.2 | Stylists and consultations (video, chat, async closet review), lookbooks, bookings, payouts | Users, stylists |
| v1.3 | Local services: tailors, dhobi/laundry, alteration pick-up; kits and physical products | Users, service partners |
| v2 | Brands and retailers (catalog, affiliate, sponsored drops, anonymised trend insights), creators, P2P resale/rental | Users, brands, creators |
| v3 | Other countries, currencies, languages and tax regimes | Everyone |

**Rule: build the seams now, not the features.** We only build tables in the MVP if they are used now, or if they are expensive to change later (identity and ownership, money, media, plans and entitlements, access sharing, IDs, currency, events). Everything else is added later with additive migrations.

## 2. Architectural principles

1. **Modular monolith.** One Postgres database, one set of Edge Functions, organised in domain modules with clear boundaries: identity, closet, places, planning, dro, media, billing, social, marketplace, services, catalog, notifications, ops. Modules talk through SQL functions and domain events, not by reaching into each other's tables. This lets us split a module into its own service later if scale demands it, without a rewrite.
2. **Postgres schemas by exposure.**
   - `public`: client-facing tables, all protected by RLS.
   - `private`: internals never exposed through the Supabase API (ledger, webhook events, outbox, AI usage, raw email metadata, rate limits, idempotency keys). Accessed only by server functions.
   - `audit`: append-only audit log.
   - `SECURITY DEFINER` functions live in `private`, set `search_path = ''`, and check the caller explicitly.
3. **IDs.** `uuid` primary keys, generated as **UUID v7** (time-ordered, better index locality) via a `private.uuid_v7()` function until native support is available. Never expose sequential numbers. Human-facing codes (booking refs, tag codes, invoice numbers) are separate columns.
4. **Ownership is explicit.** Every user-owned row has `owner_user_id` (and `household_id` where it can be shared). Organisation-owned rows have `org_id`. RLS checks go through a small set of helper functions (section 4), never copy-pasted logic.
5. **Sharing is a grant, not a copy.** Friends, family, stylists and support staff see a user's data through time-limited, revocable `access_grants`. We never duplicate a user's closet for someone else.
6. **Money is a ledger.** Every rupee and every credit moves through a double-entry ledger with currency. Balances are derived, never edited.
7. **Pricing and limits are data, not code.** Plans, prices, features, limits, trials, offers and price tests live in tables. Changing pricing never needs a code release or app update.
8. **Every important change emits an event.** Writes that matter insert a `private.domain_events` row in the same transaction (outbox pattern). Workers consume them for notifications, analytics, search sync, embeddings and future partner webhooks.
9. **State machines in the database.** Bookings, exchanges, orders, subscriptions and listings change status only through server functions that check an allowed-transitions table, and every transition is logged.
10. **Backwards-compatible change.** Mobile apps can't be force-updated, so migrations follow expand → migrate → contract. Edge Functions are versioned (`/v1/...`). `app_config.min_app_version` lets us block very old apps.
11. **Global from day one in the schema.** Money has a currency, users have country, locale and timezone, taxonomy names are translatable, and tax is stored per line. We launch with India, INR and English/Hinglish only.
12. **Privacy tiers.** Columns are classified as public, personal or sensitive. Sensitive data (body measurements, body/avatar photos, precise location, raw emails) lives in separate tables with stricter RLS, consent checks and shorter retention. It is never included in a grant unless that grant's scope names it explicitly.

## 3. Domain map and tables

**Phases:**
- **Now:** build it in the MVP and use it.
- **Seam:** build the table and its rules now, minimal use.
- **Later:** add with a new migration when the feature starts.

### 3.1 Identity and accounts

| Table | Phase | Purpose |
| --- | --- | --- |
| profiles | Now | One per auth user. Name, handle, country, locale, timezone, currency, adult confirmation, status (active, suspended, banned), inbound email token. No plan column: plan comes from entitlements. |
| consents | Now | Versioned consent history (email import, gallery, calendar, measurements, marketing, avatar). |
| device_tokens | Now | Push tokens per device. |
| body_profiles | Seam | **Sensitive.** Measurements, size passport, fit preferences. Separate table, consent required. |
| avatars | Later | **Sensitive.** Try it on avatar versions, source media and consent. |
| organizations | Later | Businesses on the platform. `type`: stylist_studio, tailor, laundry, brand, retailer, partner. Holds KYC status, GSTIN and payout account. |
| org_members | Later | User ↔ organisation with role: owner, admin, staff. |
| professional_profiles | Later | Public profile of a stylist or service provider: bio, city, languages, specialties, portfolio media, verification, ratings summary. Linked to a user (solo) or an organisation. |

A person is always one `auth.users` row. They can be a consumer, a stylist and a brand staff member at once through roles, not separate accounts.

### 3.2 Households, places and tags

| Table | Phase | Purpose |
| --- | --- | --- |
| households | Now | Replaces "homes". Every user gets a personal household at signup. Family sharing later is just more members. |
| household_members | Now | `role`: owner, adult, member, viewer. MVP: only the owner. |
| places | Now | Nested locations (`parent_id`) inside a household: room → wardrobe → shelf → box. |
| tags | Seam | Physical QR/NFC codes: random code, kind, batch, bound to a place, box or item, claimed by. Scanning opens the place. |
| tag_batches | Later | Printed kits and label packs (linked to orders). |

### 3.3 Closet and items

| Table | Phase | Purpose |
| --- | --- | --- |
| categories | Now | Global taxonomy tree. Each category has an `attribute_schema` (JSON Schema) saying which attributes it uses, so new item types (electronics, documents, home goods) need no migration. |
| category_translations | Seam | Names per locale. |
| items | Now | owner_user_id, household_id, `visibility` (private, household, friends, circle, public), kind, category, core typed columns (name, brand, size, colours, pattern, fabric, price_minor + currency, place, state, care counters, confidence, source, stub flag, return_by, warranty_until), `attributes jsonb` validated against the category schema, soft delete. |
| item_media | Now | Item ↔ media_assets with role (master, cutout, label, receipt) and position. Replaces item_photos. |
| item_embeddings | Now | vector(768) plus `model` and `model_version`, so we can re-embed with a new model side by side. |
| item_events | Now | Append-only history: state, place, owner and holder changes. Answers "where is it" and "who has it". |
| wear_logs, wear_log_items | Now | What was worn when, with whom, for which event. |
| beauty_details | Now | Opened date, period-after-opening, expiry, barcode. |
| documents_valuables | Later | Typed details for passports, warranties and gadgets (expiry, serial number), stored as sensitive. |

### 3.4 Media (one system for every file)

| Table | Phase | Purpose |
| --- | --- | --- |
| media_assets | Now | Every file in R2: owner (user or organisation), `purpose` (item_photo, wear_log, avatar_source, generated_look, post, portfolio, receipt, document, email_raw, export), r2_key, mime type, bytes, sha256, perceptual hash, width, height, `status` (pending, ready, quarantined, deleted), `sensitivity`. |
| media_variants | Now | Display, thumb and cutout renditions of an asset. |

Signed URLs are issued per asset after an access check that understands grants, so a stylist with a grant can see a client's item photos while the grant lasts, and only then.

### 3.5 Catalog, brands and retailers

| Table | Phase | Purpose |
| --- | --- | --- |
| products | Now | Shared catalog from barcodes, product pages and order emails. Unique `source_key`. Never stores who bought it. |
| brands, retailers | Seam | Normalised brand and store names (aliases for matching). Retailers hold the return-window rules and order-email templates. |
| email_templates, order_emails | Now | Order-email parsing (TECH_DESIGN section 9). |
| product_offers | Later | Price and affiliate link per retailer. |
| affiliate_clicks, campaigns | Later | Affiliate tracking and clearly labelled sponsored placements. |
| brand_insights | Later | Aggregated, anonymised trends only, with a minimum group size of 50 people. No user-level data is ever shared with brands. |

### 3.6 Planning and dro

| Table | Phase | Purpose |
| --- | --- | --- |
| looks, look_items | Now | `owner_user_id` (whose closet) and `author_user_id` (who made it: user, dro or a stylist). This is what lets stylists create looks for clients later without changes. `source`: user, rules, dro, stylist, community. |
| lookbooks, lookbook_looks | Seam | A named set of looks: trip, wedding week, or a stylist's deliverable. |
| calendar_events | Now | Events, festivals and trips the user plans for. |
| daily_picks | Now | One row per user per day, with reasons. |
| reminders | Now | Returns, dhobi pickups, ironing, expiry, lent items. |
| dro_conversations, dro_messages | Now | Chat history, with `handled_by` (rules, cache, ai). |
| answer_cache | Now | Cached answers. |
| suggestion_feedback | Now | Likes, skips and "not me" on picks and suggestions. The training signal for personal taste, with no AI cost. |
| shopping_list_items | Seam | Gaps to fill, wishlists, and later stylist recommendations with product links. |

### 3.7 Plans, entitlements and usage (pricing decided later)

| Table | Phase | Purpose |
| --- | --- | --- |
| plans | Now | Plan codes and names (free, pro, ultimate today; family, student, stylist_pro later). No prices or limits in code. |
| plan_prices | Now | Price per plan, `channel` (play, app_store, web), interval, currency, amount_minor, store product id, active window, optional experiment variant. |
| features | Now | Feature keys and type: `flag` (on/off), `limit` (e.g. max items), `quota` (per day or month, e.g. dro chats, Studio looks). |
| plan_features | Now | Value of each feature per plan. |
| entitlement_grants | Now | Why a user has access: subscription, trial, promo, referral, admin, household (family plan), org (a stylist's client perk). Has start and end. |
| user_entitlements (view) | Now | The effective plan and features per user, computed from active grants. The only thing the app and functions read. |
| usage_counters | Now | Quota use per user, feature and period. Updated atomically. |
| subscriptions | Now | Store and Razorpay subscription state (RevenueCat and Razorpay webhooks). |
| experiments, experiment_assignments | Seam | Price and paywall tests with sticky assignment. |
| offers, promo_codes, referrals | Seam | Founding offer, student offer, referral rewards: all data-driven. |

The server function `entitlement(user_id, feature_key)` is the single check every function uses.

### 3.8 Money: orders, payments, ledger and payouts

| Table | Phase | Purpose |
| --- | --- | --- |
| orders | Now | Anything bought: subscription start, credit pack, booking, kit, rental. Buyer, seller (platform, organisation or user), currency, totals, tax, status. |
| order_lines | Now | `line_type`: subscription, credit_pack, booking, kit, rental_fee, deposit, product, tip. Amount, tax rate, tax amount and HSN/SAC code per line. |
| payments, refunds | Now | Provider (razorpay, play, app_store), provider reference, status, raw payload in `private`. |
| ledger_accounts, ledger_entries | Now (`private`) | Double-entry ledger in minor units with currency. Accounts: platform revenue, store fees, tax payable, user credit wallets, provider payable, deposits held. Entries are immutable; every transaction balances to zero. |
| wallets (view) | Now | User balances by `credit_type`: studio_credits now; store credit and referral credit later. Derived from the ledger. |
| invoices | Seam | GST invoices with sequential numbering per financial year. |
| payout_accounts, payouts | Later | Razorpay Route linked accounts for stylists and partners, KYC status, commission splits, settlement schedule. |
| commission_rules | Later | Platform fee per service type or organisation. |

This replaces the separate `credit_ledger` table: Studio credits are a wallet on the same ledger. Adding stylist payouts or P2P rentals later needs no new money model.

### 3.9 Access grants (the key to sharing, stylists and support)

`access_grants`: Now.
- **Columns:** grantor_user_id; a grantee that is exactly one of a user, a circle, an organisation or a household; `scope` from a fixed list (closet_read, item_read, item_borrow, looks_write, places_read, measurements_read, support_view); an optional resource filter (one item, a category, a place); `purpose` (friend, family, consultation, support); an optional booking id; created_at, expires_at and revoked_at.
- **MVP use:** support access, which replaces the separate support grants table.
- **v1.1:** friends seeing a shared closet, family sharing, borrowing.
- **v1.2:** a stylist gets `closet_read` + `looks_write` for 7 days around a booking. The client sees exactly who can see what and can revoke it at any time.

RLS uses the helper `private.has_access(owner_user_id, scope, resource)`.

### 3.10 Social and community (v1.1)

| Table | Phase | Purpose |
| --- | --- | --- |
| connections | Later | Friend requests and status (pending, accepted, blocked). |
| circles, circle_members | Later | Groups: college friends, family, flatmates. |
| user_blocks, reports, moderation_actions | Later | Safety. Blocking hides both sides everywhere. Reports go to an admin queue. |
| posts, post_media, reactions, comments | Later | Sharing looks with circles, or publicly later. |
| challenges, challenge_entries | Later | "30 looks, 10 items" style challenges. |

### 3.11 Lending, swapping and resale (v1.1 → v2)

| Table | Phase | Purpose |
| --- | --- | --- |
| listings | Later | Item offered for lend, swap, rent or sell. Visibility (circle, friends, local), price and deposit, coarse location only (city or area, never exact). |
| exchanges | Later | A borrow, swap, rent or sale between two people, as a state machine: requested → accepted → handed_over → returned → closed, plus disputed and cancelled. MVP "lent to someone" also writes an exchange with a free-text counterparty, so history carries over. |
| exchange_events | Later | Transitions with condition photos at handover and return. |
| ratings | Later | After an exchange or booking: one rating per side. |

### 3.12 Stylists, consultations and services (v1.2 → v1.3)

| Table | Phase | Purpose |
| --- | --- | --- |
| service_offerings | Later | What a provider sells: video consultation, chat styling, async closet audit, occasion styling, tailoring, laundry pickup. Mode (video, chat, async, in_person), duration, price, currency, cancellation policy, active. |
| availability_rules, availability_exceptions | Later | Weekly hours and time off per provider, in the provider's timezone. |
| bookings | Later | Client, provider, offering, start and end, status as a state machine (requested → confirmed → in_progress → delivered → completed, plus cancelled, no_show, disputed), order link, meeting provider and room reference (video via a third party), notes. |
| booking_events | Later | Transitions and reminders. |
| deliverables | Later | What the stylist hands over: lookbooks, looks, shopping lists, notes, all linked to the booking. |
| provider_service_areas | Later | Pin codes served by tailors and laundries. |

Booking flow: the client books and pays (order + ledger; money held as provider payable) → an access grant is created for the booking window → the stylist builds looks in the client's closet (author is the stylist) → the client accepts the deliverable → payout is released minus commission → both sides rate.

### 3.13 Messaging and notifications

| Table | Phase | Purpose |
| --- | --- | --- |
| notifications | Now | In-app inbox: type, payload, read_at. Push is a delivery channel of this. |
| notification_preferences | Now | Per channel and type, quiet hours. |
| threads, thread_participants, messages | Later | Human-to-human chat for exchanges, bookings, support and circles. Attachments use media_assets. Realtime enabled. dro chat stays separate. |

### 3.14 Operations, security and analytics

| Table | Phase | Purpose |
| --- | --- | --- |
| app_config | Now | Settings, spend caps, min app version, return windows. |
| feature_flags | Now | Flags with targeting (plan, country, percentage, user list). |
| admin_users | Now | Staff roles: super_admin, admin, moderator, support, analyst, finance. |
| audit.log | Now | Append-only log of every staff action and every sensitive change. Partitioned by month. |
| private.domain_events | Now | Outbox. Partitioned by month. |
| private.webhook_events | Now | Provider idempotency. |
| private.idempotency_keys | Now | Client retries on POSTs (bulk add, purchases, bookings). |
| private.rate_limits | Now | Rate limiting. |
| private.ai_usage | Now | Every paid and in-house AI step, with cost. Partitioned by month. |
| deletion_requests, data_exports | Now | DPDP rights. |
| synonyms, unmapped_terms | Now | Dictionary for voice and search. |

## 4. Row Level Security model

Helper functions (in `private`, `SECURITY DEFINER`, `STABLE`, fully tested):

- `private.uid()`: the caller.
- `private.is_household_member(household_id, min_role)`
- `private.has_access(owner_user_id, scope, resource_ref)`: active, unexpired, unrevoked grant to the caller, their circle, their organisation or their household.
- `private.is_org_member(org_id, min_role)`
- `private.has_admin_role(role)`: also requires MFA (`aal2`).
- `private.is_blocked(a, b)`

Policy pattern for user-owned tables: the caller owns the row, OR the caller is a household member with a sufficient role and the row's visibility allows it, OR the caller has a grant with the matching scope. Sensitive tables only allow the owner, plus grants whose scope names them explicitly. Every helper and policy has pgTAP allow/deny tests, including expired and revoked grants and blocked users.

**Performance:** wrap helpers as `(select private.uid())` in policies so they run once per query; index every column a policy filters on; keep policies simple and push complex checks into the helpers.

## 5. Events, jobs and integrations

- **Outbox:** domain functions insert into `private.domain_events` (type, aggregate, aggregate_id, payload, occurred_at) in the same transaction. A dispatcher moves them to pgmq queues by topic: notifications, embeddings, search, analytics, and later partner webhooks.
- **Jobs:** pgmq consumers are idempotent and retry with backoff and a dead-letter queue. pg_cron runs schedules.
- **Analytics:** PostHog for product events from the app. Server-side, nightly roll-ups go into `private` summary tables. A warehouse is a later option fed from the outbox.
- **Partners later:** brands, retailers and service partners get scoped API keys (hashed, organisation-bound) and outbound webhooks fed from the same events.

## 6. Scale and reliability notes

- **Expected size at 1 lakh users:** about 1.5 crore items, 3 crore media rows, and 1–2 crore events a month. This is comfortable for a single Postgres with good indexes and partitioning of append-only tables. Read replicas are added before any sharding.
- **Partition by month:** audit.log, domain_events, ai_usage, notifications and later messages. Retention jobs drop old partitions instead of running large deletes.
- **Counters** (wear_count, ratings summary, follower counts) are maintained by triggers or jobs, never by counting rows on read.
- **Search** stays in Postgres (full-text + trigram + pgvector). A dedicated search engine is fed from the outbox only if needed.
- **Hot paths** (closet sync, where-is, daily pick) read only the caller's own rows through indexed keys.

## 7. What changes from TECH_DESIGN section 6

| Before | Now | Why |
| --- | --- | --- |
| homes | households + household_members | Family sharing and shared homes later without migration |
| item_photos | media_assets + media_variants + item_media | One media system for items, avatars, posts, portfolios, receipts and exports |
| plan_tier enum and profiles.plan | plans, plan_prices, features, plan_features, entitlement_grants, user_entitlements, usage_counters | Pricing decided later and changeable without releases; family, student and stylist plans later |
| credit_ledger | orders, payments and a double-entry ledger with wallets | Credits, packs, bookings, rentals, kits and payouts in one money model |
| `*_paise` columns | `*_minor` + `currency` | Global expansion |
| support_access_grants | access_grants | One sharing model for support, friends, family and stylists |
| looks without author | looks with owner_user_id + author_user_id + source | Stylists and dro author looks in a user's closet |
| No outbox | private.domain_events + pgmq | Notifications, embeddings, analytics and partner webhooks from one stream |

## 8. Configurable by design: change anything without a release

**Rule: if the business might want to change it, it lives in the database (or remote config), not in code.** The team should be able to change it from the admin panel, preview it, roll it out to a percentage of users, and roll it back, without a developer, an app-store release or a deploy.

### 8.1 What is configurable

| Area | Examples | Where it lives |
| --- | --- | --- |
| Pricing and plans | Plans, prices per channel/country, limits, quotas, trials, offers, promo codes, founding price, student price, credit packs, free-look unlock | plans, plan_prices, features, plan_features, offers, promo_codes (section 3.7) |
| Feature switches | Turn any feature on/off per plan, country, app version, platform, % of users or user list; kill switches for anything that costs money | feature_flags |
| Experiments | Price tests, paywall versions, onboarding variants, copy tests | experiments, experiment_assignments |
| App copy and content | Every user-facing string from the server (paywall text, onboarding, empty states, tips, dro's canned replies, push and email text), per locale, with fallback to the strings bundled in the app | content_strings, message_templates |
| Screens (server-driven layout) | Paywall layout and order of plans, home-screen cards and their order, onboarding steps, promo banners, "what's new" | ui_layouts (JSON validated against a schema the app understands) |
| Taxonomy | Categories, their attributes, icons, wash-after-wears defaults, care rules | categories + attribute_schema, category_translations |
| Dictionary | Synonyms in English, Hindi, Hinglish; voice-command phrases | synonyms, command_patterns |
| Rules engine | Outfit scoring weights, colour-harmony rules, weather thresholds, repeat rules, wash rules, festival and occasion rules, reminder timings | rule_sets (versioned JSON parameters read by packages/rules) |
| dro | Persona modes, system prompts, tool list, answer length per intent, which model per feature, cache times, router keywords | ai_prompts (versioned), ai_routes (feature → step → model, budget) |
| AI and cost controls | Per-user daily budgets, global spend caps, confidence thresholds for falling back to AI, batch vs live, provider choice (switch from Anthropic or FASHN to another provider with a config change) | app_config, ai_routes |
| Retailers and emails | Order-email templates, return windows, supported retailer hosts for links | email_templates, retailers |
| Notifications | Which reminders exist, timing, quiet hours defaults, frequency caps, templates per channel | notification_types, message_templates |
| Calendar data | Festivals, sale seasons, regional events per city or state | festivals / calendar_catalog |
| Limits and safety | Rate limits, upload sizes, allowed file types, moderation word lists, disposable-email blocklist | app_config, blocklists |
| Future modules | Commission rates, cancellation policies, service types, booking rules, deposit rules, countries, currencies, tax rates | commission_rules, service_types, policies, countries, tax_rates |
| App version control | Minimum app version, forced/soft update messages, maintenance mode | app_config |

### 8.2 How config works (so flexibility never breaks the app)

1. **One config registry.** Each config key is declared once in code with a Zod/JSON schema, a safe default, an owner, and whether a change needs approval. A value is rejected if it doesn't pass its schema.
2. **Versioned, never overwritten.** Each change creates a new version (`config_versions`: key, value, version, status [draft, scheduled, live, archived], author, approved_by, reason, created_at). Rolling back means making a previous version live again, in one click.
3. **Draft → preview → publish.** Admins edit a draft, preview it (as a specific test user, or a paywall/screen preview), then publish now or schedule it (e.g. a Diwali offer that starts and ends automatically).
4. **Targeting and gradual rollout.** Any value can have overrides by country, city, platform, app version, plan, user segment, experiment variant or % rollout. The most specific match wins.
5. **Safety:** changes to prices, payouts, AI budgets and kill switches need a second admin's approval (four-eyes rule). Every change is written to audit.log with before and after.
6. **Fast and cheap delivery.** The app fetches one config bundle (`config-bundle` function) at launch and every few hours, with an ETag so unchanged config costs nothing; it caches the last good bundle offline. The server caches config in memory per function instance for 60 seconds. Publishing bumps a config version so caches refresh.
7. **The app never breaks on bad or missing config.** The app ships with bundled defaults for everything. Unknown layout blocks are skipped, missing strings fall back to bundled text, and a failed config fetch uses the last cached bundle.
8. **Code reads config through typed helpers only** (`config.get('dro.max_answer_tokens', ctx)`, `flag('try_on', ctx)`, `copy('paywall.title', locale)`), never raw table reads. This makes every configurable value searchable and tested.
9. **Changing app code without a store release.** JavaScript and asset changes ship through Expo EAS Update (OTA) channels with staged rollout and rollback, within App Store and Play rules. Native changes still need a store release.
10. **Admin panel coverage.** Every table in 8.1 has an admin screen with search, validation, preview, history and rollback. Nobody edits config with SQL in production.

### 8.3 What stays in code on purpose

Security rules (RLS, auth, webhook verification), the ledger's accounting rules, privacy guarantees, data deletion and the licence bans. These must never be switchable by config.

## 9. Payments: gateway integration

**Our database is the source of truth for prices; payment gateways collect the money.** Prices are set in the admin panel (section 8) and pushed to each payment channel. We never read the price from the gateway or the app at checkout.

| What is sold | Where it is paid | Why |
| --- | --- | --- |
| Subscriptions and credit packs inside the Android/iOS app | Google Play Billing / Apple In-App Purchase, through RevenueCat | Store rules for digital goods. Check current rules on alternative billing in India (Google's user-choice billing) before launch. |
| Subscriptions and credit packs on drobie.app | Payment gateway (Razorpay first) | About 2% fee instead of 15% |
| Stylist consultations, tailor/dhobi services, kits and physical products, rentals and deposits | Payment gateway, in the app and on the web | Real-world services and physical goods are allowed to use a gateway in apps |
| Payouts to stylists and partners | Gateway's split/settlement product (Razorpay Route first) | Commission is taken automatically |

**Gateway-agnostic design:**
- One `payments` module with a `PaymentGateway` interface: create customer, create plan/price, create subscription, create order/checkout, verify webhook, parse event, refund, create payout account, split/transfer, fetch status.
- Razorpay is the first adapter. Cashfree, PayU or Stripe (for other countries) can be added as adapters without touching the ledger, entitlements or app screens.
- `payment_gateways` and `gateway_routes` config choose the gateway per country, currency, product type and channel, so we can switch or split traffic by config.
- `gateway_price_refs` maps each plan_price to the gateway's plan/price id and the store product ids. Publishing a price change in the admin panel creates the new price in the gateway (gateway plans and store prices are usually immutable, so we create new ones and move new buyers to them; existing subscribers keep their price unless we choose to migrate them). Store prices (Play/App Store) are set in their consoles and linked here; a check flags any mismatch.
- All webhooks follow the same path: verify signature → store event idempotently → normalise to our event types → update orders, payments, ledger and entitlement grants → emit domain events.
- A nightly reconciliation job compares gateway settlements and store reports with our ledger and flags any difference.
- Indian recurring-payment rules (RBI e-mandate: pre-debit notification, authentication limits) are handled through the gateway's subscription/mandate APIs; we store mandate status and send our own reminder before each charge.
- We never store card or bank numbers. Checkout uses the gateway's hosted or SDK checkout; we keep only gateway reference ids.
