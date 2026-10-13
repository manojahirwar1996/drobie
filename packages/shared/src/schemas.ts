// Zod schemas for every client write shape (insert/update) and the API
// envelope. They mirror the database constraints so bad input is rejected with
// a clear message before it reaches Postgres; the database stays the final judge.
import { z } from "zod";
import {
  CONSENT_TYPES,
  GRANT_PURPOSES,
  GRANT_SCOPES,
  ITEM_KINDS,
  ITEM_SOURCES,
  ITEM_STATES,
  ITEM_VISIBILITIES,
  PLACE_KINDS,
  PLATFORMS,
  SEASONS,
  TAG_SOURCES,
} from "./enums.ts";

export const uuid = z.string().uuid();
export const currencyCode = z.string().regex(/^[A-Z]{3}$/, "currency must be a 3-letter code");
export const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "date must be YYYY-MM-DD");
export const isoDateTime = z.string().datetime({ offset: true });
const shortText = (max: number) => z.string().trim().min(1).max(max);

// ---------------------------------------------------------------------------
// Items
// ---------------------------------------------------------------------------
const itemFields = {
  household_id: uuid.optional(),
  visibility: z.enum(ITEM_VISIBILITIES).optional(),
  kind: z.enum(ITEM_KINDS).optional(),
  category_id: uuid.nullable().optional(),
  product_id: uuid.nullable().optional(),
  brand_id: uuid.nullable().optional(),
  name: shortText(120),
  brand: z.string().trim().max(80).nullable().optional(),
  size: z.string().trim().max(30).nullable().optional(),
  colours: z.array(z.string().trim().min(1).max(30)).max(6).optional(),
  pattern: z.string().trim().max(30).nullable().optional(),
  fabric: z.string().trim().max(40).nullable().optional(),
  seasons: z.array(z.enum(SEASONS)).optional(),
  occasions: z.array(z.string().trim().min(1).max(40)).max(12).optional(),
  own_tags: z.array(z.string().trim().min(1).max(40)).max(20).optional(),
  notes: z.string().max(1000).nullable().optional(),
  attributes: z.record(z.unknown()).optional(),
  price_minor: z.number().int().nonnegative().nullable().optional(),
  currency: currencyCode.optional(),
  purchased_on: isoDate.nullable().optional(),
  return_by: isoDate.nullable().optional(),
  warranty_until: isoDate.nullable().optional(),
  place_id: uuid.nullable().optional(),
  state: z.enum(ITEM_STATES).optional(),
  holder_name: z.string().trim().max(80).nullable().optional(),
  holder_user_id: uuid.nullable().optional(),
  due_back_on: isoDate.nullable().optional(),
  confidence: z.number().min(0).max(1).nullable().optional(),
  tag_source: z.enum(TAG_SOURCES).optional(),
  source: z.enum(ITEM_SOURCES).optional(),
  is_stub: z.boolean().optional(),
  user_confirmed: z.boolean().optional(),
};

const holderOnlyWhenLent = (v: { state?: string | undefined; holder_name?: unknown; due_back_on?: unknown }) =>
  v.state === undefined || v.state === "lent" || (v.holder_name == null && v.due_back_on == null);

/** Insert: the client may supply its own UUID (offline-first). */
export const itemInsert = z
  .object({ id: uuid.optional(), ...itemFields })
  .strict()
  .refine(holderOnlyWhenLent, { message: "holder and due date are only allowed when the item is lent" });
export type ItemInsert = z.infer<typeof itemInsert>;

export const itemUpdate = z
  .object({ ...itemFields, name: shortText(120).optional(), deleted_at: isoDateTime.nullable().optional() })
  .strict()
  .refine(holderOnlyWhenLent, { message: "holder and due date are only allowed when the item is lent" })
  .refine((v) => Object.keys(v).length > 0, { message: "nothing to update" });
export type ItemUpdate = z.infer<typeof itemUpdate>;

// ---------------------------------------------------------------------------
// Places, wear logs, devices, consents, grants, profile
// ---------------------------------------------------------------------------
export const placeInsert = z
  .object({
    id: uuid.optional(),
    household_id: uuid,
    parent_id: uuid.nullable().optional(),
    name: shortText(60),
    kind: z.enum(PLACE_KINDS).optional(),
    icon: z.string().max(40).nullable().optional(),
    sort_order: z.number().int().optional(),
  })
  .strict();
