-- =============================================================================
-- drobie · 1001 · Reference data needed in every environment
-- Taxonomy with attribute schemas, plans/features (PLACEHOLDER prices),
-- tax, ledger chart of accounts, config registry, retailers, brands and the
-- starter dictionary. Moved out of seed.sql so production gets it too; seed.sql
-- now holds only local test users. Later changes go through admin tools
-- (config/plans) or new migrations, never by editing this file.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Taxonomy with attribute schemas
-- ---------------------------------------------------------------------------
create temporary table seed_schemas (name text primary key, s jsonb);
insert into seed_schemas values
('generic', '{"type":"object"}'),
('top', '{"type":"object","additionalProperties":false,"properties":{
   "sleeve":{"enum":["sleeveless","short","three_quarter","full"]},
   "neckline":{"type":"string","maxLength":30},
   "fit":{"enum":["slim","regular","relaxed","oversized"]},
   "length":{"enum":["crop","regular","long"]}}}'),
('bottom', '{"type":"object","additionalProperties":false,"properties":{
   "waist_in":{"type":"integer","minimum":20,"maximum":60},
   "inseam_in":{"type":"integer","minimum":20,"maximum":40},
   "fit":{"enum":["skinny","slim","straight","relaxed","wide","flared","bootcut"]},
   "rise":{"enum":["low","mid","high"]},
   "wash":{"enum":["light","mid","dark","black","coloured"]}}}'),
('dress', '{"type":"object","additionalProperties":false,"properties":{
   "length":{"enum":["mini","knee","midi","maxi"]},
   "sleeve":{"enum":["sleeveless","short","three_quarter","full"]},
   "silhouette":{"type":"string","maxLength":30}}}'),
('ethnic', '{"type":"object","additionalProperties":false,"properties":{
   "work":{"type":"array","uniqueItems":true,"items":{"enum":["plain","embroidered","printed","zari","mirror","sequin","block_print","bandhani","chikankari","ikat"]}},
   "set_pieces":{"type":"array","uniqueItems":true,"items":{"enum":["kurta","bottom","dupatta","jacket","blouse","petticoat","stole"]}},
   "occasion_tier":{"enum":["daily","office","festive","wedding"]},
   "length":{"enum":["short","knee","calf","ankle","floor"]}}}'),
('saree', '{"type":"object","additionalProperties":false,"properties":{
   "length_m":{"type":"number","minimum":4,"maximum":9.5},
   "blouse_included":{"type":"boolean"},
   "blouse_stitched":{"type":"boolean"},
   "weave":{"type":"string","maxLength":40},
   "work":{"type":"array","uniqueItems":true,"items":{"enum":["plain","zari","embroidered","printed","sequin","bandhani","ikat","kanjivaram","banarasi"]}},
   "occasion_tier":{"enum":["daily","office","festive","wedding"]}}}'),
('outer', '{"type":"object","additionalProperties":false,"properties":{
   "warmth":{"enum":["light","medium","heavy"]},
   "waterproof":{"type":"boolean"},
   "closure":{"enum":["zip","buttons","open","wrap"]}}}'),
('footwear', '{"type":"object","additionalProperties":false,"properties":{
   "uk_size":{"type":"number","minimum":1,"maximum":15},
   "heel_cm":{"type":"number","minimum":0,"maximum":20},
   "closure":{"enum":["lace","slip_on","buckle","velcro","zip","strap"]},
   "waterproof":{"type":"boolean"}}}'),
('jewellery', '{"type":"object","additionalProperties":false,"properties":{
   "metal":{"enum":["gold","silver","platinum","brass","oxidised","kundan","imitation","other"]},
   "purity":{"type":"string","maxLength":10},
   "stones":{"type":"array","maxItems":10,"items":{"type":"string","maxLength":20}},
   "weight_g":{"type":"number","minimum":0,"maximum":5000},
   "valuable":{"type":"boolean"}}}'),
('bag', '{"type":"object","additionalProperties":false,"properties":{
   "capacity_l":{"type":"number","minimum":0,"maximum":200},
   "laptop_in":{"type":"number","minimum":0,"maximum":20},
   "closure":{"enum":["zip","magnetic","buckle","drawstring","open"]},
   "cabin_size":{"type":"boolean"}}}'),
