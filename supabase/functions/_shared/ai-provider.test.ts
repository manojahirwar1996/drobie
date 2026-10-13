import { assert, assertEquals, assertRejects } from "@std/assert";
import { BudgetExceeded, chat, costMinor } from "./ai-provider.ts";
import { ConfigClient, type TargetRule } from "./config.ts";
import { HttpError } from "./errors.ts";
import { createLogger } from "./log.ts";
import { fakeDb, setEnv } from "./testing.ts";

const silent = createLogger({}, () => {});

function setup(opts: { globalSpend?: number; userSpend?: number; flag?: boolean } = {}) {
  const values: Record<string, { value: unknown; targeting: TargetRule[] }> = {
    "flag:dro_ai": { value: { enabled: opts.flag ?? true }, targeting: [] },
    "app:ai.daily_spend_cap_minor": { value: 50000, targeting: [] },
    "app:ai.user_daily_budget_minor": { value: { free: 100, pro: 1500 }, targeting: [] },
    "app:ai.model_prices": { value: { "claude-haiku-5-5": { input: 8000, output: 40000, cache_read: 800, cache_write: 10000 } }, targeting: [] },
    "ai_route:dro.chat": { value: { provider: "anthropic", model: "claude-haiku-5-5", max_tokens: 400 }, targeting: [] },
  };
  const usage: Record<string, unknown>[] = [];
  const db = fakeDb({
    config_version: () => 1,
    config_snapshot: () => ({ version: 1, values }),
    ai_spend_today: (a) => (a.p_user === null ? opts.globalSpend ?? 0 : opts.userSpend ?? 0),
    log_ai_usage: (a) => {
      usage.push(a.p as Record<string, unknown>);
      return null;
    },
  });
  return { db, usage, config: new ConfigClient(() => db) };
}

const okBody = {
  content: [{ type: "text", text: "Wear the maroon kurta." }, { type: "tool_use", id: "t1", name: "mark_worn", input: { item_id: "i1" } }],
  stop_reason: "tool_use",
  model: "claude-haiku-5-5",
  usage: { input_tokens: 1000, output_tokens: 200, cache_read_input_tokens: 3000 },
};
const req = { route: "dro.chat" as const, feature: "dro.chat", userId: "u1", plan: "free", system: "You are dro.", messages: [{ role: "user" as const, content: "what to wear?" }] };

Deno.test("cost from configured per-million prices, rounded up", () => {
  const prices = { m: { input: 8000, output: 40000, cache_read: 800 } };
  assertEquals(costMinor("m", { input_tokens: 1000, output_tokens: 200, cache_read_input_tokens: 3000 }, prices), 19); // 8 + 8 + 2.4 → 19
  assertEquals(costMinor("unknown", { input_tokens: 1, output_tokens: 1 }, prices), 0);
});

Deno.test("budget: kill switch, global cap and per-user budget stop the call before any spend", async () => {
  const restore = setEnv({ ANTHROPIC_API_KEY: "k" });
  try {
    let called = 0;
    const fetcher = () => (called++, Promise.resolve(new Response("{}")));
    for (const [o, scope] of [[{ flag: false }, "disabled"], [{ globalSpend: 50000 }, "global"], [{ userSpend: 100 }, "user"]] as const) {
      const s = setup(o);
      const e = await assertRejects(() => chat({ db: s.db, config: s.config, log: silent, fetcher }, req), BudgetExceeded);
      assertEquals(e.scope, scope);
    }
    assertEquals(called, 0);
  } finally {
    restore();
  }
});

Deno.test("success: prompt caching, retries on overload, usage and cost logged", async () => {
  const restore = setEnv({ ANTHROPIC_API_KEY: "k" });
  try {
    const s = setup();
    const sent: Record<string, unknown>[] = [];
    let n = 0;
    const fetcher = (_url: string, init: RequestInit) => {
      sent.push(JSON.parse(init.body as string));
      n++;
      return Promise.resolve(n === 1 ? new Response("overloaded", { status: 529 }) : new Response(JSON.stringify(okBody)));
    };
    const r = await chat({ db: s.db, config: s.config, log: silent, fetcher, sleep: () => Promise.resolve() }, {
      ...req,
      tools: [{ name: "mark_worn", description: "Mark items worn", input_schema: { type: "object" } }],
    });
    assertEquals(n, 2, "retried once after 529");
    assertEquals(r.text, "Wear the maroon kurta.");
    assertEquals(r.toolCalls, [{ id: "t1", name: "mark_worn", input: { item_id: "i1" } }]);
    const body = sent[0] as { model: string; max_tokens: number; system: { cache_control?: unknown }[]; tools: { cache_control?: unknown }[] };
    assertEquals([body.model, body.max_tokens], ["claude-haiku-5-5", 400]);
    assert(body.system[0]?.cache_control, "system prompt marked cacheable");
    assert(body.tools[0]?.cache_control, "tools marked cacheable");
    assertEquals(s.usage.length, 1);
    assertEquals([s.usage[0]?.step, s.usage[0]?.cost_minor, s.usage[0]?.ok], ["ai", 19, true]);
  } finally {
    restore();
  }
});

Deno.test("provider down: 503 to the caller, failed attempt still logged", async () => {
  const restore = setEnv({ ANTHROPIC_API_KEY: "k" });
  try {
    const s = setup();
    const fetcher = () => Promise.resolve(new Response("down", { status: 503 }));
    const e = await assertRejects(() => chat({ db: s.db, config: s.config, log: silent, fetcher, sleep: () => Promise.resolve() }, req), HttpError);
    assertEquals(e.code, "upstream_unavailable");
    assertEquals(s.usage[0]?.ok, false);
  } finally {
    restore();
  }
});
