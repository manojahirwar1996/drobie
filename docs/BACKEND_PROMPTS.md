# drobie — Backend build prompts for Claude Code

Step-by-step prompts to build the drobie backend with Claude Code, following the BRD, FRS, SRS and Technical Design.

> **Progress (updated 2026-10-13):** Steps 0–4 are done and on `main` (Step 3 still needs the dashboard settings in `docs/runbooks/auth-setup.md`). **Start with Step 5.** Before each step, Claude Code should read `docs/DATABASE.md`, `docs/API.md` and `docs/DECISIONS.md`, and reuse `supabase/functions/_shared` rather than rebuild it.

## How to use this file

1. Create the repo, then copy in this kit: `CLAUDE.md` at the root and the five specs into `docs/` (`BRD.md`, `FRS.md`, `SRS.md`, `TECH_DESIGN.md`, `PLATFORM_ARCHITECTURE.md`).
2. Run the steps **in order**, one step per Claude Code session (start a fresh session or `/clear` between steps). Paste the whole step, from its title to "Stop and report".
3. Use **plan mode** at the start of each step: let Claude Code read the docs and propose a plan; approve it before any code is written.
4. At the end of each step, review the diff, run the checks yourself, commit, and open a pull request. Do not start the next step until CI is green.
5. After every 2–3 steps, run the **Quality gate** prompt at the bottom of this file.

Steps 0–14 build the MVP backend on a data model that is ready for the whole platform. Steps 15–20 add the future modules (family and community, lending and swapping, Try it on, stylists and consultations, local services, brands, global) when each is due. Pricing is not final: everything about plans and prices is data, so it can be decided later.

---

## Step 0 — Kick-off and implementation plan

```
You are the lead backend engineer for drobie. Read CLAUDE.md fully, then docs/PLATFORM_ARCHITECTURE.md (the data model and future platform — it wins over TECH_DESIGN section 6), docs/SRS.md, docs/FRS.md, docs/TECH_DESIGN.md and the parts of docs/BRD.md about goals, users, journeys and guardrails.

Do NOT write application code in this step. Produce:

1. docs/IMPLEMENTATION_PLAN.md — the backend broken into the steps below (1–14, with 15–20 as future modules), plus a full ERD (Mermaid) of the MVP tables and the future tables they connect to, each with: scope, FRS/SRS IDs covered, tables and functions touched, risks, and how we will test it. Point out anything in the docs that is missing, ambiguous or contradictory, with a recommended resolution.
2. docs/DECISIONS.md — start the decision log with the decisions already made in the docs (stack, region, R2 for photos, in-house-first AI ladder, no phone sign-in, 18+ only, pricing as data with Free/Pro/Ultimate dro as starting plan codes and final prices TBD, Studio credits as a ledger wallet, the PLATFORM_ARCHITECTURE seams).
3. A version check: look up the current stable versions of the Supabase CLI, Deno for Supabase Edge Functions, pgvector, pgmq, Node LTS, pnpm, Turborepo, Zod, the Anthropic TypeScript SDK, RevenueCat webhooks and Razorpay Subscriptions APIs. List them with links in DECISIONS.md. Flag anything in the docs that is out of date.

Stop and report: summary of the plan, the open questions you need answered, and the versions you will use.
```

---

## Step 1 — Monorepo, tooling, local Supabase and CI

```
Goal: a clean monorepo that any developer can run locally in under 30 minutes, with CI enforcing quality from day one. Follow TECH_DESIGN section 10 and CLAUDE.md.

Build:
- pnpm workspaces + Turborepo with the folders in CLAUDE.md (apps/, packages/, supabase/, services/, workers/, docs/). Empty placeholder apps are fine; this step is backend-focused.
- TypeScript strict base config, ESLint + Prettier, shared tsconfig. Vitest for packages.
- `supabase init`, local config (Auth providers stubbed, email confirmations on), seed folder, pgTAP enabled for `supabase test db`.
- `supabase/functions/_shared/` placeholder and a `hello` health function with a Deno test.
- `.env.example` files listing every secret we will need (Supabase, R2, Anthropic, Resend, RevenueCat, Razorpay, Sentry, PostHog, embedder shared secret, email-worker HMAC secret), with placeholders only.
- GitHub Actions: on pull request run install, lint, typecheck, unit tests, `supabase start`, `supabase db reset`, `supabase test db`, `deno test` for functions. Cache pnpm. Fail on any warning in typecheck.
- Scripts: `pnpm dev`, `pnpm test`, `pnpm db:reset`, `pnpm db:types` (generates DB types into packages/shared).
- README with the "Run it locally" steps from TECH_DESIGN section 10.

Rules: no application features yet; ask before adding any dependency not named in CLAUDE.md.

Tests / done when: a fresh clone runs `pnpm install && pnpm db:reset && pnpm test` green; CI passes on a pull request; the health function test passes.

Stop and report: what was created, commands to verify, anything you could not set up.
```

