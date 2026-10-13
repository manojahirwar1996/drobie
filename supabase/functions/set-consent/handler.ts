// POST /set-consent — record one or more versioned consents.
// Body: { consents: [{ consent_type, granted, version }] }
// Versions must match the texts currently in force (config app:consent_versions);
// withdrawing "measurements" deletes stored measurements (DPDP).
// Allowed before the 18+ confirmation, because terms/privacy come first.
import { setConsentsRequest } from "@drobie/shared";
import { requireUser } from "../_shared/auth.ts";
import { serverRpc } from "../_shared/db.ts";
import { HttpError } from "../_shared/errors.ts";
import { defineHandler, ok } from "../_shared/http.ts";
import { limitUser } from "../_shared/ratelimit.ts";
import { parse } from "../_shared/validate.ts";

export const handler = defineHandler("set-consent", { methods: ["POST"], maxBodyBytes: 8 * 1024 }, async (ctx) => {
  const user = await requireUser(ctx);
  await limitUser(ctx, user.id, { capacity: 20, refillPerSec: 0.2 });
  const body = parse(setConsentsRequest, await ctx.json());
  const state = await serverRpc<{ exists: boolean; status?: string }>(ctx.service(), "account_state", {
    p_user: user.id,
  });
  if (!state.exists || state.status !== "active") {
    throw new HttpError(403, "account_inactive", "this account is not active");
  }

  const result = await serverRpc<{ recorded: number; changed: number }>(ctx.service(), "set_consents", {
    p_user: user.id,
    p_consents: body.consents,
    p_source: ctx.platform === "web" ? "web" : "app",
  });
  const current = await serverRpc<Record<string, unknown>>(ctx.service(), "current_consents", { p_user: user.id });
  ctx.annotate({ consents_changed: result.changed });
  return ok({ ...result, current });
});
