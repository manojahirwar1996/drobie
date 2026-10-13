# drobie — Functional Requirements Specification (FRS)

Oct 9, 2026 · @Rudy · v1.0 for development

## 1. Introduction

This FRS lists what drobie must do, feature by feature, so design, engineering and testing work from one checklist. Each requirement has an ID, a priority and acceptance criteria a tester can check.

- **Product:** drobie, an AI wardrobe assistant (Android and iOS together at launch) with the agent dro, plus a web admin panel.
- **In scope:** the end-user app (MVP and v1.1) and the admin panel.
- **Out of scope here:** non-functional needs (speed, security, privacy, uptime), the tech stack and data design. Those live in the SRS and the Technical Design.
- **Sources:** the drobie BRD (features, journeys, smart suggestions, daily habit design), the Technical Design, and the prototype canvas (screen codes like A2 or SC3).

**Conventions**

- **IDs:** FR-\<module>-\<number>, for example FR-CAP-03. Admin requirements use FR-ADM.
- **"Must"** is required for the release named; **"should"** is expected but can slip one release.

**In-house first:** every requirement is built with rules, database queries and on-device models by default. Paid cloud AI is used only where a requirement says so (open-ended dro conversations, Try it on, and fallbacks listed in SRS sections 8 and 11), so features keep working if the AI provider is switched off.

## 2. Users and roles

| Role | Who | What they can do |
| --- | --- | --- |
| Guest | Downloaded, not signed in | See the welcome screens with sample photos only; no closet data |
| Free user | Signed-in user on the free plan | Up to 100 items, daily dro limit, all MVP basics, circles and Swap |
| Pro user | Paid or rewarded Pro | Unlimited items and dro, planners, beauty scanning, receipt import, insights and Wrapped, priority Swap |
| Circle member | Any user added to another user's circle | See only items shared to that circle; request to borrow |
| Borrower / lender | Either side of a Swap booking | See that booking, its chat and condition photos |
| super\_admin | Founders | Everything in the admin panel, including managing admins |
| admin | Ops staff | Users, content, Swap, flags, broadcasts, taxonomy, festivals, trend cards |
| moderator | Trust and safety | Reports, listings, disputes, suspensions |
| support | Customer support | Account summaries; user photos only through a time-limited grant the user approves |
| analyst | Data | Read-only dashboards and anonymised metrics |
| stylist | Contract stylist | Create and approve trend cards and edit the style rulebook |

## 3. Functional requirements

### 3.1 Onboarding and account (ONB)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-ONB-01 | Welcome screens before sign-in show only sample (stock) photos, never user data | MVP | No user photo or name appears until sign-in completes; sample photos are labelled |
| FR-ONB-02 | Sign in with Google, Apple, or email (password, email OTP or magic link); no phone, SMS, Truecaller or WhatsApp sign-in | MVP | New user reaches the next step in 1 tap with Google/Apple; email codes expire in 10 minutes; sign-in costs nothing per user |
| FR-ONB-03 | Ask city (auto-detected) and style vibe (multi-select chips) | MVP | City pre-filled from location permission or IP; at least 1 vibe can be skipped |
| FR-ONB-04 | Request photo access and show only clothing-like gallery photos to pick from | MVP | Classification runs on device; nothing uploads until the user taps Add |
| FR-ONB-05 | Process the first picks and show a first outfit | MVP | First outfit shown within 2 minutes of opening the app for 10 photos on a mid-range phone |
| FR-ONB-06 | Founding-member offer: first 10,000 users get 3 months of Pro and a badge | MVP | Counter enforced server-side; badge shows on profile |
| FR-ONB-07 | Referral code entry and sharing | MVP | Reward granted only after the invited friend adds 25 items |
| FR-ONB-08 | Account deletion and data export from Settings | MVP | Export delivers JSON + photo zip; deletion completes within 30 days |