('beauty', '{"type":"object","additionalProperties":false,"properties":{
   "skin_types":{"type":"array","uniqueItems":true,"items":{"enum":["oily","dry","combination","normal","sensitive"]}},
   "finish":{"enum":["matte","dewy","satin","natural","shimmer"]},
   "volume_ml":{"type":"number","minimum":0,"maximum":2000},
   "vegan":{"type":"boolean"}}}'),
('watch', '{"type":"object","additionalProperties":false,"properties":{
   "type":{"enum":["analog","digital","smart","hybrid"]},
   "strap":{"enum":["metal","leather","silicone","fabric","ceramic"]},
   "dial_mm":{"type":"number","minimum":10,"maximum":60}}}'),
('document', '{"type":"object","additionalProperties":false,"properties":{
   "document_type":{"enum":["passport","aadhaar_card","pan_card","driving_licence","voter_id","certificate","warranty_card","insurance","other"]},
   "expiry_tracked":{"type":"boolean"},
   "original":{"type":"boolean"}},
   "$comment":"Never store ID numbers here (DPDP). Expiry lives in items.warranty_until / reminders."}'),
('gadget', '{"type":"object","additionalProperties":false,"properties":{
   "model":{"type":"string","maxLength":60},
   "warranty_months":{"type":"integer","minimum":0,"maximum":120},
   "has_box":{"type":"boolean"}}}');

