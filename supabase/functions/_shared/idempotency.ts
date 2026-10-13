// Idempotency for client POSTs that create things (Idempotency-Key header) and
// for provider webhooks (provider event id). Retries never double-apply.
import { serverRpc } from "./db.ts";
import { badRequest, HttpError } from "./errors.ts";
import { type Ctx, type HandlerResult, respond } from "./http.ts";

export async function sha256Hex(text: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(d), (b) => b.toString(16).padStart(2, "0")).join("");
}

type BeginState =
  | { state: "new" }
  | { state: "in_progress" }
  | { state: "mismatch" }
  | { state: "completed"; response_status: number; response: unknown };

/**
 * Run `work` at most once per (user, Idempotency-Key). A replay returns the
 * stored response; a concurrent duplicate gets 409; reusing a key for a
 * different body gets 422. Without the header, `required` decides.
 */
export async function withIdempotency(
  ctx: Ctx,
  userId: string,
  work: () => Promise<HandlerResult>,
  opts: { required?: boolean } = {},
): Promise<HandlerResult> {
  const key = ctx.req.headers.get("idempotency-key");
  if (!key) {
    if (opts.required) throw badRequest("Idempotency-Key header is required");
    return await work();
  }
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(key)) throw badRequest("Idempotency-Key must be 8–128 letters, digits, - or _");

  const hash = await sha256Hex(await ctx.text());
  const endpoint = `${ctx.req.method} ${ctx.fn}`;
  const begin = await serverRpc<BeginState>(ctx.service(), "idempotency_begin", {
    p_user: userId,
    p_key: key,
    p_endpoint: endpoint,
    p_request_hash: hash,
  });

  if (begin.state === "completed") {
    ctx.annotate({ idempotent_replay: true });
    return respond(begin.response_status, begin.response, { "idempotent-replayed": "true" });
  }
  if (begin.state === "in_progress") {
    throw new HttpError(409, "idempotency_conflict", "the same request is already being processed");
  }
  if (begin.state === "mismatch") {
    throw new HttpError(422, "idempotency_conflict", "this Idempotency-Key was used for a different request");
  }

  try {
    const result = await work();
    const status = result instanceof Response ? result.status : result.status ?? 200;
    if (status < 500) {
      const body = result instanceof Response ? await result.clone().json().catch(() => null) : { data: result.data };
      await serverRpc(ctx.service(), "idempotency_complete", {
        p_user: userId,
        p_key: key,
        p_status: status,
        p_response: body,
      });
    } else {
      await serverRpc(ctx.service(), "idempotency_release", { p_user: userId, p_key: key });
    }
    return result;
  } catch (e) {
    // Failed requests release the key so the client can retry safely.
    await serverRpc(ctx.service(), "idempotency_release", { p_user: userId, p_key: key }).catch(() => undefined);
    throw e;
  }
}

/** Record a provider webhook once. `duplicate: true` means it was already seen. */
export async function receiveWebhook(
  ctx: Ctx,
  provider: string,
  eventId: string,
  eventType: string,
  payload: unknown,
  signatureOk: boolean,
): Promise<{ id: string; duplicate: boolean; status?: string }> {
  return await serverRpc(ctx.service(), "webhook_receive", {
    p_provider: provider,
    p_event_id: eventId,
    p_event_type: eventType,
    p_payload: payload,
    p_signature_ok: signatureOk,
  });
}

export async function markWebhook(ctx: Ctx, id: string, status: "processed" | "failed" | "ignored", error?: string) {
  await serverRpc(ctx.service(), "webhook_mark", { p_id: id, p_status: status, p_error: error ?? null });
}