### 3.2 Capture, scan and import (CAP)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-CAP-01 | Guided camera with auto-capture when the item is steady and fully in frame | MVP | Shutter fires on its own; "step back a bit" hint when an edge touches the frame |
| FR-CAP-02 | Show the whole photo fitted in the tile (never cropped) instantly; background removal is an optional per-item or closet-wide switch | MVP | Tile visible in under 0.5 s; toggle swaps to cut-out within about 1 s; falls back to full photo if edges fail |
| FR-CAP-03 | Auto-adjust light and white balance without shifting item colour | MVP | Colour difference before/after within the agreed limit (SRS) |
| FR-CAP-04 | Read brand, size, fit and fabric from visible labels (on-device text recognition) | MVP | Read fields shown as solid chips; guesses shown as dashed chips |
| FR-CAP-05 | Auto-tag category, colours, pattern, season, occasion | MVP | Category, colour and pattern shown on the phone in under 1 s with no cloud call; season and occasion from rules; cloud refinement only when the phone is unsure; any tag fixed in one tap |
| FR-CAP-06 | Duplicate check against items already saved | MVP | Warning shown when similarity is above the threshold; user can override |
| FR-CAP-07 | Location pre-filled with the last-used spot | MVP | Save possible in 2 taps from camera open |
| FR-CAP-08 | Point-and-scan mode: pan the camera; each item held about 2 s is captured, saved to a tray and skipped if already owned | MVP | Live detection on device; one still uploaded per item; review grid grouped by category before final save |
| FR-CAP-09 | Add many: batch pick from gallery (up to 50) with a review grid | MVP | Items needing attention filtered first; Save all in one tap |
| FR-CAP-10 | Add from a store link or share sheet | MVP | Store photo and details filled from the page's built-in product data (no AI); labelled "store photo" until replaced |
| FR-CAP-11 | Multi-item photo split (pile or flat-lay) | v1.1 | Each detected item offered separately; user picks which to save |
| FR-CAP-12 | Care-label symbol reading (wash, iron, bleach, dry) | v1.1 | Symbols recognised on the phone (small bundled model) and shown as care chips |
| FR-CAP-13 | Receipt import by forwarding emails to a drobie address | v1.1 | Items, price, date and return window extracted by retailer templates (AI only for unknown formats); user confirms |
| FR-CAP-14 | Gmail auto-import with consent | Later | Only after Google verification; revocable in Settings |
| FR-CAP-15 | Messy-photo help: retake prompt for blurry or partial photos; optional AI "tidy view" labelled as AI | MVP (retake) / Later (tidy view) | Original photo always kept as the source of truth |

### 3.2b Effortless adding (primary capture methods)

The goal is the simplest adding experience users have ever seen: most items arrive by themselves or with one sentence, one photo or one share. These methods are the default; one-by-one photo capture (3.2) remains for anyone who prefers it.

| ID | Method | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- | --- |
| FR-ADD-01 | Order emails | Items from forwarded order emails (Myntra, Ajio, Amazon, Flipkart, Nykaa, H&M, Zara and others) are created with product photo, brand, size, price and order date; returns remove or flag the item | MVP | Guided one-time forwarding setup under 1 minute; items appear within 5 minutes of the email |
| FR-ADD-02 | Gallery sweep | Photos of the user wearing clothes are found on the phone; garments are suggested as items, repeats merged into one item with wear dates | MVP | Nothing uploads before the user confirms; suggestions shown as a swipe or checklist |
| FR-ADD-03 | Voice add | "Add my navy linen shirt from Zara, bought last month for ₹2,000" creates an item with icon, brand, colour, price and date | MVP | Works in English, Hindi and Hinglish; item saved in under 5 seconds |
| FR-ADD-04 | Voice add + place | "New white sneakers, keeping them in the shoe rack" creates the item and sets its location in one sentence | MVP | Location matched to existing places or created new after one confirm |
| FR-ADD-05 | Share from any app | Sharing a product link, Instagram post or screenshot to drobie offers "I own this" | MVP | Item created with image and details; works from any app's share menu |
| FR-ADD-06 | Price tag or barcode | Scanning a price tag or barcode adds the product | v1.1 | Known products fill instantly; unknown ones ask for one photo of the tag |
| FR-ADD-07 | Bill photo | One photo of a store bill creates all clothing and beauty lines as items | v1.1 | User confirms all lines in one list |
| FR-ADD-08 | Shopping-bag unpack | One photo of several new items laid out creates each as a separate item | v1.1 | Each item separated, tagged and duplicate-checked; one confirm |
| FR-ADD-09 | Drawer, shelf or rail photo | One photo of a wardrobe section adds every visible item and sets that section as their location | MVP | Location taken from the chosen section; items confirmed in one list |
| FR-ADD-10 | Brand catalog pick | Search a product ("Levi's 511 dark blue") and tap "I have this" | v1.1 | Results from drobie's saved product list; photo and details filled |
| FR-ADD-11 | "Add later" stubs | Typing or saying just a name ("black kurta") creates a placeholder item with an icon | MVP | Stub is completed later from gallery, orders or the next wear |

**Smart rules for every method**

