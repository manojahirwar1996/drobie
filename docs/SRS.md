# drobie — Software Requirements Specification (SRS)

Oct 9, 2026 · @Rudy · v1.0 for development

## 1. Introduction

This SRS defines how drobie's software must be built and how well it must run: platforms, tech stack, interfaces, performance, security, privacy, data, AI and quality. What each feature does is in the FRS; this document sets the constraints every feature must meet.

- **System:** the drobie mobile app (Android and iOS together at launch), the admin web panel, the backend on Supabase, and supporting services (AI model, fashion embedding server, notifications).
- **Readers:** the founders, developers, testers and any future engineering hires or vendors.
- **References:** drobie BRD, drobie FRS, drobie Technical Design, design system, prototype canvas.

**Definitions**

| Term | Meaning |
| --- | --- |
| dro | The in-app AI assistant |
| RLS | Row-level security: database rules that decide which rows each user can read or write |
| Edge Function | A small server function running on Supabase (Deno, TypeScript) |
| Embedding | A list of numbers that describes an image or text, used to find similar items |
| PAO | Period after opening, the "12M" jar symbol on cosmetics |
| DPDP Act | India's Digital Personal Data Protection Act, 2023 |
| MVP / v1.1 / Later | Release priorities, as defined in the FRS |

## 2. Overall description

drobie is a new, standalone product: a phone app that does the fast, private work on the device and a cloud backend that stores data, runs AI in the background and enforces security in the database.

**How the parts fit**

1. **Mobile app** (Expo / React Native): camera, on-device vision (cut-out, labels, barcodes, live scan), offline closet, UI.
2. **Supabase backend:** Postgres with RLS for all data, Auth for sign-in, Cloudflare R2 for photos (private, signed URLs), Edge Functions for server logic, Queues and cron for background jobs, Realtime for chat.
3. **AI provider module:** used last, only for open-ended dro conversations and fallbacks the in-house steps can't handle (Claude Haiku 5.5 default, Sonnet 5.5 on request, Batch API for anything that can wait). Tagging, search, voice and planning run in-house first (sections 8 and 11).
4. **Embedding server:** Marqo-FashionSigLIP in a Docker container for similar-item search and duplicates.
5. **Admin panel** (Next.js): staff tools on the same database, behind roles and an audit log.
6. **Outside services:** Google Play Billing, FCM/APNs push via Expo, Apple In-App Purchase via RevenueCat, Razorpay web checkout, weather API, Resend email, Sentry and PostHog.

**User classes:** guests, free users, Pro users, circle members, borrowers and lenders, and admin roles (super\_admin, admin, moderator, support, analyst, stylist). See FRS section 2.

**Operating environment**

| Item | Requirement |
| --- | --- |
| Android | Android 9 (API 28) and above; tuned for mid-range phones with 4 GB RAM |
| iOS | iOS 16 and above at launch; subject lift and live scan need iOS 17 |
| Admin panel | Latest Chrome, Edge and Safari on desktop |
| Network | Works on 4G; core closet features work offline |
| Hosting region | Supabase region in Mumbai (ap-south-1) for India data residency and low latency |

**Constraints**

- Lean budget: about ₹5,300 a month at 1,000 users and about ₹2 per active user at 100,000 (BRD 10b).
- Small team: one TypeScript codebase across app, admin and functions.
- India's DPDP Act 2023; Google Play and App Store policies on photos, payments and minors.
- No store order-history APIs exist; purchase import relies on receipt forwarding first.

**Assumptions**

- Most users are on Android, 18–30, comfortable with English or Hinglish.
- Users accept photo and optional calendar permissions when the value is explained.
- The AI provider keeps pricing close to current Haiku-class rates.

## 3. Tech stack

One language, TypeScript, runs the app, admin panel and server functions; every layer uses open standards so it can move to bigger infrastructure later without a rewrite. Versions as checked 8 Oct 2026 (Technical Design).