create temporary table seed_categories (
  slug text, parent text, name text, kind text, schema_name text, wash smallint, ord int, audience text[]
);
insert into seed_categories values
-- roots
('tops', null, 'Tops', 'apparel', 'top', null, 10, '{}'),
('bottoms', null, 'Bottoms', 'apparel', 'bottom', null, 20, '{}'),
('dresses-jumpsuits', null, 'Dresses & jumpsuits', 'apparel', 'dress', null, 30, '{women}'),
('indian-wear', null, 'Indian wear', 'apparel', 'ethnic', null, 40, '{}'),
('outerwear', null, 'Outerwear', 'apparel', 'outer', null, 50, '{}'),
('innerwear-loungewear', null, 'Innerwear & loungewear', 'apparel', 'generic', null, 60, '{}'),
('activewear', null, 'Activewear', 'apparel', 'generic', null, 70, '{}'),
('footwear', null, 'Footwear', 'footwear', 'footwear', null, 80, '{}'),
('accessories', null, 'Accessories', 'accessory', 'generic', null, 90, '{}'),
('jewellery', null, 'Jewellery', 'jewellery', 'jewellery', null, 100, '{}'),
('bags', null, 'Bags', 'bag', 'bag', null, 110, '{}'),
('beauty', null, 'Beauty', 'beauty', 'beauty', null, 120, '{}'),
('documents-valuables', null, 'Documents & valuables', 'document', 'document', null, 130, '{}'),
('gadgets', null, 'Gadgets', 'gadget', 'gadget', null, 140, '{}'),
-- tops
('t-shirts', 'tops', 'T-shirts', 'apparel', 'top', 1, 1, '{}'),
('shirts', 'tops', 'Shirts', 'apparel', 'top', 2, 2, '{}'),
('polos', 'tops', 'Polos', 'apparel', 'top', 1, 3, '{}'),
('tops-blouses', 'tops', 'Tops & blouses', 'apparel', 'top', 2, 4, '{women}'),
('sweaters', 'tops', 'Sweaters', 'apparel', 'top', 5, 5, '{}'),
('sweatshirts-hoodies', 'tops', 'Sweatshirts & hoodies', 'apparel', 'top', 4, 6, '{}'),
-- bottoms
('jeans', 'bottoms', 'Jeans', 'apparel', 'bottom', 6, 1, '{}'),
('trousers', 'bottoms', 'Trousers', 'apparel', 'bottom', 3, 2, '{}'),
('chinos', 'bottoms', 'Chinos', 'apparel', 'bottom', 3, 3, '{}'),
('shorts', 'bottoms', 'Shorts', 'apparel', 'bottom', 2, 4, '{}'),
('skirts', 'bottoms', 'Skirts', 'apparel', 'bottom', 2, 5, '{women}'),
('leggings', 'bottoms', 'Leggings', 'apparel', 'bottom', 1, 6, '{women}'),
('joggers', 'bottoms', 'Joggers', 'apparel', 'bottom', 3, 7, '{}'),
-- dresses
('dresses', 'dresses-jumpsuits', 'Dresses', 'apparel', 'dress', 1, 1, '{women}'),
('jumpsuits', 'dresses-jumpsuits', 'Jumpsuits', 'apparel', 'dress', 1, 2, '{women}'),
('co-ord-sets', 'dresses-jumpsuits', 'Co-ord sets', 'apparel', 'dress', 2, 3, '{}'),
-- indian wear
('kurtas', 'indian-wear', 'Kurtas', 'apparel', 'ethnic', 2, 1, '{}'),
('kurta-sets', 'indian-wear', 'Kurta sets', 'apparel', 'ethnic', 2, 2, '{}'),
('sarees', 'indian-wear', 'Sarees', 'apparel', 'saree', 3, 3, '{women}'),
('lehengas', 'indian-wear', 'Lehengas', 'apparel', 'ethnic', 5, 4, '{women}'),
('salwar-suits', 'indian-wear', 'Salwar suits', 'apparel', 'ethnic', 2, 5, '{women}'),
('anarkalis', 'indian-wear', 'Anarkalis', 'apparel', 'ethnic', 2, 6, '{women}'),
('sherwanis', 'indian-wear', 'Sherwanis', 'apparel', 'ethnic', 5, 7, '{men}'),
('nehru-jackets', 'indian-wear', 'Nehru jackets', 'apparel', 'ethnic', 5, 8, '{men}'),
('dupattas-stoles', 'indian-wear', 'Dupattas', 'apparel', 'ethnic', 3, 9, '{}'),
('ethnic-bottoms', 'indian-wear', 'Churidars, palazzos & salwars', 'apparel', 'bottom', 2, 10, '{}'),
('dhotis', 'indian-wear', 'Dhotis & mundus', 'apparel', 'ethnic', 2, 11, '{men}'),
('blouses-ethnic', 'indian-wear', 'Saree blouses', 'apparel', 'ethnic', 2, 12, '{women}'),
-- outerwear
('jackets', 'outerwear', 'Jackets', 'apparel', 'outer', 10, 1, '{}'),
('blazers', 'outerwear', 'Blazers', 'apparel', 'outer', 8, 2, '{}'),
('coats', 'outerwear', 'Coats', 'apparel', 'outer', 10, 3, '{}'),
('shrugs', 'outerwear', 'Shrugs & cardigans', 'apparel', 'outer', 4, 4, '{}'),
-- innerwear & loungewear
('innerwear', 'innerwear-loungewear', 'Innerwear', 'apparel', 'generic', 1, 1, '{}'),
('nightwear', 'innerwear-loungewear', 'Nightwear', 'apparel', 'generic', 3, 2, '{}'),
('loungewear', 'innerwear-loungewear', 'Loungewear', 'apparel', 'generic', 3, 3, '{}'),
('socks', 'innerwear-loungewear', 'Socks', 'apparel', 'generic', 1, 4, '{}'),
-- activewear
('sports-tops', 'activewear', 'Sports tops', 'apparel', 'top', 1, 1, '{}'),
('track-pants', 'activewear', 'Track pants', 'apparel', 'bottom', 2, 2, '{}'),
('sports-bras', 'activewear', 'Sports bras', 'apparel', 'generic', 1, 3, '{women}'),
-- footwear
('sneakers', 'footwear', 'Sneakers', 'footwear', 'footwear', null, 1, '{}'),
('sports-shoes', 'footwear', 'Sports shoes', 'footwear', 'footwear', null, 2, '{}'),
('formal-shoes', 'footwear', 'Formal shoes', 'footwear', 'footwear', null, 3, '{}'),
('sandals', 'footwear', 'Sandals & floaters', 'footwear', 'footwear', null, 4, '{}'),
('heels', 'footwear', 'Heels', 'footwear', 'footwear', null, 5, '{women}'),
('flats', 'footwear', 'Flats & ballerinas', 'footwear', 'footwear', null, 6, '{women}'),
('juttis-mojaris', 'footwear', 'Juttis & mojaris', 'footwear', 'footwear', null, 7, '{}'),
('kolhapuris', 'footwear', 'Kolhapuris', 'footwear', 'footwear', null, 8, '{}'),
('boots', 'footwear', 'Boots', 'footwear', 'footwear', null, 9, '{}'),
('slippers', 'footwear', 'Slippers & flip-flops', 'footwear', 'footwear', null, 10, '{}'),
-- accessories
('watches', 'accessories', 'Watches', 'accessory', 'watch', null, 1, '{}'),
('belts', 'accessories', 'Belts', 'accessory', 'generic', null, 2, '{}'),
('sunglasses', 'accessories', 'Sunglasses', 'accessory', 'generic', null, 3, '{}'),
('caps-hats', 'accessories', 'Caps & hats', 'accessory', 'generic', 5, 4, '{}'),
('scarves-stoles', 'accessories', 'Scarves & stoles', 'accessory', 'generic', 4, 5, '{}'),
('ties', 'accessories', 'Ties & pocket squares', 'accessory', 'generic', null, 6, '{men}'),
('wallets', 'accessories', 'Wallets', 'accessory', 'generic', null, 7, '{}'),
-- jewellery
('earrings', 'jewellery', 'Earrings & jhumkas', 'jewellery', 'jewellery', null, 1, '{}'),
('necklaces', 'jewellery', 'Necklaces & chains', 'jewellery', 'jewellery', null, 2, '{}'),
('rings', 'jewellery', 'Rings', 'jewellery', 'jewellery', null, 3, '{}'),
('bangles-bracelets', 'jewellery', 'Bangles, kadas & bracelets', 'jewellery', 'jewellery', null, 4, '{}'),
('anklets', 'jewellery', 'Anklets & payal', 'jewellery', 'jewellery', null, 5, '{women}'),
('nose-pins', 'jewellery', 'Nose pins & nath', 'jewellery', 'jewellery', null, 6, '{women}'),
('maang-tikka', 'jewellery', 'Maang tikka & hair jewellery', 'jewellery', 'jewellery', null, 7, '{women}'),
-- bags
('handbags', 'bags', 'Handbags', 'bag', 'bag', null, 1, '{women}'),
('backpacks', 'bags', 'Backpacks', 'bag', 'bag', null, 2, '{}'),
('totes', 'bags', 'Totes', 'bag', 'bag', null, 3, '{}'),
('clutches-potlis', 'bags', 'Clutches & potlis', 'bag', 'bag', null, 4, '{women}'),
('sling-bags', 'bags', 'Sling bags', 'bag', 'bag', null, 5, '{}'),
('luggage', 'bags', 'Luggage & trolleys', 'bag', 'bag', null, 6, '{}'),
-- beauty
('skincare', 'beauty', 'Skincare', 'beauty', 'beauty', null, 1, '{}'),
('makeup', 'beauty', 'Makeup', 'beauty', 'beauty', null, 2, '{}'),
('haircare', 'beauty', 'Haircare', 'beauty', 'beauty', null, 3, '{}'),
('fragrance', 'beauty', 'Fragrance & attar', 'beauty', 'beauty', null, 4, '{}'),
('nail', 'beauty', 'Nail care', 'beauty', 'beauty', null, 5, '{}'),
-- documents & gadgets
('identity-documents', 'documents-valuables', 'ID documents', 'document', 'document', null, 1, '{}'),
('certificates', 'documents-valuables', 'Certificates', 'document', 'document', null, 2, '{}'),
('warranty-cards', 'documents-valuables', 'Warranty cards & bills', 'document', 'document', null, 3, '{}'),
('phones', 'gadgets', 'Phones', 'gadget', 'gadget', null, 1, '{}'),
('laptops', 'gadgets', 'Laptops & tablets', 'gadget', 'gadget', null, 2, '{}'),
('headphones', 'gadgets', 'Headphones & earbuds', 'gadget', 'gadget', null, 3, '{}'),
('chargers-cables', 'gadgets', 'Chargers & cables', 'gadget', 'gadget', null, 4, '{}');