| ID | Rule | Acceptance criteria |
| --- | --- | --- |
| FR-ADD-R1 | Duplicate check before saving: "Looks like your navy Zara shirt. Same one?" | Shown when similarity is high; merging keeps the best photo and all history |
| FR-ADD-R2 | Fill gaps silently: photo later from gallery, price from order email, place from the next "keeping it in…" note | Missing fields never block saving |
| FR-ADD-R3 | Confirm in bulk: one checklist or swipe deck, never one screen per item | Up to 50 items confirmable in under a minute |
| FR-ADD-R4 | Icon until a photo exists (72-icon library) | Every item visible in the closet immediately |
| FR-ADD-R5 | Recommended 2-minute first setup: connect order emails, allow gallery, take 3–5 section photos | New user sees 80–150 items on day one (target) |

### 3.3 Catalog, search and filters (CAT)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-CAT-01 | Item profile: category, colours, pattern, fabric, brand, size, season, occasion, price, purchase date, notes, tags | MVP | All fields editable; AI-guessed vs confirmed tags distinguished |
| FR-CAT-02 | Category browse with counts and a cover per category | MVP | Categories without photos use the category icon |
| FR-CAT-03 | Category icon library covers every catalog category | MVP | No item ever shows a blank tile |
| FR-CAT-04 | Smart sections auto-built and refreshed daily (ready to wear, not worn in 60 days, cost-per-wear champions, goes with X, festive ready, near-duplicates, beauty expiring) | MVP | Sections update after each wear or state change; user can pin sections |
| FR-CAT-05 | Filters: category, colour family, pattern, fabric, brand, size and fit, occasion, season, state, place, times worn, last worn, cost per wear, price, own tags | MVP | Filters combine; result count shown before applying |
| FR-CAT-06 | Sort by recently added, most/least worn, last worn, cost per wear, rainbow colour, price | MVP | Sort persists per section |
| FR-CAT-07 | Save a filter combination as a custom smart section | MVP | Saved section updates itself |
| FR-CAT-08 | Smart search in plain words or Hinglish, parsed on the phone with a synonym dictionary ("red stuff, clean, for match day") | MVP | Query shown as editable filter chips; exact matches first, then similar |
| FR-CAT-09 | Visual search with a photo or screenshot | v1.1 | Returns similar owned items ranked by similarity |
| FR-CAT-10 | Accessories and beauty catalogs with their own filters (expiry, opened, skin type, SPF) | MVP | Beauty tiles show expiry badges |
| FR-CAT-11 | Multi-select (long-press) for bulk state, place or circle changes | MVP | Undo available for 10 s after a bulk change |

### 3.4 Locations, states and care (LOC)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-LOC-01 | Places as home > room > storage > shelf; several homes (flat, parents', hostel, suitcase) | MVP | Every item has exactly one current place |
| FR-LOC-02 | Item states: clean, worn, in the wash, at dhobi/press, at tailor, lent, packed | MVP | State changes logged with time; shown as a badge on the tile |
| FR-LOC-03 | Find anything by text or voice ("where's my black jeans?") | MVP | Answer with photo and exact place in under 1 s from database search |
| FR-LOC-04 | Dhobi and tailor tracking with a pickup reminder on a smart default day (3 and 7 days) | MVP | Reminder created automatically; user can change the day in 1 tap |
| FR-LOC-05 | Lent-out tracking: who, since when, return date | MVP | Both lender and borrower get a reminder the day before |
| FR-LOC-06 | Laundry and care hub showing counts and groups by state | MVP | "Collected" and "Mark clean" act on the whole group |
| FR-LOC-07 | Offline closet: browse items, places and states without network | v1.1 | Edits queue offline and sync later without data loss |