---

## Step 2 — Database foundation: future-ready schema, RLS, tests

```
Goal: the core database for the MVP, built on the seams the whole platform needs (PLATFORM_ARCHITECTURE sections 2–4 and 7) so we never redo it. Secure by default. Follow CLAUDE.md conventions. Build only the tables marked "Now" and "Seam"; do NOT create "Later" tables.

Foundations:
- Extensions: pgcrypto, citext, pg_trgm, vector, pgmq, pg_cron (and pg_partman if available; otherwise native partitioning with a monthly job).
- Schemas: public (client tables, RLS), private (internals, not exposed by the API), audit. Revoke default privileges; expose only what the app needs.
- private.uuid_v7() and use it as the default id everywhere.
- Shared triggers: updated_at, immutable owner columns, domain-event helper `private.emit(type, aggregate, id, payload)`.
- RLS helpers from PLATFORM_ARCHITECTURE section 4 (uid, is_household_member, has_access, has_admin_role, is_blocked stub), SECURITY DEFINER with search_path = '', fully tested.

Tables (Now + Seam), with columns as in PLATFORM_ARCHITECTURE section 3:
- Identity: profiles (no plan column), consents, device_tokens, body_profiles (sensitive, seam).
- Households and places: households, household_members, places (nested, unique name per parent, depth limit 6), tags (seam).
- Closet: categories (with attribute_schema), category_translations (seam), items (typed core columns + attributes jsonb validated against the category's schema by a trigger or function; price_minor + currency; visibility; generated tsvector), item_media, item_embeddings (model + model_version, HNSW cosine), item_events, wear_logs, wear_log_items, beauty_details.
- Media: media_assets, media_variants.
- Catalog: products, brands, retailers (seam).
- Plans as data: plans, plan_prices, features, plan_features, entitlement_grants, usage_counters, subscriptions, experiments + experiment_assignments (seam), offers, promo_codes, referrals (seam); the view user_entitlements and the function entitlement(user_id, feature_key) returning the value for flags, limits and quotas; consume_quota(user_id, feature_key) that increments atomically and fails cleanly at the limit.
- Money: orders, order_lines, payments, refunds, invoices (seam); private.ledger_accounts and private.ledger_entries (double entry, immutable, each transaction sums to zero per currency, enforced by a deferred constraint trigger); wallets view by credit_type.
- Sharing: access_grants (exactly one grantee type enforced by a check; scopes as a fixed enum).
- Notifications: notifications, notification_preferences.
- Config (PLATFORM_ARCHITECTURE section 8): config_versions (versioned values with status, targeting overrides, schedule, author, approver), content_strings, message_templates, ui_layouts, rule_sets, ai_prompts, ai_routes, notification_types, blocklists, countries, tax_rates — all versioned with rollback.
- Ops: app_config, feature_flags, admin_users, audit.log (append-only, partitioned monthly), private.domain_events (partitioned), private.webhook_events, private.idempotency_keys, private.rate_limits, private.ai_usage (partitioned), deletion_requests, data_exports, synonyms, unmapped_terms.
Later steps add: order_emails, email_templates, looks, lookbooks, calendar_events, daily_picks, reminders, dro tables, answer_cache, suggestion_feedback, shopping_list_items.

Security:
- RLS on every public table, default deny, using the helpers. Owner access; household access by role and item visibility; grant-based access by scope; sensitive tables owner-only unless a grant names them. Global tables (categories, products, brands, plans, plan_prices, features, plan_features) readable by authenticated users, never writable by clients.
- Clients can never write entitlements, subscriptions, ledger, usage_counters, profiles.status or any owner column. Column grants + triggers + tests.
- Check constraints everywhere (non-negative money and counters, confidence 0–1, currency format, valid date ranges, exactly-one grantee).
- Indexes: every foreign key and every column used in a policy or a hot query (items by owner+state, owner+category, owner+updated_at, owner+place; GIN on tsvector; trigram on name/brand; HNSW on embeddings; grants by grantee and expiry).

Tests (pgTAP): allow/deny for every table (owner, other user, household member by role, valid grant, expired grant, revoked grant, anon); protected columns; ledger always balances; entitlement() for each feature type; consume_quota at and over the limit, concurrently; attribute_schema validation; partition creation.

Seed: taxonomy with attribute schemas (western and Indian wear, footwear, accessories, jewellery, bags, beauty, documents/valuables); plans free/pro/ultimate with features and PLACEHOLDER prices clearly marked "TBD" (items limit, dro chats per day, Studio looks per month, free looks unlock at 30 items); ledger accounts; feature flags; a local-only test user with a 200-item closet; a second user and a household member for RLS tests.

Then generate DB types into packages/shared and Zod schemas for every insert/update shape.

Stop and report: ERD (Mermaid), policy list, test results, query plans for the hot paths, and anything you had to interpret.
```