insert into public.categories (slug, name, kind, icon, attribute_schema, default_wash_after_wears, sort_order, audience)
select c.slug, c.name, c.kind, c.slug, s.s, c.wash, c.ord, c.audience
from seed_categories c join seed_schemas s on s.name = c.schema_name
where c.parent is null;

insert into public.categories (slug, parent_id, name, kind, icon, attribute_schema, default_wash_after_wears, sort_order, audience)
select c.slug, p.id, c.name, c.kind, c.slug, s.s, c.wash, c.ord, c.audience
from seed_categories c
join seed_schemas s on s.name = c.schema_name
join public.categories p on p.slug = c.parent;

insert into public.category_translations (category_id, locale, name)
select id, 'hi-IN', t.name from public.categories c
join (values ('kurtas', 'कुर्ते'), ('sarees', 'साड़ियाँ'), ('jeans', 'जीन्स'), ('footwear', 'जूते-चप्पल'),
             ('jewellery', 'गहने'), ('dupattas-stoles', 'दुपट्टे'), ('juttis-mojaris', 'जूतियाँ')) t(slug, name)
  on t.slug = c.slug;

-- ---------------------------------------------------------------------------
-- Plans, features, plan_features. Values from FRS §6 (limits) and FRS-CST-03.
-- Every price is a PLACEHOLDER (is_placeholder = true) until pricing is final.
-- ---------------------------------------------------------------------------
insert into public.plans (code, name, description, rank, is_default, sort_order) values
  ('free', 'Free', 'drobie basics', 0, true, 1),
  ('pro', 'Pro', 'More closet, more dro', 10, false, 2),
  ('ultimate', 'Ultimate dro', 'Everything, with Studio looks included', 20, false, 3);