export type PlaceInsert = z.infer<typeof placeInsert>;

export const placeUpdate = placeInsert
  .omit({ id: true, household_id: true })
  .partial()
  .extend({ deleted_at: isoDateTime.nullable().optional() })
  .strict();

export const wearLogInsert = z
  .object({
    id: uuid.optional(),
    worn_on: isoDate,
    occasion: z.string().trim().max(40).nullable().optional(),
    event_name: z.string().trim().max(80).nullable().optional(),
    with_people: z.array(z.string().trim().min(1).max(60)).max(20).optional(),
    notes: z.string().max(500).nullable().optional(),
    item_ids: z.array(uuid).min(1).max(30),
  })
  .strict();
export type WearLogInsert = z.infer<typeof wearLogInsert>;

export const deviceTokenUpsert = z
  .object({
    token: z.string().min(10).max(400),
    platform: z.enum(PLATFORMS),
    app_version: z.string().regex(/^\d+\.\d+\.\d+$/).optional(),
  })
  .strict();

export const consentInput = z
  .object({
    consent_type: z.enum(CONSENT_TYPES),
    granted: z.boolean(),
    /** Version of the text the user saw; must match the current version in config. */
    version: z.string().min(1).max(20),
  })
  .strict();
export type ConsentInput = z.infer<typeof consentInput>;

export const setConsentsRequest = z
  .object({ consents: z.array(consentInput).min(1).max(CONSENT_TYPES.length) })
  .strict()
  .refine((v) => new Set(v.consents.map((c) => c.consent_type)).size === v.consents.length, {
    message: "each consent type may appear once",
  });
export type SetConsentsRequest = z.infer<typeof setConsentsRequest>;

export const accessGrantInsert = z
  .object({
    grantee_user_id: uuid.optional(),
    grantee_household_id: uuid.optional(),
    scope: z.enum(GRANT_SCOPES),
    purpose: z.enum(GRANT_PURPOSES),
    resource_item_id: uuid.optional(),
    resource_category_id: uuid.optional(),
    resource_place_id: uuid.optional(),
    note: z.string().max(200).optional(),
    expires_at: isoDateTime.optional(),
  })
  .strict()
  .refine((v) => [v.grantee_user_id, v.grantee_household_id].filter(Boolean).length === 1, {
    message: "exactly one grantee",
  })
  .refine((v) => [v.resource_item_id, v.resource_category_id, v.resource_place_id].filter(Boolean).length <= 1, {
    message: "at most one resource filter",
  })
  .refine((v) => (v.scope === "support_view") === (v.purpose === "support"), {
    message: "support_view is only for support grants",
  })
  .refine((v) => !["support", "consultation"].includes(v.purpose) || v.expires_at !== undefined, {
    message: "support and consultation grants must expire",
  });

export const profileUpdate = z
  .object({
    display_name: shortText(60).optional(),
    handle: z.string().regex(/^[a-z0-9_.]{3,30}$/).nullable().optional(),
    city: z.string().trim().max(80).nullable().optional(),
    locale: z.string().regex(/^[a-z]{2}(-[A-Z]{2})?$/).optional(),
    timezone: z.string().min(1).max(64).optional(),
    morning_time: z.string().regex(/^\d{2}:\d{2}$/).optional(),
    vibe: z.string().max(40).nullable().optional(),
    settings: z.record(z.unknown()).optional(),
  })
  .strict();

// ---------------------------------------------------------------------------
// API envelope (every Edge Function)
// ---------------------------------------------------------------------------
export const ERROR_CODES = [
  "bad_request",
  "validation_failed",
  "unauthorized",
  "forbidden",
  "adult_confirmation_required",
  "account_inactive",
  "not_found",
  "conflict",
  "payload_too_large",
  "rate_limited",
  "quota_exceeded",
  "limit_reached",
  "budget_exceeded",
  "upgrade_required",
  "idempotency_conflict",
  "upstream_unavailable",
  "internal",
] as const;
export type ErrorCode = (typeof ERROR_CODES)[number];

export type ApiError = { code: ErrorCode; message: string; details?: unknown };
export type ApiResponse<T> = { data: T } | { error: ApiError };