---

## Step 3 — Auth, profiles and account lifecycle

```
Goal: free, safe sign-in and a clean account lifecycle. Follow FRS 3.1 (FR-ONB), SRS sections 4 and 6, TECH_DESIGN section 7.

Build:
- Supabase Auth: Google, Apple, and email (password, email OTP, magic link). No phone/SMS/WhatsApp providers. Email sending via Resend SMTP. OTP/link expiry 10 minutes. Configure redirect URLs for the Expo app (deep link) and drobie.app.
- On signup: trigger creates profiles (country IN, locale en-IN, currency INR, timezone Asia/Kolkata), a personal household with the user as owner, a starter set of places (Wardrobe, Drawer, Shoe rack), a free-plan entitlement grant, and a unique random inbound_token.
- `confirm-adult` function: records adult_confirmed_at; every user-facing function (later steps) rejects users without it (shared middleware).
- Consents: `set-consent` function writing versioned rows for email_import, gallery, calendar, measurements, marketing.
- Session security: short access tokens (1 hour), refresh rotation on; document how the app must store refresh tokens (Keychain / Keystore).
- Rate limits on auth endpoints configured in Supabase; our own Postgres-backed rate limiter in _shared for functions (per user and per IP).

Tests: trigger creates profile/household/places/free entitlement; users without adult confirmation are rejected; consent history is append-only; rate limiter unit tests.

Stop and report: auth configuration checklist (what must be set in the Supabase dashboard, Google Cloud and Apple Developer), test results.
```

---

## Step 4 — Shared function library (_shared)

```
Goal: one well-tested library every Edge Function uses, so security, validation, logging and cost tracking are consistent. Follow CLAUDE.md conventions and SRS section 10 (CE-44 to CE-48).

Build in supabase/functions/_shared:
- `http.ts`: request handler wrapper (CORS for our origins only, request id, JSON parsing with size limit, error envelope { error: { code, message } }, correct status codes, no stack traces to clients).
- `auth.ts`: get the caller from their JWT (user-scoped Supabase client for RLS-bound queries); separate service client only for privileged steps; `requireAdult`, `requireAdminRole(role)`.
- `validate.ts`: Zod helpers.
- `ratelimit.ts`: Postgres-backed token bucket (per user, per IP, per feature).
- `log.ts`: structured JSON logs with request id, user id hash, function, duration; PII scrubbing.
- `sentry.ts`: Sentry for Deno with PII off.
- `idempotency.ts`: webhook_events insert-or-skip.
- `config.ts`: the config registry — every key declared once with a Zod schema, safe default, owner and approval flag; typed helpers `config.get(key, ctx)`, `flag(key, ctx)`, `copy(key, locale)`; targeting resolution (country, city, platform, app version, plan, segment, experiment, % rollout; most specific wins); 60-second in-memory cache refreshed when the config version changes.
- `config-bundle` function: returns the client config bundle (flags, copy, layouts, limits, rule-set parameters, min app version) with an ETag; 304 when unchanged.
- `entitlements.ts`: `can(user, feature)`, `limit(user, feature)`, `consume(user, feature)` wrapping the SQL functions. The ONLY way any function checks plan access.
- `events.ts`: emit domain events inside the same transaction; queue consumer helper with retries, backoff and dead-letter.
- `idempotency-key.ts`: honour an `Idempotency-Key` header on POSTs that create things (bulk add, purchases, bookings later).
- `ai-provider.ts`: the ONLY place that calls paid AI. Interface: `chat`, `vision`, `batch`. Anthropic implementation with prompt caching (fixed system prompt and tool definitions first, cache_control set), strict JSON-schema output where needed, timeouts and retries with backoff. Before every call: check per-user daily budget and the global daily spend cap from app_config; if exceeded, throw a typed `BudgetExceeded` so callers fall back to rules. After every call: insert into private.ai_usage (feature, step='ai', model, tokens, cost_minor (INR) computed from a price table in app_config, latency).
- `r2.ts`: S3-compatible signing (aws4fetch or equivalent, MIT/Apache) for presigned PUT/GET with short expiry; keys always prefixed `u/<user_id>/`.

Tests: every module unit-tested (deno test), including budget-exceeded fallback, cost calculation, idempotency, rate limits, CORS, error envelope.

Tests also cover: invalid config rejected by schema, targeting precedence, fallback to defaults when config is missing, rollback to a previous version.

Stop and report: module APIs, test results, and a short example function using them.
```