insert into public.features (key, type, period, unit, description) values
  ('closet.max_items', 'limit', null, 'items', 'Maximum active items in the closet'),
  ('dro.chats', 'quota', 'day', 'messages', 'dro questions per day (rules-answered questions are not counted)'),
  ('studio.looks', 'quota', 'month', 'looks', 'Studio looks included per month'),
  ('dro.think_harder', 'flag', null, null, 'Use the larger model on request'),
  ('reels.no_watermark', 'flag', null, null, 'Fit reels without watermark');

insert into public.plan_features (plan_id, feature_id, enabled, limit_value)
select p.id, f.id, v.enabled, v.limit_value
from (values
  ('free', 'closet.max_items', true, 40::bigint),
  ('pro', 'closet.max_items', true, 300),
  ('ultimate', 'closet.max_items', true, null),
  ('free', 'dro.chats', true, 5),
  ('pro', 'dro.chats', true, 150),
  ('ultimate', 'dro.chats', true, null),
  ('free', 'studio.looks', false, 0),
  ('pro', 'studio.looks', false, 0),
  ('ultimate', 'studio.looks', true, 20),
  ('free', 'dro.think_harder', false, null),
  ('pro', 'dro.think_harder', true, null),
  ('ultimate', 'dro.think_harder', true, null),
  ('free', 'reels.no_watermark', false, null),
  ('pro', 'reels.no_watermark', false, null),
  ('ultimate', 'reels.no_watermark', true, null)
) v(plan_code, feature_key, enabled, limit_value)
join public.plans p on p.code = v.plan_code
join public.features f on f.key = v.feature_key;

insert into public.plan_prices (plan_id, channel, billing_interval, currency, amount_minor, store_product_id, trial_days, is_placeholder)
select p.id, v.channel, v.billing_interval, 'INR', v.amount, v.product, v.trial, true
from (values
  ('pro', 'play', 'month', 39900::bigint, 'drobie_pro_monthly', 0),
  ('pro', 'play', 'year', 399900, 'drobie_pro_yearly', 0),
  ('pro', 'app_store', 'month', 39900, 'app.drobie.pro.monthly', 0),
  ('pro', 'app_store', 'year', 399900, 'app.drobie.pro.yearly', 0),
  ('pro', 'web', 'month', 36900, 'web_pro_monthly', 0),
  ('ultimate', 'play', 'month', 59900, 'drobie_ultimate_monthly', 7),
  ('ultimate', 'play', 'year', 599900, 'drobie_ultimate_yearly', 7),
  ('ultimate', 'app_store', 'month', 59900, 'app.drobie.ultimate.monthly', 7),
  ('ultimate', 'app_store', 'year', 599900, 'app.drobie.ultimate.yearly', 7),
  ('ultimate', 'web', 'month', 54900, 'web_ultimate_monthly', 7)
) v(plan_code, channel, billing_interval, amount, product, trial)
join public.plans p on p.code = v.plan_code;

-- ---------------------------------------------------------------------------
-- Tax (verify SAC codes with the CA before launch)
-- ---------------------------------------------------------------------------
insert into public.tax_rates (country, tax_code, rate_pct, hsn_sac, applies_to, valid_from) values
  ('IN', 'GST_18', 18, null, '{subscription,credit_pack,booking,service_fee}', '2017-07-01');

