// Config registry + typed reads (PLATFORM_ARCHITECTURE §8.2).
// Every key is declared ONCE here with a Zod schema and a safe default. Values
// come from the versioned config store (server.config_snapshot), cached per
// instance and refreshed when the config version changes (checked every 60 s).
// Bad or missing config never breaks a request: the default is used instead.
import { z } from "zod";
import { type Db, serverRpc } from "./db.ts";
import type { Logger } from "./log.ts";

const flagSchema = z.object({ enabled: z.boolean(), rollout_pct: z.number().int().min(0).max(100).optional() });
const semver = z.string().regex(/^\d+\.\d+\.\d+$/);

export const registry = {
  "app:min_app_version": {
    schema: z.object({ ios: semver, android: semver, message: z.string().optional() }),
    default: { ios: "1.0.0", android: "1.0.0" },
  },
  "app:maintenance": {
    schema: z.object({ enabled: z.boolean(), message: z.string().optional() }),
    default: { enabled: false },
  },
  "app:consent_versions": { schema: z.record(z.string()), default: { terms: "1.0", privacy: "1.0" } },
  "app:ai.daily_spend_cap_minor": { schema: z.number().int().min(0), default: 0 },
  "app:ai.user_daily_budget_minor": {
    schema: z.record(z.number().int().min(0)),
    default: {} as Record<string, number>,
  },
  "app:ai.tag_confidence_threshold": { schema: z.number().min(0).max(1), default: 0.6 },
  "app:ai.model_prices": {
    schema: z.record(
      z.object({
        input: z.number(),
        output: z.number(),
        cache_read: z.number().optional(),
        cache_write: z.number().optional(),
      }),
    ),
    default: {} as Record<string, { input: number; output: number; cache_read?: number; cache_write?: number }>,
  },
  "app:credits.free_looks": {
    schema: z.object({ amount: z.number().int(), min_items: z.number().int() }),
    default: { amount: 0, min_items: 30 },
  },
  "app:credits.web_bonus_pct": { schema: z.number().int().min(0).max(100), default: 0 },
  "app:founding.offer": {
    schema: z.object({ enabled: z.boolean(), max_users: z.number().int(), pro_months: z.number().int().optional() }),
    default: { enabled: false, max_users: 0 },
  },
  "limit:upload.max_bytes": {
    schema: z.record(z.number().int().positive()),
    default: { master: 614400, display: 204800, thumb: 61440 },
  },
  "limit:rate.default": {
    schema: z.object({ capacity: z.number().positive(), refill_per_sec: z.number().positive() }),
    default: { capacity: 60, refill_per_sec: 1 },
  },
  "flag:dro_ai": { schema: flagSchema, default: { enabled: false } },
  "flag:email_import": { schema: flagSchema, default: { enabled: false } },
  "flag:generate_look": { schema: flagSchema, default: { enabled: false } },
  "flag:try_on": { schema: flagSchema, default: { enabled: false } },
  "copy:paywall.title": { schema: z.string().min(1), default: "Go further with drobie" },
  "copy:paywall.subtitle": { schema: z.string(), default: "" },
  "ai_route:dro.chat": {
    schema: z.object({
      provider: z.literal("anthropic"),
      model: z.string().min(3),
      max_tokens: z.number().int(),
      temperature: z.number().optional(),
    }),
    default: { provider: "anthropic" as const, model: "claude-haiku-5-5", max_tokens: 400 },
  },
} as const;
// Safe defaults: AI spend cap 0 and kill switches off — if config cannot be
// read, nothing that costs money runs.

export type ConfigKey = keyof typeof registry;
export type ConfigValue<K extends ConfigKey> = z.infer<(typeof registry)[K]["schema"]>;
export type FlagKey = { [K in ConfigKey]: K extends `flag:${string}` ? K : never }[ConfigKey];
export type CopyKey = { [K in ConfigKey]: K extends `copy:${string}` ? K : never }[ConfigKey];

/** Request context used for targeting. */
export interface TargetCtx {
  userId?: string;
  country?: string;
  city?: string;
  platform?: string;
  appVersion?: string;
  plan?: string;
  segments?: string[];
  experiments?: Record<string, string>;
}

export interface TargetRule {
  when: {
    country?: string[];
    city?: string[];
    platform?: string[];
    min_app_version?: string;
    plan?: string[];
    segment?: string[];
    experiment?: { key: string; variant: string };
    rollout_pct?: number;
  };
  value: unknown;
}

interface Entry {
  value: unknown;
  targeting: TargetRule[];
}

