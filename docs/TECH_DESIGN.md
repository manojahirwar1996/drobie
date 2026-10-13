# drobie — Technical Design

Oct 8, 2026 · @Rudy · v1.0 for development

## 1. Summary and engineering principles

We build a React Native app (Expo) that launches on Android and iOS together, and a Next.js admin panel, all in TypeScript, on Supabase (Postgres, Auth, Storage, Edge Functions, Queues), with in-house logic first (rules, database queries, on-device ML Kit / Apple Vision and our own small classifier), a small self-hosted fashion embedding server, and Claude Haiku only as the last step for open-ended dro conversations and fallbacks. Every layer uses open standards so it can move to bigger infrastructure later without a rewrite. This matches the lean cost model in the BRD (target ₹1.5 per active user per month at scale; see SRS sections 8, 10 and 11).

**Principles every feature follows**

1. **Security in the database, not the app.** Every table has row-level security (RLS); the app only ever holds the user's own token. Privileged work runs in server functions.
2. **Phone first, cloud second.** Cut-out, adjustments, label text and barcodes run on the device; only the cleaned photo and text go up.
3. **AI only when needed.** Rules, search and cached results first; the AI model is the last step, with per-user daily limits.
4. **Fast by default.** Optimistic UI, thumbnails, pagination, an offline cache and background processing; every user journey has a time budget (BRD 7b).
5. **Private by default.** Nothing is shared without an explicit choice; personal data can be exported and deleted.
6. **Everything admins do is logged.** Admin actions go through audited server functions with role checks.
7. **Build small, ship weekly.** Feature flags let us ship hidden and turn features on per group.

## 2. System architecture

&#91;embedded content: drobie architecture · phone, backend, 4 supporting services\]

The phone captures, tags, plans and answers most questions offline; the backend stores data and runs small functions; photos upload straight to R2 with signed URLs; paid AI (dashed) is called only for open dro conversations, Try it on and the few items the phone is unsure about.

## 3. Tech stack

