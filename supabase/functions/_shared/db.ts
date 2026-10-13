// Minimal typed PostgREST client (no supabase-js: smaller cold starts, no
// extra dependency). Two flavours:
//   userDb(token)  – acts AS the user; every read/write goes through RLS
//   serviceDb()    – service role; only for the `server` schema and privileged steps
import { anonKey, restUrl, serviceRoleKey } from "./env.ts";
import { DbError } from "./errors.ts";

type Json = string | number | boolean | null | Json[] | { [k: string]: Json };
export type Filter = Record<string, string>;

export interface Db {
  rpc<T>(fn: string, args?: Record<string, unknown>, opts?: { schema?: string }): Promise<T>;
  select<T>(table: string, query: Filter, opts?: { schema?: string; single?: boolean }): Promise<T>;
  insert<T>(table: string, rows: unknown, opts?: { schema?: string; returning?: boolean; upsertOn?: string }): Promise<T>;
  update<T>(table: string, filter: Filter, patch: Record<string, unknown>, opts?: { schema?: string }): Promise<T>;
}

export type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

export function createDb(bearer: string, apikey: string, fetcher: FetchLike = fetch, base = restUrl()): Db {
  const headers = (schema: string, write: boolean): Record<string, string> => ({
    apikey,
    authorization: `Bearer ${bearer}`,
    "content-type": "application/json",
    [write ? "content-profile" : "accept-profile"]: schema,
  });

  async function call<T>(url: string, init: RequestInit): Promise<T> {
    let res: Response;
    try {
      res = await fetcher(url, { ...init, signal: AbortSignal.timeout(10_000) });
    } catch (e) {
      throw new DbError(503, undefined, `database unreachable: ${(e as Error).message}`);
    }
    const text = await res.text();
    if (!res.ok) {
      let body: { code?: string; message?: string; hint?: string; details?: string } = {};
      try {
        body = JSON.parse(text);
      } catch { /* non-JSON error page */ }
      throw new DbError(res.status, body.code, body.message ?? `database error ${res.status}`, body.hint ?? undefined, body.details);
    }
    return (text ? JSON.parse(text) : null) as T;
  }

  return {
    rpc<T>(fn: string, args: Record<string, unknown> = {}, opts: { schema?: string } = {}) {
      const schema = opts.schema ?? "public";
      return call<T>(`${base}/rpc/${encodeURIComponent(fn)}`, {
        method: "POST",
        headers: headers(schema, true),
        body: JSON.stringify(args),
      });
    },
    select<T>(table: string, query: Filter, opts: { schema?: string; single?: boolean } = {}) {
      const h = headers(opts.schema ?? "public", false);
      if (opts.single) h.accept = "application/vnd.pgrst.object+json";
      return call<T>(`${base}/${encodeURIComponent(table)}?${new URLSearchParams(query)}`, { method: "GET", headers: h });
    },
    insert<T>(table: string, rows: unknown, opts: { schema?: string; returning?: boolean; upsertOn?: string } = {}) {
      const h = headers(opts.schema ?? "public", true);
      const prefer = [opts.returning === false ? "return=minimal" : "return=representation"];
      if (opts.upsertOn) prefer.push("resolution=merge-duplicates");
      h.prefer = prefer.join(",");
      const qs = opts.upsertOn ? `?on_conflict=${encodeURIComponent(opts.upsertOn)}` : "";
      return call<T>(`${base}/${encodeURIComponent(table)}${qs}`, { method: "POST", headers: h, body: JSON.stringify(rows as Json) });
    },
    update<T>(table: string, filter: Filter, patch: Record<string, unknown>, opts: { schema?: string } = {}) {
      if (Object.keys(filter).length === 0) throw new Error("refusing an unfiltered update");
      const h = { ...headers(opts.schema ?? "public", true), prefer: "return=representation" };
      return call<T>(`${base}/${encodeURIComponent(table)}?${new URLSearchParams(filter)}`, {
        method: "PATCH",
        headers: h,
        body: JSON.stringify(patch),
      });
    },
  };
}

/** Database access as the signed-in user (RLS applies). */
export const userDb = (accessToken: string, fetcher?: FetchLike) => createDb(accessToken, anonKey(), fetcher);

/** Service-role access. Use only for `server.*` RPCs and steps the user may not do themselves. */
export const serviceDb = (fetcher?: FetchLike) => createDb(serviceRoleKey(), serviceRoleKey(), fetcher);

/** Shorthand for service-only server API calls. */
export const serverRpc = <T>(db: Db, fn: string, args: Record<string, unknown> = {}) => db.rpc<T>(fn, args, { schema: "server" });
