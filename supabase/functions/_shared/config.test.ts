import { assert, assertEquals } from "@std/assert";
import { compareSemver, ConfigClient, resolveTargeting, rolloutBucket, type TargetRule } from "./config.ts";
import { fakeDb } from "./testing.ts";

function snapshotDb(state: { version: number; values: Record<string, { value: unknown; targeting: TargetRule[] }> }) {
  return fakeDb({
    config_version: () => state.version,
    config_snapshot: () => structuredClone(state),
  });
}

Deno.test("targeting: most specific matching rule wins; ties go to the first", () => {
  const rules: TargetRule[] = [
    { when: { country: ["IN"] }, value: "india" },
    { when: { country: ["IN"], platform: ["ios"] }, value: "india-ios" },
    { when: { platform: ["ios"] }, value: "ios" },
  ];
  assertEquals(resolveTargeting("k", "base", rules, { country: "IN", platform: "ios" }), "india-ios");
  assertEquals(resolveTargeting("k", "base", rules, { country: "IN", platform: "android" }), "india");
  assertEquals(resolveTargeting("k", "base", rules, { country: "US" }), "base");
});

Deno.test("targeting: app version, plan, experiment and rollout", () => {
  const rules: TargetRule[] = [{ when: { min_app_version: "1.2.0", plan: ["pro"] }, value: "new" }];
  assertEquals(resolveTargeting("k", "old", rules, { appVersion: "1.10.0", plan: "pro" }), "new");
  assertEquals(resolveTargeting("k", "old", rules, { appVersion: "1.1.9", plan: "pro" }), "old");
  assertEquals(resolveTargeting("k", "a", [{ when: { experiment: { key: "paywall", variant: "b" } }, value: "b" }], {
    experiments: { paywall: "b" },
  }), "b");
  assertEquals(compareSemver("1.10.0", "1.9.9"), 1);
  // rollout is stable per user and roughly proportional
  const inRollout = Array.from({ length: 2000 }, (_, i) => rolloutBucket(`flag:x:user-${i}`) < 20).filter(Boolean).length;
  assert(inRollout > 300 && inRollout < 500, `20% rollout gave ${inRollout}/2000`);
  assertEquals(rolloutBucket("flag:x:u1"), rolloutBucket("flag:x:u1"));
});

Deno.test("get: typed value, invalid value falls back to default, missing key falls back", async () => {
  const db = snapshotDb({
    version: 1,
    values: {
      "app:ai.daily_spend_cap_minor": { value: 80000, targeting: [] },
      "app:credits.web_bonus_pct": { value: "lots", targeting: [] },
    },
  });
  const c = new ConfigClient(() => db);
  assertEquals(await c.get("app:ai.daily_spend_cap_minor"), 80000);
  assertEquals(await c.get("app:credits.web_bonus_pct"), 0, "invalid → default");
  assertEquals(await c.get("app:maintenance"), { enabled: false }, "missing → default");
});

Deno.test("config fetch failure: nothing that costs money runs (safe defaults)", async () => {
  const c = new ConfigClient(() => fakeDb({}));
  assertEquals(await c.flag("flag:dro_ai", { userId: "u" }), false);
  assertEquals(await c.get("app:ai.daily_spend_cap_minor"), 0);
});

Deno.test("cache: refreshes only when the config version changes; rollback is picked up", async () => {
  const state = { version: 1, values: { "copy:paywall.title": { value: "v1", targeting: [] as TargetRule[] } } };
  const db = snapshotDb(state);
  let t = 0;
  const c = new ConfigClient(() => db, undefined, 60_000, () => t);
  assertEquals(await c.copy("copy:paywall.title"), "v1");
  state.values["copy:paywall.title"].value = "v2";
  t = 30_000;
  assertEquals(await c.copy("copy:paywall.title"), "v1", "within TTL: cached");
  t = 61_000; // TTL passed but version unchanged → no refetch
  assertEquals(await c.copy("copy:paywall.title"), "v1");
  state.version = 2; // publish (or rollback) bumps the version
  t = 130_000;
  assertEquals(await c.copy("copy:paywall.title"), "v2");
  assertEquals(db.calls.filter((x) => x.fn === "config_snapshot").length, 2);
});

Deno.test("flags: enabled + percentage rollout", async () => {
  const db = snapshotDb({ version: 1, values: { "flag:try_on": { value: { enabled: true, rollout_pct: 0 }, targeting: [] } } });
  const c = new ConfigClient(() => db);
  assertEquals(await c.flag("flag:try_on", { userId: "u1" }), false);
});