---

## Step 5 — Photo storage on R2

```
Goal: fast, private, cheap photo storage. Follow SRS 10.4 (CE-24 to CE-29) and TECH_DESIGN section 7 (Photos).

Build:
- A generic media service on media_assets / media_variants (PLATFORM_ARCHITECTURE 3.4), used by items now and by avatars, posts, portfolios, receipts and exports later.
- `media-upload-url`: input purpose, content type (allow-list per purpose; image/webp for item photos), byte size (per-purpose limits: 600 KB master, 200 KB display, 60 KB thumb), sha256. Creates a pending media_assets row and returns a presigned PUT URL (5-minute expiry) for key `u/<user_id>/<purpose>/<media_id>/<variant>.webp`.
- `media-confirm`: verifies the object exists in R2 with the expected size and hash, marks the asset ready, and links it (e.g. item_media for an item, replacing the older master).
- `media-read-urls`: batch of presigned GET URLs (1-hour expiry) after an access check through has_access (owner now; household, friends and stylist grants later work without changes); one call per screen.
- Clean-up job (pg_cron + function): delete unconfirmed uploads and temporary previews older than 24 hours; delete all R2 objects of purged accounts.
- Document the R2 bucket settings (private, CORS for our app origins, lifecycle rule) in docs/runbooks/r2.md.

Security: ownership checked on every call; never accept a client-supplied key; content type and size enforced; keys never reveal names.

Tests: cannot get URLs for another user's item; wrong size or hash rejected; clean-up removes the right objects (mock R2 client in tests).

Stop and report: API contracts for the app team, cost per user estimate, test results.
```

---

## Step 6 — Adding items I: items API, product catalog, links, duplicates

```
Goal: the server side of "effortless adding". Follow FRS 3.2b (FR-ADD-01 to 11, FR-ADD-R1 to R5), SRS section 11 and TECH_DESIGN section 9.

Build:
- `items-bulk-upsert`: the app sends one or many items with their on-device results (category, colours, pattern, confidence, tag_source, place). Server validates, enforces the plan's item limit from app_config, sets is_stub for name-only items, writes item_state_events, and returns saved items. Must handle 50 items in one call under 1 second.
- `items-sync`: keyset delta sync (changed since cursor) for the offline closet, including soft deletes.
- `check-duplicates`: given phash, colours, category (and later an embedding), returns likely duplicates from the caller's closet with a similarity score. In-house only.
- `ingest-link`: input URL or shared text. Fetch server-side with SSRF protection (https only, allowlist of retailer hosts plus a generic path, block private and link-local IPs after DNS resolution, max 2 MB, 5-second timeout, no cross-host redirects). Extract product data from schema.org JSON-LD and Open Graph (name, brand, image, price, colour, product id). Upsert into products by source_key (cache), return an item draft. Only if no structured data: return `needs_photo` (no AI call in this step).
- Keyword categoriser in packages/shared: maps product titles ("Men Slim Fit Cotton Shirt", "Women Anarkali Kurta") to our taxonomy using a dictionary; unit-test it with 200+ real Indian product titles (write the fixtures).

Rules: no paid AI in this step. Every path logs `answer_step` for analytics.

Tests: limits enforced per plan; SSRF tests (private IP, redirect to another host, oversized page); JSON-LD fixtures for Myntra, Ajio, Amazon, Flipkart, Nykaa, H&M, Zara, Meesho; categoriser accuracy ≥ 90% on the fixtures.

Stop and report: API contracts, categoriser accuracy, gaps in retailer coverage.
```

---

## Step 7 — Adding items II: order emails and fallback tagging