| Layer | Choice now (lean) | Path when we scale | Cost now | Why |
| --- | --- | --- | --- | --- |
| Code repo | pnpm + Turborepo monorepo; shared database types and Zod schemas | Same | Free | Change a table once, every app gets the new types |
| Mobile app | Expo SDK 56 (React Native 0.85, React 19.2), Expo Router, TypeScript | Same; native modules as needed | Free | Android and iPhone from one codebase; over-the-air fixes |
| Data in the app | TanStack Query; expo-sqlite + Drizzle for the offline closet | Same | Free | Instant screens, offline closet |
| Camera and live scan | react-native-vision-camera with frame processors | Same | Free | Point-and-scan mode at camera speed |
| On-device vision | Google ML Kit (subject segmentation, object detection and tracking, text, barcode); Apple Vision on iOS | Same | Free | Fast, private, no per-photo cost |
| On-device classifier | Our own multi-output classifier (EfficientNet-Lite0 / MobileNetV3, under 10 MB) for category, pattern and details, trained on Fashionpedia (CC BY 4.0) and photos users agree to share; one TFLite file runs on both platforms via react-native-fast-tflite (Core ML / GPU delegates); updated over the air | Same | Free | Gallery scan and instant categories without the cloud |
| Images | expo-image caching; resized on the phone to WebP: 1,600 px master, 800 px display, 300 px thumbnail; camera original never stored | CDN resizing | Free | Fast grids, small uploads |
| Backend | Supabase: Postgres, Auth, Storage, Edge Functions (Deno), Realtime | Larger Supabase plan, or Postgres on AWS Aurora / Neon | About ₹2,100/month (Pro plan) | Standard Postgres, no lock-in |
| Background jobs | Supabase Queues (pgmq) + pg\_cron | Managed queue such as SQS | Included | Durable tagging, embedding and reminder jobs |
| Vector search | pgvector with HNSW index | Dedicated vector store only if needed | Included | Similar items without another bill |
| AI model | Fallback only: Claude Haiku 5.5 for open dro questions and unknown formats; Sonnet 5.5 on request; Batch API for anything that can wait | Same interface, larger models where they pay off | ₹0 for \~90% of items; about ₹0.1–0.2 per fallback item | Pay only where in-house methods aren't enough |
| AI interface | Internal "AI provider" module with prompts and JSON schemas in the repo | Swap or mix providers | Free | Avoids vendor lock-in |
| Fashion embeddings | Marqo-FashionSigLIP in Docker (FastAPI) on a small CPU server that scales to zero; one embedding per item, computed once | Same container on GPU or autoscaling | About ₹800–1,500/month | Accurate fashion matching; portable |
| Photo storage | Cloudflare R2 (no download fees) behind a CDN with signed URLs, accessed through a storage module | Same; cold storage for inactive accounts | Free up to 10 GB, then about ₹1.3 per GB a month | Simple now, cheap later |
| Admin panel | Next.js 16 (App Router, Server Actions), shadcn/ui, TanStack Table | Same | Free hosting tier | Fast to build data-heavy screens |
| Website and waitlist | Next.js on Vercel or Cloudflare Pages at drobie.app | Same | Free | HTTPS by default, required for .app |
| Sign-in | Google and Apple sign-in; email + password, email OTP or magic link (no phone, SMS, Truecaller or WhatsApp) | Add passkeys | Free (Supabase Auth; Resend free tier for emails) | Sign-up free for almost everyone |
| Payments | Google Play Billing and Apple in-app purchase via RevenueCat; licensed partner for Swap deposits | Same | Store fee on Pro only; Apple developer account about $99/year | Required by store rules |
| Email | Resend free tier (3,000/month); Porkbun forwarding for hello@drobie.app | Paid tier | Free | Free to start |
| Push | Expo Notifications over FCM and APNs | Same | Free | One API for both platforms |
| Weather | A weather API by city | Same | Free tier | Morning brief and rain swaps |
| Monitoring | Sentry, PostHog (analytics, feature flags), OpenTelemetry traces | Any OpenTelemetry backend | Free tiers | Standard tracing, no lock-in |
| CI/CD | GitHub Actions + EAS Build and EAS Update | Same | Free tiers | One pipeline for app, admin and functions |

**Added for outfits from photos and Try it on (v1.1):** garment outlining runs on the phone (segmentation) and the original crop is the item photo by default; the product photo from the order email replaces it when one exists. Paid image models are used only for Try it on and the optional tidy view: a multi-reference image model (Gemini Flash Image class, about $0.04 per image) by default and a virtual try-on API such as FASHN for "make it exact" (about $0.05–0.075 per image, lower at volume), all behind the same AI provider module. Prices approximate as of Oct 2026.

Total running cost targets are in the BRD cost model (10b). Prices are estimates and should be rechecked before purchase.

Tthe feature Google announced in April 2026. It’s coming to Android this summer and iOS after that. It’s a good approach, and it doubles as a third way to fill the closet alongside scanning. Here’s how drobie would do it:

1. **Find your photos.** The phone finds gallery photos of you wearing clothes, after you identify yourself once. Other people’s photos are skipped.
2. **Pull out each garment.** Each piece gets a clean, catalogue-style image like in your screenshots. The original crop is always kept, and the cleaned image is labelled as AI.
3. **Merge repeats.** The same shirt seen in 12 photos becomes one item, and the photo dates become its wear history. Cost per wear is filled in from day one, which Google’s version doesn’t do.
4. **Build outfits.** Pick pieces by category into a collage, then save it as a look or to a moodboard (work, wedding, trip).
5. **Try it on.** You add 1–2 full-body photos once, and drobie generates you wearing the outfit, labelled “AI preview.”

Things to know:

- **Cost:** cleaning up each garment costs about **$0.04,** and each Try it on image about** $0.05–0.075** through a try-on service like FASHN. So it works best as a Pro feature with monthly credits. The outfit builder itself is free, and I set it as MVP; extraction and Try it on are v1.1.
- **Rules:** only your own body is ever used; no body editing; reference photos are encrypted and deletable in one tap; no Try it on for under-18s.
- **Competition:** Google will have this for free inside Photos. drobie’s edge is everything around it: knowing where each item is and whether it’s clean, the morning pick, dhobi and tailor tracking, Before you buy, and friends and Swap.

## 4. External interfaces

**User interface**

- Follows the drobie design system: final palette (Fresh Purple + Green Glow), Bricolage Grotesque and DM Sans, light and dark themes, 44 px minimum touch targets.
- Five-tab layout: Today, Closet, dro (centre), Friends, Plan.
- Item photos shown whole and fitted (never cropped by default); category icons only when no photo exists.

