// Postgres-backed token buckets (server.rate_limit_take). Per user, per IP and
// per feature; limits come from config so they can change without a deploy.
import { serverRpc } from "./db.ts";
import { rateLimited } from "./errors.ts";
import type { Ctx } from "./http.ts";

export interface Bucket {
  capacity: number;
  refillPerSec: number;
}

export async function takeToken(ctx: Ctx, key: string, bucket: Bucket, cost = 1): Promise<void> {
  const allowed = await serverRpc<boolean>(ctx.service(), "rate_limit_take", {
    p_bucket: key,
    p_capacity: bucket.capacity,
    p_refill_per_sec: bucket.refillPerSec,
    p_cost: cost,
  });
  if (!allowed) {
    ctx.annotate({ rate_limited: key.split(":")[0] });
    throw rateLimited(cost / bucket.refillPerSec);
  }
}

/** Standard check for a user-facing function: one bucket per user per function, one per IP. */
export async function limitUser(ctx: Ctx, userId: string, bucket: Bucket): Promise<void> {
  await takeToken(ctx, `u:${userId}:${ctx.fn}`, bucket);
  if (ctx.ip) await takeToken(ctx, `ip:${ctx.ip}:${ctx.fn}`, { capacity: bucket.capacity * 5, refillPerSec: bucket.refillPerSec * 5 });
}