```
Goal: closets that fill themselves from order emails, with paid AI only as a rare fallback. Follow FRS FR-ADD-01, FR-CAP-13, SRS 11.2 and TECH_DESIGN section 9.

Build:
- Tables: order_emails (user_id, received_at, original_from_domain, subject, template_id, status [parsed, needs_ai, failed, ignored, confirmation], raw_r2_key, parsed jsonb, error), email_templates (retailer, from_domains, version, rules jsonb, active), plus RLS (users read their own order_emails; templates admin-only).
- workers/email-inbound: Cloudflare Email Worker for `*@in.drobie.app`. Reads the token from the address, rejects unknown tokens, stores the raw MIME in R2 (encrypted bucket path), and POSTs metadata to `ingest-order-email` with an HMAC signature and timestamp (reject if older than 5 minutes).
- `ingest-order-email`: verify HMAC; parse MIME (MIT/Apache library); detect Gmail/Outlook forwarding-confirmation emails and surface the code/link to the user (needed for one-time forwarding setup); match a retailer template by original sender domain and structure; extract items (name, size, colour, price, quantity, image URL, order id, order date, delivery date) and returns/cancellations; create item drafts linked to products; set return_by from the retailer's return window table in app_config; queue a return reminder.
- Templates for the top 8 retailers (Myntra, Ajio, Amazon.in, Flipkart, Nykaa/Nykaa Fashion, H&M, Zara, Meesho). Build them from real anonymised sample emails (ask me for samples; never commit personal data).
- Unknown format → status needs_ai → queue for the AI fallback; also log it so an admin can add a template.
- `refine-item` worker (pgmq consumer): processes items with tag_confidence below the threshold in app_config and needs_ai emails, using ai-provider `batch` (Anthropic Batch API) overnight; validates output against a JSON schema; writes tag_source='ai'. Never re-tag an item already confirmed by the user.

Security: only the owner sees their emails; raw emails deleted after 30 days; nothing from email bodies is logged.

Tests: fixtures per retailer (orders, returns, cancellations, multi-item orders); forwarding-confirmation detection; HMAC and replay protection; AI fallback path with a mocked provider; budget-exceeded path leaves items for the user to tag.

Stop and report: template coverage, % of fixture emails parsed without AI (target ≥ 90%), cost estimate per 100 emails.
```

---

## Step 8 — Dictionary, voice commands, search and similarity

```
Goal: search and voice that work without AI. Follow SRS sections 8 and 11.1, FRS FR-ADD-03/04, FR-CAT and "where is it" requirements, TECH_DESIGN section 9 (parse-command, search, embed-item).

Build:
- Tables: synonyms (term citext, lang, maps_to_type [category, colour, place, state, occasion, season, action], maps_to_value, source [seed, admin, learned]) and unmapped_terms (term, count, last_seen). Seed English, Hindi and Hinglish terms (almari = wardrobe, daraaz = drawer, kurta, dupatta, juttis, presswala, dhobi, etc.).
- packages/shared `parse-command`: deterministic grammar for "add …", "keeping X in Y", "X is in Y", "where is X", "gave X to Y, back by Z", "moved all X to Y", plus quantity, brand, colour, price and date extraction. Pure TypeScript, used on the phone; the `parse-command` function wraps it server-side and returns candidate items and places with scores. Unparsed phrases go to unmapped_terms and, only if the user asks again, to ai-provider (small, logged).
- `search`: dictionary parser → filter chips (category, colour, state, place, occasion, season, brand) → SQL with FTS/trigram, ranked; optional vector similarity when the query is "like this item". Keyset pagination. Under 300 ms p95 on a 1,000-item closet.
- `place-item` and `where-is`: set or answer an item's place with history (item_state_events); "where is" must answer from SQL in under 100 ms.
- services/embedder: FastAPI + Marqo-FashionSigLIP (Apache-2.0) on CPU, endpoints /embed-image and /embed-text, shared-secret auth, batch support, health check, Dockerfile, model downloaded at build time.
- `embed-item` pgmq consumer: one embedding per item, computed once (re-run only when the master photo changes); `similar-items` RPC using the HNSW index, restricted to the caller's items.

Tests: parser test suite with 300+ phrases (English, Hindi, Hinglish), search relevance fixtures, latency checks, embedder contract test with a tiny fixture image, RLS on similarity.

Stop and report: parser coverage, latency numbers, embedder memory/CPU footprint and hosting suggestion.
```

---

## Step 9 — Rules engine, daily picks, care and reminders

```
Goal: the daily habit runs with zero AI cost. Follow FRS 3.4, 3.5 and 3.7, SRS section 8 (morning pick row) and section 10 (CE-11, CE-35, CE-36, CE-39).

Build:
- packages/rules (pure TypeScript, deterministic, no I/O; every weight, threshold and rule is a parameter loaded from a versioned rule_set, with bundled defaults): outfit scoring (weather, item state, wash status, colour harmony, occasion, repeat rules, user taste weights), morning pick with 2 alternates, evening-before card, week plan, office rotation, packing list, wash status inferred from wears (default_wash_after_wears per category), "rescue the buried" suggestions. Every result includes `reasons` (the real inputs used) for the "thinking" UI.
- Tables: looks, look_items, daily_picks (user_id, date unique, items, reasons, weather), festivals, reminders (user_id, item_id, kind, due_at, sent_at, payload).
- Weather: cached per city per hour (one external call per city per hour, not per user).
- `morning-pick` cron: pre-computes daily_picks for active users in the off-peak window, respecting each user's timezone and morning_time.
- `log-wear`: records wear_logs, increments counts, updates wash status and state events.
- `send-reminders` cron: due reminders (returns, pickups, ironing, expiry, lent items) sent via Expo push, respecting quiet hours and max 1 marketing push a day; device tokens cleaned on errors.
- Make packages/rules importable by Edge Functions (single source of truth; add a CI check that the function copy matches the package build if a copy is needed).

Tests: rules engine unit tests with snapshot fixtures (100+ scenarios including Indian wear and festivals), cron idempotency, timezone handling, quiet hours.

Stop and report: rules engine API, performance (target < 300 ms per user), cost per 10,000 users per day.
```