**Hardware**

| Device feature | Used for | Permission |
| --- | --- | --- |
| Camera | Add item, point-and-scan, labels, barcodes | Asked on first use |
| Photo library | Gallery picks and gallery scan | Asked with an explanation; limited access supported |
| Microphone | Talking to dro | Asked on first voice use |
| Location | City only, for weather and Swap distance | Optional; city can be typed instead |
| Haptics | Scan ticks, confirmations | None |

**Software interfaces**

| Interface | Direction | Data | Notes |
| --- | --- | --- | --- |
| Supabase REST, RPC and Realtime | App ↔ backend | All user data | User token only; RLS on every table |
| Edge Functions | App → backend | tag-item, embed-item, ask-dro, morning-pick, before-you-buy, swap-actions, export-data, delete-account | Rate-limited per user |
| Anthropic Claude API | Backend → AI | Fallback cases only: item JSON and the user's question; a photo only when in-house tagging is unsure | Keys server-side only; output checked against a JSON schema |
| Embedding server | Backend → embedder | Image or text | HTTPS with a shared secret |
| RevenueCat (Google Play Billing, Apple IAP) and Razorpay web checkout | App ↔ store → webhook | Purchases, renewals | Plan changes only through the verified webhook |
| Email OTP and magic links (Supabase Auth + Resend) | Backend → user's inbox | Email address | No phone numbers collected for sign-in; codes expire in 10 minutes |
| Expo push (FCM, APNs) | Backend → device | Notification text | Respects limits and quiet hours |
| Weather API | Backend → provider | City | Cached per city per hour |
| Calendar (device) | App reads | Event titles and times | Opt-in; read on device |
| Store link fetch | Backend → public web | Product page | Allowlist of hosts, size and time limits |
| Receipt email | Email → Resend inbound → backend | Order emails the user forwards | Parsed by retailer templates; AI only for unknown formats; user confirms |

**Communications:** HTTPS (TLS 1.2+) everywhere; .app requires HTTPS by default; push via FCM and APNs.

**Added for subscription boosters (BRD 10e, FRS 3.15):** WhatsApp Business Cloud API (backend ↔ WhatsApp; Ultimate only, opt-in, capped messages per user, cost logged per conversation); Instagram API for creator and business accounts plus parsing of the user's Instagram data-download file (backend reads only the user's own posts; nothing posted on their behalf); colour analysis runs one vision-model call per selfie with the image deleted after analysis; fit reels are rendered on the phone, not the server.

## 5. System features

The full list of features, with IDs and acceptance criteria, is in the FRS; this table shows where each module runs.

| Module (FRS) | Runs on the phone | Runs in the cloud |
| --- | --- | --- |
| Onboarding (ONB) | Gallery classification, first picks | Account, founding counter, referrals |
| Capture and scan (CAP) | Camera, auto-capture, live detection, cut-out, labels, duplicates against local cache | Detailed tags, embeddings, receipt and link import |
| Catalog (CAT) | Offline browse, filters, sort | Search parsing (rules), similarity search, smart section refresh |
| Locations and care (LOC) | State changes (optimistic) | Reminders (cron) |
| Today and outfits (OUT) | Widgets, Wear this | Morning pick (rules + cache), pairings |
| dro (DRO) | Voice to text, UI cards | Chat (AI only for open styling questions), actions and plans (rules) |
| Notifications (NOT) | Local display | Scheduling, limits, quiet hours |
| Beauty (BEA) | Barcode, PAO and date reading | Product lookup, expiry reminders |
| Before you buy (BUY) | Share-sheet target | Link fetch, matching |
| Plan (PLN) | Calendar read | Occasion and trip planning |
| Friends and Swap (SOC) | Photos, chat UI | Circles, bookings, ratings, Realtime chat, moderation |
| Payments (PAY) | Store purchase UI | Billing webhook, plan state |
| Admin (ADM) | — | Admin panel and audited functions |

## 6. Non-functional requirements

Each requirement is measured on a mid-range Android phone (4 GB RAM) on 4G unless stated.

