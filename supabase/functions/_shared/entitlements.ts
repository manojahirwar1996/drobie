// The ONLY way a function checks plan access. Pricing and limits are data
// (plans / plan_features); nothing here names a plan.
import { type Db, serverRpc } from "./db.ts";
import { HttpError } from "./errors.ts";

export interface Entitlement {
  feature: string;
  type: "flag" | "limit" | "quota";
  enabled: boolean;
  limit: number | null;
  period: "day" | "month" | null;
  used: number | null;
  remaining: number | null;
  plan: string;
}

export interface QuotaResult {
  ok: boolean;
  reason?: "quota_exceeded" | "not_enabled";
  limit: number | null;
  used: number;
  remaining: number | null;
}

export const entitlement = (db: Db, userId: string, featureKey: string) =>
  serverRpc<Entitlement>(db, "entitlement", { p_user: userId, p_feature_key: featureKey });

/** Flag or feature enabled? */
export async function can(db: Db, userId: string, featureKey: string): Promise<boolean> {
  return (await entitlement(db, userId, featureKey)).enabled;
}

/** Numeric limit (null = unlimited). */
export async function limit(db: Db, userId: string, featureKey: string): Promise<number | null> {
  const e = await entitlement(db, userId, featureKey);
  return e.enabled ? e.limit : 0;
}

/** Atomically use quota; throws 429 quota_exceeded / 403 upgrade_required. */
export async function consume(db: Db, userId: string, featureKey: string, amount = 1): Promise<QuotaResult> {
  const r = await serverRpc<QuotaResult>(db, "consume_quota", {
    p_user: userId,
    p_feature_key: featureKey,
    p_amount: amount,
  });
  if (r.ok) return r;
  if (r.reason === "not_enabled") {
    throw new HttpError(403, "upgrade_required", "this feature is not included in your plan", { feature: featureKey });
  }
  throw new HttpError(429, "quota_exceeded", "you have used today's allowance", {
    feature: featureKey,
    limit: r.limit,
    used: r.used,
  });
}

/** Give quota back when the paid step failed. */
export const release = (db: Db, userId: string, featureKey: string, amount = 1) =>
  serverRpc<null>(db, "release_quota", { p_user: userId, p_feature_key: featureKey, p_amount: amount });