-- ---------------------------------------------------------------------------
-- Ledger chart of accounts
-- ---------------------------------------------------------------------------
insert into private.ledger_accounts (code, name, type, currency) values
  ('cash:razorpay', 'Razorpay clearing', 'asset', 'INR'),
  ('receivable:play', 'Google Play receivable', 'asset', 'INR'),
  ('receivable:app_store', 'App Store receivable', 'asset', 'INR'),
  ('revenue:subscriptions', 'Subscription revenue', 'revenue', 'INR'),
  ('revenue:credit_packs', 'Credit pack revenue', 'revenue', 'INR'),
  ('revenue:commission', 'Platform commission', 'revenue', 'INR'),
  ('expense:store_fees', 'Store fees', 'expense', 'INR'),
  ('expense:gateway_fees', 'Payment gateway fees', 'expense', 'INR'),
  ('liability:gst_payable', 'GST payable', 'liability', 'INR'),
  ('liability:provider_payable', 'Payable to providers', 'liability', 'INR'),
  ('liability:deposits_held', 'Deposits held', 'liability', 'INR'),
  ('credits:issued', 'Credits issued', 'expense', 'CRD'),
  ('credits:consumed', 'Credits consumed', 'revenue', 'CRD');

-- ---------------------------------------------------------------------------
-- Config registry (keys + schema + safe default). Values change via
-- config_versions (draft → approve → publish), never by editing defaults.
-- ---------------------------------------------------------------------------
insert into public.config_keys (namespace, key, description, value_schema, default_value, owner, requires_approval, client_visible) values
('app', 'min_app_version', 'Oldest app version allowed to run',
  '{"type":"object","required":["ios","android"],"additionalProperties":false,"properties":{"ios":{"type":"string","pattern":"^[0-9]+\\.[0-9]+\\.[0-9]+$"},"android":{"type":"string","pattern":"^[0-9]+\\.[0-9]+\\.[0-9]+$"},"message":{"type":"string","maxLength":200}}}',
  '{"ios":"1.0.0","android":"1.0.0"}', 'eng', false, true),
('app', 'maintenance', 'Maintenance mode banner and read-only switch',
  '{"type":"object","required":["enabled"],"additionalProperties":false,"properties":{"enabled":{"type":"boolean"},"message":{"type":"string","maxLength":200}}}',
  '{"enabled":false}', 'eng', true, true),
('app', 'consent_versions', 'Current versions of each consent text (re-prompt when changed)',
  '{"type":"object","additionalProperties":{"type":"string","maxLength":20}}',
  '{"terms":"1.0","privacy":"1.0","email_import":"1.0","gallery":"1.0","calendar":"1.0","measurements":"1.0","marketing":"1.0"}', 'legal', true, true),
('app', 'ai.daily_spend_cap_minor', 'Global paid-AI spend cap per day (paise). Above it dro falls back to rules-only.',
  '{"type":"integer","minimum":0}', '50000', 'founder', true, false),
('app', 'ai.user_daily_budget_minor', 'Per-user daily paid-AI budget by plan code (paise)',
  '{"type":"object","additionalProperties":{"type":"integer","minimum":0}}', '{"free":100,"pro":1500,"ultimate":3000}', 'founder', true, false),
('app', 'ai.tag_confidence_threshold', 'Below this, on-device tags are queued for overnight refinement',
  '{"type":"number","minimum":0,"maximum":1}', '0.6', 'eng', false, false),
('app', 'credits.free_looks', 'One-time free Studio looks unlock',
  '{"type":"object","required":["amount","min_items"],"additionalProperties":false,"properties":{"amount":{"type":"integer","minimum":0,"maximum":50},"min_items":{"type":"integer","minimum":0}}}',
  '{"amount":5,"min_items":30}', 'founder', true, true),
('app', 'credits.web_bonus_pct', 'Extra credits on web pack purchases (%)', '{"type":"integer","minimum":0,"maximum":100}', '10', 'founder', true, false),
('app', 'founding.offer', 'Founding member offer counter and limits',
  '{"type":"object","required":["enabled","max_users"],"properties":{"enabled":{"type":"boolean"},"max_users":{"type":"integer","minimum":0},"pro_months":{"type":"integer","minimum":0}}}',
  '{"enabled":true,"max_users":10000,"pro_months":3}', 'founder', true, true),