| ID | Area | Requirement |
| --- | --- | --- |
| NFR-PERF-01 | Performance | Cold start to Today screen under 2 s (cached data first) |
| NFR-PERF-02 | Performance | Closet grid scrolls at 60 fps with 500+ items |
| NFR-PERF-03 | Performance | Photo shows in its tile under 0.5 s; saved item under 3 s; tags within 5 s in the background |
| NFR-PERF-04 | Performance | Point-and-scan captures an item about 2 s after it is held steady; live detection at 5+ frames per second |
| NFR-PERF-05 | Performance | "Where is" answer under 1 s; dro chat first words under 2 s (streamed) |
| NFR-PERF-06 | Performance | Morning pick ready under 300 ms (cached per day); Before you buy sheet under 3 s |
| NFR-SEC-01 | Security | RLS on every table, default deny; the app holds only the user's own token |
| NFR-SEC-02 | Security | Users cannot change plan, status or ban fields; plans change only via the billing webhook |
| NFR-SEC-03 | Security | Photos in private buckets, owner-prefixed paths, short-lived signed URLs; metadata stripped on upload |
| NFR-SEC-04 | Security | AI, push and embedder keys only in server secrets; app ships the public key only |
| NFR-SEC-05 | Security | Admins use 2-step verification; every admin action audited; support needs a user-approved grant |
| NFR-SEC-06 | Security | Rate limits on sign-in, OTP, AI calls, listings and messages |
| NFR-SEC-07 | Security | AI output validated against JSON schemas; user text treated as data in prompts |
| NFR-SEC-08 | Security | Release builds obfuscated; Play Integrity check before listings and deposits |
| NFR-PRIV-01 | Privacy | Built to DPDP Act 2023: clear consent per purpose, export and deletion from Settings, deletion within 30 days |
| NFR-PRIV-02 | Privacy | Gallery classification and live scan run on the phone; only chosen photos upload |
| NFR-PRIV-03 | Privacy | Location stored as city only; Swap distance rounded to about 1 km |
| NFR-PRIV-04 | Privacy | Aggregate trend signals use groups of 50+ users only; opt-out available |
| NFR-PRIV-05 | Privacy | No ads in the closet; personal data never sold |
| NFR-AVL-01 | Availability | 99.5% monthly uptime for the API; core closet works offline during outages |
| NFR-AVL-02 | Availability | Daily backups; point-in-time recovery on the paid plan; restore tested quarterly |
| NFR-SCL-01 | Scalability | Handles 100,000 users and 5 million items without a redesign; storage moves to R2/S3 past about 100 GB |
| NFR-ACC-01 | Accessibility | WCAG 2.1 AA contrast (lowest pair 6.0:1 light, 7.0:1 dark); screen-reader labels on all controls; text scales to 200% |
| NFR-L10N-01 | Localisation | English and Hinglish search at launch; Hindi UI later; all strings in resource files |
| NFR-OBS-01 | Observability | Crash-free sessions 99.5%+; Sentry traces for app and functions; alerts on login failures, AI cost spikes, RLS errors |
| NFR-COST-01 | Cost | Running cost ≤ ₹1.5 per active user per month at 100,000 users; daily cost alerts (see section 10) |
| NFR-WELL-01 | Wellbeing | At most 1 push a day by default; no dark patterns; no streaks, public feed or Swap for under-18s |

## 7. Data requirements

All data lives in one Postgres database with RLS; photos live in private storage. Full table design will be in the Technical Design (section 6).

| Entity | Key data | Retention |
| --- | --- | --- |
| profiles | Name, city, vibe, plan, Pro end date, age band, settings | Until account deletion |
| homes, places | Home > room > storage > shelf | Until deleted by user |
| items | Category, colours, pattern, fabric, brand, size, season, occasion, price, dates, state, place, tags (AI vs confirmed) | Until deleted by user |
| item\_photos | 1,600 px master, 800 px display and 300 px thumbnail (WebP), optional cut-out; camera original not stored | Deleted with the item |
| item\_embeddings | Image and text vectors (pgvector) | Deleted with the item |
| item\_state\_events, wear\_logs | State changes and wears with dates | Kept for stats; deleted with account |
| looks, look\_items, daily\_picks | Outfits and plans | Until deleted |
| beauty\_details | Opened date, PAO, expiry, barcode | Deleted with the item |
| reminders, notifications, device\_tokens | Due dates, sends, push tokens | Sent notifications kept 90 days |
| dro\_conversations, dro\_messages | Chat history | 12 months, or until the user clears it |
| circles, members, item\_shares | Groups and what is shared | Until left or deleted |
| listings, bookings, booking\_messages, ratings | Swap activity and condition photos | Booking photos 30 days after close; records kept for disputes |
| reports, blocks, user\_verifications | Safety records | Kept as needed for safety and law |
| subscriptions, referrals | Plan, billing state, rewards | As required for tax and accounting |
| trend\_cards, style\_rules, festivals, taxonomy | Admin-managed content | Versioned; old versions kept |
| ai\_usage, app\_config, admin\_users, admin\_audit\_log | Limits, config, staff, audit | Audit log kept at least 1 year |

- **Backups:** daily, with point-in-time recovery on the paid plan; backups expire on schedule so deleted data does not live forever.
- **Data residency:** primary region Mumbai; no personal data sent to analytics beyond pseudonymous IDs.
- **Export format:** JSON for data plus a zip of the user's photos.

## 8. AI and ML requirements

