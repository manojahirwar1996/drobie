// Who is calling, and may they? The user-scoped database client (userDb) then
// enforces row access through RLS; the service client is only for server.*.
import type { AdminRole } from "@drobie/shared";
import { serverRpc } from "./db.ts";
import { serviceRoleKey } from "./env.ts";
import { forbidden, HttpError, unauthorized } from "./errors.ts";
import type { Ctx } from "./http.ts";
import { hashUserId } from "./log.ts";
import { type JwtClaims, verifyJwt } from "./jwt.ts";

export interface User {
  id: string;
  /** Authenticator assurance level: aal2 = MFA completed. */
  aal: string;
  token: string;
  claims: JwtClaims;
}

export interface AccountState {
  exists: boolean;
  status?: "active" | "suspended" | "banned" | "deleted";
  adult_confirmed?: boolean;
  deleted?: boolean;
  country?: string;
  locale?: string;
  timezone?: string;
  plan?: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function bearer(req: Request): string | undefined {
  const h = req.headers.get("authorization") ?? "";
  const m = /^Bearer\s+(.+)$/i.exec(h);
  return m?.[1]?.trim();
}

/** Signed-in end user (role authenticated). */
export async function requireUser(ctx: Ctx): Promise<User> {
  const token = bearer(ctx.req);
  if (!token) throw unauthorized();
  const claims = await verifyJwt(token);
  if (claims.role !== "authenticated" || typeof claims.sub !== "string" || !UUID.test(claims.sub)) throw unauthorized();
  ctx.annotate({ user: await hashUserId(claims.sub) });
  return { id: claims.sub, aal: typeof claims.aal === "string" ? claims.aal : "aal1", token, claims };
}

/** Account must exist, be active and have confirmed 18+ (BRD guardrail). */
export async function requireActiveAdult(ctx: Ctx, user: User): Promise<AccountState> {
  const state = await accountState(ctx, user);
  if (!state.exists || state.deleted || state.status === "deleted") throw unauthorized("account not found");
  if (state.status !== "active") throw new HttpError(403, "account_inactive", "this account is not active");
  if (!state.adult_confirmed) {
    throw new HttpError(403, "adult_confirmation_required", "please confirm you are 18 or older");
  }
  return state;
}

export async function accountState(ctx: Ctx, user: User): Promise<AccountState> {
  return await serverRpc<AccountState>(ctx.service(), "account_state", { p_user: user.id });
}

/** Mirrors private.has_admin_role: MFA required; super_admin covers all; admin covers moderator/support/analyst. */
export function roleSatisfies(held: readonly string[], needed: AdminRole): boolean {
  return held.includes(needed) || held.includes("super_admin") ||
    (held.includes("admin") && ["moderator", "support", "analyst"].includes(needed));
}

export async function requireAdminRole(ctx: Ctx, user: User, role: AdminRole): Promise<string[]> {
  if (user.aal !== "aal2") throw new HttpError(403, "forbidden", "two-step verification required for staff actions");
  const held = await serverRpc<string[]>(ctx.service(), "admin_roles", { p_user: user.id });
  if (!roleSatisfies(held, role)) throw forbidden();
  return held;
}

function timingSafeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

/** Internal callers (pg_cron → function, workers) present the service key. */
export function requireServiceCaller(ctx: Ctx): void {
  const token = bearer(ctx.req);
  if (!token || !timingSafeEqual(token, serviceRoleKey())) throw unauthorized();
}