### 3.5 Today and outfits (OUT)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-OUT-01 | Morning brief at a user-chosen time: weather, events, today's rail outfit, 2 alternates, at most 2 nudges | MVP | Pick uses only clean items in the current home; ready before the push fires |
| FR-OUT-02 | Wear this: one tap logs the outfit and moves items to worn | MVP | Wear history and cost per wear update immediately |
| FR-OUT-03 | Swap one piece on the rail | MVP | Replacement respects weather, occasion and colour rules |
| FR-OUT-04 | What goes with this: pairing suggestions for any item | MVP | At least 3 suggestions when the closet has 15+ items |
| FR-OUT-05 | Saved looks and planning looks by date | MVP | Planned look appears on that day's rail |
| FR-OUT-06 | Evening-before card: weather swap, ironing and prep reminders | MVP | Shown only when something changes or is due |
| FR-OUT-07 | Rate today's look (loved it / fine / not me) | MVP | Rating feeds the taste profile; never shared |
| FR-OUT-08 | Repeat radar: warn when the same outfit meets the same people or event | v1.1 | Warning shown while planning, with a one-tap swap |
| FR-OUT-09 | Make it trendy: restyle a look using current trend cards and owned items only | v1.1 | Never suggests buying |
| FR-OUT-10 | Daily surprise card (forgotten gem, new combo, friend's look to recreate) | MVP | Same card type not repeated within a week |
| FR-OUT-11 | Home-screen and lock-screen widgets showing today's rail | v1.1 | Widget refreshes after the morning pick and after Wear this |
| FR-OUT-12 | Recreate a look: share or upload any outfit photo (Instagram, Pinterest, screenshot, friend's post); dro detects each piece, finds the same or closest owned items, shows a match % and suggests swaps or friends to borrow from for missing pieces | MVP | Works from the share sheet and in dro chat; result in under 5 s; each piece swappable; never suggests buying; the inspiration photo is not stored after matching unless saved by the user |

### 3.6 dro, the assistant (DRO)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-DRO-01 | Chat with dro about the user's own items, places, plans and care | MVP | Lookups (where is, how many, what's clean, what's at the dhobi) answered from the database in under 1 s with no AI call; open styling questions stream first words within 2 s; answers cite real items with photos |
| FR-DRO-02 | Voice input (tap to talk) | MVP | Speech turned into text on the device where supported |
| FR-DRO-03 | dro performs actions from chat ("dropped 6 things at the press-wala") | MVP | Common commands understood by the phrase grammar without AI; shows what it changed, with Undo and "wrong item?" |
| FR-DRO-04 | Rich answers: lookbook cards, vibe meter, plans, this-or-that comparisons | MVP | Each card has one-tap actions (wear, plan, swap piece) |
| FR-DRO-05 | Thinking state shows real reasoning steps (weather checked, items skipped and why) | MVP | Steps come from the rules engine's actual inputs, never invented |
| FR-DRO-06 | Rate my fit from a photo, in honest or hype mode | v1.1 | Scored by rules (colour harmony, occasion, weather, dress code) with template comments; AI only for free-form honest feedback; upgrades use owned items only; body-shape comments never made |
| FR-DRO-07 | Plan my week with no repeats and laundry awareness | v1.1 | Built by the rules engine (no AI call); respects calendar events and wash days |
| FR-DRO-08 | Personality modes: hype bestie, honest stylist, minimal, desi | MVP | Mode changes tone only, never facts |
| FR-DRO-09 | Daily question limits by plan | MVP | Limit shown before it is reached; Pro is unlimited |
| FR-DRO-10 | "hey dro" hands-free wake word | Later | Opt-in only, with an on-screen listening indicator |

### 3.7 Reminders and notifications (NOT)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-NOT-01 | Reminders for ironing, pickups, tailor deadlines, returns, expiry, events | MVP | Each reminder has Done and Remind later |
| FR-NOT-02 | At most 1 push a day and 2 nudges on screen by default | MVP | Enforced server-side; user can raise or lower to 0–3 |
| FR-NOT-03 | Quiet hours and pause for a week | MVP | No push sent during quiet hours or a pause |
| FR-NOT-04 | Every nudge has "not useful", which lowers that nudge type's score | MVP | Same tip not repeated within 7 days |
| FR-NOT-05 | Per-type notification toggles | MVP | Settings change applies to the next send |

### 3.8 Beauty and expiry (BEA)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-BEA-01 | Detect expirable categories (skincare, makeup, sunscreen, perfume, hair, nails, lens solution) | MVP | Clothes and shoes are never asked about expiry |
| FR-BEA-02 | Read printed expiry, manufacture date and PAO symbol from the pack | v1.1 | Found values pre-filled for one-tap confirmation |
| FR-BEA-03 | Optional prompt: Opened today, Not opened yet, Add date, Skip | MVP | Never blocks saving; estimate labelled as an estimate |
| FR-BEA-04 | Barcode scan with product lookup | v1.1 | Name and brand filled when found; manual entry otherwise |
| FR-BEA-05 | Expiry reminders at 30 and 7 days; "finish the oldest first" for duplicates | MVP | Reminders respect notification limits |
| FR-BEA-06 | Return windows and warranties from receipts | v1.1 | Reminder 2 days before the window closes |

### 3.9 Before you buy and money (BUY)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-BUY-01 | Share a link or screenshot from any shopping app to see similar owned items | MVP | Sheet opens in under 3 s with match % and Skip / Borrow / Buy anyway |
| FR-BUY-02 | Borrow option finds similar items in the user's circles | v1.1 | Only items shared with the user are shown |
| FR-BUY-03 | Money-saved counter for skipped duplicates | MVP | Counter updates on Skip; shown on Insights |
| FR-BUY-04 | Cost per wear and insights (most and least worn, colour mix, gaps) | v1.1 | Values recalculate after each wear |
| FR-BUY-05 | Monthly tidy-up: keep, lend, sell or donate items unworn for 12 months | Later | Selling is a link out; drobie takes no cut |
| FR-BUY-06 | drobie Wrapped monthly and yearly, shareable | v1.1 | Share card contains no private data unless the user adds it |

### 3.10 Plan: occasions, festivals and trips (PLN)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-PLN-01 | Week plan calendar with looks and events | MVP | Empty days filled by the morning pick |
| FR-PLN-02 | Calendar sync (opt-in) to read events | MVP | Only titles and times read; revocable |
| FR-PLN-03 | Occasion planner (weddings, parties) with functions, looks and prep tasks | v1.1 | Prep tasks become reminders automatically |
| FR-PLN-04 | Festival packs (for example Navratri 9 colours) by region | v1.1 | Shows ready, borrowable or missing per day |
| FR-PLN-05 | Trip packing list from clean items, weather and plans | v1.1 | Packed items move to "packed" until unpacked |

### 3.11 Friends, community and Swap (SOC)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-SOC-01 | Friends tab with Feed, Swap, Circles and Events | v1.1 | Tab replaces Swap in the bottom bar |
| FR-SOC-02 | Add friends by contacts, handle, QR code or WhatsApp invite | v1.1 | Requests need acceptance; contact matching is opt-in |
| FR-SOC-03 | Circles (family, flatmates, best friends, college) with per-circle sharing | v1.1 | Private by default; share chosen items or whole closet per circle |
| FR-SOC-04 | Fit posts and stories; react and comment; "recreate from my closet" | v1.1 | Posts visible only to chosen circles |
| FR-SOC-05 | Friend profile with their shared closet and borrow button | v1.1 | Shows availability and lender rating |
| FR-SOC-06 | Lend an item: availability calendar, circles or radius, optional deposit | v1.1 | Days the owner planned to wear it are blocked automatically |
| FR-SOC-07 | Borrow request with trust details; accept or decline in one tap | v1.1 | Both sides get a booking chat |
| FR-SOC-08 | Handover and return with condition photos from both sides | v1.1 | Photos timestamped and kept until the booking closes plus 30 days |
| FR-SOC-09 | Ratings for lenders and borrowers | v1.1 | Rating only after a completed booking |
| FR-SOC-10 | Help me decide polls | v1.1 | Poll closes at a set time; results visible to voters |
| FR-SOC-11 | Challenges (#30DayRewear, No-buy November) with streak tracking and campus boards | v1.1 | Kind streaks: 2 free skip days a week |
| FR-SOC-12 | Event rooms (Garba, weddings) with colour plans and who-wears-what | Later | Members see each other's planned colour only |
| FR-SOC-13 | Group chat with dro as group stylist | Later | dro acts only on items members have shared |
| FR-SOC-14 | Safety: report and block everywhere, verified badges, women-only circles, rounded distance | v1.1 | Exact address never shown or stored on listings |

### 3.12 Plans, payments and rewards (PAY)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-PAY-01 | Free, Pro and Ultimate dro plans with limits from config | MVP | Limits changeable by admins without an app release |
| FR-PAY-02 | Plan purchase via Google Play Billing and Apple in-app purchase (RevenueCat), and web checkout on drobie.app (Razorpay) | MVP | Plan updated only by a verified store or Razorpay webhook; a plan bought anywhere works on every platform |
| FR-PAY-03 | 7-day Ultimate dro trial, with a reminder 2 days before any charge | MVP | One trial per account |
| FR-PAY-04 | Founding price for the first 1,000 paying users, kept while subscribed | MVP | Price stored on the subscription record |
| FR-PAY-05 | Rewards for real use (items added, friends who stay) | MVP | Free Pro months capped per person |
| FR-PAY-06 | One-tap cancel and a reminder 3 days before any charge | MVP | No dark patterns in the cancel flow |
| FR-PAY-07 | Swap deposits and paid rentals through a licensed payment partner | Later | drobie never holds funds directly |

### 3.13 Habit and progress (HAB)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-HAB-01 | Closet completeness and wardrobe levels that unlock features (week planner at 25 items, trip packer at 50) | MVP | Progress visible on Profile and Today |
| FR-HAB-02 | Rewear and fit-logging streaks with freeze days and no guilt copy | v1.1 | Streak pauses automatically when the user marks travel or rest |
| FR-HAB-03 | Sunday week-ahead card | v1.1 | Shown once a week; dismissible |
| FR-HAB-04 | Seasonal moments (festivals, wedding season, monsoon, new year reset) | v1.1 | Scheduled from the admin festivals module |
| FR-HAB-05 | Every journey ends with a next useful action | MVP | No dead-end screen in the prototype review |
| FR-HAB-06 | No streaks, public feed or Swap for users under 18 | MVP | Enforced from the age given at sign-up |

### 3.14 Outfits from photos, outfit builder and Try it on (WRD)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-WRD-01 | Find gallery photos where the user is wearing visible clothes, after the user identifies themselves once | v1.1 | Person and face matching run on the phone; opt-in; other people's photos are skipped |
| FR-WRD-02 | Extract each garment from those photos and categorise it (outerwear, tops, bottoms, footwear, accessories) | v1.1 | Each item shows the original crop plus an optional AI-cleaned product image, labelled |
| FR-WRD-03 | Merge the same garment seen across photos into one item; use photo dates as wear history | v1.1 | User can split or merge in the review grid; wears and cost per wear filled in |
| FR-WRD-04 | Outfit builder: pick items per category into an auto-arranged flat-lay collage | MVP | Selections show as checkmarks; collage updates live; save as look or moodboard |
| FR-WRD-05 | Moodboards for occasions (work, wedding, trip) with sharing to circles | v1.1 | Shared boards show only the chosen looks |
| FR-WRD-06 | Try it on: generate an image of the user wearing the selected outfit from their reference photo | v1.1 | Result in under 60 s with a progress state; labelled "AI preview"; Regenerate, rate, Save, Share |
| FR-WRD-07 | Reference photo management: add, replace, delete; explicit consent | v1.1 | Deleting removes the photo and all generated previews within 24 hours |
| FR-WRD-08 | Try it on credits by plan | v1.1 | Remaining credits shown before generating |
| FR-WRD-09 | Safety: no images of other people, no body editing, no use under 18 | v1.1 | Blocked server-side; reported results reviewed by moderators |

### 3.15 Subscription boosters (BRD 10e)

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-CLR-01 | Colour analysis from one daylight selfie: season, undertone, best colours, colours to avoid | MVP | Computed on the phone (face landmarks + colour rules, no AI call); guided capture checks light and face position; result in under 5 seconds |
| FR-CLR-02 | Free users see their season and 3 best colours; Pro sees the full palette and avoid list | MVP | Paywall shown on the locked palette, never before the free result |
| FR-CLR-03 | Every closet item gets a "suits you" score; filters and dro suggestions use it | MVP | Scores update when the analysis is redone |
| FR-CLR-04 | Before you buy and Recreate show whether a new item's colour suits the user | v1.1 | Shown as a simple badge with a reason |
| FR-CLR-05 | Selfie never leaves the phone and is deleted after analysis unless the user saves it; no wording ranks skin tones | MVP | Privacy screen states this; copy reviewed |
| FR-RPT-01 | Each logged outfit can be tagged with an event and people or groups | v1.1 | Tagging takes under 3 taps; suggested from calendar and circles |
| FR-RPT-02 | Repeat warning when a planned outfit (or a key item) was worn with the same people or group in the last 60 days (configurable) | v1.1 | Warning offers 2 alternatives from the user's closet |
| FR-RPT-03 | Instagram history import: personal accounts via the Instagram data-download file; creator and business accounts via the Instagram API | v1.1 | Only the user's own posts; user confirms detected outfits before saving |
| FR-RPT-04 | Import depth by plan: Pro last 12 months, Ultimate all history | v1.1 | Limit read from config |
| FR-WA-01 | Ultimate users can link WhatsApp to get the morning pick, reminders and Sunday plan, and ask dro questions | v1.2 | Opt-in with phone confirmation; unlink anytime; monthly message cap from config |
| FR-WA-02 | WhatsApp answers use the same limits, caching and rules-first logic as in-app dro | v1.2 | Cost logged per message (CE-45) |
| FR-SQD-01 | Squad room for an event: host sets functions, dates and a theme per function | v1.1 | Ultimate host; guests join free by link |
| FR-SQD-02 | Each member gets outfit suggestions from their own closet that match the theme | v1.1 | Members see others' picks only if shared |
| FR-SQD-03 | Clash and duplicate warnings across members (same outfit or too-similar colours) | v1.1 | Warning names the function and offers alternatives |
| FR-SEL-01 | Items unworn for 6+ months are suggested for resale | v1.1 | Snooze or "keep forever" option |
| FR-SEL-02 | One-tap listing: cleaned photos, title, description and suggested price, ready to copy or share to OLX, Instagram or thrift pages | v1.1 | Marking an item sold adds the amount to money saved |
| FR-REEL-01 | Monthly fit reel or collage from logged outfits, built on the phone | MVP | Exports as video and image; Free version carries a small drobie watermark |
| FR-REEL-02 | Ultimate removes the watermark and unlocks extra reel styles | MVP | Styles configurable by admins |
| FR-SAV-01 | Savings promise: if money saved is under ₹1,000 after 3 paid months, the next month is free | v1.1 | Automatic credit; one per user; shows the items counted |
| FR-REF-01 | Creator and campus codes with tracked sign-ups and paid conversions | MVP | Dashboard for each partner; payouts 20–30% of first-year revenue, set per partner by admins |
| FR-REF-02 | Partner codes apply on web checkout and in-app (where store rules allow offer codes) | MVP | Code attribution kept for 30 days |

## 4. Admin panel (ADM)

The admin panel is a separate web app; every action checks the admin's role and is written to the audit log.

| ID | Requirement | Roles | Priority | Acceptance criteria |
| --- | --- | --- | --- | --- |
| FR-ADM-01 | Sign-in with 2-step verification and role-based menus | all | MVP | Menus and actions hidden when the role lacks access |
| FR-ADM-02 | Dashboard: sign-ups, daily and weekly active users, items added, D1/D7/D30 retention, Pro conversions, Swap volume | all | MVP | Numbers refresh at least hourly |
| FR-ADM-03 | Users: search by phone or email; view plan, status, verification; suspend or ban with a reason | support (view), moderator+ | MVP | Every change logged with before and after |
| FR-ADM-04 | Support access to a user's items only through a time-limited grant the user approves | support | MVP | Access ends automatically; each view logged |
| FR-ADM-05 | Reports and moderation queue for users, listings, posts and messages | moderator+ | v1.1 | Actions: dismiss, warn, remove, suspend; notes kept |
| FR-ADM-06 | Swap and disputes: bookings, deposits, condition photos side by side, decisions | moderator+ | v1.1 | Decision notifies both parties |
| FR-ADM-07 | AI usage and costs per day, feature and user; adjust limits | admin+, analyst (read) | MVP | Alert when daily cost passes a set threshold |
| FR-ADM-08 | Taxonomy: categories, icons, colours, patterns, occasions | admin+ | MVP | Changes reach apps without a release |
| FR-ADM-09 | Festivals and occasions calendar with colour schedules by region | admin+ | v1.1 | Festival packs appear on the dates set |
| FR-ADM-10 | Trend studio: create, schedule, approve and retire trend cards by region and season | stylist, admin+ | v1.1 | Cards need stylist approval; expire after 8 weeks unless renewed |
| FR-ADM-11 | Style rulebook editor with version history | stylist, admin+ | v1.1 | Every version can be compared and restored |
| FR-ADM-12 | Broadcasts: push and in-app messages to segments, scheduled, with preview | admin+ | MVP | Respects user quiet hours and push limits |
| FR-ADM-13 | Feature flags and config (plan limits, rollout percentages) | admin+ | MVP | Change takes effect within 5 minutes |
| FR-ADM-14 | Referrals and rewards with abuse checks | admin+ | MVP | Suspicious patterns flagged for review |
| FR-ADM-15 | AI evaluation dashboard for model changes against a stylist-rated test set | admin+ | v1.1 | New model must match or beat the current one before switching |
| FR-ADM-16 | Audit log of every admin action: who, what, when, before and after | super\_admin, admin | MVP | Log cannot be edited or deleted from the panel |

## 5. Business rules

| Rule | Value |
| --- | --- |
| Item limits | Free 40, Pro 300, Ultimate dro unlimited (configurable) |
| Free plan dro questions | Daily limit set in config; rises with rewards |
| Plans and prices | Free ₹0; Pro ₹399/month or ₹3,999/year; Ultimate dro ₹599/month or ₹5,999/year (incl. GST). Web prices on drobie.app: ₹369 / ₹549 a month. Studio image credits sold separately, except 20 looks a month included in Ultimate dro |
| Founding offer | First 1,000 paying users: Pro ₹299 / Ultimate dro ₹449 a month, kept while subscribed, plus a badge |
| Referral reward | 1 month of Pro to both, only after the friend adds 25 items |
| Pushes | At most 1 a day by default; 2 nudges on screen; quiet hours respected |
| Same tip cool-down | 7 days |
| Dhobi / tailor default pickup | 3 days / 7 days after drop-off |
| Expiry reminders | 30 and 7 days before |
| Lent item reminders | Day before return, to both sides |
| Trend cards | Stylist-approved; expire after 8 weeks unless renewed |
| Swap location | Rounded to about 1 km; exact address never stored on listings |
| Data deletion | Rows and photos removed within 30 days of the request |
| Under 18 | No streaks, public feed or Swap |
| Purchases | drobie never pushes buying or affiliate links; no ads inside the closet |

## 6. Traceability

Every BRD feature maps to requirements here and to prototype screens, so nothing is built without a design and nothing designed is forgotten.

| BRD area | Requirements | Prototype screens |
| --- | --- | --- |
| Onboarding and account | FR-ONB-01 to 08 | O1–O6, U1, U4 |
| Capture and import | FR-CAP-01 to 15 | A1–A7, X3 |
| Point-and-scan mode | FR-CAP-08 | SC1–SC6 |
| Catalog, search, smart sections, filters | FR-CAT-01 to 11 | C1–C13, Icon library |
| Locations, states, laundry | FR-LOC-01 to 07 | C6, K1–K3, X2 |
| Today and outfits | FR-OUT-01 to 12 | T1–T5 |
| dro assistant | FR-DRO-01 to 10 | D1–D11 |
| Reminders and notifications | FR-NOT-01 to 05 | K3, U2, T3 |
| Beauty and expiry | FR-BEA-01 to 06 | E1–E4, C12 |
| Before you buy and money | FR-BUY-01 to 06 | B1–B2, I1–I3 |
| Plan, festivals, trips | FR-PLN-01 to 05 | P1–P4 |
| Friends, community, Swap | FR-SOC-01 to 14 | F1–F8, W1–W6 |
| Plans, payments, rewards | FR-PAY-01 to 07 | U3, W6 |
| Daily habit design (BRD 7c) | FR-HAB-01 to 06, FR-OUT-10 to 11 | T1, T5, F5 |
| Admin panel | FR-ADM-01 to 16 | Not yet designed |

Added in v0.2: outfits from photos, outfit builder and Try it on map to FR-WRD-01 to 09 (BRD features 82–84; screens not yet designed).

**Open questions**

- Price test after launch: ₹399 / ₹599 against ₹449 / ₹649 a month
- Minimum age for sign-up: 13, 16 or 18?
- Which payment partner for Swap deposits (needed before FR-PAY-07)?

## 7. Cost controls (functional requirements)

These are the user-visible behaviours that keep running costs low; the engineering rules behind them are in SRS section 10 (CE-01 to CE-48).

| ID | Requirement | Priority | Acceptance criteria |
| --- | --- | --- | --- |
| FR-CST-01 | Morning pick, "where is my…", filters, reminders and duplicate checks work without an AI call | MVP | Turning off the AI provider leaves these features working |
| FR-CST-02 | dro shows a short answer first with a "tell me more" option | MVP | Default answers fit one screen; "tell me more" makes a new call only when tapped |
| FR-CST-03 | Daily dro limits per plan (Free 5, Pro 150, Ultimate unlimited with fair use), shown to the user | MVP | Counter visible; limits read from config |
| FR-CST-04 | Instant on-device tags when an item is added; cloud refinement arrives later without blocking the user | MVP | Item saved and visible in under 2 seconds offline |
| FR-CST-05 | Try it on shows a saved result instantly when the same outfit was generated before | v1.1 | No new credit charged for a repeat outfit |
| FR-CST-06 | Studio images are standard quality; HD download costs 1 extra credit | v1.1 | HD offered only on save or share |
| FR-CST-07 | First Regenerate on a look is free; later ones use a credit, with the cost shown before tapping | v1.1 | Credit count visible on the button |
| FR-CST-08 | Credits are checked before generation and refunded automatically if it fails | v1.1 | No charge for failed or blocked images |
| FR-CST-09 | 5 free Studio looks unlock at 30 items, once per person | v1.1 | Blocked for repeat or disposable-email accounts |
| FR-CST-10 | Inactive accounts (6+ months) get an email, then full-size photos move to archive storage; they come back on next sign-in | v1.1 | Thumbnails stay visible; restore within 1 minute of opening the closet |
| FR-CST-11 | drobie.app sells plans, gifts and founding offers through Razorpay with a web bonus (+1 month on yearly, +10% images on packs) | MVP | Purchase on the web unlocks the plan in the app within 1 minute |
| FR-CST-12 | The iOS app never shows web prices or links to web checkout | MVP | App review checklist item |
| FR-CST-13 | Admins see AI and storage cost per user, per feature and per day, with alerts | MVP | Alert fires when a cost target in SRS section 10 is crossed |
| FR-CST-14 | Admins can switch costly features to cheaper modes (rules-only dro, no HD, smaller model) instantly | MVP | Change applies without an app release |