One language, TypeScript, runs the app, the admin panel and the server functions, and the database types are generated once and shared by all three. Versions checked 8 Oct 2026: [Expo SDK 56](https://expo.dev/sdk/56) (React Native 0.85, React 19.2, released May 2026) and [Next.js 16.4](https://endoflife.date/nextjs) (released 6 Oct 2026).

| Layer | Choice now (lean) | Path when we scale | Why |
| --- | --- | --- | --- |
| Code repo | One monorepo: pnpm + Turborepo; shared package for database types and Zod schemas | Same | Change a table once, every app gets the new types |
| Mobile app | Expo SDK 56 (React Native 0.85, React 19.2), Expo Router, TypeScript | Same; add native modules as needed | Android and iPhone from one codebase; over-the-air updates (EAS Update) fix bugs without waiting for store review; largest hiring pool |
| Data in the app | TanStack Query for server data; expo-sqlite + Drizzle for the offline closet | Same | Instant screens, offline closet, typed queries |
| On-device vision | ML Kit (subject segmentation, text, barcode) on Android and Apple Vision on iOS, via Expo modules and vision-camera | Same | Free, fast, private |
| Images | expo-image (caching) + on-device WebP compression | CDN image resizing | Fast grids, small uploads |
| Backend | Supabase: Postgres, Auth, Storage, Edge Functions (Deno, TypeScript), Realtime | Same Postgres moved to a larger Supabase plan or AWS Aurora / Neon | Standard Postgres; no lock-in |
| Background jobs | Supabase Queues (pgmq) + pg\_cron | Managed queue (for example SQS) | Durable jobs for tagging, embeddings, reminders |
| Vectors | pgvector (HNSW) in the same Postgres | Dedicated vector store only if needed | Similar items without another bill |
| AI | Fallback only: Claude Haiku 5.5 for open dro questions and items the phone is unsure about; Sonnet 5.5 on request; Batch API for anything that can wait | Same interface, larger models where they pay off | Accuracy where it matters, low cost everywhere else |
| AI interface | One internal "AI provider" module with prompts and JSON schemas in the repo | Swap or mix providers without app changes | Avoids lock-in to one vendor |
| Fashion embeddings | Marqo-FashionSigLIP in a Docker container (FastAPI) on a small CPU server | Same container on a GPU or autoscaling service | Accurate fashion matching; portable |
| Photo storage | Cloudflare R2 behind a CDN with signed URLs, through a storage module | Same; cold storage for inactive accounts | No download fees |
| Admin panel | Next.js 16 (App Router, Server Actions), shadcn/ui, TanStack Table | Same | Fast to build data-heavy screens; free hosting tier |
| Sign-in | Google, Apple and email (password, OTP or magic link) through Supabase Auth; no phone sign-in | Same, plus passkeys | Free per user |
| Email | Resend free tier (3,000 emails a month, 100 a day) for receipts forwarding and admin mail | Paid tier | Free to start |
| Push | Expo Notifications over FCM and APNs | Same | Free |
| Monitoring | Sentry, PostHog (analytics + feature flags), OpenTelemetry traces in functions | Any OpenTelemetry backend | Standard tracing; no lock-in |
| CI/CD | GitHub Actions + EAS Build | Same | One pipeline |

**Sign-in:** Google, Apple and email (password, email OTP or magic link) through Supabase Auth, with emails sent on the [Resend free tier](https://resend.com/blog/new-free-tier.md). No phone, SMS, Truecaller or WhatsApp sign-in, so sign-in costs nothing per user.

**Accuracy and performance tools we keep, even though they cost a little:** the FashionSigLIP matching server (fixed cost, scales to zero), Sentry performance monitoring, and point-in-time database backups on the paid Supabase plan. Paid AI checks are kept only below a confidence threshold.

## 4. End-user modules

The MVP app has five tabs (Today, Closet, centre dro button, Friends, Plan) plus onboarding and settings; each module below lists the tables and functions it uses.

| Module | Screens | Data (tables) | Server functions |
| --- | --- | --- | --- |
| Onboarding | Sign in (Google, Apple or email), city, style vibe, gallery pick of first 10 items | profiles, homes, items | ingest-order-email, refine-item (fallback) |
| Today | Weather line, hanging tags (events), today's rail, nudges, Ask bar | daily\_picks, items, reminders, notifications | morning-pick |
| Closet | Grid with filters (category, state, place, colour), search, multi-select actions | items, places, categories | (database search only) |
| Add item | Order emails, gallery sweep, voice add, share, drawer photo, camera; tags on the device; one-list confirm | items, item\_photos (storage), places | ingest-order-email, ingest-link, parse-command, refine-item (fallback), embed-item |
| Item detail | Photo, place, state, stats (wears, cost per wear), pairings, Lend | items, item\_state\_events, wear\_logs, looks | similar-items |
| Ask dro | Chat and voice; answers with item cards and actions | dro\_conversations, dro\_messages, items | ask-dro |
| Laundry and care | Batch "sent to dhobi / tailor / wash", pickup reminders | items, item\_state\_events, reminders | send-reminders (cron) |
| Beauty shelf | Barcode scan, opened date, PAO, expiry list | items, beauty\_details | lookup-barcode |
| Plan | Calendar of looks, occasions (Navratri, weddings), trip packing | looks, look\_items, festivals | plan-occasion |
| Before you buy | Share-sheet target; matches you own | items, item\_embeddings | before-you-buy |
| Swap and circles | Circles, listings, booking calendar, requests, chat, handover and return photos, ratings | circles, circle\_members, item\_shares, listings, bookings, booking\_messages, ratings | swap-actions |
| Safety | Report, block, verification | reports, blocks, user\_verifications | verify-college-email |
| Settings and privacy | Notifications, quiet hours, homes and places, plan, export data, delete account | profiles, device\_tokens, subscriptions | export-data, delete-account |
| Referrals and rewards | Invite code, founding offer, rewards status | referrals, profiles | apply-referral |

## 5. Admin panel

The admin panel is a separate web app where staff sign in with the same Supabase auth; what each person can see and do comes from their role in the `admin_users` table, and every change is written to `admin_audit_log`.

**Roles**

| Role | Can do |
| --- | --- |
| super\_admin | Everything, including managing admins and app settings |
| admin | Users, content, Swap, flags, broadcasts, taxonomy, festivals |
| moderator | Reports, listings, Swap disputes, suspend users |
| support | View a user's account summary (no photos unless the user grants access), resend verification, cancel a booking |
| analyst | Read-only dashboards and anonymised metrics |

**Modules**

| Module | What it shows and does | Roles |
| --- | --- | --- |
| Dashboard | Sign-ups, weekly active closets, items added, retention, Pro conversions, Swap volume | all |
| Users | Search by email or user ID, plan, status, verification; suspend or ban with a reason | support (view), moderator+, admin+ |
| Reports and moderation | Queue of reports on users, listings and messages; take action, dismiss, add notes | moderator+ |
| Swap and disputes | Listings, bookings, deposits, condition photos side by side, dispute decisions | moderator+ |
| AI usage and costs | Tokens and cost per day, per feature, top users, error rates; adjust limits | admin+, analyst (read) |
| Taxonomy | Categories, colours, patterns, occasions used by tagging and filters | admin+ |
| Festivals and occasions | Festival dates and colour schedules (for example Navratri's 9 colours) per region | admin+ |
| Broadcasts | Push and in-app messages to segments, scheduled, with a preview | admin+ |
| Feature flags and config | Turn features on per plan or percentage; free-plan limits (items, dro questions) | admin+ |
| Referrals and rewards | Codes, rewards given, abuse checks | admin+ |
| Audit log | Every admin action: who, what, when, before and after | super\_admin, admin |

**Privacy rule:** admins never browse a user's closet photos. Support can open a user's items only through a time-limited access grant the user approves in the app.

## 6. Database design

&#91;embedded content: core data model · items at the centre\]

Every user-owned table carries `user_id` with a row-level security policy, so the app can only ever read its own rows; `products` is the one shared table, holding public product details (never who bought them).

| Area | Tables | Key columns | Indexes and rules |
| --- | --- | --- | --- |
| People | `profiles`, `homes`, `places`, `subscriptions`, `device_tokens` | `places.parent_id` (nested spots), `subscriptions.source` (store or web), `entitlement` | `(user_id)` on all; one active entitlement per user |
| Closet | `items`, `item_photos`, `item_embeddings`, `item_state_events`, `wear_logs`, `beauty_details` | `items.tag_source` (phone, template, ai, user), `confidence`, `product_id`, `place_id`, `state`; `wear_logs.event`, `people` | `(user_id, state)`, `(user_id, category_id)`, `(user_id, updated_at)`; full-text on name and brand; HNSW on embeddings |
| Adding | `products`, `order_emails`, `email_templates`, `synonyms` | `products.source_key` (barcode or page id), `image_hash`; `order_emails.template_id`, `status` | Unique `(source_key)`; templates and synonyms edited in admin |
| Planning | `looks`, `look_items`, `daily_picks`, `festivals`, `reminders` | `daily_picks.date`, `reasons` (rules-engine steps) | `(user_id, date)` unique per pick |
| dro | `dro_conversations`, `dro_messages`, `answer_cache` | `dro_messages.handled_by` (rules, cache, ai) | Cache key = hash of intent, question, item ids, closet version; 24 h expiry |
| Community | `circles`, `circle_members`, `item_shares`, `listings`, `bookings`, `booking_messages`, `ratings`, `reports`, `blocks` | `bookings.during` (date range) | Exclusion constraint stops double bookings |
| Operations | `ai_usage`, `app_config`, `admin_users`, `admin_audit_log`, `referrals` | `ai_usage.feature`, `model`, `tokens`, `cost_inr`, `step` | Daily cost roll-ups; audit log append-only |

**Rules for every migration:** written as SQL files in the repo, applied by CI; every new table gets RLS with an allow and a deny test; keyset pagination only (no OFFSET); `updated_at` on every synced table for delta sync.

## 7. Security

The database enforces who can read and write every row, so a bug or a tampered app cannot expose another person's closet.

| Area | How we handle it |
| --- | --- |
| Sign-in | Supabase Auth with Google, Apple and email (password, OTP or magic link); no phone numbers collected for sign-in; users confirm they are 18 or older. Short-lived access tokens (1 hour) with refresh tokens kept in secure device storage (Android Keystore, iOS Keychain). |
| Row-level security | RLS on every table. Owners read and write their own rows; circle members read only items shared to that circle; booking parties read only their booking. Default deny. |
| Protected columns | Users cannot change `plan`, `pro_until`, `status` or `is_banned` on their own profile: column-level grants plus a trigger. Plans change only through the billing webhook. |
| Public profile | Other users see only a limited view (display name, avatar, verification badges, rating), never phone, email or home city detail. |
| Admin access | `admin_users` table with roles; RLS helper `has_admin_role()`; privileged changes only through server functions that check the role and write to `admin_audit_log`. Admins use 2-step verification. |
| Support access to user data | Only with a time-limited grant the user approves in the app (`support_access_grants`), logged. |
| Photos | Private Cloudflare R2 bucket; object keys start with the owner's user id; uploads and reads only through short-lived signed URLs issued by server functions after an ownership check. Images are re-encoded on upload, which strips location and camera metadata. |
| Secrets | AI, FCM and embedder keys live only in server function secrets; the app ships with the public anon key only. Embedder accepts calls only with a shared secret over HTTPS. |
| Rate limits and abuse | Per-user daily limits on AI calls (table `ai_usage`), per-IP limits on sign-in and OTP (Supabase), limits on listing creation and messages; referral rewards only after the friend adds 25 items. |
| Input safety | All user text is parameterised (no string-built SQL); prompts wrap user content and item data as data; AI output is validated against a JSON schema before saving. Store links are fetched server-side with an allowlist of public hosts, size and time limits. |
| Swap safety | Exact addresses never stored on listings; location rounded to about 1 km; block and report everywhere; deposits through a licensed payment partner. |
| Privacy and deletion | Data export (JSON + photos zip) and account deletion from settings; deletion removes rows and storage within 30 days; backups expire on schedule. Consent screens for calendar, email import and measurements. Built to DPDP Act 2023 expectations. |
| Transport and storage | HTTPS only; data encrypted at rest by the platform; daily backups with point-in-time recovery on the paid plan. |
| App hardening | Certificate checks on API calls, obfuscated release builds, Play Integrity check before sensitive actions (listing, deposits). |
| Monitoring | Alerts on spikes in failed logins, AI usage, reports, and on RLS errors; dependency updates checked weekly. |

## 8. Performance

The app feels instant because the slow work (AI tagging, embeddings) happens in the background after the user has already moved on.

**Budgets (mid-range Android, 4G)**

| Moment | Target |
| --- | --- |
| Cold start to Today screen | under 2 s (cached data first, refresh after) |
| Closet grid scroll | 60 fps with 500+ items |
| Photo to saved item | under 3 s on device; tags appear within 5 s in the background |
| "Where is" answer | under 1 s from database search |
| AI chat answer | first words under 2 s (streamed) |
| Morning pick | under 300 ms (cached per day) |

**How we hit them**

- **Images:** cut-out and compression on the device; upload WebP at 1,600 px master, 800 px display and 300 px thumbnail to Cloudflare R2; grids load thumbnails only; signed URLs cached for their lifetime; images cached on device.
- **Offline-first closet:** items, places and states mirror into on-device SQLite (expo-sqlite with Drizzle); the UI reads locally and syncs changes since `updated_at`; edits are queued offline.
- **Optimistic updates:** state changes (worn, at dhobi) show immediately and roll back only on error.
- **Database:** indexes on every foreign key and on `(user_id, state)`, `(user_id, category_id)`, `(user_id, updated_at)`; full-text search column on items; HNSW index for embeddings; keyset pagination (no OFFSET); exclusion constraint for booking dates.
- **Server functions:** small, single-purpose; order emails parsed by retailer templates; heavy steps queued (only fallback tagging goes to the Batch API); responses streamed for chat.
- **AI cost and latency:** follow the in-house ladder (rules → on-device models → own server → paid AI); answer "where/what/how many" questions from SQL; tag on the phone and cache per item (never re-tag); prompt caching for the system prompt; Haiku only for open questions; daily limits per plan in `app_config`.
- **Realtime only where needed:** booking chat and request status; everything else is pull-to-refresh or sync.
- **Measure:** Sentry performance traces in the app and functions; slow query log in Supabase; weekly review of the top 5 slowest endpoints.

## 9. Server functions and the in-house pipeline

Every function follows the same ladder and stops at the first confident step: rules and SQL → on-device result sent by the app → our embedding server → paid AI. Each function logs which step answered, so the share of paid calls is visible in the admin panel (target: under 10% of items, and only open-ended chat).

| Function | Input | In-house path | Paid AI only when | Output |
| --- | --- | --- | --- | --- |
| `ingest-order-email` | Forwarded email | Retailer template match → fields → keyword category → product saved to the shared product list | No template matches (then a template is added) | Items to confirm, return window |
| `ingest-link` | Product URL or shared text | schema.org JSON-LD / Open Graph product data, cached per product | Page has no product data | Item draft |
| `refine-item` | Item with on-device tags and confidence | Accept phone tags above threshold; colour and pattern already computed on the phone | Below threshold → queued to the Batch API overnight | Final tags |
| `embed-item` | Item photo | FashionSigLIP on our CPU server, once per item | Never | Vector for search, duplicates, matching |
| `parse-command` | Voice or typed text | Phrase grammar + synonym dictionary + fuzzy match on items and places | Unusual phrasing | Action (add, place, where, lend) |
| `search` | Query text | Dictionary parser → filter chips → SQL + vector search | Words the parser can't map (logged to grow the dictionary) | Results + chips |
| `morning-pick` | User, weather, calendar | Shared TypeScript rules engine (also runs on the phone offline) | Never | Daily rail, pre-computed for pushes |
| `ask-dro` | Chat message | Intent router → SQL and rules handlers → answer cache | Open styling questions (Haiku; Sonnet on "think harder") | Streamed answer + cards + actions |
| `generate-look` | Avatar + items | Cache lookup by outfit hash; credit check | Always (image generation has no in-house option) | Image, cached |

**Limits:** per-plan daily caps and per-user token budgets in `app_config`; a global daily spend cap switches dro to rules-only mode; every paid call is logged in `ai_usage` with feature, model, tokens and cost.

**Continuous improvement:** corrections and photos users agree to share improve our on-device classifier (retailer photos are not used for training without legal clearance); every unknown email format becomes a new template; every unmapped search word grows the dictionary. Paid AI use should fall month on month.

## 10. Code, environments and operations

One private GitHub monorepo, three Supabase environments, and every change shipped through CI; a new developer runs the whole stack locally in under 30 minutes.

**Repository (pnpm + Turborepo)**

| Folder | What lives there |
| --- | --- |
| `apps/mobile` | Expo app (Expo Router, TanStack Query, expo-sqlite + Drizzle, vision-camera frame processors) |
| `apps/admin` | Next.js admin panel (shadcn/ui, TanStack Table) |
| `apps/web` | drobie.app website, waitlist and Razorpay web checkout |
| `packages/shared` | Database types, Zod schemas, the taxonomy, the synonym dictionary |
| `packages/rules` | Rules engine for morning pick, week plan, rotation, packing, repeat radar (runs on phone and server) |
| `packages/ml` | On-device classifier model files, colour and pattern code, model version manifest |
| `supabase/` | SQL migrations, RLS policies and tests, Edge Functions, seed data, retailer email templates |
| `services/embedder` | FashionSigLIP FastAPI service with its Dockerfile |

**Environments**

| Environment | Used for | Data |
| --- | --- | --- |
| Local | Daily development | Supabase CLI in Docker, seeded test closet of about 200 items |
| Staging | Every merged change; internal testers on EAS preview builds | Fake users only |
| Production | Store builds and drobie.app | Real users, Mumbai region, daily backups |

**Branching and CI (GitHub Actions)**

- Short-lived branches, a pull request for every change, one review by the other developer; `main` is always releasable.
- On every pull request: type-check, lint, unit tests (rules engine, parsers, templates), RLS allow/deny tests against local Postgres, Edge Function tests.
- On merge to `main`: migrations applied to staging, functions deployed, EAS Update published to the staging channel.
- Release: a tag triggers EAS Build for Android and iOS and store submission; JS-only fixes ship as EAS Update to production.
- Secrets live in GitHub and Supabase secrets only; the app ships only public keys.

**Monitoring**

- Sentry for crashes and performance traces (app, admin, functions); PostHog for product analytics and feature flags.
- Admin cost dashboard from `ai_usage` and storage metrics; alerts when a cost target in SRS section 10 is crossed.
- Weekly 30-minute review: crash-free rate, slowest 5 endpoints, paid-AI share of items, cost per active user.

**Run it locally**

1. Install Node 22, pnpm, Docker and the Supabase CLI.
2. `pnpm install` at the repo root.
3. `supabase start`, then `supabase db reset` to apply migrations and seed data.
4. Copy `.env.example` to `.env.local` in `apps/mobile` and `apps/admin`.
5. `pnpm dev` starts the admin panel, website and functions; `pnpm --filter mobile start` opens the Expo dev build on a phone.
6. Optional: `docker compose up embedder` for similarity features.

## 11. Build order

Build in the order the pieces depend on each other, with adding items first because it is drobie's core; sprint dates and owners are in the [Build plan](https://claude.ai/artifact/U6a66Y3eCejBMjcaJgncBw) (MVP launch targeted for April 2027).

1. **Foundation:** monorepo, three environments, CI, auth (Google, Apple, email), profiles, homes and places, RLS tests, Sentry and PostHog. *Done when* a signed-in tester sees an empty closet on both platforms.
2. **Adding items (the core):** on-device tagging, colour and duplicate checks; order-email templates for the top 8 retailers; gallery sweep; share and link import; voice add and voice place; add-later stubs; drawer photo; one-list confirm; R2 uploads. *Done when* a tester gets 80+ items in under 5 minutes with no paid AI call for at least 90% of them.
3. **Closet:** grid, categories and icon library, filters, search parser, item detail, states, "where is it". *Done when* any item is found in two taps or one sentence.
4. **Today:** rules engine, weather, morning pick, widgets, evening card, wear logging, colour analysis and the monthly fit reel (both on the phone). *Done when* a daily pick appears at the chosen time with no AI call.
5. **dro:** intent router, SQL and rules handlers, answer cache, Haiku for open questions, actions with Undo, daily limits. *Done when* 80% of test questions are answered without a paid call.
6. **Care, beauty and reminders:** laundry and dhobi states, beauty shelf with barcode and expiry, reminder scheduling. *Done when* reminders fire on time for a test closet.
7. **Plans and payments:** RevenueCat (store) and Razorpay (web) into one entitlement, paywall, trial, limits from `app_config`. *Done when* a plan bought on the web unlocks the app within a minute.
8. **Admin and launch hardening:** admin modules, cost dashboard and alerts, store listings, privacy and deletion flows, load tests. *Done when* the launch checklist in the Build plan is all ticked.

**After MVP (v1.1):** price tag and barcode, bill and bag photos, brand catalog pick, Try it on, Recreate, friends and Swap, repeat radar and the remaining subscription boosters (BRD 10e).
