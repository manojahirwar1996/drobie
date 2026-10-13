// GET /health — liveness for uptime checks. `?deep=1` (service key only) also
// checks the database round trip.
import { requireServiceCaller } from "../_shared/auth.ts";
import { serverRpc } from "../_shared/db.ts";
import { defineHandler, ok } from "../_shared/http.ts";
import { BUILD } from "../_shared/runtime.ts";

export const handler = defineHandler("health", { methods: ["GET"] }, async (ctx) => {
  const deep = new URL(ctx.req.url).searchParams.get("deep") === "1";
  if (!deep) return ok({ status: "ok", build: BUILD });
  requireServiceCaller(ctx);
  const started = performance.now();
  const configVersion = await serverRpc<number>(ctx.service(), "config_version");
  return ok({
    status: "ok",
    build: BUILD,
    db: { ok: true, ms: Math.round(performance.now() - started), config_version: configVersion },
  });
});
