import type { ErrorCode } from "@drobie/shared";

/** An error that is safe to show the client. Anything else becomes a generic 500. */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    message: string,
    readonly details?: unknown,
    readonly headers?: Record<string, string>,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

export const badRequest = (message: string, details?: unknown) => new HttpError(400, "bad_request", message, details);
export const unauthorized = (message = "sign in required") => new HttpError(401, "unauthorized", message);
export const forbidden = (message = "not allowed") => new HttpError(403, "forbidden", message);
export const notFound = (message = "not found") => new HttpError(404, "not_found", message);
export const conflict = (message: string) => new HttpError(409, "conflict", message);
export const rateLimited = (retryAfterSeconds: number) =>
  new HttpError(429, "rate_limited", "too many requests, slow down", undefined, {
    "retry-after": String(Math.max(1, Math.ceil(retryAfterSeconds))),
  });

/** Error returned by PostgREST / Postgres. */
export class DbError extends Error {
  constructor(
    readonly httpStatus: number,
    readonly pgCode: string | undefined,
    message: string,
    readonly hint?: string,
    readonly details?: string,
  ) {
    super(message);
    this.name = "DbError";
  }
}

/**
 * Translate database errors into client-safe HTTP errors. Database messages
 * for constraint and validation failures are written for users (see
 * migrations), so they are passed through; anything unexpected is hidden.
 */
export function fromDbError(e: DbError): HttpError {
  const hint = e.hint ?? "";
  if (hint.startsWith("limit_reached")) return new HttpError(403, "limit_reached", e.message, { limit: hint.split(":")[1] });
  if (hint === "insufficient_balance") return new HttpError(402, "upgrade_required", "not enough credits");
  if (hint === "stale_consent_version") return new HttpError(409, "conflict", e.message);
  switch (e.pgCode) {
    case "42501":
      return forbidden();
    case "23505":
      return conflict("already exists");
    case "23503":
      return badRequest("refers to something that does not exist");
    case "23514":
    case "22023":
    case "22P02":
    case "23502":
      return new HttpError(400, "validation_failed", e.message);
    case "PGRST116":
      return notFound();
    default:
      return new HttpError(502, "upstream_unavailable", "the database could not complete the request");
  }
}
