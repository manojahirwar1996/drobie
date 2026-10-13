// The ONLY place that calls paid AI (CLAUDE.md non-negotiable 2).
// Before every call: kill switch, per-user daily budget and global daily cap.
// After every call: usage and cost logged to private.ai_usage.
// Models and prices come from config (ai_route:*, app:ai.model_prices), not code.
import { type Db, serverRpc } from "./db.ts";
import { env } from "./env.ts";
import { HttpError } from "./errors.ts";
import type { ConfigClient } from "./config.ts";
import type { Logger } from "./log.ts";

export class BudgetExceeded extends HttpError {
  constructor(readonly scope: "user" | "global" | "disabled") {
    super(429, "budget_exceeded", "smart answers are resting for today; quick answers still work", { scope });
    this.name = "BudgetExceeded";
  }
}

export type ContentBlock =
  | { type: "text"; text: string }
  | { type: "image"; source: { type: "base64"; media_type: string; data: string } | { type: "url"; url: string } };

export interface ChatMessage {
  role: "user" | "assistant";
  content: string | ContentBlock[];
}

export interface ToolDef {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
}

export interface ChatRequest {
  /** Config route, e.g. "dro.chat" → ai_route:dro.chat */
  route: "dro.chat";
  feature: string;
  userId?: string;
  plan?: string;
  /** Fixed system prompt (cached). Put user data in messages, never here. */
  system: string;
  tools?: ToolDef[];
  messages: ChatMessage[];
  maxTokens?: number;
  /** Override the route's model only for explicit "think harder" requests. */
  model?: string;
  requestId?: string;
}

export interface Usage {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
}

export interface ChatResult {
  text: string;
  toolCalls: { id: string; name: string; input: unknown }[];
  stopReason: string;
  model: string;
  usage: Usage;
  costMinor: number;
  latencyMs: number;
}

export type ModelPrices = Record<string, { input: number; output: number; cache_read?: number; cache_write?: number }>;

/** Cost in paise from per-million-token prices (also in paise). Rounds up so budgets never under-count. */
export function costMinor(model: string, usage: Usage, prices: ModelPrices): number {
  const p = prices[model];
  if (!p) return 0;
  const m = 1_000_000;
  const raw = (usage.input_tokens * p.input) / m + (usage.output_tokens * p.output) / m +
    ((usage.cache_read_input_tokens ?? 0) * (p.cache_read ?? p.input)) / m +
    ((usage.cache_creation_input_tokens ?? 0) * (p.cache_write ?? p.input)) / m;
  return Math.ceil(raw);
}

export interface AiDeps {
  db: Db;
  config: ConfigClient;
  log: Logger;
  fetcher?: (url: string, init: RequestInit) => Promise<Response>;
  sleep?: (ms: number) => Promise<void>;
}

const RETRYABLE = new Set([408, 429, 500, 502, 503, 504, 529]);

export async function checkBudget(deps: AiDeps, userId: string | undefined, plan: string | undefined): Promise<void> {
  if (!(await deps.config.flag("flag:dro_ai", userId ? { userId } : {}))) throw new BudgetExceeded("disabled");
  const cap = await deps.config.get("app:ai.daily_spend_cap_minor");
  const globalSpend = await serverRpc<number>(deps.db, "ai_spend_today", { p_user: null });
  if (globalSpend >= cap) throw new BudgetExceeded("global");
  if (userId) {
    const budgets = await deps.config.get("app:ai.user_daily_budget_minor");
    const budget = budgets[plan ?? "free"] ?? 0;
    const spent = await serverRpc<number>(deps.db, "ai_spend_today", { p_user: userId });
    if (spent >= budget) throw new BudgetExceeded("user");
  }
}