---

## Step 10 — ask-dro (rules first, Haiku last)

```
Goal: dro answers fast and cheaply. Follow FRS 3.6 (FR-DRO-01 to 10), FRS 7 (FR-CST), SRS section 8 (dro chat row) and 10.1 (CE-01 to CE-12), TECH_DESIGN section 9 (ask-dro).

Build:
- Tables: dro_conversations, dro_messages (role, content, cards jsonb, intent, handled_by answer_step, tokens, cost_minor), answer_cache (key = hash of intent + normalised question + relevant item ids + closet version; 24-hour expiry).
- Intent router (rules; keywords and intents from config, not code): lookup (where is, how many, what's clean, what's at the dhobi), action (mark worn, send to dhobi, lend, move), plan (today, week, trip), style question (open), other.
- Handlers: lookups and actions answered by SQL and packages/rules with item cards and an Undo token; plans from the rules engine.
- Open styling questions: retrieve the top ~20 relevant items (filters + vector), build compact item JSON, call ai-provider `chat` with the model chosen by ai_routes (Claude Haiku 5.5 by default), a versioned system prompt from ai_prompts (cached) (dro persona modes from the BRD, style rulebook, safety rules), tool definitions for actions, JSON output for cards, short answers by default (output token cap per intent), streaming. Sonnet only when the user taps "think harder".
- Limits: per-plan daily caps from app_config, shown to the client; global spend cap falls back to rules-only answers with a friendly message.
- Prompt safety: user text and item data wrapped as data; tool calls validated server-side; never reveal other users' data; no body-shape comments.
- Eval set: 100 test questions in docs/evals/dro.jsonl with expected handler and quality notes; a script that reports the % answered without AI (target ≥ 80%) and cost per 100 questions.

Tests: router classification tests, action + Undo, cache hits, budget fallback, streaming, prompt-injection fixtures.

Stop and report: eval results, cost per active user per month estimate, latency (first token < 2 s for AI answers, < 1 s for lookups).
```

---

## Step 11 — Plans, payments, ledger and credits

```
Goal: one entitlement across Play, App Store and the web; all money and credits through the ledger; pricing fully data-driven because final prices are not decided yet. Follow PLATFORM_ARCHITECTURE 3.7–3.8, FRS 3.12 (FR-PAY), FRS 7 (FR-CST-05 to 12), SRS 10.7.

Build:
- Price catalog API: `plans-catalog` returns plans, features and prices for the caller's channel, country and experiment variant (from plan_prices). The app renders the paywall from this; nothing hard-coded. The iOS channel never receives web prices or links.
- `revenuecat-webhook`: verify the authorization header, idempotent by event id, map store product ids to plans via plan_prices, update subscriptions, create/end entitlement_grants, record orders/payments and post ledger entries (gross, store fee, tax, net revenue).
- Payments module (PLATFORM_ARCHITECTURE section 9): a `PaymentGateway` interface with Razorpay as the first adapter; payment_gateways, gateway_routes and gateway_price_refs config; publishing a price in admin creates the matching gateway plan/price; a mismatch check against store product prices; nightly reconciliation of settlements against the ledger; mandate status and pre-debit reminders.
- Razorpay web: `razorpay-create-subscription` (plan and price looked up server-side from plan_prices for channel 'web'; never from the client) and `razorpay-webhook` (verify X-Razorpay-Signature HMAC-SHA256 over the raw body; idempotent; activated, charged, halted, cancelled, completed, payment failed); orders, payments, ledger, entitlement grants.
- Credits as a wallet on the ledger (credit_type 'studio_credits'): pack purchases (store consumables and Razorpay orders), monthly grants for plans whose plan_features include a Studio quota, the free-looks unlock (amount and threshold from plan_features/app_config; once per person; block disposable email domains), web bonus percentage from app_config. Spending a credit = a ledger transaction; a balance never goes negative (checked under row lock).
- `generate-look` skeleton behind a feature flag: cache by outfit hash; reserve a credit; call the image adapter interface (implemented in Step 17); release or refund automatically on failure; first regenerate free.
- Offers and promo codes (founding price, student, referral) applied as data: an offer changes the plan_price or grants credits/entitlements; all through the same paths.
- Trials, grace periods, upgrades and downgrades (proration handled by the store / Razorpay; our grants follow the provider's events).
- GST: tax amount and rate per order line; invoice records for web purchases (numbering per financial year) — PDF generation can come later.

Security: plans, prices, entitlements and balances change only through these paths; webhooks verified and idempotent; all amounts amount_minor + currency.

Tests: webhook fixtures for every event type including out-of-order and duplicates; signature failures; entitlement transitions; ledger balances after every scenario; concurrent credit spends; price changes in plan_prices take effect without code changes; experiment assignment is sticky.

Stop and report: product id mapping, ledger account list, test results, manual setup checklist for RevenueCat, Play Console, App Store Connect and Razorpay.
```