('limit', 'upload.max_bytes', 'Max upload size per media variant (bytes)',
  '{"type":"object","additionalProperties":{"type":"integer","minimum":1}}', '{"master":614400,"display":204800,"thumb":61440}', 'eng', false, true),
('flag', 'dro_ai', 'Kill switch for paid AI answers in dro',
  '{"type":"object","required":["enabled"],"additionalProperties":false,"properties":{"enabled":{"type":"boolean"},"rollout_pct":{"type":"integer","minimum":0,"maximum":100}}}',
  '{"enabled":true,"rollout_pct":100}', 'founder', true, true),
('flag', 'email_import', 'Order email import',
  '{"type":"object","required":["enabled"],"additionalProperties":false,"properties":{"enabled":{"type":"boolean"},"rollout_pct":{"type":"integer","minimum":0,"maximum":100}}}',
  '{"enabled":true,"rollout_pct":100}', 'product', false, true),
('flag', 'generate_look', 'Studio look generation',
  '{"type":"object","required":["enabled"],"additionalProperties":false,"properties":{"enabled":{"type":"boolean"},"rollout_pct":{"type":"integer","minimum":0,"maximum":100}}}',
  '{"enabled":false,"rollout_pct":0}', 'founder', true, true),
('flag', 'try_on', 'Try it on (v1.1)',
  '{"type":"object","required":["enabled"],"additionalProperties":false,"properties":{"enabled":{"type":"boolean"},"rollout_pct":{"type":"integer","minimum":0,"maximum":100}}}',
  '{"enabled":false,"rollout_pct":0}', 'product', false, true),
('copy', 'paywall.title', 'Paywall headline', '{"type":"string","minLength":1,"maxLength":80}', '"Hang out with more of your wardrobe"', 'product', false, true),
('copy', 'paywall.subtitle', 'Paywall subtitle', '{"type":"string","maxLength":160}', '"More items, more dro, more looks."', 'product', false, true);

-- ---------------------------------------------------------------------------
-- Retailers (return windows are starting values; verify per retailer policy)
-- ---------------------------------------------------------------------------
insert into public.retailers (name, slug, hosts, email_domains, return_window_days) values
  ('Myntra', 'myntra', '{myntra.com,www.myntra.com}', '{myntra.com}', 14),
  ('AJIO', 'ajio', '{ajio.com,www.ajio.com}', '{ajio.com}', 15),
  ('Amazon.in', 'amazon-in', '{amazon.in,www.amazon.in,amzn.in}', '{amazon.in}', 10),
  ('Flipkart', 'flipkart', '{flipkart.com,www.flipkart.com,dl.flipkart.com}', '{flipkart.com}', 10),
  ('Nykaa', 'nykaa', '{nykaa.com,www.nykaa.com,nykaafashion.com,www.nykaafashion.com}', '{nykaa.com,nykaafashion.com}', 15),
  ('H&M', 'hm', '{www2.hm.com,hm.com}', '{hm.com}', 15),
  ('Zara', 'zara', '{www.zara.com,zara.com}', '{zara.com}', 30),
  ('Meesho', 'meesho', '{meesho.com,www.meesho.com}', '{meesho.com}', 7);

insert into public.brands (name, slug, aliases) values
  ('Levi''s', 'levis', '{levis,"levi strauss"}'), ('H&M', 'hm', '{"h and m",hnm}'), ('Zara', 'zara', '{}'),
  ('Fabindia', 'fabindia', '{"fab india"}'), ('Biba', 'biba', '{}'), ('W', 'w-for-woman', '{"w for woman"}'),
  ('Manyavar', 'manyavar', '{}'), ('Allen Solly', 'allen-solly', '{}'), ('Roadster', 'roadster', '{}'),
  ('Nike', 'nike', '{}'), ('Adidas', 'adidas', '{}'), ('Puma', 'puma', '{}'), ('Bata', 'bata', '{}'),
  ('Uniqlo', 'uniqlo', '{}'), ('Libas', 'libas', '{}');

