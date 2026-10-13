# CLAUDE.md — drobie

Read this file at the start of every session. It is the standing brief for anyone (human or AI) writing code in this repo.

## What we are building

**drobie** is an AI wardrobe app for 18–30-year-olds in India, Android and iOS together at launch, with the assistant **dro** ("hey dro"). Tagline: *Hang out with your wardrobe.* Company: Drobie Labs.

The core promise: **adding clothes and personal items is the simplest and fastest people have ever seen**, and the app then plans outfits, answers "where is it?", tracks care, and saves money — while running at about **₹1.5 per active user per month** at scale.

## Source documents (in `docs/`)

| File | Use it for |
| --- | --- |
| `docs/SRS.md` | **How** to build: stack, interfaces, NFRs, data, AI ladder (section 8), cost rules CE-01…CE-48 (section 10), capture engine and model choices (section 11) |
| `docs/FRS.md` | **What** each feature must do, with IDs (FR-ADD-…, FR-CAP-…, FR-DRO-…, FR-CST-…) and acceptance criteria |
| `docs/TECH_DESIGN.md` | Architecture, modules, database design (section 6), security (section 7), server functions (section 9), repo and CI (section 10), build order (section 11) |
| `docs/PLATFORM_ARCHITECTURE.md` | The future-ready data model and platform rules (households, media, plans as data, money ledger, access grants, events, future modules: community, lending, stylists, services, brands, global) |
| `docs/BRD.md` | Why: business goals, users, journeys, guardrails |

If documents disagree: **PLATFORM_ARCHITECTURE wins for the data model, SRS wins for other technical decisions, FRS wins for behaviour.** If something is missing or contradictory, stop and ask; record the decision in `docs/DECISIONS.md`.

## Non-negotiables

1. **Security lives in the database.** Every table has Row Level Security enabled, default deny. Users can only touch their own rows. The mobile app only ever holds the user's JWT and the public anon key. The `service_role` key is used only inside server functions, never in apps.
2. **In-house first, paid AI last.** Every task walks this ladder and stops at the first confident step: rules and SQL → on-device models (results sent by the app) → our own server (embedder) → paid AI. Paid AI is only for open-ended dro chat, Try it on, and low-confidence fallbacks. Every paid call is logged in `ai_usage` with cost.
3. **Privacy by default.** 18+ only. Nothing shared without explicit choice. Consents recorded with version. Export and deletion work end to end. No PII in logs. Built to India's DPDP Act.
4. **Money and limits are server truths.** Plans, entitlements, credits and limits change only through verified webhooks or server functions. Never trust the client for plan, price, credits or limits.
5. **Licences.** Only commercially usable licences (MIT, Apache-2.0, BSD, CC BY). **Never** use Ultralytics YOLO (AGPL), YOLO-World (GPL), BRIA RMBG, InsightFace models, or anything trained on DeepFashion, DeepFashion2, LIP or ATR. Retailer product photos are shown to their owner but never used for training.
6. **Build for the platform, not just the MVP.** drobie will add family sharing, friends and circles, lending and swapping, stylists and consultations, local services, brands and other countries. Build the seams in PLATFORM_ARCHITECTURE now (households, media_assets, plans as data, money ledger, access grants, outbox events, currency); add feature tables later with additive migrations. Do not build future features early.
7. **Pricing is data.** No plan names, prices, limits, trials or offers in code. Everything is read from the plans/features tables through `entitlement(user_id, feature_key)`. Pricing will change; code should not have to.
8. **Configurable by design.** If the business might want to change it (prices, limits, copy, screen layouts, categories, synonyms, rule weights, dro prompts, AI models and budgets, notification timing, retailer templates, commissions), it lives in versioned config with a schema, a safe default, targeting and rollback (PLATFORM_ARCHITECTURE section 8). Code reads it only through typed helpers (`config.get`, `flag`, `copy`). Security, ledger rules, privacy and deletion are never configurable.
9. **Cost awareness.** Follow SRS section 10 (CE rules). Any feature that calls AI, stores files or sends notifications must state its cost per use, log it, cache or limit it, and have a fallback when the paid service is down or over budget.

## Stack (check current versions before installing; do not downgrade)

