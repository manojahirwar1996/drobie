// GET /config-bundle?locale=en-IN — the app's config bundle (flags, copy,
// limits, min app version…) with an ETag. Unchanged config costs one tiny
// query and a 304. Works before sign-in (no user data in the bundle).
import { serverRpc } from "../_shared/db.ts";
import { badRequest } from "../_shared/errors.ts";
import { defineHandler } from "../_shared/http.ts";
import { takeToken } from "../_shared/ratelimit.ts";

const LOCALE = /^[a-z]{2}(-[A-Z]{2})?$/;

export const handler = defineHandler("config-bundle", { methods: ["GET"] }, async (ctx) => {
  const locale = new URL(ctx.req.url).searchParams.get("locale") ?? "en-IN";
  if (!LOCALE.test(locale)) throw badRequest("invalid locale");
  if (ctx.ip) await takeToken(ctx, `ip:${ctx.ip}:${ctx.fn}`, { capacity: 30, refillPerSec: 0.5 });

  const db = ctx.service();
  const version = await serverRpc<number>(db, "config_version");
  const etag = `W/"cfg-${version}-${locale}"`;
  const headers = { etag, "cache-control": "private, no-cache", vary: "Accept-Language" };
  if (ctx.req.headers.get("if-none-match") === etag) {
    ctx.annotate({ not_modified: true });
    return new Response(null, { status: 304, headers });
  }
  const bundle = await serverRpc<Record<string, unknown>>(db, "config_bundle", { p_locale: locale });
  return new Response(JSON.stringify({ data: bundle }), {
    status: 200,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
});