---

## Step 12 — Admin backend, config and cost dashboards

```
Goal: safe tools for the team, with every action audited. Follow TECH_DESIGN section 5 and FRS section 4 (FR-ADM), SRS 10.8.

Build:
- Use admin_users (roles super_admin, admin, moderator, support, analyst, finance), audit.log (append-only) and access_grants with purpose 'support' (user-approved, time-limited, scope support_view) from Step 2.
- `has_admin_role(role)` SQL helper; admin functions check role + MFA (aal2) and write audit.log in the same transaction. Finance role: read-only access to orders, payments, ledger reports and GST summaries.
- Admin functions: users list/search by email or id (masked), suspend/ban with reason, view account summary (no photos unless a support grant exists), edit app_config, feature flags, plans, plan_prices, plan_features, offers and experiments with validation and a preview of who is affected (pricing is decided here, not in code), manage email_templates and synonyms (review queue from unmapped_terms and needs_ai emails), taxonomy and festivals, broadcasts (scheduled, previewed, rate-limited).
- Config console: for every configurable table — search, edit as draft, schema validation, preview as a test user (paywall, home cards, onboarding, push/email text), schedule start/end, % rollout and targeting, version history, one-click rollback, four-eyes approval for prices, payouts, AI budgets and kill switches.
- Cost and usage views: daily roll-ups (pg_cron) of ai_usage by feature, step and model; paid-AI share of items; storage per user; cost per active user; top 1% heaviest users. Alert function (email/Slack webhook) when any SRS section 10 target is crossed.

Tests: role matrix tests (each role allowed/denied for each function), audit rows written for every change, MFA required, analysts read-only.

Stop and report: admin API list for the admin-panel team, role matrix, alert thresholds.
```

---

## Step 13 — Privacy, data rights and retention

```
Goal: DPDP-ready data rights and retention. Follow TECH_DESIGN section 7 (Privacy and deletion), SRS section 6 and 7, BRD guardrails.

Build:
- `export-data`: builds a ZIP (JSON of all the user's rows + their photos) in R2, emails a 24-hour signed link; rate-limited to once a day.
- `delete-account`: immediate soft delete (profile and items hidden, sessions revoked, push tokens removed), deletion_requests row, purge job after 30 days removing all rows and R2 objects, then auth user deletion; confirmation email. Cancels active web subscriptions and explains store subscriptions.
- Retention jobs: raw order emails after 30 days, unsaved previews after 24 hours, ai_usage detail rolled up after 90 days, inactive-account cold-storage warning flow (flagged off until v1.1).
- Grievance contact and consent version stored in app_config; consent re-prompt when the version changes.
- Logging audit: scan the codebase for PII in logs and remove it.

Tests: export completeness test against the seed user, purge removes everything (rows and mocked R2), deleted users cannot sign in or be found, retention jobs idempotent.

Stop and report: data map (what we store, where, how long), test results.
```

---

## Step 14 — Hardening, performance and release readiness

```
Goal: confidence before beta. Follow SRS sections 6 and 9 and TECH_DESIGN sections 7, 8 and 10.

Do:
- Security review: walk every table and function against TECH_DESIGN section 7; threat model (STRIDE) in docs/security/threat-model.md; confirm no service_role usage outside functions; dependency and licence audit (fail CI on GPL/AGPL); secret scanning in CI.
- Performance: k6 load tests for items-sync, items-bulk-upsert, search, where-is, ask-dro (rules path) at 100 and 1,000 concurrent users; fix slow queries with EXPLAIN ANALYZE; verify budgets in TECH_DESIGN section 8.
- Reliability: backups and a restore drill on staging; runbooks in docs/runbooks (incident, AI provider down, R2 down, webhook failures, cost spike).
- Staging pipeline: on merge to main, migrations and functions deploy to staging; production deploy on tag with manual approval.
- Cost check: run the seed workload and report cost per active user against SRS section 10 targets.

Stop and report: security findings and fixes, load-test results, cost report, remaining risks before beta.
```