export async function chat(deps: AiDeps, req: ChatRequest): Promise<ChatResult> {
  const fetcher = deps.fetcher ?? fetch;
  const sleep = deps.sleep ?? ((ms: number) => new Promise((r) => setTimeout(r, ms)));
  await checkBudget(deps, req.userId, req.plan);

  const route = await deps.config.get(`ai_route:${req.route}`);
  const tools = req.tools ?? [];
  const model = req.model ?? route.model;
  const body = {
    model,
    max_tokens: Math.min(req.maxTokens ?? route.max_tokens, 4096),
    ...(route.temperature !== undefined ? { temperature: route.temperature } : {}),
    // Prompt caching: fixed system prompt and tool definitions first, marked cacheable.
    system: [{ type: "text", text: req.system, cache_control: { type: "ephemeral" } }],
    // the last tool definition closes the cached prefix
    ...(tools.length
      ? { tools: tools.map((t, i) => (i === tools.length - 1 ? { ...t, cache_control: { type: "ephemeral" } } : t)) }
      : {}),
    messages: req.messages,
  };

  const started = performance.now();
  let res: Response | undefined;
  let lastErr: unknown;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      res = await fetcher("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": env("ANTHROPIC_API_KEY"),
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(30_000),
      });
      if (!RETRYABLE.has(res.status)) break;
      lastErr = new Error(`provider status ${res.status}`);
    } catch (e) {
      lastErr = e;
      res = undefined;
    }
    if (attempt < 2) await sleep(500 * 2 ** attempt + Math.floor(Math.random() * 250));
  }
  const latencyMs = Math.round(performance.now() - started);

  if (!res || !res.ok) {
    await logUsage(deps, req, model, { input_tokens: 0, output_tokens: 0 }, 0, latencyMs, false);
    deps.log.error("ai provider failed", { status: res?.status, error: lastErr });
    throw new HttpError(503, "upstream_unavailable", "smart answers are unavailable right now");
  }

  const out = (await res.json()) as {
    content: ({ type: "text"; text: string } | { type: "tool_use"; id: string; name: string; input: unknown })[];
    stop_reason: string;
    model: string;
    usage: Usage;
  };
  const prices = await deps.config.get("app:ai.model_prices");
  const cost = costMinor(model, out.usage, prices);
  if (!(model in prices)) deps.log.warn("no price configured for model; cost logged as 0", { model });
  await logUsage(deps, req, model, out.usage, cost, latencyMs, true);

  return {
    text: out.content.filter((c): c is { type: "text"; text: string } => c.type === "text").map((c) => c.text).join(""),
    toolCalls: out.content
      .filter((c): c is { type: "tool_use"; id: string; name: string; input: unknown } => c.type === "tool_use")
      .map(({ id, name, input }) => ({ id, name, input })),
    stopReason: out.stop_reason,
    model: out.model ?? model,
    usage: out.usage,
    costMinor: cost,
    latencyMs,
  };
}

async function logUsage(
  deps: AiDeps,
  req: ChatRequest,
  model: string,
  u: Usage,
  cost: number,
  latencyMs: number,
  ok: boolean,
) {
  try {
    await serverRpc(deps.db, "log_ai_usage", {
      p: {
        user_id: req.userId ?? null,
        feature: req.feature,
        step: "ai",
        provider: "anthropic",
        model,
        input_tokens: u.input_tokens,
        output_tokens: u.output_tokens,
        cache_read_tokens: u.cache_read_input_tokens ?? 0,
        cache_write_tokens: u.cache_creation_input_tokens ?? 0,
        cost_minor: cost,
        latency_ms: latencyMs,
        ok,
        request_id: req.requestId ?? null,
      },
    });
  } catch (e) {
    deps.log.error("failed to log ai usage", { error: e });
  }
}

/** Record a step answered without paid AI (rules, cache, device…) so the paid share is measurable. */
export const logFreeStep = (
  db: Db,
  p: {
    userId?: string;
    feature: string;
    step: "rules" | "cache" | "device" | "template" | "embedder";
    requestId?: string;
  },
) =>
  serverRpc(db, "log_ai_usage", {
    p: {
      user_id: p.userId ?? null,
      feature: p.feature,
      step: p.step,
      cost_minor: 0,
      ok: true,
      request_id: p.requestId ?? null,
    },
  });
