// POST /confirm-adult — the user confirms they are 18 or older (BRD guardrail).
// Runs AS the user (RLS + the confirm_adult RPC); idempotent.
import { requireUser } from "../_shared/auth.ts";
import { userDb } from "../_shared/db.ts";
import { defineHandler, ok } from "../_shared/http.ts";
import { limitUser } from "../_shared/ratelimit.ts";
import { config } from "../_shared/runtime.ts";

export const handler = defineHandler("confirm-adult", { methods: ["POST"] }, async (ctx) => {
  const user = await requireUser(ctx);
  const rate = await config.get("limit:rate.default");
  await limitUser(ctx, user.id, { capacity: 10, refillPerSec: rate.refill_per_sec / 10 });
  const confirmedAt = await userDb(user.token).rpc<string>("confirm_adult");
  return ok({ adult_confirmed_at: confirmedAt });
});
