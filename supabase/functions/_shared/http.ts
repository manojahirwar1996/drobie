// Request handler wrapper used by every Edge Function: CORS for our origins
// only, request id, JSON body with a size limit, { data } / { error } envelope,
// correct status codes, no stack traces to clients, one structured log line.
import { DbError, fromDbError, HttpError } from "./errors.ts";
import { envOptional } from "./env.ts";
import { createLogger, type Logger } from "./log.ts";
import { type Db, serviceDb } from "./db.ts";

const DEFAULT_ORIGINS = ["https://drobie.app", "https://www.drobie.app", "https://admin.drobie.app"];

export function allowedOrigins(): string[] {
  const fromEnv = envOptional("ALLOWED_ORIGINS");
  return fromEnv ? fromEnv.split(",").map((s) => s.trim()).filter(Boolean) : DEFAULT_ORIGINS;
}

export interface Ctx {
  req: Request;
  fn: string;
  requestId: string;
  log: Logger;
  ip: string | undefined;
  platform: string | undefined;
  appVersion: string | undefined;
  /** Parsed JSON body (cached). Empty body → undefined. */
  json(): Promise<unknown>;
  /** Raw body text (cached) — webhooks need the exact bytes for signatures. */
  text(): Promise<string>;
  /** Lazily created service-role client. */
  service(): Db;
  /** Extra fields for the final log line (never PII). */
  annotate(fields: Record<string, unknown>): void;
}

export interface HandlerOptions {
  methods: readonly string[];
  maxBodyBytes?: number;
}

export type HandlerResult = Response | { data: unknown; status?: number; headers?: Record<string, string> };

/** Build a JSON response in the standard envelope. */
export function respond(status: number, payload: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });
}

export const ok = (data: unknown, status = 200, headers?: Record<string, string>): HandlerResult => ({
  data,
  status,
  ...(headers ? { headers } : {}),
});

function corsHeaders(origin: string | null): Record<string, string> {
  if (!origin || !allowedOrigins().includes(origin)) return {};
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-headers":
      "authorization, apikey, content-type, x-client-info, x-request-id, idempotency-key, x-app-version, x-platform, if-none-match",
    "access-control-allow-methods": "GET, POST, PATCH, OPTIONS",
    "access-control-max-age": "600",
    vary: "Origin",
  };
}

export function defineHandler(
  fn: string,
  opts: HandlerOptions,
  run: (ctx: Ctx) => Promise<HandlerResult>,
): (req: Request) => Promise<Response> {
  const maxBody = opts.maxBodyBytes ?? 64 * 1024;

  return async (req: Request): Promise<Response> => {
    const started = performance.now();
    const origin = req.headers.get("origin");
    const cors = corsHeaders(origin);
    const requestId = req.headers.get("x-request-id")?.slice(0, 64) || crypto.randomUUID();
    const extra: Record<string, unknown> = {};
    const log = createLogger({ fn, request_id: requestId });

    // Browsers from other origins get no CORS headers; reject their preflight.
    if (req.method === "OPTIONS") {
      return new Response(null, { status: origin && Object.keys(cors).length ? 204 : 403, headers: cors });
    }

    let bodyText: string | undefined;
    let service: Db | undefined;
    const ctx: Ctx = {
      req,
      fn,
      requestId,
      log,
      ip: req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || undefined,
      platform: req.headers.get("x-platform") ?? undefined,
      appVersion: req.headers.get("x-app-version") ?? undefined,
      async text() {
        if (bodyText !== undefined) return bodyText;
        const declared = Number(req.headers.get("content-length") ?? "0");
        if (declared > maxBody) throw new HttpError(413, "payload_too_large", "request body is too large");
        const buf = new Uint8Array(await req.arrayBuffer());
        if (buf.byteLength > maxBody) throw new HttpError(413, "payload_too_large", "request body is too large");
        bodyText = new TextDecoder().decode(buf);
        return bodyText;
      },
      async json() {
        const t = await ctx.text();
        if (t.trim() === "") return undefined;
        try {
          return JSON.parse(t);
        } catch {
          throw new HttpError(400, "bad_request", "body must be valid JSON");
        }
      },
      service() {
        service ??= serviceDb();
        return service;
      },
      annotate(fields) {
        Object.assign(extra, fields);
      },
    };

    let res: Response;
    let errCode: string | undefined;
    try {
      if (!opts.methods.includes(req.method)) {
        throw new HttpError(405, "bad_request", `method ${req.method} not allowed`, undefined, { allow: opts.methods.join(", ") });
      }
      const out = await run(ctx);
      res = out instanceof Response ? out : respond(out.status ?? 200, { data: out.data }, out.headers);
    } catch (e) {
      const err = e instanceof HttpError ? e : e instanceof DbError ? fromDbError(e) : undefined;
      if (err) {
        errCode = err.code;
        if (err.status >= 500) log.error("request failed", { error: e });
        res = respond(err.status, { error: { code: err.code, message: err.message, ...(err.details ? { details: err.details } : {}) } }, err.headers);
      } else {
        errCode = "internal";
        log.error("unhandled error", { error: e });
        res = respond(500, { error: { code: "internal", message: "something went wrong" } });
      }
    }

    for (const [k, v] of Object.entries(cors)) res.headers.set(k, v);
    res.headers.set("x-request-id", requestId);
    log.info("request", {
      method: req.method,
      status: res.status,
      duration_ms: Math.round(performance.now() - started),
      ...(errCode ? { error_code: errCode } : {}),
      ...extra,
    });
    return res;
  };
}
