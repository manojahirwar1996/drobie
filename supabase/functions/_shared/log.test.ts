import { assert, assertEquals } from "@std/assert";
import { createLogger, hashUserId, scrub } from "./log.ts";
import { captureLogs } from "./testing.ts";

Deno.test("scrub removes PII keys and masks emails and phone numbers", () => {
  const out = scrub({
    email: "a@b.com",
    holder_name: "Riya",
    note: "mail riya@example.in or call +91 9876543210",
    nested: { Authorization: "Bearer x", ok: 1 },
  }) as Record<string, unknown>;
  assertEquals(out.email, "[redacted]");
  assertEquals(out.holder_name, "[redacted]");
  assertEquals(out.note, "mail [email] or call [phone]");
  assertEquals(out.nested, { Authorization: "[redacted]", ok: 1 });
});

Deno.test("logger writes one JSON object per line with base fields", () => {
  const cap = captureLogs();
  createLogger({ fn: "t", request_id: "r1" }, cap.sink).with({ user: "abc" }).info("hello", { email: "x@y.z" });
  const line = cap.lines[0] as Record<string, unknown>;
  assertEquals([line.fn, line.request_id, line.user, line.msg, line.email], ["t", "r1", "abc", "hello", "[redacted]"]);
  assert(typeof line.ts === "string");
});

Deno.test("user ids are hashed stably and never logged raw", async () => {
  const a = await hashUserId("00000000-0000-4000-a000-00000000a11c");
  assertEquals(a, await hashUserId("00000000-0000-4000-a000-00000000a11c"));
  assertEquals(a.length, 16);
  assert(!a.includes("a11c"));
});
