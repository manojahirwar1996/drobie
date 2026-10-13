import { assertEquals } from "@std/assert";
import { defineHandler, ok } from "./http.ts";
import { withIdempotency } from "./idempotency.ts";
import { fakeDb, setEnv } from "./testing.ts";

Deno.test("idempotency: new → run once, replay → stored response, mismatch → 422, busy → 409", async () => {
  const store = new Map<string, { hash: string; status?: number; response?: unknown }>();
  const db = fakeDb({
    idempotency_begin: (a) => {
      const k = String(a.p_key);
      const e = store.get(k);
      if (!e) {
        store.set(k, { hash: String(a.p_request_hash) });
        return { state: "new" };
      }
      if (e.hash !== a.p_request_hash) return { state: "mismatch" };
      return e.status ? { state: "completed", response_status: e.status, response: e.response } : { state: "in_progress" };
    },
    idempotency_complete: (a) => {
      const e = store.get(String(a.p_key));
      if (e) Object.assign(e, { status: a.p_status, response: a.p_response });
      return null;
    },
    idempotency_release: (a) => (store.delete(String(a.p_key)), null),
  });
  const restore = setEnv({ SUPABASE_URL: "http://x", SUPABASE_SERVICE_ROLE_KEY: "s", SUPABASE_ANON_KEY: "a" });
  let runs = 0;
  const h = defineHandler("create", { methods: ["POST"] }, (ctx) => {
    ctx.service = () => db;
    return withIdempotency(ctx, "u1", () => {
      runs++;
      return Promise.resolve(ok({ created: runs }, 201));
    });
  });
  const send = (body: string, key = "key-abcdef12") =>
    h(new Request("http://x", { method: "POST", body, headers: { "idempotency-key": key } }));
  try {
    const first = await send('{"a":1}');
    assertEquals([first.status, await first.json()], [201, { data: { created: 1 } }]);
    const replay = await send('{"a":1}');
    assertEquals([replay.status, await replay.json(), replay.headers.get("idempotent-replayed")], [201, { data: { created: 1 } }, "true"]);
    assertEquals(runs, 1);
    assertEquals((await send('{"a":2}')).status, 422);
    store.set("key-busy0001", { hash: "x" });
    assertEquals((await send('{"a":1}', "key-busy0001")).status, 422, "different body on a busy key");
    assertEquals((await send('{"a":1}', "bad key!")).status, 400);
  } finally {
    restore();
  }
});