AI is the last step, not the first. Every task goes down the same ladder and stops at the first step that is confident: **1. rules and database queries → 2. on-device models (free) → 3. our own server models (fixed cost) → 4. paid cloud AI (per call)**. Paid cloud AI is reserved for open-ended language (dro's styling conversations) and for the few cases the earlier steps can't handle; section 11 covers adding items in detail.

| Task | Method (in order) | Where | Paid AI used when | Requirement |
| --- | --- | --- | --- | --- |
| Clothing vs not (gallery, camera) | ML Kit / Apple Vision labels + our bundled classifier (MobileNet-class, under 10 MB, LiteRT on Android, Core ML on iOS) trained on our taxonomy | Phone | Never | 95%+ precision on clothes; no upload |
| Live item detection (scan mode) | ML Kit object detection and tracking; Apple Vision | Phone | Never | 5+ fps; same item never captured twice |
| Cut-out (optional) | ML Kit subject segmentation; Apple Vision foreground mask | Phone | Never | Falls back to the full photo on poor edges |
| Category | Order-email title keywords → on-device classifier → user's one-tap fix | Phone + server rules | Only below a confidence threshold, batched overnight | 90%+ correct before any paid call |
| Colour family and pattern | Pixel clustering mapped to a fixed colour list; simple pattern measures | Phone, plain code | Never | Colour family 90%+ on the test set |
| Brand, size, fabric, price | Order-email templates, product-page data (schema.org, Open Graph), label and bill OCR + rules | Phone + server | Unknown email formats and unreadable bills | Pre-fill only; user confirms |
| Duplicates | Perceptual hash + colour histogram on the phone; embeddings for near-duplicates | Phone + own server | Never | Asks before merging |
| Similar items, Before you buy, Recreate matching | Marqo-FashionSigLIP embeddings (computed once per item) + colour rules, pgvector | Own server (CPU) | Never | Top-3 contains the true item 85%+ of the time |
| Search ("red stuff, clean, for match day") | Query parser: dictionary of categories, colours, occasions, states and Hindi/Hinglish synonyms + fuzzy matching → filter chips | Phone | Only for words the parser can't map (logged to grow the dictionary) | Understood filters shown as editable chips |
| Voice commands (add, place, where is, lend) | Phone speech recognition + phrase grammar + fuzzy match on items and places | Phone | Unusual phrasing only | Saved in under 5 seconds |
| Morning pick, week plan, office rotation, packing | Shared TypeScript rules engine (weather, state, wear history, taste and trend weights, repeat rules) | Phone (offline) + server pre-compute for pushes | Never | Under 300 ms; no daily AI call |
| Repeat radar, rescue the buried, wash status, run-out dates | Database queries and rules | Server + phone | Never | Real-time |
| Colour analysis | Face landmarks (ML Kit / Vision) → sample skin, hair and eye colour under a light check → CIELAB rules for undertone, contrast and season | Phone | Never (poor light asks for a retake) | Result in under 5 seconds; selfie never uploaded |
| "Your size here" measuring | Garment outline + A4 sheet as a ruler (geometry); size charts read from product-page data, saved per product | Phone + server | Size charts only available as images (read once, cached) | Within ±1.5 cm on test garments |
| Swap advice for Recreate | Templates ("Swap X for your Y — same colour family") | Server | Optional richer text only when the user asks | Under 5 s |
| dro chat | Intent router (rules) → rules and SQL handlers for lookups, counts, places, reminders and actions → cached answers → Claude Haiku 5.5 for open styling questions (Sonnet only on "think harder") | Phone + cloud | Open-ended styling and advice only | Answers cite real items; actions show Undo |
| Style and trends | Stylist-written rulebook and trend cards stored as structured data the rules engine uses directly | Server | Never | No retraining; cards stylist-approved |

| Task | Model or method | Where | Requirement |
| --- | --- | --- | --- |
| Garments from photos of the user | Person detection, face match and garment segmentation on the phone; repeats merged by embeddings on our server; AI clean-up image only when the user taps "tidy view" (uses a credit) | Phone + own server | Original crop kept; AI image labelled; repeats merged by embeddings |
| Try it on | Paid image model (no in-house option): one multi-reference call per look by default, FASHN for "make it exact"; results cached per outfit | Cloud | Under 60 s; labelled AI preview; no body editing; reference photos encrypted and deletable |

**Guardrails**

- Prompts treat user text and item data as data; outputs validated against JSON schemas before saving.
- No comments on body shape or weight; fit topics opt-in only; trends suggest, never push buying.
- Never invent items the user does not own; dro's thinking steps show only real inputs.
- Per-user daily AI limits by plan; prompt caching; Batch API for bulk tagging at about half price.
- **Evaluation:** a 500-photo test set (western and Indian wear, phone-quality light), re-run before any model or prompt change; a new model ships only if it matches or beats the current one.

## 9. Quality, testing and release

A build ships only when its tests pass, its FRS acceptance criteria are checked and the performance budgets hold on a real mid-range phone.

| Area | Requirement |
| --- | --- |
| Unit tests | Shared logic (rules engine, limits, parsers) covered at 70%+ |
| Database tests | Every RLS policy has an allow and a deny test; run in CI against a local Postgres |
| Function tests | Each Edge Function tested with valid, invalid and over-limit inputs |
| End-to-end | Key journeys (onboarding, add item, scan mode, Wear this, Ask dro, Before you buy, lend) automated on Android |
| AI evaluation | Test-set scores recorded per release; no drop allowed |
| Device testing | At least 3 Android phones (budget, mid-range, flagship); iOS when launched |
| Accessibility | Screen-reader pass and contrast check per release |
| Security | Dependency scan weekly; a third-party security review before public launch |
| Environments | Local, staging and production, each with its own Supabase project and keys |
| Releases | Weekly app releases behind feature flags; EAS Update for JavaScript fixes; staged Play rollout (10% → 50% → 100%) |
| Rollback | Any release can be rolled back within 30 minutes (flag off or previous update) |
| Definition of done | Code reviewed, tests passing, analytics events added, docs updated, the retention metric it should move named |

## 10. Running-cost efficiency (engineering rules)

Every feature is built to these rules so the app runs at about ₹1.2–1.5 per active user per month at scale; a pull request that breaks one needs a written reason. Rules are numbered CE-xx so code reviews and tickets can cite them.

**Cost targets**

| Measure | Target | Alert at |
| --- | --- | --- |
| Total running cost per active user | ≤ ₹1.5/month at 1 lakh users | ₹2 |
| Free user (AI + storage + bandwidth) | ≤ ₹0.70/month | ₹1 |
| AI cost per Pro user | ≤ ₹13/month | ₹20 |
| AI cost per Ultimate dro user (excluding included looks) | ≤ ₹22/month | ₹35 |
| Cost per Try it on look | ≤ ₹5 average | ₹7 |
| Fixed platform cost up to 1,000 users | ≈ ₹0 (free tiers and credits) | ₹5,000/month |

**10.1 AI chat (dro) and text models**

| ID | Rule |
| --- | --- |
| CE-01 | **Rules before AI.** Morning pick, "where is my…", filters, search chips, reminders, laundry states, duplicate checks and streaks run as code and SQL. An AI call is made only when the request needs language or judgement. |
| CE-02 | **Intent router first.** A small on-device or rules-based classifier sends each dro message to: a cached answer, a rules handler, Haiku, or (rarely) Sonnet. |
| CE-03 | **Cheapest model by default.** Claude Haiku is the only default cloud model, used for open dro questions and fallbacks (tagging and parsing go through section 11 first); escalate to Sonnet only when Haiku returns low confidence or the user taps "think harder". Log every escalation. |
| CE-04 | **Prompt caching.** dro's system prompt, style rulebook, taxonomy and tool definitions sit in a fixed, cacheable prefix; per-user and per-turn content goes after it. Never put timestamps or random IDs in the cached prefix. |
| CE-05 | **Send only what's needed.** Retrieve the top \~20 relevant items with pgvector + filters and send compact item JSON (id, category, colour, pattern, state), never photos or the whole closet. |
| CE-06 | **Compact context.** Keep the last 6 turns verbatim; older turns are replaced by a short running summary. Strip markdown, URLs and duplicate fields before sending. |
| CE-07 | **Short answers by default.** Cap output tokens per intent (e.g. 250 for an outfit answer); "tell me more" makes a second call only when tapped. |
| CE-08 | **Structured output.** Ask for JSON that the app renders (lookbook cards, chips) instead of long prose. |
| CE-09 | **Answer cache.** Cache answers by hash of (intent, normalised question, relevant item IDs, closet version) for 24 hours; serve repeats without a model call. |
| CE-10 | **Batch what can wait.** Fallback tagging and parsing run through the Batch API overnight (about 50% cheaper). Weekly insights, Wrapped and Sunday plans are built from rules and templates, with no AI call. |
| CE-11 | **Pre-compute daily picks** for all active users in one off-peak job; the app reads the stored result in the morning. |
| CE-12 | **Hard limits.** Per-plan daily message caps (Free 5, Pro 150), per-user token budgets per day, and a global daily AI spend cap with an automatic fallback to rules-only mode. |

**10.2 On-device first (capture, scan and tagging)**

| ID | Rule |
| --- | --- |
| CE-13 | Category, colour, "is this clothing", label text (OCR) and background lift run on the phone (ML Kit, Apple Vision). The user sees an instant on-device result; the cloud only refines. |
| CE-14 | Scan mode uploads **one** best still per item, never video or bursts; duplicates are skipped on device using tracker ID + image fingerprint. |
| CE-15 | Blur, low-light and "not clothing" checks happen before upload; rejected frames never leave the phone. |
| CE-16 | Gallery scan and outfits-from-photos filter candidates on device; only photos the user confirms are uploaded. |
| CE-17 | Embeddings are computed once per item and reused for search, duplicates and matching; recompute only when the photo changes. |

**10.3 Image generation (Try it on, Recreate, AI tidy view)**

| ID | Rule |
| --- | --- |
| CE-18 | **One call per look.** Default to a multi-reference image model (Gemini Flash Image class, about ₹3.5 per image) that takes the avatar and all items in a single request; use FASHN only for "Make it exact" on 1–2 main garments. |
| CE-19 | **Generate once, reuse forever.** Cache results by hash of (avatar version, sorted item IDs, pose, quality); the same outfit is never generated twice. Build the avatar once per user. |
| CE-20 | **Standard quality first.** 1K, one image per request; HD (upscale) only on save or share, costing one extra credit. |
| CE-21 | **Regenerate limit.** First regenerate free, then each costs a credit; show the cached previous result while a new one loads. |
| CE-22 | **Credits checked server-side before every call**; failed or blocked generations are refunded automatically. |
| CE-23 | Free Studio looks unlock only at 30 items, once per account (device + account checks). |

**10.4 Storage, images and bandwidth**

| ID | Rule |
| --- | --- |
| CE-24 | Resize and compress on the phone before upload: WebP, longest side 1,600 px, quality \~80 (about 150–250 KB). Never store the camera original. |
| CE-25 | Generate three sizes: thumbnail (\~300 px) for grids, display (\~800 px) for detail screens, master (1,600 px). Grids never load the master. |
| CE-26 | Store photos on Cloudflare R2 (no egress fees) behind a CDN with long cache headers and content-hashed file names; the database keeps only keys. |
| CE-27 | Cache images on the device (expo-image disk cache); re-download only when the hash changes. |
| CE-28 | Delete unsaved previews, failed uploads and temporary try-on images after 24 hours; lifecycle rules do this automatically. |
| CE-29 | Accounts inactive for 6+ months get a warning email, then their masters move to cold storage (thumbnails stay); restore on next sign-in. Deleted accounts are purged within 30 days. |

**10.5 Backend, database and jobs**

| ID | Rule |
| --- | --- |
| CE-30 | Offline-first app: read from local SQLite and sync deltas (changed rows since last sync), never full closet reloads. |
| CE-31 | Paginate every list (cursor-based, 30 items); select only needed columns; index every filter column; no N+1 queries. |
| CE-32 | Use Postgres (pgvector, pgmq queues, pg\_cron) before adding any new paid service. |
| CE-33 | Realtime subscriptions only on screens that need them (chat, swap handover); unsubscribe on leave. |
| CE-34 | The embedding server scales to zero when idle and batches requests; move to a small CPU instance before any GPU. |
| CE-35 | Cache external API results: weather per city per hour, store-link fetches per URL per day. |
| CE-36 | Heavy jobs (insights, Wrapped, reminders) run off-peak in batches, not per request. |

**10.6 App, network and notifications**

| ID | Rule |
| --- | --- |
| CE-37 | No background polling; use push or pull-to-refresh. Batch analytics events and send them on Wi-Fi or app close. |
| CE-38 | Gzip/Brotli all API responses; send compact JSON (short keys only where it doesn't hurt readability). |
| CE-39 | At most one marketing push a day; reminders are scheduled locally on the device where possible (free). |
| CE-40 | Over-the-air updates (EAS Update) for JS changes; native builds only when needed, to stay within free build minutes. |

**10.7 Payments (engineering side)**

| ID | Rule |
| --- | --- |
| CE-41 | RevenueCat manages store purchases; Razorpay powers web checkout on drobie.app. Both update one shared entitlement table through verified webhooks, so a plan bought anywhere works everywhere. |
| CE-42 | The app never shows web prices or links to web checkout on iOS (store rules); marketing emails, gifts, founding offers and the website link to drobie.app. |
| CE-43 | Web checkout supports UPI Autopay and cards with Razorpay Subscriptions; failed renewals retry and notify before the plan lapses. |

**10.8 Abuse, monitoring and accountability**

| ID | Rule |
| --- | --- |
| CE-44 | Rate limits per user and per IP on sign-up, AI calls, uploads and generation; block disposable-email domains for free-look unlocks. |
| CE-45 | Every AI and generation call logs user, feature, model, tokens/credits and cost; the admin panel shows cost per user, per feature and per day. |
| CE-46 | Daily cost alerts (Slack/email) when any target in the table above is crossed; weekly review of the top 1% heaviest users. |
| CE-47 | Feature flags can switch any costly feature to a cheaper mode (rules-only dro, no HD, smaller model) without an app release. |
| CE-48 | Stay on free tiers (Supabase, Expo EAS, PostHog, Sentry, Resend, Cloudflare) until a limit is reached; apply for startup cloud and AI credits at incorporation; pay yearly for tools kept long term. |

**Definition of done for any feature that calls AI, stores files or sends notifications:** cost per use estimated in the ticket, logging per CE-45 in place, a cache or limit applied, and a fallback when the paid service is down or over budget.

## 11. Capture engine: in-house first, AI last

Adding items is drobie's most important flow. Target: **90% of items added with no paid cloud AI call**, under 2 seconds of user effort per item, and 100 items in under 5 minutes on day one. Paid AI is used only when the in-house path is not confident.

**11.1 In-house building blocks (no paid AI)**

| Need | In-house approach | Runs on |
| --- | --- | --- |
| Cut out the item, keep full photo | ML Kit Subject Segmentation (Android), Apple Vision foreground mask (iOS) | Phone, free |
| Is it clothing? Rough category | ML Kit / Vision image labels + a small bundled on-device classifier (TFLite / Core ML) trained on our taxonomy | Phone, free |
| Colour name | Pixel clustering (k-means on the cut-out) mapped to a fixed colour list (navy, olive, maroon…) | Phone, plain code |
| Pattern (solid, stripes, checks, print) | Simple image measures (edge direction and repetition) with an "unsure" fallback | Phone, plain code |
| Duplicate check | Perceptual hash + colour histogram + small on-device embedding; compare with the closet | Phone, free |
| Text on labels, tags, bills | On-device text recognition (ML Kit / Vision OCR) + rules for brand, size, price, fabric | Phone, free |
| Barcodes | ML Kit / Vision barcode scanning → drobie's saved product list | Phone + database |
| Order emails | **Per-retailer templates** (Myntra, Ajio, Amazon, Flipkart, Nykaa, H&M, Zara, Meesho, Tata CLiQ…): fixed rules pull name, size, price, image link; product titles mapped to categories with a keyword dictionary | Server, plain code |
| Product links and shares | Read the page's built-in product data (schema.org JSON-LD, Open Graph tags: name, brand, image, price, colour) | Server, plain code |
| Voice commands | Phone speech recognition + a phrase grammar ("add…", "keeping X in Y", "where's X") with an English–Hindi synonym list (almari = wardrobe, daraaz = drawer) | Phone, free |
| Matching items and places | Fuzzy text matching + synonyms + the user's own history (most used places first) | Phone, plain code |
| Brand catalog | drobie's own product list, built from (anonymised) product details seen in orders and shares, de-duplicated by product ID and image hash | Database |
| Smart defaults | Learn each user's usual brands, sizes and places; prefill and rank choices | Phone, plain code |

**11.2 Per-method pipeline (FRS 3.2b)**

| Method | In-house path | Paid AI only when | Cost per use |
| --- | --- | --- | --- |
| Order emails | Retailer templates + keyword categories | An unknown email format (then a template is added) | ₹0 (fallback ₹0.10–0.30) |
| Gallery sweep | On-device person and clothing detection, segmentation, duplicate merge | Detail tags for confirmed items, batched overnight | ₹0 (₹0.10 per confirmed item, batched) |
| Voice add / voice + place | Speech + grammar + fuzzy match | Unusual phrasing | ₹0 (₹0.05–0.10) |
| Share from any app | Page product data | Screenshots or pages without product data | ₹0 (₹0.20–0.50, cached) |
| Price tag / barcode | Barcode lookup, tag OCR + rules | Unknown product with unreadable tag | ₹0 |
| Bill photo | OCR + line-item rules (brand list, size and price patterns) | Messy handwritten bills | ₹0 (₹0.50) |
| Shopping-bag unpack / drawer photo | On-device multi-object segmentation, colour, duplicate check | Items the phone can't separate or classify | ₹0 (₹0.50–1) |
| Brand catalog pick | Search our product list | Never | ₹0 |
| Add-later stubs | Text + icon | Never | ₹0 |

**11.3 Speed rules for the adding experience**

- Save instantly, process later: every item appears in under 1 second; tags refine in the background.
- Swipe deck for suggestions: right = mine, left = not mine, about 1 second per item.
- Continuous camera: keep shooting; each item auto-separated with a haptic tick and a running count.
- Predicted chips: category, colour, size and place offered in the user's most-likely order; "same as last" button.
- Bulk edit: select many and set place, season or occasion once.
- Voice lists: "add blue jeans, black tee, white sneakers" creates three items.
- Entry points everywhere: home-screen quick-add widget, share menu, lock-screen voice button, Siri / Google Assistant shortcut.
- Show progress: "37 items in 2 minutes" to reward speed.

**11.4 Measures**

| Measure | Target |
| --- | --- |
| Items added without paid AI | ≥ 90% |
| User effort per item | ≤ 2 seconds |
| Day-one closet size | 80–150 items |
| Time to first 50 items | ≤ 3 minutes |
| Wrong category after in-house tagging | ≤ 10% (user fixes in one tap) |

**11.5 Model choices (all licensed for commercial use)**

| Need | Model or tool | Runs | Licence |
| --- | --- | --- | --- |
| Live detection, scan mode | ML Kit Object Detection & Tracking | Phone | Google SDK |
| Fine-grained items, multi-item photos (v1.1) | RF-DETR or D-FINE (small), trained on Fashionpedia + our photos | Phone | Apache-2.0; data CC BY 4.0 |
| Cut-out | Apple Vision foreground mask (iOS), ML Kit Subject Segmentation (Android) | Phone | Platform SDKs |
| Cut-out fallback, garments in worn photos | MobileSAM or EfficientSAM, prompted by detector boxes | Phone | Apache-2.0 |
| Category, pattern, sleeve, neckline | Multi-output EfficientNet-Lite0 / MobileNetV3 | Phone | Apache-2.0 |
| Colour | White balance + LAB k-means + named colour list | Phone | Our code |
| Brand, size, fabric | ML Kit Text Recognition v2, Apple Vision text + dictionary and patterns | Phone | Platform SDKs |
| Care symbols (v1.1) | Small classifier trained on rendered symbols | Phone | Our model |
| Barcodes | ML Kit Barcode Scanning, Apple Vision | Phone | Platform SDKs |
| Similarity | Marqo-FashionSigLIP | Own server | Apache-2.0 |
| Long-tail detection (later) | Florence-2 or Grounding DINO | Own server | MIT / Apache-2.0 |
| Voice | iOS Speech, Android SpeechRecognizer; Whisper small (whisper.cpp) fallback | Phone | Platform / MIT |
| Paid fallback, open chat | Claude Haiku 5.5 | Cloud | API |
| Try it on | Gemini Flash Image class; FASHN for "make it exact" | Cloud | API |

**Not allowed (licences):** Ultralytics YOLO (AGPL), YOLO-World (GPL), BRIA RMBG (non-commercial), InsightFace models, and anything trained on DeepFashion, DeepFashion2, LIP or ATR. Retailer product photos from order emails are shown to their owner but not used for training without legal clearance.
