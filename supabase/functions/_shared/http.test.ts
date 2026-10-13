import { assert, assertEquals } from "@std/assert";
import { defineHandler, ok } from "./http.ts";
import { DbError, HttpError } from "./errors.ts";
import { setEnv } from "./testing.ts";

const echo = defineHandler("echo", { methods: ["POST"], maxBodyBytes: 100 }, async (ctx) => ok({ got: await ctx.json() }, 201));

const post = (body: string, headers: Record<string, string> = {}) =>
  new Request("http://x/echo", { method: "POST", body, headers: { "content-type": "application/json", ...headers } });

Deno.test("success uses the { data } envelope and echoes the request id", async () => {
  const res = await echo(post('{"a":1}', { "x-request-id": "req-123" }));
  assertEquals(res.status, 201);
  assertEquals(await res.json(), { data: { got: { a: 1 } } });
  assertEquals(res.headers.get("x-request-id"), "req-123");
  assertEquals(res.headers.get("cache-control"), "no-store");
});

Deno.test("wrong method → 405; bad JSON → 400; too large → 413", async () => {
  const r405 = await echo(new Request("http://x/echo", { method: "GET" }));
  assertEquals(r405.status, 405);
  assertEquals(r405.headers.get("allow"), "POST");
  const r400 = await echo(post("{nope"));
  assertEquals((await r400.json()).error.code, "bad_request");
  const r413 = await echo(post(JSON.stringify({ big: "x".repeat(200) })));
  assertEquals(r413.status, 413);
  assertEquals((await r413.json()).error.code, "payload_too_large");
});

Deno.test("unexpected errors become a generic 500 without internals", async () => {
  const boom = defineHandler("boom", { methods: ["GET"] }, () => {
    throw new Error("password=hunter2 at db.ts:42");
  });
  const res = await boom(new Request("http://x", { method: "GET" }));
  assertEquals(res.status, 500);
  const text = await res.text();
  assert(!text.includes("hunter2") && !text.includes("db.ts"));
});

Deno.test("database errors are mapped to client-safe codes", async () => {
  const cases: [DbError, number, string][] = [
    [new DbError(403, "42501", "permission denied for table items"), 403, "forbidden"],
    [new DbError(400, "23514", "places nest at most 6 deep"), 400, "validation_failed"],
    [new DbError(400, "P0001", "item limit reached (40)", "limit_reached:closet.max_items"), 403, "limit_reached"],
    [new DbError(500, "XX000", "internal secret detail"), 502, "upstream_unavailable"],
  ];
  for (const [err, status, code] of cases) {
    const h = defineHandler("db", { methods: ["GET"] }, () => Promise.reject(err));
    const res = await h(new Request("http://x", { method: "GET" }));
    const body = await res.json();
    assertEquals([res.status, body.error.code], [status, code]);
    assert(!JSON.stringify(body).includes("internal secret"));
  }
});

Deno.test("HttpError headers pass through (e.g. Retry-After)", async () => {
  const h = defineHandler("rl", { methods: ["GET"] }, () => Promise.reject(new HttpError(429, "rate_limited", "slow", undefined, { "retry-after": "3" })));
  const res = await h(new Request("http://x", { method: "GET" }));
  assertEquals([res.status, res.headers.get("retry-after")], [429, "3"]);
});

Deno.test("CORS only for our origins; other browsers' preflights are refused", async () => {
  const restore = setEnv({ ALLOWED_ORIGINS: "https://drobie.app" });
  try {
    const pre = await echo(new Request("http://x", { method: "OPTIONS", headers: { origin: "https://drobie.app" } }));
    assertEquals([pre.status, pre.headers.get("access-control-allow-origin")], [204, "https://drobie.app"]);
    const evil = await echo(new Request("http://x", { method: "OPTIONS", headers: { origin: "https://evil.example" } }));
    assertEquals([evil.status, evil.headers.get("access-control-allow-origin")], [403, null]);
    const app = await echo(post("{}")); // mobile apps send no Origin
    assertEquals(app.status, 201);
  } finally {
    restore();
  }
});
