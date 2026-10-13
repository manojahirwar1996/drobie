// Mirrors of database enums and CHECK lists (supabase/migrations). A test in
// enums.test.ts keeps these honest against the migration SQL.

export const ITEM_STATES = ["clean", "worn", "in_wash", "at_dhobi", "at_tailor", "lent", "packed"] as const;
export type ItemState = (typeof ITEM_STATES)[number];

export const ITEM_VISIBILITIES = ["private", "household", "friends", "circle", "public"] as const;
export type ItemVisibility = (typeof ITEM_VISIBILITIES)[number];

export const ITEM_KINDS = [
  "apparel",
  "footwear",
  "accessory",
  "jewellery",
  "bag",
  "beauty",
  "document",
  "gadget",
  "home",
  "other",
] as const;
export type ItemKind = (typeof ITEM_KINDS)[number];

export const TAG_SOURCES = ["phone", "template", "link", "barcode", "embedder", "ai", "user"] as const;
export type TagSource = (typeof TAG_SOURCES)[number];

export const ITEM_SOURCES = [
  "camera",
  "gallery",
  "section_photo",
  "email",
  "link",
  "barcode",
  "voice",
  "manual",
  "bulk",
  "import",
] as const;
export type ItemSource = (typeof ITEM_SOURCES)[number];

export const SEASONS = ["summer", "monsoon", "winter", "all"] as const;
export type Season = (typeof SEASONS)[number];

export const PLACE_KINDS = ["home", "room", "storage", "shelf", "box", "suitcase", "bag", "vehicle", "other"] as const;
export type PlaceKind = (typeof PLACE_KINDS)[number];

export const CONSENT_TYPES = [
  "terms",
  "privacy",
  "email_import",
  "gallery",
  "calendar",
  "measurements",
  "marketing",
  "avatar",
  "location",
] as const;
export type ConsentType = (typeof CONSENT_TYPES)[number];

export const GRANT_SCOPES = [
  "closet_read",
  "item_read",
  "item_borrow",
  "looks_write",
  "places_read",
  "measurements_read",
  "support_view",
] as const;
export type GrantScope = (typeof GRANT_SCOPES)[number];

export const GRANT_PURPOSES = ["friend", "family", "consultation", "support"] as const;
export type GrantPurpose = (typeof GRANT_PURPOSES)[number];

export const ADMIN_ROLES = ["super_admin", "admin", "moderator", "support", "analyst", "finance"] as const;
export type AdminRole = (typeof ADMIN_ROLES)[number];

export const PLATFORMS = ["ios", "android", "web"] as const;
export type Platform = (typeof PLATFORMS)[number];

export const MEDIA_PURPOSES = [
  "item_photo",
  "wear_log",
  "avatar_source",
  "profile_photo",
  "generated_look",
  "post",
  "portfolio",
  "receipt",
  "document",
  "email_raw",
  "export",
  "place_photo",
] as const;
export type MediaPurpose = (typeof MEDIA_PURPOSES)[number];

export const AI_STEPS = ["rules", "cache", "device", "template", "embedder", "ai"] as const;
export type AiStep = (typeof AI_STEPS)[number];
