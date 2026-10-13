import { assertEquals } from "@std/assert";
import { backoffSeconds, consumeBatch, type QueueMessage } from "./events.ts";
import { createLogger } from "./log.ts";
import { fakeDb } from "./testing.ts";

const silent = createLogger({}, () => {});

Deno.test("backoff doubles per attempt and is capped", () => {
  assertEquals([1, 2, 3, 4].map((a) => backoffSeconds(a, 30)), [30, 60, 120, 240]);
  assertEquals(backoffSeconds(20, 30), 3600);
});

Deno.test("consumeBatch: success deletes, failure backs off, repeated failure dead-letters", async () => {
  const msgs: QueueMessage<{ n: number }>[] = [
    { msg_id: 1, read_ct: 1, enqueued_at: "", message: { n: 1 } },
    { msg_id: 2, read_ct: 2, enqueued_at: "", message: { n: 2 } },
    { msg_id: 3, read_ct: 5, enqueued_at: "", message: { n: 3 } },
  ];
  const db = fakeDb({
    queue_read: () => msgs,
    queue_delete: () => true,
    queue_set_vt: () => true,
    queue_send: () => 99,
    queue_archive: () => true,
  });
  const report = await consumeBatch<{ n: number }>(
    db,
    "search",
    (m) => {
      if (m.message.n !== 1) throw new Error("boom");
      return Promise.resolve();
    },
    silent,
    { maxAttempts: 5, backoffSeconds: 30 },
  );
  assertEquals(report, { processed: 1, retried: 1, deadLettered: 1 });
  const byFn = (fn: string) => db.calls.filter((c) => c.fn === fn).map((c) => c.args);
  assertEquals(byFn("queue_delete"), [{ p_queue: "search", p_msg_id: 1 }]);
  assertEquals(byFn("queue_set_vt"), [{ p_queue: "search", p_msg_id: 2, p_seconds: 60 }]);
  assertEquals(byFn("queue_send")[0]?.p_queue, "dead_letter");
  assertEquals(byFn("queue_archive"), [{ p_queue: "search", p_msg_id: 3 }]);
});
