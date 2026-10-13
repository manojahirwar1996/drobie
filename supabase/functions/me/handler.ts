// GET   /me — everything the app needs after sign-in, in one round trip:
//              profile, households, plan + features, consents, wallets.
// PATCH /me — update safe profile fields (column grants + RLS enforce the rest).
// Reads run AS the user, so RLS decides what comes back.
import { profileUpdate } from "@drobie/shared";
import { requireActiveAdult, requireUser } from "../_shared/auth.ts";
import { serverRpc, userDb } from "../_shared/db.ts";
import { notFound } from "../_shared/errors.ts";
import { defineHandler, ok } from "../_shared/http.ts";
import { limitUser } from "../_shared/ratelimit.ts";
import { config } from "../_shared/runtime.ts";
import { parse } from "../_shared/validate.ts";

const PROFILE_COLUMNS =
  "id,display_name,handle,country,city,locale,timezone,currency,morning_time,vibe,settings,adult_confirmed_at,status,inbound_email_token,created_at";

export const handler = defineHandler("me", { methods: ["GET", "PATCH"], maxBodyBytes: 8 * 1024 }, async (ctx) => {
  const user = await requireUser(ctx);
  const rate = await config.get("limit:rate.default");
  await limitUser(ctx, user.id, { capacity: rate.capacity, refillPerSec: rate.refill_per_sec });
  const db = userDb(user.token);

  if (ctx.req.method === "PATCH") {
    await requireActiveAdult(ctx, user);
    const patch = parse(profileUpdate, await ctx.json());
    const rows = await db.update<unknown[]>("profiles", { id: `eq.${user.id}`, select: PROFILE_COLUMNS }, patch);
    if (!rows.length) throw notFound("profile not found");
    return ok({ profile: rows[0] });
  }

  const [profile, households, entitlements, consents, wallets] = await Promise.all([
    db.select<Record<string, unknown>>("profiles", { id: `eq.${user.id}`, select: PROFILE_COLUMNS }, { single: true }),
    db.select<unknown[]>("household_members", {
      user_id: `eq.${user.id}`,
      select: "role,household:households(id,name,kind)",
    }),
    db.select<
      {
        feature_key: string;
        feature_type: string;
        period: string | null;
        enabled: boolean;
        limit_value: number | null;
        plan_code: string;
      }[]
    >(
      "user_entitlements",
      { select: "feature_key,feature_type,period,enabled,limit_value,plan_code" },
    ),
    serverRpc<Record<string, unknown>>(ctx.service(), "current_consents", { p_user: user.id }),
    db.rpc<{ credit_type: string; currency: string; balance: number }[]>("my_wallets"),
  ]);

  return ok({
    profile,
    households,
    plan: entitlements[0]?.plan_code ?? null,
    features: Object.fromEntries(
      entitlements.map((
        e,
      ) => [e.feature_key, { type: e.feature_type, period: e.period, enabled: e.enabled, limit: e.limit_value }]),
    ),
    consents,
    wallets,
    needs: {
      adult_confirmation: profile.adult_confirmed_at == null,
    },
  });
});