- Monorepo: pnpm workspaces + Turborepo, TypeScript `strict` everywhere.
- Backend: Supabase (Postgres 15+, Auth, Edge Functions on Deno, Queues/pgmq, pg_cron, pgvector, Realtime), region Mumbai (ap-south-1).
- Photos: Cloudflare R2 (S3 API) behind a CDN, private bucket, signed URLs only.
- Inbound order emails: Cloudflare Email Routing + Email Worker → `ingest-order-email` function (HMAC-signed).
- AI: Anthropic Claude Haiku 5.5 (`claude-haiku-5-5`) by default, Sonnet 5.5 only on explicit request; prompt caching; Batch API for anything that can wait. All behind one `ai-provider` module.
- Embeddings: Marqo-FashionSigLIP (768-dim) in `services/embedder` (FastAPI, Docker, CPU).
- Payments: RevenueCat (Google Play + Apple IAP) and Razorpay Subscriptions (web) → one entitlement.
- Email: Resend. Push: Expo Notifications. Monitoring: Sentry + PostHog. CI: GitHub Actions.

## Repo layout

```
apps/mobile      Expo app            apps/admin   Next.js admin
apps/web         drobie.app + web checkout
packages/shared  generated DB types, Zod schemas, taxonomy, synonym seed
packages/rules   rules engine (pure TS, runs on phone and server)
packages/ml      on-device model files + colour/pattern code
supabase/        migrations, tests (pgTAP), functions (Deno), seed
services/embedder  FashionSigLIP FastAPI service
workers/email-inbound  Cloudflare Email Worker
docs/            SRS, FRS, TECH_DESIGN, BRD, DECISIONS, runbooks
```

## Conventions

- **SQL:** snake_case; `uuid` primary keys (`gen_random_uuid()`); `timestamptz` in UTC; money as integer minor units plus currency (`amount_minor bigint`, `currency char(3)` default 'INR'); UUID v7 ids; client-facing tables in `public` with RLS, internals in `private`, staff audit in `audit`; `created_at`, `updated_at` (trigger) on every table; soft delete via `deleted_at` only where specified. One migration per change, named `YYYYMMDDHHMMSS_short_name.sql`, never edited after merge.
- **Every new table ships with:** RLS enabled, explicit policies, indexes on every foreign key and filter column, and pgTAP tests proving one allowed and one denied access.
- **Pagination:** keyset only (no OFFSET). Sync endpoints return rows changed since an `updated_at` cursor.
- **Edge Functions:** one folder per function, shared code in `supabase/functions/_shared`. Validate every input with Zod. Return `{ data }` or `{ error: { code, message } }` with correct HTTP status. Structured JSON logs with a request id, no PII. Idempotent webhooks (store provider event ids).
- **TypeScript:** no `any`, no non-null assertions without a comment; DB types generated (`supabase gen types`) into `packages/shared`.
- **Tests:** pgTAP for schema and RLS, `deno test` for functions, Vitest for packages. Webhook and email parsers tested against stored fixtures.
- **Events:** every important state change inserts a `private.domain_events` row in the same transaction (outbox); side effects (push, embeddings, analytics) run from queues, never inline.
- **State machines:** statuses change only through server functions that check allowed transitions and log them.
- **Compatibility:** migrations are expand → migrate → contract; functions are versioned (`/v1/`); never break an older app version still above `min_app_version`.
- **Database rules:** follow `docs/DATABASE.md` ("Adding a table"). Always filter list reads by `owner_user_id`/`household_id` (RLS is the safety net, not the query plan); no function is executable by PUBLIC, so grant EXECUTE explicitly and update the allow-list test.
- **Secrets:** only in Supabase secrets / GitHub secrets / `.env.local` (git-ignored). Commit `.env.example` with placeholders.

## How to work in this repo

1. Start every task by reading the relevant doc sections and restating the goal, scope and acceptance criteria. For anything larger than a small fix, write a short plan first and wait for approval.
2. Work in small, reviewable steps. After each step run: `pnpm lint`, `pnpm typecheck`, `pnpm test`, `supabase db reset && supabase test db`.
3. Never mark a task done with failing checks, skipped tests or TODOs in security-relevant code.
4. Ask before adding a dependency; prefer the platform and the standard library. Check the licence of every new package.
5. Record any decision that changes or clarifies the docs in `docs/DECISIONS.md` (date, decision, reason).
6. End each task with a short report: what changed, how to verify, cost impact, open questions.

## Definition of done

- Acceptance criteria from the FRS met and demonstrated by tests.
- RLS policies and allow/deny tests for every table touched.
- Inputs validated, errors handled, logs structured, no PII in logs.
- Cost per use estimated; paid calls logged; caches and limits in place.
- Lint, typecheck and all tests green locally and in CI.
- Docs and `DECISIONS.md` updated where behaviour or design changed.