---

## Future modules (run when each is due, same rules as above)

Each future step starts by re-reading CLAUDE.md, PLATFORM_ARCHITECTURE and the FRS section for that feature, writes a short plan, and only adds tables marked "Later" for that module. No rework of MVP tables should be needed; if it is, stop and explain why before changing anything.

### Step 15 — Family, friends and circles (v1.1)

```
Build PLATFORM_ARCHITECTURE 3.10 and household sharing: household invites and roles; connections (requests, accept, block); circles and members; user_blocks, reports, moderation queue; access grants created and revoked from sharing settings; item visibility enforced in every read path; family plan as an entitlement grant shared through the household. Tests: every visibility × relationship × role combination, block hides both sides, revoked grants take effect immediately. Stop and report.
```

### Step 16 — Lending, swapping and resale (v1.1 → v2)

```
Build PLATFORM_ARCHITECTURE 3.11: listings, exchanges as a state machine, exchange_events with condition photos, ratings, threads/messages for each exchange, reminders for return dates, deposits and rental fees through orders + ledger (held, released, forfeited). Coarse location only. Tests: every transition allowed/denied, ledger balances in each path, disputes freeze funds. Stop and report.
```

### Step 17 — Avatar and Try it on (v1.1)

```
Build avatars (sensitive, consent required, deletable), the image-generation adapter (Gemini Flash Image–class default, FASHN for "make it exact") behind ai-provider with cost logging, the generated-look cache, credit spending through the ledger, and safety checks on inputs and outputs. Tests: no generation without consent and credit; refund on failure; cache hit costs nothing. Stop and report.
```

### Step 18 — Stylists and consultations (v1.2)

```
Build PLATFORM_ARCHITECTURE 3.12 and 3.1 (organizations, org_members, professional_profiles): stylist onboarding with KYC and verification, service offerings, availability in the stylist's timezone, slot search, bookings as a state machine, payment into provider payable on the ledger, a booking-scoped access grant (closet_read + looks_write, measurements only with explicit client consent), deliverables (lookbooks, looks authored by the stylist, shopping lists), video room via a third-party provider (adapter), reviews, cancellations and refunds by policy, payouts through Razorpay Route with commission_rules, a stylist dashboard API, and admin review of stylists. Tests: a stylist can see a client's closet only during the grant window; payouts equal paid amount minus commission and tax; no double booking under concurrency. Stop and report.
```

### Step 19 — Local services: tailor, dhobi, alterations (v1.3)

```
Reuse Step 18 for service providers with in-person/pickup modes: service areas by pin code, pickup and drop slots, item state updates (at_tailor, at_dhobi) driven by booking events, photos at handover, partner app API with org-scoped keys. Stop and report.
```

### Step 20 — Brands, retailers and global (v2 → v3)

```
Brands/retailers as organizations with scoped API keys and outbound webhooks from the outbox; product_offers, affiliate_clicks and labelled campaigns; brand_insights as anonymised aggregates with a minimum group size of 50; then new countries: currency and tax per country, category translations, locale-aware dictionary, region-aware storage if residency rules require it. Stop and report.
```

---

## Quality gate (run after every 2–3 steps)

```
Act as a strict reviewer who did not write this code. Review everything changed since the last quality gate against CLAUDE.md, docs/PLATFORM_ARCHITECTURE.md, docs/SRS.md and docs/TECH_DESIGN.md:

1. Security: RLS on every table with allow/deny tests; protected columns; no service_role in client paths; webhook signatures and idempotency; SSRF and injection risks; secrets handling.
2. Data: migrations reversible or safely forward-only; indexes for every query path; keyset pagination; constraints.
3. Cost: any paid call outside ai-provider? Every paid call logged with cost? Caches and limits in place? Rules-first ladder respected?
4. Privacy: PII in logs, consent checks, data minimisation.
5. Quality: types, error handling, tests that actually assert behaviour, flaky tests, dead code.
6. Future-readiness and flexibility: anything hard-coded that should be config (plans, prices, limits, copy, layouts, rule weights, prompts, models, timings, currencies, categories)? Does every config key have a schema, default, and rollback? Anything that would block households, grants, stylists or other countries later?
7. Docs: DECISIONS.md and docs updated.

Output a prioritised list (critical, high, medium, low) with file and line references, then fix critical and high items, re-run all checks, and report.
```

## If Claude Code gets stuck

- Ask it to restate the requirement from the docs and list what it has tried.
- Reduce scope: finish the smallest testable slice, commit, then continue.
- For anything touching money, auth, RLS or deletion, require tests first, then code.
