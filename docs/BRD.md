# drobie — Business Requirements Document (BRD)

Oct 8, 2026 · @Rudy · v1.0 for development

## 1. Executive summary

drobie is an AI wardrobe assistant that remembers everything a person owns and helps them wear it, find it, care for it and share it. Inside lives **dro**, a friendly agent people talk to: "hey dro, where's my black jeans?"

- **For:** young adults (18–30), India-first, built to go global.
- **Promise:** Never 'nothing to wear' again. Logo tagline: *Hang out with your wardrobe.*
- **Core engine:** a catalog of every item (photo, attributes, location, state, dates) plus an AI that reasons over it.
- **What makes it different:** item location and laundry/tailor state, cosmetics expiry, a "before you buy" duplicate check, occasion planning (Navratri, weddings) and a local borrow/swap network.
- **Why now:** phone cameras and on-device AI can now turn a photo into a clean, tagged item in seconds, which removes the biggest barrier wardrobe apps have always had: onboarding effort.
- **Moat:** each user's catalog (high switching cost), local swap network effects, and dro's personality.

## 2. Problem and opportunity

People own more than they remember, so they rebuy, lose, waste and stress. No product today acts as a memory for everything in the wardrobe and shelf.

**Everyday pains we solve**

- "Where is my black Zara jeans?" — no way to track where items are kept (almirah, hostel, parents' home, suitcase, lent to a friend).
- "I have nothing to wear" — while the wardrobe is full; no help planning outfits for the day, weather or occasion.
- Duplicate buying — "I already have that shade of jeans" is only realised after purchase.
- Expiring cosmetics — lotions and sunscreen expire unused; PAO ("12M") and batch codes are unreadable.
- Laundry, dhobi, press-wala and tailor — items get stuck, forgotten before a function.
- Fit changes — clothes that no longer fit sit unused.
- Occasions — Navratri 9 colours, weddings (haldi to pheras), parties need planning, ironing and pickup reminders.
- Wearing an outfit once — festive wear is costly and rarely reused; friends nearby have exactly what you need.

**Why existing apps fail.** Wardrobe apps have existed for years, but most users quit at onboarding: photographing 200+ items one by one is too much work. The second failure is that they are static catalogs with little daily value. drobie wins by (1) making capture nearly effortless and (2) giving a reason to open the app every day (dro's morning pick, reminders, nudges).

## 3. Goals and success metrics

The north-star metric is **weekly active closets**: users who open drobie and act on an item (wear, find, move, plan, lend) at least once in a week. Targets below are starting proposals to confirm after validation.

| Metric | What it tells us | Proposed target (first 6 months after launch) |
| --- | --- | --- |
| Onboarding completion | Capture is easy enough | 60% of sign-ups add 25+ items in week 1 |
| Items per active user | Depth of the catalog (the moat) | 100+ by day 30 |
| Day-30 retention | Daily value is real | 30%+ |
| Morning pick opens | dro's daily habit works | 3+ days a week per active user |
| "Before you buy" checks | The viral, money-saving feature is used | 1+ per active user per month |
| Free-to-Pro conversion | Willingness to pay | 4–6% of monthly actives |
| Swap requests fulfilled | Community works locally | 70% of requests accepted in launch campuses |

**Business goals:** prove retention in India within 6 months of launch, reach a paying base that covers AI and hosting costs, then expand to a second market.

## 4. Target users and personas

The launch audience is 18–30 year olds in Indian cities and campuses; the product is built in English first and designed to localise.

| Persona | Who | Top jobs for drobie | Wins them over |
| --- | --- | --- | --- |
| The hostel student | 19–23, lives between hostel/PG and parents' home, tight budget | Track what's where, borrow festive wear, plan outfits for college events | Multi-home locations, Swap, Navratri planner |
| The young professional | 23–30, new job, shops online often | Morning outfit picks, avoid duplicate buys, laundry and tailor reminders | Morning brief, Before you buy, cost-per-wear |
| The beauty and skincare lover | 18–30, large cosmetics shelf | Track expiry and opened dates, use products before they spoil | Shelf scan, expiry nudges |
| The family organiser | 25–35, manages kids' or siblings' clothes | Outgrown alerts, hand-me-downs, shared family wardrobe | Family circles, size tracking |

All personas share one trait: they want help without effort. Every feature is judged by how few taps it costs.

## 5. Complete feature list

The MVP is the catalog, effortless capture, location and laundry state, dro (chat and daily picks), reminders and the Before you buy check; community, beauty scanning and occasions follow in v1.1. Change any priority from its dropdown.

| # | Module | Feature | What it does | Priority |
| --- | --- | --- | --- | --- |
| 1 | Capture | Quick photo add | Snap one item; real photo kept, background removed, auto-adjusted, auto-tagged | MVP |
| 2 | Capture | Multi-item photo | One photo of a pile or flat-lay is split into separate items | v1.1 |
| 3 | Capture | Point-and-scan mode | Point the camera at the wardrobe; hold about 2 s per item and it is spotted, captured, cut out, tagged and saved on its own. Replaces the heavy video scan | MVP |
| 4 | Capture | Order-history import | Reads shopping receipts in email (with consent) and adds items with brand, size, price, photo | v1.1 |
| 5 | Capture | Product link import | Share or paste a store link; item added with the store photo and details | MVP |
| 6 | Capture | Tag and care-label scan | Reads brand, size, fabric and wash-care symbols from the label | v1.1 |
| 7 | Capture | Lazy capture | "Log today's outfit" adds items gradually through normal life | MVP |
| 8 | Catalog | Item profile | Category, colours, pattern, fabric, brand, size, season, occasion, price, purchase date, notes | MVP |
| 9 | Location | Where it's kept | Home > room > storage > shelf; several homes (hostel, parents', suitcase) | MVP |
| 10 | Location | Item state | Clean, worn, in the wash, at dhobi/press-wala, at tailor, lent, packed | MVP |
| 11 | Location | Lent-out tracking | Who has it since when, return reminders | MVP |
| 12 | Location | Find anything | "Where's my black jeans?" by text or voice | MVP |
| 13 | Outfits | Morning pick | Daily outfit from clean items using weather, calendar and wear history | MVP |
| 14 | Outfits | What goes with this | Pairing suggestions for any item | MVP |
| 15 | Outfits | Saved looks | Build and save outfits, plan by date | MVP |
| 16 | Outfits | Repeat radar | Warns when the same outfit meets the same group or event | v1.1 |
| 17 | Outfits | Occasion planner | Navratri 9 colours, wedding functions, parties: outfits, accessories, prep tasks | v1.1 |
| 18 | Outfits | Trip packing | Packing list from your own wardrobe for days, weather and plans | v1.1 |
| 19 | dro | Ask dro (chat + voice) | Natural-language assistant over the whole catalog, "hey dro" | MVP |
| 20 | dro | Proactive nudges | "psst" cards: expiry, duplicates, laundry, returns | MVP |
| 21 | Beauty | Shelf and barcode scan | Identify products, read PAO symbol and batch code | v1.1 |
| 22 | Beauty | Expiry tracking | Opened date + PAO, use-it-first nudges | v1.1 |
| 23 | Money | Before you buy | Share any shopping link; drobie shows similar items you already own | MVP |
| 24 | Money | Cost-per-wear and insights | Price ÷ wears, most and least worn, colour and category gaps | v1.1 |
| 25 | Money | Declutter | Items unworn for 12 months: sell, donate or list for borrowing | Later |
| 26 | Money | drobie Wrapped | Monthly and yearly shareable recap | Later |
| 27 | Fit | Fit check (opt-in) | Measurements over time; "these might feel snug" with a kind tone | Later |
| 28 | Reminders | Prep reminders | Iron, pick up laundry, tailor deadline, return a lent item, event prep | MVP |
| 29 | Community | Circles | Friends and family groups; share chosen items or whole closet | v1.1 |
| 30 | Community | Swap marketplace | List an item with an availability calendar; request, accept, hand over, return | v1.1 |
| 31 | Community | Help me decide | Post 2–3 outfit options; friends vote in one tap | v1.1 |
| 32 | Community | Event rooms | Shared space for a wedding or Garba night: colour themes, who wears what | Later |
| 33 | Community | Rewear feed and challenges | Celebrate rewearing; 30-day no-buy, capsule challenges | Later |
| 34 | Community | Trust and safety | Verified profiles, ratings, deposits, reporting | v1.1 |
| 35 | Family | Family wardrobes | Kids' clothes, outgrown alerts, hand-me-downs | Later |
| 36 | Platform | Account and privacy | Sign-up, onboarding, consent, export and delete data | MVP |
| 37 | Platform | Notification controls | Choose nudge types, quiet hours, daily summary | MVP |
| 38 | Platform | Offline catalog | Browse items and locations without network | v1.1 |
| 39 | Platform | Languages | Hindi first, then more Indian and global languages | Later |

**Features added in v0.2**

| # | Module | Feature | What it does | Priority |
| --- | --- | --- | --- | --- |
| 40 | Capture | Gallery scan | With permission, the phone finds clothing photos in the gallery and groups look-alikes; nothing uploads until the user picks | MVP |
| 41 | Capture | Full-photo tiles | Every photo shows whole, fitted in its tile, instantly; background removal is an optional switch | MVP |
| 42 | Capture | Label reading | Brand, size, fit and fabric read from visible labels on the phone | MVP |
| 43 | Capture | Several items in one photo | Spots extra items (a belt with the jeans) and offers to save each | v1.1 |
| 44 | Capture | Messy-photo help | Retake prompt for blurry or cut-off photos; store photo offered when the exact item is recognised | MVP |
| 45 | Capture | AI tidy view | Neat AI-made version of a crumpled item, labelled and user-approved; real photo stays the source of truth | Later |
| 46 | Catalog | Category browse and icon library | Categories with counts and covers; 72 category icons for items without photos | MVP |
| 47 | Catalog | Smart sections | Auto-built, daily-refreshed collections (ready to wear, not worn in 60 days, goes with X, festive ready, near-duplicates); pin favourites | MVP |
| 48 | Catalog | Full filters and sort | Category, colour family, pattern, fabric, size, occasion, season, state, place, wears, cost per wear, price; save as a section | MVP |
| 49 | Catalog | AI search | Plain words or Hinglish ("red stuff, clean, for match day") turned into editable filter chips | MVP |
| 50 | Catalog | Visual search | Search the closet with a photo or screenshot | v1.1 |
| 51 | Catalog | Accessories and beauty catalogs | Own views and filters (watches, bags, jewellery; expiry, opened, skin type, SPF) | MVP |
| 52 | Catalog | Bulk actions | Long-press to select many and change state, place or circle at once, with Undo | MVP |
| 53 | Outfits | Evening-before card | Weather swaps, ironing and prep for tomorrow, only when something is due | MVP |
| 54 | Outfits | Rate today's look | Loved it / fine / not me; teaches dro taste privately | MVP |
| 55 | Outfits | Daily surprise card | Forgotten gem, new combination or a friend's look to recreate; never the same type twice a week | MVP |
| 56 | Outfits | Make it trendy | Restyle any look with current trend cards using only owned items | v1.1 |
| 57 | Outfits | Widgets | Home-screen and lock-screen widgets with today's rail | v1.1 |
| 58 | dro | Personality modes | Hype bestie, honest stylist, minimal or desi mode; changes tone, never facts | MVP |
| 59 | dro | Thinking that shows its work | Animated hanger rail plus real reasoning steps while dro styles | MVP |
| 60 | dro | Lookbook answers | Swipeable outfit cards with a vibe meter and one-tap actions | MVP |
| 61 | dro | Actions from chat | "Dropped 6 things at the press-wala" updates items and reminders, with Undo | MVP |
| 62 | dro | Rate my fit | Photo of today's outfit scored on colour, fit and occasion, with upgrades from owned items | v1.1 |
| 63 | dro | Plan my week | Five days, no repeats, laundry-aware, events covered | v1.1 |
| 64 | dro | This or that | Compares two options with repeat warnings and owned accessories to complete the look | v1.1 |
| 65 | Beauty | Smart expiry detection | Knows which products expire, reads dates and PAO, asks optionally; estimates labelled | MVP |
| 66 | Money | Return windows and warranties | Reads them from receipts and reminds before they close | v1.1 |
| 67 | Money | Money-saved counter | Adds up skipped duplicates from Before you buy | MVP |
| 68 | Community | Friends tab | Feed, Swap, Circles and Events in one tab (replaces the Swap tab) | v1.1 |
| 69 | Community | Add friends | Contacts (opt-in), handle, QR code or WhatsApp invite | v1.1 |
| 70 | Community | Fit posts and stories | Share today's fit to chosen circles; friends react and recreate it from their own closet | v1.1 |
| 71 | Community | Friend profile and shared closet | See what a friend shares, availability and lender rating; ask to borrow | v1.1 |
| 72 | Community | Challenges and campus boards | #30DayRewear, No-buy November, capsule challenges, rewear leaderboards | v1.1 |
| 73 | Community | Group chat with dro | Trip and event groups where dro coordinates outfits and lending | Later |
| 74 | Habit | Closet levels and completeness | Progress that unlocks dro powers (week planner at 25 items, trip packer at 50) | MVP |
| 75 | Habit | Kind streaks | Rewear and fit-logging streaks with free skip days and no guilt messages | v1.1 |
| 76 | Habit | Sunday week-ahead | One card a week with a ready plan | v1.1 |
| 77 | Habit | Seasonal moments | Festival packs, wedding season, monsoon mode, new-year closet reset | v1.1 |
| 78 | Platform | Dark mode | Designed dark theme that follows the phone setting | MVP |
| 79 | Platform | Plans, trial and rewards | Free and Pro, 14-day trial on first Pro use, founding price, rewards for real use, one-tap cancel | MVP |
| 80 | Style AI | Trend studio and style rulebook | Stylist-approved weekly trend cards and a versioned rulebook that keep dro current | v1.1 |
| 81 | Admin | Admin panel | Roles, audit log, users, moderation, Swap disputes, AI costs, taxonomy, festivals, broadcasts, flags | MVP |
| 82 | Capture | Outfits from your photos | Finds photos of the user wearing clothes, extracts each garment, merges repeats into one item (with wear history from photo dates) and categorises them; user confirms | v1.1 |
| 83 | Outfits | Outfit builder | Pick items by category into a flat-lay collage; save as a look or to a moodboard (work, wedding, trip) | MVP |
| 84 | Outfits | Try it on (AI avatar) | Generates an image of the user wearing the chosen outfit from their own reference photo; opt-in, labelled as AI, deletable | v1.1 |
| 85 | Outfits | Recreate a look | Share or upload any outfit photo (Instagram, Pinterest, a screenshot, a friend's post); dro finds the same or closest pieces you own, shows how much of the look you can recreate, and suggests swaps or friends to borrow from for what's missing, never pushing a purchase | MVP |

## 6. Personalisation and smart suggestions

dro earns the daily open by combining a few signals into one useful, well-timed suggestion, and by staying quiet the rest of the time.

**Signals dro uses**

| Signal | Source | Example use |
| --- | --- | --- |
| Weather | Weather API by current city | "Sunny today, light layers work" |
| Calendar | Phone calendar (opt-in) | "Riya's party · 8 pm": office-to-party fit |
| Item state | Catalog | Only suggest clean items in the current home |
| Wear history | Logged outfits | Rotate least-worn items, avoid repeats with the same group |
| Location | Home and storage per item | "Your winter jacket is in Indore, you're in Bangalore" |
| Dates | Purchase, opened, lent, dropped at dhobi or tailor | Expiry, return and pickup reminders |
| Style feedback | Thumbs up/down on picks, saved looks | Learns colours, fits and combos the user likes |
| Occasions and festivals | Calendar + regional festival calendar | Navratri colour of the day, wedding function plans |

**The morning brief (default 8 am, user can change):** weather line, events today, one outfit pick hung on "today's rail" with two alternates, and at most two nudges.

**Nudges and reminders**

- Laundry and dhobi pickup: "Your sangeet kurta is at the press-wala. Pick up by Friday?"
- Ironing and prep: evening before an event.
- Expiry: 30 and 7 days before; "use it up first".
- Lent items: return reminder to the borrower and the owner.
- Before you buy: when a shopping link is shared.
- Trip: packing list 2 days before travel in the calendar.

**Rules:** at most 2 nudges on screen and 1 push notification a day unless the user asks for more; quiet hours respected; every nudge has a one-tap action and a "not useful" option that teaches dro. Fit and body topics are opt-in only and never framed around weight.

## 6b. Style intelligence that keeps evolving

dro's fashion sense is never frozen: it combines a stable rulebook of fashion principles, a trend layer refreshed every week, and each user's own taste, all updated without retraining the AI model.

| Layer | What it holds | How often it updates | Where it comes from |
| --- | --- | --- | --- |
| Fashion principles | Colour theory (neutrals, complementary, tonal), proportion and silhouette, fabric and season, occasion dress codes, Indian wear pairing (kurta lengths, dupattas, juttis, jhumkas), kind fit guidance | Reviewed every quarter | Written with stylists; versioned "style rulebook" |
| Trends | What's in this season by region and age: colours, silhouettes, prints, aesthetics, festival looks | Every week | Licensed trend reports and data partners, public search-interest tools, retail new-arrival feeds through partnerships, and anonymised in-app signals (rising combinations, most-saved looks) |
| Personal taste | Each user's likes and skips, outfits worn, saved looks, colours they reach for, opt-in fit preferences | Continuously | The user's own activity |

**How dro uses it:** when dro suggests an outfit or answers a question, it pulls the relevant principles, the current trend cards and the user's taste profile into its reasoning (retrieval at answer time). The morning pick's rules engine also takes trend weights, for example giving a small boost to a trending colour the user already owns.

**Why not retrain the AI model:** retrieval is cheaper, updates the same day, is easy to audit, and works with any AI model. When a newer, better model is released we switch through the AI provider module, but only after it passes our evaluation set of stylist-rated outfits.

**Guardrails**

- **Trends suggest, never pressure.** Trend tips are built from what the user already owns ("make it trendy with your mustard kurta"), never "buy this".
- **Human review.** A stylist approves each trend card in the admin panel before it goes live; cards expire after 8 weeks unless renewed.
- **Respect.** No stereotyping by gender, body or region; users can set modesty and comfort preferences that always win over trends.
- **Privacy.** In-app signals are used only in aggregate, never below a minimum group size of 50 users, and users can opt out.
- **Clean data.** Only licensed or permitted sources; no scraping platforms against their terms.
- **Measured.** Each trend card tracks acceptance, saves and "not my style" taps; poor performers retire automatically.

**What users see:** a weekly "trending with what you own" card, a "make it trendy" button on any look, festival trend packs (for example Navratri colours of the year), and "your style this year" in drobie Wrapped.

**Admin tools needed:** a Trend studio (create, schedule and retire trend cards by region and season), a Style rulebook editor with version history, and an evaluation dashboard for AI model changes.

## 6c. Smart suggestions, smart sections, filters and AI search

Every screen should answer "what's useful right now?" without being asked. This section lists every smart suggestion, auto-built section, filter and search capability so none are missed.

**Smart suggestions catalogue**

| # | Trigger | What dro says | One-tap action | Where it appears |
| --- | --- | --- | --- | --- |
| 1 | New item saved | "These jeans go with 6 things you own. Want a look?" | Show looks | Closet, after save |
| 2 | Item not worn in 45+ days | "Your green kurta misses you. Wear it Friday?" | Add to plan | Today |
| 3 | Weather change tomorrow | "Rain tomorrow: suede loafers stay home, sneakers instead" | Swap piece | Evening before |
| 4 | Event in calendar | "Riya's party at 8: an office-to-party fit" | See look | Today tags |
| 5 | Same outfit, same people | "You wore this to Riya's last party" | Swap one piece | While planning |
| 6 | Gap in the wardrobe | "Lots of neutrals, no bold tops. Borrow one for Saturday?" | Find in circles | Insights |
| 7 | Trend match | "Butter yellow is trending and you own 2 pieces" | Make it trendy | Weekly card |
| 8 | Trip in calendar | "These 12 items make 20 outfits for Goa" | Packing list | 2 days before |
| 9 | At dhobi or press 3+ days | "Your sangeet kurta is still at the press-wala" | Mark collected | Today |
| 10 | Event tomorrow | "Iron the blue shirt tonight?" | Set reminder | Evening before |
| 11 | Tailor deadline near | "Pick up the lehenga by Thursday" | Done / remind later | Today |
| 12 | Favourites in the wash | "5 favourites are in the wash, tomorrow's pick avoids them" | See pick | Today |
| 13 | Same item searched often | "You looked for your black jeans 3 times. Pin them?" | Pin | Search |
| 14 | Shopping link shared | "Psst, you already own a 92% match" | Skip / borrow / buy | Before you buy sheet |
| 15 | Cost-per-wear milestone | "Down to ₹142 a wear. 3 more wears halves it" | See stats | Item page |
| 16 | Not worn in 12 months | "Lend it, sell it or donate it?" | List on Swap | Monthly tidy-up |
| 17 | Beauty product expiring (30 and 7 days) | "Sunscreen expires in 3 weeks. Use it first?" | Move to front | Today, Beauty shelf |
| 18 | Several opened of the same product | "3 sunscreens open: finish the oldest first" | Mark order | Beauty shelf |
| 19 | Friend looking for something you own | "Ananya is looking for a lehenga like yours" | Offer to lend | Swap |
| 20 | Festival approaching | "Navratri in 10 days: 7 of 9 colours ready; 2 friends have yellow" | Plan 9 looks | Plan, Today |
| 21 | Lent item due back | "Priya returns your lehenga tomorrow" | Remind Priya | Today |
| 22 | Fit check (opt-in only) | "These 4 might feel snug. Move to a 'later' shelf?" | Move | Monthly |
| 23 | Morning, every day | Today's rail outfit with 2 alternates | Wear this | Today |
| 24 | Monthly | drobie Wrapped: most worn, forgotten gems, cost-per-wear champion | Share | Monthly |

**Smart suggestions added in v0.2**

| # | Trigger | What dro says | One-tap action | Where it appears |
| --- | --- | --- | --- | --- |
| 25 | Scan mode finished | "9 things in 3 minutes. Your leather jacket goes with 5 of them" | See looks | Scan summary |
| 26 | Scanned item already in the closet | "Already in your closet, skipped" | It's new | Scan mode |
| 27 | Two items in one photo | "Spotted a black belt too. Save it as its own item?" | Save both | Add item |
| 28 | Crumpled item photographed | "Looks a bit crumpled. Add it to the ironing pile?" | Yes | Add item |
| 29 | Blurry or cut-off photo | "Bit blurry and the legs are cut off. One more try?" | Retake | Add item |
| 30 | Skincare or makeup added | "This is skincare. Track when it expires?" | Opened today | Add item |
| 31 | Link import similar to an owned item | "Similar to your navy polo. Still add?" | See it | Add from link |
| 32 | Accessory never paired with an item | "Your leather watch hasn't met your blazer yet. Power move for Monday?" | Try | Accessories |
| 33 | Several active serums | "3 serums with actives. Niacinamide AM, retinol PM?" | Set routine | Beauty shelf |
| 34 | Return window closing | "Return window closes in 2 days. Still keeping these jeans?" | Keep / return | Today |
| 35 | A look rated "loved it" | "You loved this one. Save it as a look?" | Save look | After rating |
| 36 | Picks skipped repeatedly | "You skipped heels 3 times this week. Fewer heels for now?" | Adjust | Today |
| 37 | Friend posts a look you can recreate | "You can recreate this with your white tee, jeans and sneakers" | Try it | Friends feed |
| 38 | Friend needs a colour for an event | "Priya needs yellow for Day 2. Meera has one free" | Connect | Event room |
| 39 | Borrow request on a day you planned to wear it | "You planned to wear it Saturday. Lend from Sunday?" | Suggest dates | Swap request |
| 40 | Group trip outfit plan | "All-white Saturday is covered. Lend your shirt to Dev?" | Lend | Group chat |
| 41 | Streak needs today's fit | "Post today's fit to keep the streak. I picked your blue henley" | Post | Challenge |
| 42 | Closet level reached | "25 items! Week planner unlocked" | Try it | Today |
| 43 | Sunday evening | "Your week is planned: 5 days, 0 repeats" | Accept | Today, Plan |
| 44 | Trip ended, items still packed | "Back from Goa? 9 things are still marked packed" | Unpack | Today |
| 45 | Inspiration photo shared or uploaded | "You can recreate 80% of this with your blazer, white tee and grey jeans. Ananya has the loafers" | See my version | Share sheet, dro chat |

The same rules apply to these: a relevance score, at most 2 on screen and 1 push a day, a 7-day cool-down, and "not useful" on every card.

**Rules for suggestions:** each one gets a relevance score (urgency, usefulness, the user's past response); at most 2 on screen and 1 push a day; a cool-down so the same tip never repeats within a week; every card has "not useful", which lowers that type for that user. Suggestions never push buying new things.

**Smart sections (auto-built collections in the Closet)**

- Ready to wear: clean, in the current home, right for today's weather
- Not worn in 60 days
- Most worn and cost-per-wear champions
- In the wash, at dhobi or press, at tailor
- Lent out and borrowed
- Goes with: (any item the user picks)
- Trending in your closet
- Festive and ethnic ready
- Travel capsule
- New this month
- Near-duplicates
- Beauty: expiring soon, opened, unopened

**Filters and sorting**

| Filter group | Options |
| --- | --- |
| What | Category and sub-category, colour (shade families: "all blues"), pattern, fabric, brand, size |
| When | Season, occasion and vibe, last worn (range), purchase date |
| Where and status | Home, room, storage spot, state (clean, worn, wash, dhobi, tailor, lent, packed), shared to circle or listed on Swap |
| Usage and money | Times worn, cost per wear, price range |
| Tags | Your own tags, AI-guessed vs confirmed tags |
| Sort by | Recently added, most worn, least worn, last worn, cost per wear, colour (rainbow order), price |

Filters combine, are saved as custom smart sections with one tap, and show result counts before applying.

**AI search: what people can type or say**

| Criteria | Example |
| --- | --- |
| Colour and shade words | "maroon tops", "anything olive" |
| Type, pattern, fabric, brand, size | "floral cotton kurtas", "my Zara jeans" |
| Occasion and vibe | "something for a sangeet", "office but comfy" |
| Availability | "clean jeans", "what's not at the dhobi" |
| Place | "what's in my Indore almirah", "what's packed" |
| Time | "haven't worn this month", "bought last Diwali" |
| Usage and price | "worn less than 3 times", "over ₹2,000" |
| Relations | "goes with my brown shirt", "similar to this photo" |
| People | "lent to Priya", "borrowed from Ananya" |
| Negation | "tops, not black" |
| Visual search | Search with a photo or screenshot |
| Languages | Typos and Hinglish ("kala kurta" finds black kurtas); Hindi later |

**How AI search works:** dro turns the question into structured filters plus a similarity search, shows the understood filters as editable chips ("colour: maroon · type: tops · state: clean"), and ranks exact matches first, then visually similar items, then recent ones. Zero results always offer a next step: loosen a filter, check circles, or add the item. Simple searches run as database queries without calling the AI model, so they are instant and free.

## 7. Photo capture and image processing

Every item shows a real photograph of the user's own piece, cleaned up automatically, so the closet looks like a beautiful store shelf without any editing work.

**Capture requirements**

- Guided camera: live outline and tips ("lay it flat", "more light"), shutter auto-fires when the item is steady and in frame.
- Adding one item takes under 10 seconds from camera open to saved.
- Inputs: camera, gallery (batch select up to 50), screenshots, store links, email receipts.
- Original photo always kept; the cleaned version is shown by default and the user can switch back.

**Automatic processing (on every photo)**

1. Background removal and subject cut-out.
2. Auto-adjust: exposure, white balance and shadows so colours look true; auto-crop, straighten and centre.
3. Consistent display: same soft backdrop, size and padding for every item in the grid.
4. Colour extraction: dominant and secondary colours as named shades (for matching and "same shade" checks).
5. Auto-tagging on the phone: category, sub-type, colour, pattern, fabric hints, season, occasion, and brand from tags or order emails; the cloud is asked only when the phone is unsure.
6. Duplicate check: warns if the same item already exists.
7. User confirms or edits tags in one screen; corrections improve future tagging.

**Later capture modes:** multi-item photo split, wardrobe video scan, and "wear it" mirror photos that log outfits.

**Quality bar:** processing finishes in under 3 seconds on mid-range Android phones; colour shift after auto-adjust is small enough that users trust the "same shade" check.

**Real photos, never fake ones.** Every item with a photo shows the user's own photo: cut out, placed on the theme backdrop, centred at about 85% of a 4:5 tile (1:1 for beauty and accessories) with a soft contact shadow. Line icons appear only as placeholders while a photo processes or when an item has no photo.

**Messy photos (folded, wrinkled, half-visible)**

- Tagging works on folded or wrinkled items; cleanup (cut-out, straighten, light and colour) runs on every photo.
- If the item is recognisable, drobie offers the store's product photo: "Found the store photo for this exact item. Use it?"
- If too little is visible, dro asks gently for one more shot, or picks the best frame from a short video.
- **Tidy view (later, Pro):** an AI-generated neat, flat version, clearly labelled "AI-tidied" and shown only after the user approves it. The real photo stays the source of truth for colour matching, search and duplicate checks, because generated images can invent details (prints, necklines, lengths) that the item does not have.

**Smart expiry detection**

1. When an item is added, its category tells drobie whether it can expire (skincare, makeup, sunscreen, perfume, hair care, nail polish, lens solution). Clothes and shoes are never asked.
2. On-device text reading looks for a printed expiry date, a manufacture date or the open-jar PAO symbol ("12M") and pre-fills what it finds for one-tap confirmation.
3. If nothing is found, dro asks, never forces: "This looks like sunscreen. Want me to track when it expires?" with Opened today · Not opened yet · Add date · Skip. "Opened today" suggests a typical shelf life for that product type, clearly marked as an estimate the user can change.
4. Reminders follow at 30 and 7 days, plus "finish the oldest first" for duplicates.
5. The same detection reads **return windows and warranties** from purchase receipts: "Your return window closes in 2 days. Still keeping these jeans?"

## 7b. Key user journeys: smart, fast, never boring

Every journey has a tap and time budget, and drobie fills in everything it can guess so the user only confirms.

**Design rules for every input**

- Never ask what can be inferred: category, colour, brand, size, season, location and dates are pre-filled from the photo, label, last-used spot or calendar.
- One-tap confirm, with undo instead of "Are you sure?" dialogs.
- Voice and text work everywhere through dro ("dropped 6 things at the press-wala").
- Batch actions: select many items and change state, location or circle at once.
- Learn from every correction, so the same question is never asked twice.
- Show results instantly (optimistic updates); slow AI work finishes in the background.
- No empty screens: every screen offers the next useful action.

| # | Journey | How drobie makes it smart | Taps | Time target |
| --- | --- | --- | --- | --- |
| 1 | First open to first value | Sign in with phone or Google, 2 quick choices (city, style vibe), pick 10 photos from the gallery; dro shows a first outfit from them | 6–8 | Under 2 min |
| 2 | Add one item | Camera auto-shoots when steady; cut-out, adjust and tags done; location pre-filled with last spot; tap Save | 2 | Under 10 s |
| 3 | Add many items | Multi-select from gallery or one pile photo; all processed in the background; review grid with one-tap fixes | 3 + fixes | Under 1 min for 20 |
| 4 | Get dressed in the morning | Push at the user's chosen time; outfit already on today's rail; tap "Wear this" and items move to worn | 1 | Under 5 s |
| 5 | Find an item | "hey dro, where's my black jeans?" by voice or text; answer with photo and exact spot | 1 | Under 2 s answer |
| 6 | Laundry, dhobi, tailor | Say or select what went; dro sets the state and a pickup reminder with a smart default day | 2 | Under 10 s |
| 7 | Before you buy | Share a link from any shopping app; drobie opens a sheet with matches you own | 1 (share) | Under 3 s |
| 8 | Add a cosmetic | Scan barcode; product fills in; "opened today?" defaults to yes; PAO read from the pack | 3 | Under 15 s |
| 9 | Plan an occasion | "Plan my Garba week"; dro proposes 9 looks by colour of the day; accept all or swap one; ironing and pickup reminders auto-added | 2–4 | Under 1 min |
| 10 | Lend or swap | From the item page tap Lend; dates you're wearing it are already blocked; choose circles; publish | 3 | Under 20 s |
| 11 | Pack for a trip | Trip detected from calendar; packing list from clean items; tick off as you pack | 1 to open | Under 30 s |

## 7c. Daily habit design: why people open drobie every day

Goal: drobie becomes part of getting dressed, like checking the weather. People come back because it saves time and makes them feel good, not because they are nagged or tricked. Every feature below must pass one test: would the user miss it if it were gone tomorrow?

### The daily loop

| Time | Trigger | What the user does | What they get back |
| --- | --- | --- | --- |
| Morning (user's chosen time) | One push or widget: today's rail is ready | 1 tap: Wear this, or swap one piece | Dressed in under 5 s; items move to worn |
| Daytime (as needed) | A question, a shopping link, a friend's post | Ask dro, check Before you buy, react to a fit | An answer in 2 s, money saved, a social moment |
| Evening | Quiet card, no push unless something is due | Rate today's look, see tomorrow's weather swap, tick laundry | dro learns taste; tomorrow is already sorted |
| Weekly | Sunday "week ahead" card | Accept the 5-day plan | No repeats, laundry-aware, events covered |
| Monthly | drobie Wrapped | Share it | Pride, a reason to post, new friends join |

### Hooks that come from real value

- **The closet gets smarter the more it is used.** Every wear, rating and swap makes picks better, so the app is visibly more useful in week 4 than week 1 ("dro now knows you prefer relaxed fits"). This is the main reason to stay: leaving means starting over.
- **Something new every day.** A rotating surprise slot on Today: a forgotten gem ("not worn since July"), a new combo nobody has suggested yet, "make it trendy" with what you own, a friend's look you can recreate. Never the same card twice in a week.
- **Progress you can see.** Closet completeness ("64 of \~90 items added"), cost-per-wear dropping, rewear streaks, money saved by Before you buy, wardrobe "levels" that unlock new dro powers (week planner at 25 items, trip packer at 50).
- **Streaks that are kind.** A rewear or "logged my fit" streak with 2 free freeze days a week, no loss-shaming copy, and streaks paused automatically when travelling or ill if the user says so.
- **Friends make it social.** Daily fit stories, Help me decide polls, Swap requests, event rooms and group chats with dro. A friend borrowing your lehenga is a reason to open the app that no reminder can match.
- **Real-life reminders people need.** Dhobi pickups, tailor deadlines, expiring sunscreen, return windows, lent items. These are useful nudges, not engagement bait.
- **dro has personality.** Hype bestie, honest stylist, minimal or desi mode; playful loading moments, witty but kind replies, festival-aware content (Navratri colours, wedding season). Fun to talk to, so people talk to it.
- **Always within one tap.** Home-screen and lock-screen widgets showing today's rail, a "hey dro" shortcut, and share-sheet Before you buy, so drobie is present without opening the app.
- **Seasonal moments.** Festival packs, wedding season, monsoon mode, back-to-college capsule, New Year closet reset. Fresh reasons to come back several times a year.

### Every journey must end with a reason to return

| Journey | Ends with |
| --- | --- |
| Onboarding | First outfit plus "add 10 more and I'll plan your week" |
| Add or scan items | "Goes with 6 things you own, see the looks?" |
| Get dressed | "Rate today's look" plus tomorrow's preview |
| Find an item | Offer to pin it, or "wear it this week?" |
| Laundry, dhobi, tailor | Pickup reminder set with a smart default day |
| Before you buy | Money saved counter plus "wear yours this week instead?" |
| Beauty | Expiry tracked; "use it first" on the shelf |
| Plan, Navratri, trip | Daily countdown and prep tasks until the day |
| Swap and friends | Return date, rating, and "what else can you borrow?" |
| Wrapped | Shareable card plus next month's goal |

### Retention targets

- Day 1 retention 55%+, day 7 35%+, day 30 22%+ (strong for a lifestyle app).
- Daily active / monthly active (stickiness) 35%+.
- 60%+ of daily users act on the morning pick within 10 minutes.
- Tracked per cohort in PostHog; every new feature ships with the retention metric it should move.

### Guardrails: habit, not addiction

- No dark patterns: no fake urgency, no infinite feeds, no guilt messages, no hiding the off switch.
- At most 1 push a day by default, quiet hours respected, every nudge has "not useful" and a pause-for-a-week option.
- Session design is short on purpose: the best day is one where drobie took 30 seconds and the user felt good.
- Never push buying; the promise stays "wear what you own".
- Wellbeing check: if usage spikes in unhealthy ways (for example body or fit topics), dro softens and points to the opt-out.
- Kids and under-18 users get no streaks, no public feed and no Swap.

## 7d. Use cases

49 use cases cover everything a user or admin does in drobie; each maps to features in section 5 and requirements in the FRS.

| ID | Area | Use case | Actor | Trigger | Main flow | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| UC-01 | Start | Discover and sign up | New user | Installs the app | Welcome (sample photos) → Google, Apple or email → city and vibe | Account in under 1 minute |
| UC-02 | Start | First closet from gallery | New user | Finishes sign-up | Allows photos → dro shows clothing photos → picks 10 → processing | First outfit within 2 minutes |
| UC-03 | Start | Claim founding offer or referral | New user | Joins early or via a friend's link | Badge and 3 months Pro; referral reward after 25 items | Pro unlocked, friend rewarded |
| UC-04 | Add | Add one item by camera | User | Buys or finds an item | Auto-snap → instant full photo → labels read → confirm place → Save | Saved in 2 taps, under 10 s |
| UC-05 | Add | Scan a whole wardrobe | User | Wants to catch up fast | Scan mode → hold each item 2 s → tray fills → review grid by category | 20+ items in a few minutes |
| UC-06 | Add | Add many from gallery | User | Has old photos | Multi-select up to 50 → background processing → fix flagged items | 20 items in about 1 minute |
| UC-07 | Add | Add from a store link | User | Bought online | Paste or share link → store photo and details filled → Add | Item saved with price and date |
| UC-08 | Add | Add a beauty product | User | New sunscreen | Beauty mode → barcode or pack read → "opened today?" | Expiry tracked |
| UC-09 | Add | Import from receipts | User | Online order email | Forwards receipt → items extracted → confirm | Items with price and return window |
| UC-10 | Add | Fix a messy photo | User | Blurry, folded or cut-off photo | dro asks for a retake or offers the store photo | Clean, usable tile |
| UC-11 | Daily | Get dressed in the morning | User | Morning push or widget | Open → today's rail → Wear this or swap one piece | Dressed in under 5 s |
| UC-12 | Daily | Prepare for tomorrow | User | Evening card | Sees rain swap, ironing reminder → accepts | Tomorrow sorted |
| UC-13 | Daily | Rate today's look | User | After wearing | Loved it / fine / not me | Better picks over time |
| UC-14 | Daily | Get a surprise idea | User | Opens Today | Forgotten gem or new combo card → add to plan | Wears something neglected |
| UC-15 | Find | Find an item | User | Can't find it | "Where's my black jeans?" by voice or text | Photo and exact spot in under 2 s |
| UC-16 | Find | Browse by category or smart section | User | Wants an overview | Categories or pinned sections → item | Finds options quickly |
| UC-17 | Find | Search in plain words | User | Specific need | "Red stuff, clean, for match day" → editable chips → results | Exact matches first |
| UC-18 | Find | Filter and save a section | User | Recurring need | Filters → count → Save as section ("Office Mondays") | Section updates itself |
| UC-19 | Care | Send clothes to the dhobi | User | Drops clothes | Bulk select or say it → state set → pickup reminder | Never forgets a pickup |
| UC-20 | Care | Track tailor work | User | Alteration | Mark at tailor → due date reminder | Collected on time |
| UC-21 | Care | Manage laundry | User | Washing day | Care hub → Mark clean for a group | Accurate clean list for picks |
| UC-22 | dro | Ask dro for an outfit | User | Event or mood | Asks → thinking animation with real reasons → lookbook cards | Wears or saves a look |
| UC-23 | dro | Tell dro what happened | User | Life update | "Dropped 6 things at the press-wala" → dro updates and sets reminder | Closet stays accurate with no forms |
| UC-24 | dro | Rate my fit | User | Before going out | Photo → scores and upgrades from owned items | Confident and polished |
| UC-25 | dro | Plan my week | User | Sunday | One request → 5-day plan, no repeats | Week sorted |
| UC-26 | dro | This or that | User | Torn between two | Compare → recommendation with reasons and accessories | Decision in seconds |
| UC-27 | dro | Choose dro's personality | User | Settings or chat | Hype bestie, honest stylist, minimal, desi | dro feels personal |
| UC-28 | Money | Check before buying | User | Shopping app | Share link → match sheet → Skip, Borrow or Buy | Duplicate avoided, money saved |
| UC-29 | Money | Review cost per wear and insights | User | Curiosity | Insights → champions, gaps, colour mix | Smarter wearing and buying |
| UC-30 | Money | Monthly tidy-up | User | Monthly card | Keep, lend, sell or donate unworn items | Lighter closet |
| UC-31 | Beauty | Use products before expiry | User | 30- and 7-day reminder | "Use it first" → moved to front | Less waste |
| UC-32 | Plan | Plan a festival | User | Navratri approaching | 9-colour planner → ready, borrow or missing per day | Every night covered |
| UC-33 | Plan | Plan a wedding | User | Invitation | Functions → looks, repeat check, prep tasks | No repeats, no last-minute rush |
| UC-34 | Plan | Pack for a trip | User | Trip in calendar | Packing list from clean items → tick as packed | Packed in 30 s, unpacked after |
| UC-35 | Friends | Add friends and build circles | User | Wants to share | Contacts, QR or WhatsApp → circles with chosen sharing | Private network ready |
| UC-36 | Friends | Post a fit and react | User | Likes today's look | Post to circles → friends react or recreate | Social reason to open daily |
| UC-37 | Friends | Ask friends to decide | User | Unsure | Poll with 2–3 looks → votes | Quick consensus |
| UC-38 | Friends | Join a challenge | User | Community tab | Join #30DayRewear → daily fit → streak | Rewears more, buys less |
| UC-39 | Friends | Coordinate an event | Group | Garba night or wedding | Event room → colour plan → who needs to borrow | Group looks sorted |
| UC-40 | Swap | Lend an item | Lender | Friend asks or item idle | Lend → dates (own wear days blocked) → circles → publish | Listing live in 20 s |
| UC-41 | Swap | Borrow an item | Borrower | Needs an outfit | Request dates → lender sees trust details → accept | Booking confirmed |
| UC-42 | Swap | Hand over and return | Both | Booking day | Condition photos at handover and return → ratings | Trust built, disputes avoidable |
| UC-43 | Account | Upgrade to Pro | User | Hits a Pro feature | Trial starts → choose plan → Play Billing | Pro active; cancel in one tap |
| UC-44 | Account | Control notifications and privacy | User | Settings | Push count, quiet hours, consents, export, delete | User in control |
| UC-45 | Admin | Moderate reports and disputes | Moderator | New report | Review evidence → action → parties notified | Safe community |
| UC-46 | Admin | Publish trend cards | Stylist | Weekly | Create → approve → schedule by region | dro's style stays current |
| UC-47 | Admin | Watch costs and limits | Admin | Daily | AI cost dashboard → adjust limits or flags | Costs stay on budget |
| UC-48 | Admin | Help a user | Support | Support ticket | User approves a time-limited grant → support views items | Issue solved without breaching privacy |
| UC-49 | dro | Recreate a look from any photo | User | Sees an outfit on Instagram, Pinterest or a friend's post | Share or upload the photo → dro finds each piece → closest owned matches and a match % → swap pieces or ask a friend for missing ones → save or wear | The look recreated from their own closet, no purchase needed |

## 8. Scanning and identification: recommended tools

Recommendation: do the fast, private steps on the phone with free platform SDKs, send the cleaned image to a cloud AI for tagging, and own the "similar items" search ourselves with an open fashion embedding model. That keeps costs low and the core matching logic ours.

| Job | Recommended tool | Build or buy | Why |
| --- | --- | --- | --- |
| Background cut-out (Android) | [Google ML Kit Subject Segmentation](https://developers.google.com/ml-kit/vision/subject-segmentation/android) | Platform SDK | Returns a foreground mask and bitmap, can return each subject separately (useful for multi-item photos); adds about 200 KB; still in beta |
| Background cut-out (iPhone) | [Apple Vision foreground instance mask](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest) | Platform SDK | Separates noticeable objects from the background on-device (the "lift subject" feature) |
| Auto-adjust (light, colour, crop) | On-device image filters (Android and iOS core imaging) | Build | Simple, fast, no per-photo cost |
| Clothes tagging (category, colour, pattern, material) | In-house: our own on-device classifier (category), colour clustering (colour), simple pattern measures, order-email and label data (brand, size, fabric). Paid benchmark and fallback only: [Ximilar Fashion Tagging](https://www.ximilar.com/faq/fashion-tagging-faq) or a multimodal AI model (for example Claude) for items the phone is unsure about | Build; paid fallback | Target: 90% of items tagged with no paid call. We train our own model on Fashionpedia (CC BY 4.0) and photos users agree to share (retailer product photos are not used for training without legal clearance); we measure it against a paid model on 500 real Indian wardrobe photos and use the paid one only below a confidence threshold |
| "Similar / same shade" matching (Before you buy, duplicates, pairing) | [Marqo-FashionSigLIP](https://github.com/marqo-ai/marqo-FashionCLIP) embeddings + our colour data | Build on open model | Fashion-tuned image and text embeddings (Apache-2.0 repo), outperform FashionCLIP 2.0 on the repo's benchmarks; lets us search "items like this" across a user's closet and store photos |
| Tag and care-label reading | On-device text recognition (ML Kit / Apple Vision) + a small on-device model for the \~40 standard wash-care symbols | Platform SDK + build | OCR reads brand, size, fabric %; care symbols are a small fixed set, so no paid AI is needed |
| Cosmetics barcode lookup | On-device barcode scanning + [Open Beauty Facts API](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/scanning-cosmetics-pet-food-and-other-products/) | Free open data | Barcode gives product name, brand and ingredients where the community has added it; coverage of Indian brands needs testing |
| Cosmetics expiry | OCR for printed expiry and the PAO symbol ("12M"), plus an "opened on" date the user taps | Build | No reliable public API decodes batch codes across brands; batch decoding is a later partnership |
| Order-history import | Forwarded order emails read by per-retailer templates (Myntra, Ajio, Amazon, Flipkart, Nykaa, H&M, Zara…); AI only for unknown formats; Gmail API later | Build | High value, but Gmail read scopes are restricted: [Google requires verification and a yearly third-party security assessment](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification). Plan for several weeks of review; start with forwarding receipts to a drobie email address as a simpler first version |
| Store link import | Product data built into the page (schema.org, Open Graph) + store photo; no AI | Build | Covers "paste a Myntra/Ajio/Zara link" and the share-sheet Before you buy |
| Weather | A weather API by city | Buy | Morning brief |
| Voice ("hey dro") | Platform speech-to-text in the app first; a true always-on wake word later | Platform SDK | Always-on listening drains battery and raises privacy concerns, so start with a tap-to-talk button |

**Next step:** a 2-week technical spike that runs 500 real photos (western and Indian wear, phone-quality light) through Options A and B and measures tag accuracy, colour accuracy, speed and cost per item.

### Point-and-scan mode (replaces wardrobe video scan)

The user opens Scan mode and pans slowly across a rail, shelf or bed. Each item held in view for about 2 seconds is spotted, captured and saved on its own; at the end a review grid shows everything already sorted into categories. No video is recorded or uploaded.

- **Spotting (free, on the phone):** Google ML Kit Object Detection & Tracking in stream mode (it has a built-in "fashion good" class) on Android, Apple Vision on iPhone, run on camera frames through react-native-vision-camera frame processors.
- **Capture (free, on the phone):** a tracked item that stays steady and sharp for \~2 s auto-captures its best frame, then on-device subject lift cuts it out. Haptic tick plus the item pops into a tray ("7 found").
- **No duplicates (free, on the phone):** the tracker ID stops the same item being captured twice in one sweep; a photo fingerprint and a quick similarity check skip items already in the closet ("already saved", with an "it's new" override).
- **First category (free, on the phone):** a small on-device image–text model and colour extraction give category and colour instantly, so the review grid is already grouped (Tops, Layers, Footwear, Accessories, Beauty).
- **Detailed tags (mostly free):** category, colour, pattern and duplicates are worked out on the phone; brand, size and fabric come from labels and order emails. Only items the phone is unsure about send one still to the cloud model, batched overnight at about ₹0.05–0.10 each.
- **Works best on** clothes on hangers, shoes on a rack, items laid on a bed, bags and beauty on a shelf. **Struggles with** tight folded stacks, hidden items and dark clothes in poor light, so items are always confirmed in the review grid, never added silently.
- **Target:** about one item per 2 seconds, a full rail in a few minutes. Prototype screens SC1–SC6.
- **Licences:** avoid Ultralytics YOLO (AGPL) and YOLO-World (GPL) in the app; if a server detector is needed later, use Apache or MIT models (Grounding DINO, OWLv2, Florence-2, SAM 2).

### Outfits from your photos, outfit builder and Try it on

Inspired by Google Photos' Wardrobe (announced April 2026): drobie reads the user's own photos of themselves, pulls out each garment as a clean item, lets them build outfits from those items, and shows the outfit on them with an AI image. It is also a third way to fill the closet, next to camera scan and gallery scan.

1. **Find photos of you (on the phone).** With permission, the phone finds photos with a person wearing visible clothes. The user picks themselves once (a selfie or a tap on their photos); matching runs on the phone and is opt-in.
2. **Extract each garment (cloud).** A clothing-parsing model outlines top, bottom, outerwear, shoes and accessories; each crop is cleaned into a product-style image by an image model.
3. **Merge repeats.** The same shirt seen in 12 photos becomes one item, using fashion embeddings and colour; photo dates become wear history, so cost per wear starts filled in.
4. **Categorise and confirm.** Items land in a review grid by category (outerwear, bottoms, footwear, accessories); the user keeps, merges or removes.
5. **Outfit builder.** Pick items per category; they arrange into a flat-lay collage; save as a look or to a moodboard (work, wedding, trip).
6. **Try it on.** The user adds 1–2 full-body reference photos once; drobie generates them wearing the chosen outfit. Results are labelled "AI preview", with Regenerate, thumbs up/down, Save and Share.

**Cost (approximate):** product-style clean-up about $0.04 per garment with a Gemini Flash-class image model; try-on about $0.05–0.075 per image with a try-on API such as FASHN (cheaper at volume). So extraction is a Pro or rewarded feature with monthly credits, and Try it on uses credits (for example 20 a month on Pro).

**Rules**

- AI-cleaned item images are labelled and the original photo crop is always kept; colour matching uses the original, not the AI image (BRD "Real photos, never fake ones").
- Only the user's own body is used for Try it on; never generate images of friends or other people from their photos.
- Reference photos and avatars are stored encrypted, used only for Try it on, never for training, and deletable in one tap; explicit consent under the DPDP Act.
- No body-shape comments, no slimming or editing of the user's body; under-18 users cannot use Try it on.
- Partly hidden garments are offered as "partial"; the user can replace them with a real photo later.

Sources (opened 8 Oct 2026): [ML Kit subject segmentation](https://developers.google.com/ml-kit/vision/subject-segmentation/android) · [Apple Vision](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest) · [Ximilar fashion tagging FAQ](https://www.ximilar.com/faq/fashion-tagging-faq) · [Marqo-FashionCLIP repo](https://github.com/marqo-ai/marqo-FashionCLIP) · [Open Beauty Facts scanning guide](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/scanning-cosmetics-pet-food-and-other-products/) · [Google restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)

## 9. Community and Swap

Community launches campus by campus, because a borrowing network only works when lenders and borrowers live close together.

**Circles:** private groups (family, best friends, flatmates, college). Users share chosen items or their whole closet per circle. Everything is private by default.

**Swap flow**

1. List an item: photo from the closet, condition, size, the days it is available (calendar), circles or radius it is visible to, optional deposit.
2. Request: a borrower picks dates; dro shows their trust details.
3. Accept or decline with one tap; both get a chat thread.
4. Handover: both take a condition photo in the app; the item's state becomes "lent".
5. Return: reminder the day before; return photo; both rate each other; state goes back to "clean" or "in the wash".

**Trust and safety requirements**

- Phone verification for all; college email or ID verification for campus circles.
- Ratings for lenders and borrowers; visible return history.
- Optional deposit held through the payment partner and released on return.
- Women-only circles option; suggested public meet-up spots; block and report on every profile.
- Damage and dispute process with condition photos as evidence.
- No sharing of exact home address; distance shown in rounded kilometres.

**Social features (later):** Help me decide polls, event rooms for weddings and Garba nights, a rewear feed that celebrates repeat wear, challenges, and stylists who build looks from a user's own closet.

**Paid smart tools to add once there is capital**

| Upgrade | What it unlocks | Trigger to add it |
| --- | --- | --- |
| Gmail auto-import | Purchases added automatically | Forwarding import is popular and revenue covers the yearly assessment |
| Higher-accuracy fashion tagging (if the spike shows a gap) | Better tags on tricky items | Users correct tags often |
| Wardrobe video scan | Whole closet in one pass | Onboarding drop-off stays high |
| Larger AI model for styling | Richer outfit advice | Pro users ask for it |
| "Hey dro" hands-free wake word | Truly hands-free | Voice use is high |
| Hindi and more languages | Wider India reach | After the first city works |
| Brand partnerships for purchase import | Purchases sync from stores | drobie has enough users to negotiate |

## 10d. Cost efficiency (business rules)

Costs fall into three buckets, and the biggest is the app store fee, not servers or AI; these rules apply from day one and are built per SRS section 10 (CE-01 to CE-48) and FRS section 7.

**1. App store and payment fees (biggest bucket: about ₹2.4 lakh a month at 1 lakh users)**

| Rule | Saving |
| --- | --- |
| Join Apple's Small Business Program and Google Play's 15% tier on day one | Keeps the fee at 15% instead of 30% |
| Sell on drobie.app through Razorpay (\~2% fee); all marketing, emails, gifts and founding offers point there | About ₹70,000 a month at 1 lakh users if 35% buy on the web |
| Web prices slightly lower (Pro ₹369, Ultimate dro ₹549 a month) plus a web bonus (+1 month on yearly, +10% images on packs) | Pushes web sales toward 40–50% |
| The iOS app never mentions web prices or links (store rules); Android may add Google's alternative billing later | Avoids app rejection |
| GST registration early to claim input credit on cloud, AI and tool bills | About 15% off most running costs |

**2. AI chat and tagging (about ₹25 per Pro and ₹40 per Ultimate user a month today; target 40–50% lower)**

- Rules before AI: morning pick, "where is my…", filters, reminders and duplicate checks run as plain code and database lookups.
- Cheapest model by default (Claude Haiku); a bigger model only when the small one isn't confident.
- Prompt caching: dro's fixed instructions and style rules are reused, so repeated parts cost about 90% less.
- Send only what's needed: the 20 relevant items, not the whole closet.
- Tagging happens on the phone; the few items it is unsure about are batched overnight at about 50% off.
- First pass on the phone: category, colour and "is this clothing" detected on-device for free.
- Cache common answers for the same closet; short answers by default with "tell me more".

**3. Image generation (Studio)**

- One multi-item image call per look (about ₹3.5) by default; FASHN only for "make it exact" on 1–2 main garments.
- Never generate the same outfit twice; standard quality first, HD only on save.
- First regenerate free, then 1 credit; 5 free looks only after 30 items.

**4. Free users and servers**

| Rule | Saving |
| --- | --- |
| Keep Free mostly AI-free: on-device tagging, 5 dro chats a day, rules-based daily pick | Free-user cost from \~₹1.20 to \~₹0.70 a month |
| Photos as compressed WebP (\~1,600 px) with small thumbnails for grids | 60–70% less storage and bandwidth |
| Cloudflare R2 for photos (no download fees) behind a CDN | Bandwidth almost free |
| Accounts inactive 6+ months move to cold storage, with notice | Storage stops growing for people who left |
| Matching server shuts down when idle | Pay only for use |
| Free tiers until outgrown (Supabase, Expo EAS, PostHog, Sentry, Resend) plus startup cloud and AI credits | About ₹0 fixed cost up to \~1,000 users |

**Result:** profit per month rises about 20–25% at the same prices (about ₹1.65 lakh instead of ₹1.3 lakh at 10,000 users). AI and storage cost per user is tracked daily in the admin panel, with alerts when a target is crossed.

## 10e. Subscription boosters

Eight additions, each built to give a clear, personal reason to pay; personal colour analysis is the lead feature for launch.

| # | Feature | What it does | Why it sells | Plan | Cost to us | Phase |
| --- | --- | --- | --- | --- | --- | --- |
| 86 | **Personal colour analysis** | A daylight selfie gives the user's colour season, best colours and colours to avoid; every closet item gets a "suits you" score; Before you buy uses it | Huge online trend; in-person analysis costs ₹3,000–10,000; instant "aha" on day one | Free: season + 3 colours. Pro: full palette, closet scores, avoid list | ₹0 (computed on the phone with face landmarks and colour rules) | MVP |
| 87 | **Repeat radar** | Remembers which outfit was worn to which event and with which friends or groups; warns before a repeat in front of the same people | Solves "did I already wear or post this?" | Pro; Ultimate adds full photo and Instagram history | Database only | v1.1 |
| 88 | **Instagram history import** | Builds wear history from the user's own posts (Instagram data download for personal accounts; Instagram API for creator and business accounts) | Fills repeat radar and outfits-from-photos instantly | Pro (last 12 months), Ultimate (all) | ₹0 for most photos (on-phone detection); cloud only when unsure | v1.1 |
| 89 | **dro on WhatsApp** | Morning pick, "hey dro" questions, reminders and the Sunday plan on WhatsApp | Keeps the daily habit without opening the app | Ultimate only | ₹5–15 per Ultimate user a month (capped) | v1.2 |
| 90 | **Shaadi and squad mode** | Group room for a wedding or event: theme per function, outfits from each member's closet, clash and duplicate warnings | Highest-spend season; one host brings 5–10 people | Ultimate hosts; guests join free | Low | v1.1, timed for Oct–Feb |
| 91 | **Sell what you don't wear** | Finds items unworn for 6+ months and writes a ready listing (photos, title, price) for OLX, Instagram or thrift pages | "drobie paid for itself" proof | Pro | Low | v1.1 |
| 92 | **Monthly fit reel** | Auto-made Reel or collage of the month's logged outfits, ready to post | Free marketing and a reason to log daily | Free (watermarked); Ultimate removes the watermark and adds styles | Low (made on the phone) | MVP |
| 93 | **Savings promise** | If drobie doesn't save the user at least ₹1,000 in 3 months (skipped duplicates + resale earnings), the next month is free | Removes "is it worth it?" at the payment screen | Pro and Ultimate | At most one free month per user | v1.1 |

**Sales engine (business, not a feature): creator and campus programme.** Fashion creators and college ambassadors get a personal code and earn 20–30% of their referrals' first-year subscription, paid through the web checkout. Launch with 20–30 micro-creators and 10 campuses.

**Guardrails:** colour analysis never ranks skin tones or uses "fair" or "dark" as better or worse; the selfie never leaves the phone and is deleted after analysis unless the user saves it. Repeat radar and Instagram import are opt-in and visible only to the user. Squad rooms are invite-only. Savings-promise numbers are shown to the user with the items behind them.

## 11. Non-functional requirements

A person's wardrobe, body measurements, photos and location are personal data, so privacy is a product feature, not a checkbox.

| Area | Requirement |
| --- | --- |
| Privacy | Private by default; nothing shared without an explicit per-item or per-circle choice. Measurements, email import and calendar are opt-in. No sale of personal data. |
| Compliance | Comply with India's Digital Personal Data Protection Act, 2023 and its rules at launch; GDPR-ready before any EU launch. Clear consent screens, data export and delete-my-account within the app. Legal review before launch. |
| Security | Encryption in transit and at rest; photos in private storage with signed URLs; Swap payments through a licensed payment partner (no card data stored by drobie). |
| Performance | App opens to Today in under 2 seconds; photo processed in under 3 seconds; dro answers simple "where is" questions in under 2 seconds. |
| Device range | Works well on mid-range Android phones (the majority in India) and iPhone. |
| Offline | Closet, item locations and saved looks viewable offline; changes sync later. |
| Accessibility | Text contrast 4.5:1, touch targets 44 px, screen-reader labels, dynamic text size. |
| Localisation | English first; Hindi next; dates, currency and festivals per region. |
| Reliability | 99.5% monthly uptime for core services; no loss of photos or items. |
| AI safety and tone | dro never shames bodies, purchases or repeat outfits; fit features are opt-in and kind; AI errors are easy to correct. |
| Cost control | AI tagging cached per item; on-device steps first; cost per active user tracked monthly. |

## 12. Architecture and data model

The app does capture, cut-out, tagging, colour, duplicate checks, label reading, voice commands and the daily pick on the phone for speed, privacy and zero cost per use; the cloud holds the catalog, reads order emails with retailer templates, runs matching on our own server, and calls paid AI only for open-ended dro conversations, Try it on and the few items the phone is unsure about.

&#91;embedded content: drobie architecture · 3 layers\]

Only the cleaned photo and extracted text leave the phone; dro sits in the middle and reads every other service.

**Core data model**

| Object | Key fields |
| --- | --- |
| User | profile, home city, homes, preferences, measurements (opt-in), plan |
| Item | photos (original + cleaned), category, colours, pattern, fabric, brand, size, price, purchase date, tags, embedding |
| Place | home > room > storage > shelf |
| Item state | clean, worn, in wash, at dhobi/press-wala, at tailor, lent, packed + since date |
| Wear log | item(s), date, occasion, photo (optional) |
| Look | items, name, occasion, planned date |
| Beauty product | barcode, brand, opened date, PAO months, expiry date |
| Reminder | type, item, due time, status |
| Circle | members, shared items |
| Listing and booking | item, available dates, deposit, borrower, status, condition photos, ratings |

## 13. Brand and design references

The brand is set; the main app colour is pending the colour test (lilac, indigo or teal).

- **Name:** drobie; agent dro, called with "hey dro". Handles: @hey\_drobie.
- **Logo:** capital D drawn as a sideways wire hanger, the o as dro's chat bubble. Tagline: *Hang out with your wardrobe.* Store headline: *Never 'nothing to wear' again.*
- **Colours:** about 80% soft neutrals, 15% main colour, 5% pop lime and peach.
- **Type:** Bricolage Grotesque for headings, DM Sans for app text.
- **Signature UI ideas:** today's rail (outfits on hangers), hanging tags for weather and plans, dro speaking in bubbles, dro peeking over the Ask bar, centre "talk to dro" button.
- **References:** the drobie brand guidelines (design system) and the sample screens canvas in this project.

## 14. Risks and mitigations

The biggest risk is onboarding effort; the second is AI accuracy on Indian clothing.

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Users quit before adding enough items | No daily value, churn | Lazy capture, batch gallery import, store links, receipt import; value shown after the first 10 items |
| Tagging is wrong on ethnic wear (kurtas, lehengas, sarees, dupattas) | Bad suggestions, low trust | Test set of Indian wear in the spike; easy corrections that train the model; custom labels |
| Colour shifts make "same shade" checks unreliable | Before you buy loses credibility | Colour calibration in auto-adjust; show both photos side by side; say "similar" not "same" below a confidence level |
| AI and image costs grow faster than revenue | Losses per user | On-device first, caching, tag once per item, Pro limits |
| Gmail restricted-scope review delays import | Feature late | Start with receipt forwarding; begin Google verification early |
| Swap damage, theft or safety incidents | Trust and legal risk | Verification, deposits, condition photos, women-only circles, clear policy |
| Privacy concerns about photos and measurements | Low sign-ups, regulatory risk | Private by default, opt-in data, plain-language privacy page, DPDP compliance |
| A large player copies features | Slower growth | Move fast, build catalog depth and local networks, brand personality |
| Notification fatigue | Uninstalls | Max 1 push a day, smart timing, easy controls |

## 15. Roadmap and milestones

The plan moves through four phases, and each gate must be passed before spending on the next phase. Dates assume a small dedicated team (the founders, building in-house, close to full time) and should be reset after the first month of building.

&#91;embedded content: drobie roadmap · 4 phases, 3 gates\]

Swap and the Navratri planner are timed to be live before Navratri 2027, the biggest borrowing moment of the year in the launch market.

## 