export function compareSemver(a: string, b: string): number {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return Math.sign(d);
  }
  return 0;
}

/** Stable 0–99 bucket for percentage rollouts (FNV-1a). */
export function rolloutBucket(seed: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < seed.length; i++) {
    h ^= seed.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0) % 100;
}

function matches(rule: TargetRule, key: string, ctx: TargetCtx): boolean {
  const w = rule.when;
  const inList = (list: string[] | undefined, v: string | undefined) => !list || (v !== undefined && list.includes(v));
  if (
    !inList(w.country, ctx.country) || !inList(w.city, ctx.city) || !inList(w.platform, ctx.platform) ||
    !inList(w.plan, ctx.plan)
  ) {
    return false;
  }
  if (w.segment && !w.segment.some((s) => ctx.segments?.includes(s))) return false;
  if (w.min_app_version && (!ctx.appVersion || compareSemver(ctx.appVersion, w.min_app_version) < 0)) return false;
  if (w.experiment && ctx.experiments?.[w.experiment.key] !== w.experiment.variant) return false;
  if (w.rollout_pct !== undefined) {
    if (!ctx.userId) return false;
    if (rolloutBucket(`${key}:${ctx.userId}`) >= w.rollout_pct) return false;
  }
  return true;
}

/** Most specific matching override wins (most conditions); ties go to the earlier rule. */
export function resolveTargeting(key: string, base: unknown, rules: TargetRule[], ctx: TargetCtx): unknown {
  let best: { score: number; value: unknown } | undefined;
  for (const r of rules) {
    if (!r || typeof r !== "object" || !r.when) continue;
    if (!matches(r, key, ctx)) continue;
    const score = Object.keys(r.when).length;
    if (!best || score > best.score) best = { score, value: r.value };
  }
  return best ? best.value : base;
}

interface Snapshot {
  version: number;
  values: Record<string, Entry>;
}
interface CacheSlot {
  snapshot?: Snapshot;
  checkedAt: number;
}

export class ConfigClient {
  private slots = new Map<string, CacheSlot>();
  constructor(
    private db: () => Db,
    private log?: Logger,
    private ttlMs = 60_000,
    private now: () => number = Date.now,
  ) {}

  private async snapshot(locale: string): Promise<Snapshot | undefined> {
    const slot = this.slots.get(locale) ?? { checkedAt: 0 };
    if (slot.snapshot && this.now() - slot.checkedAt < this.ttlMs) return slot.snapshot;
    try {
      if (slot.snapshot) {
        const v = await serverRpc<number>(this.db(), "config_version");
        if (v === slot.snapshot.version) {
          slot.checkedAt = this.now();
          this.slots.set(locale, slot);
          return slot.snapshot;
        }
      }
      slot.snapshot = await serverRpc<Snapshot>(this.db(), "config_snapshot", { p_locale: locale });
      slot.checkedAt = this.now();
      this.slots.set(locale, slot);
    } catch (e) {
      this.log?.warn("config fetch failed; using last good values or defaults", { error: e });
    }
    return slot.snapshot;
  }

  /** Typed, validated, targeted value. Falls back to the registry default. */
  async get<K extends ConfigKey>(key: K, ctx: TargetCtx = {}, locale = "en-IN"): Promise<ConfigValue<K>> {
    const def = registry[key];
    const snap = await this.snapshot(locale);
    const entry = snap?.values[key];
    if (!entry) return def.default as ConfigValue<K>;
    const raw = resolveTargeting(key, entry.value, Array.isArray(entry.targeting) ? entry.targeting : [], ctx);
    const parsed = def.schema.safeParse(raw);
    if (!parsed.success) {
      this.log?.warn("invalid config value; using default", { key });
      return def.default as ConfigValue<K>;
    }
    return parsed.data as ConfigValue<K>;
  }

  /** Feature flag with % rollout (stable per user). */
  async flag(key: FlagKey, ctx: TargetCtx = {}): Promise<boolean> {
    const f = await this.get(key, ctx);
    if (!f.enabled) return false;
    if (f.rollout_pct === undefined || f.rollout_pct >= 100) return true;
    return ctx.userId !== undefined && rolloutBucket(`${key}:${ctx.userId}`) < f.rollout_pct;
  }

  /** User-facing copy in the caller's locale (falls back to '*', then the bundled default). */
  copy(key: CopyKey, locale = "en-IN"): Promise<string> {
    return this.get(key, {}, locale);
  }

  /** For tests and the config-bundle function. */
  async version(locale = "en-IN"): Promise<number | undefined> {
    return (await this.snapshot(locale))?.version;
  }
}
