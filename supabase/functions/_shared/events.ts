// Outbox events and queue consumers. Writes that matter emit their event in
// the same transaction in SQL (private.emit); functions emit through
// server.emit only for events that have no database write of their own.
import { type Db, serverRpc } from "./db.ts";
import type { Logger } from "./log.ts";

export const emit = (
  db: Db,
  type: string,
  aggregate: string,
  aggregateId: string | null,
  payload: Record<string, unknown> = {},
  actor?: string,
) =>
  serverRpc<string>(db, "emit", {
    p_type: type,
    p_aggregate: aggregate,
    p_aggregate_id: aggregateId,
    p_payload: payload,
    p_actor: actor ?? null,
  });

export interface QueueMessage<T = Record<string, unknown>> {
  msg_id: number;
  read_ct: number;
  enqueued_at: string;
  message: T;
}

export interface ConsumeOptions {
  /** Seconds a message stays hidden while being processed. */
  visibilitySeconds?: number;
  batchSize?: number;
  /** After this many failed reads the message goes to the dead_letter queue. */
  maxAttempts?: number;
  /** Base backoff in seconds; doubles each attempt (capped at 1 hour). */
  backoffSeconds?: number;
}

export interface ConsumeReport {
  processed: number;
  retried: number;
  deadLettered: number;
}

export function backoffSeconds(attempt: number, base: number): number {
  return Math.min(3600, base * 2 ** Math.max(0, attempt - 1));
}

/**
 * Process one batch. Handlers must be idempotent: a message can be delivered
 * more than once (visibility timeout expiry, crashes).
 */
export async function consumeBatch<T>(
  db: Db,
  queue: string,
  handle: (msg: QueueMessage<T>) => Promise<void>,
  log: Logger,
  opts: ConsumeOptions = {},
): Promise<ConsumeReport> {
  const { visibilitySeconds = 60, batchSize = 10, maxAttempts = 5, backoffSeconds: base = 30 } = opts;
  const msgs = await serverRpc<QueueMessage<T>[]>(db, "queue_read", {
    p_queue: queue,
    p_visibility_seconds: visibilitySeconds,
    p_qty: batchSize,
  });
  const report: ConsumeReport = { processed: 0, retried: 0, deadLettered: 0 };
  for (const m of msgs) {
    try {
      await handle(m);
      await serverRpc(db, "queue_delete", { p_queue: queue, p_msg_id: m.msg_id });
      report.processed++;
    } catch (e) {
      if (m.read_ct >= maxAttempts) {
        await serverRpc(db, "queue_send", {
          p_queue: "dead_letter",
          p_message: {
            queue,
            msg_id: m.msg_id,
            attempts: m.read_ct,
            error: String((e as Error).message ?? e),
            message: m.message,
          },
        });
        await serverRpc(db, "queue_archive", { p_queue: queue, p_msg_id: m.msg_id });
        report.deadLettered++;
        log.error("message dead-lettered", { queue, msg_id: m.msg_id, attempts: m.read_ct });
      } else {
        await serverRpc(db, "queue_set_vt", {
          p_queue: queue,
          p_msg_id: m.msg_id,
          p_seconds: backoffSeconds(m.read_ct, base),
        });
        report.retried++;
        log.warn("message failed, will retry", { queue, msg_id: m.msg_id, attempt: m.read_ct });
      }
    }
  }
  return report;
}
