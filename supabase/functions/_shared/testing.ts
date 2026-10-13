// Test doubles shared by unit tests (not imported by production code).
import type { Db, Filter } from "./db.ts";
import { DbError } from "./errors.ts";

export interface RpcCall {
  fn: string;
  args: Record<string, unknown>;
  schema: string | undefined;
}

export type RpcHandler = (args: Record<string, unknown>) => unknown;

/** A fake Db whose RPCs are answered by handlers; unknown RPCs throw. */
export function fakeDb(handlers: Record<string, RpcHandler>): Db & { calls: RpcCall[] } {
  const calls: RpcCall[] = [];
  const notImplemented = () => Promise.reject(new Error("not implemented in fakeDb"));
  return {
    calls,
    rpc<T>(fn: string, args: Record<string, unknown> = {}, opts: { schema?: string } = {}): Promise<T> {
      calls.push({ fn, args, schema: opts.schema });
      const h = handlers[fn];
      if (!h) return Promise.reject(new DbError(404, "PGRST202", `no fake for ${fn}`));
      try {
        return Promise.resolve(h(args) as T);
      } catch (e) {
        return Promise.reject(e);
      }
    },
    select: <T>(_t: string, _q: Filter): Promise<T> => notImplemented(),
    insert: <T>(): Promise<T> => notImplemented(),
    update: <T>(): Promise<T> => notImplemented(),
  };
}

/** Silence and capture log lines. */
export function captureLogs() {
  const lines: Record<string, unknown>[] = [];
  return { lines, sink: (line: string) => lines.push(JSON.parse(line)) };
}

export function setEnv(vars: Record<string, string>): () => void {
  const prev: Record<string, string | undefined> = {};
  for (const [k, v] of Object.entries(vars)) {
    prev[k] = Deno.env.get(k);
    Deno.env.set(k, v);
  }
  return () => {
    for (const [k, v] of Object.entries(prev)) v === undefined ? Deno.env.delete(k) : Deno.env.set(k, v);
  };
}