-- ---------------------------------------------------------------------------
-- Dictionary seed (English, Hindi, Hinglish). Step 8 grows this to full size.
-- ---------------------------------------------------------------------------
insert into public.synonyms (term, lang, maps_to_type, maps_to_value) values
  ('almari', 'hinglish', 'place', 'wardrobe'), ('almirah', 'hinglish', 'place', 'wardrobe'),
  ('अलमारी', 'hi', 'place', 'wardrobe'), ('daraaz', 'hinglish', 'place', 'drawer'), ('drawer', 'en', 'place', 'drawer'),
  ('cupboard', 'en', 'place', 'wardrobe'), ('closet', 'en', 'place', 'wardrobe'), ('shoe rack', 'en', 'place', 'shoe rack'),
  ('peti', 'hinglish', 'place', 'box'), ('sandook', 'hinglish', 'place', 'box'), ('attachi', 'hinglish', 'place', 'suitcase'),
  ('kurta', 'hinglish', 'category', 'kurtas'), ('kurti', 'hinglish', 'category', 'kurtas'), ('कुर्ता', 'hi', 'category', 'kurtas'),
  ('saree', 'en', 'category', 'sarees'), ('sari', 'en', 'category', 'sarees'), ('साड़ी', 'hi', 'category', 'sarees'),
  ('lehenga', 'hinglish', 'category', 'lehengas'), ('ghagra', 'hinglish', 'category', 'lehengas'),
  ('dupatta', 'hinglish', 'category', 'dupattas-stoles'), ('chunni', 'hinglish', 'category', 'dupattas-stoles'),
  ('jutti', 'hinglish', 'category', 'juttis-mojaris'), ('juttis', 'hinglish', 'category', 'juttis-mojaris'), ('mojari', 'hinglish', 'category', 'juttis-mojaris'),
  ('chappal', 'hinglish', 'category', 'slippers'), ('jhumka', 'hinglish', 'category', 'earrings'), ('jhumki', 'hinglish', 'category', 'earrings'),
  ('payal', 'hinglish', 'category', 'anklets'), ('kada', 'hinglish', 'category', 'bangles-bracelets'), ('choodi', 'hinglish', 'category', 'bangles-bracelets'),
  ('potli', 'hinglish', 'category', 'clutches-potlis'), ('tee', 'en', 'category', 't-shirts'), ('tshirt', 'en', 'category', 't-shirts'),
  ('denims', 'en', 'category', 'jeans'), ('pant', 'hinglish', 'category', 'trousers'), ('pajama', 'hinglish', 'category', 'nightwear'),
  ('dhobi', 'hinglish', 'state', 'at_dhobi'), ('presswala', 'hinglish', 'state', 'at_dhobi'), ('istri', 'hinglish', 'state', 'at_dhobi'),
  ('laundry', 'en', 'state', 'in_wash'), ('dhulai', 'hinglish', 'state', 'in_wash'), ('darzi', 'hinglish', 'state', 'at_tailor'),
  ('tailor', 'en', 'state', 'at_tailor'), ('saaf', 'hinglish', 'state', 'clean'), ('ganda', 'hinglish', 'state', 'worn'),
  ('lal', 'hinglish', 'colour', 'red'), ('laal', 'hinglish', 'colour', 'red'), ('neela', 'hinglish', 'colour', 'blue'),
  ('kaala', 'hinglish', 'colour', 'black'), ('safed', 'hinglish', 'colour', 'white'), ('peela', 'hinglish', 'colour', 'yellow'),
  ('hara', 'hinglish', 'colour', 'green'), ('gulabi', 'hinglish', 'colour', 'pink'), ('naarangi', 'hinglish', 'colour', 'orange'),
  ('shaadi', 'hinglish', 'occasion', 'wedding'), ('sangeet', 'hinglish', 'occasion', 'wedding'), ('mehendi', 'hinglish', 'occasion', 'wedding'),
  ('office', 'en', 'occasion', 'office'), ('match day', 'en', 'occasion', 'sports'), ('puja', 'hinglish', 'occasion', 'festive'),
  ('diwali', 'en', 'occasion', 'festive'), ('baarish', 'hinglish', 'season', 'monsoon'), ('sardi', 'hinglish', 'season', 'winter'),
  ('garmi', 'hinglish', 'season', 'summer'), ('kahan hai', 'hinglish', 'action', 'where_is'), ('rakh diya', 'hinglish', 'action', 'place'),
  ('de diya', 'hinglish', 'action', 'lend');

drop table seed_schemas;
drop table seed_categories;
