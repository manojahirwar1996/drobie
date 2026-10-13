// End-to-end: function handlers → PostgREST → Postgres (RLS on). Run via
// scripts/dev/e2e.sh, which starts PostgREST and sets the env. Skipped otherwise.
import { assert, assertEquals } from "@std/assert";
import { signHs256 } from "../_shared/jwt.ts";
import { registry } from "../_shared/config.ts";
import { handler as health } from "../health/handler.ts";
import { handler as configBundle } from "../config-bundle/handler.ts";
import { handler as me } from "../me/handler.ts";
import { handler as confirmAdult } from "../confirm-adult/handler.ts";
import { handler as setConsent } from "../set-consent/handler.ts";

const enabled = Deno.env.get("E2E") === "1";
const t = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeOps: false, sanitizeResources: false, fn });

async function sql(query: string): Promise<string> {
  const out = await new Deno.Command("psql", {
    args: ["-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-d", Deno.env.get("E2E_DB") ?? "drobie", "-c", query],
    env: { PGUSER: Deno.env.get("PGUSER") ?? "postgres" },
  }).output();
  if (!out.success) throw new Error(new TextDecoder().decode(out.stderr));
  return new TextDecoder().decode(out.stdout).trim();
}

async function newUser(adult: boolean): Promise<{ id: string; token: string }> {
  const id = await sql(`select tests.create_user('e2e-${crypto.randomUUID()}@e2e.test', ${adult})`);
  const token = await signHs256(
    { sub: id, role: "authenticated", aud: "authenticated", aal: "aal1", exp: Math.floor(Date.now() / 1000) + 3600 },
    Deno.env.get("SUPABASE_JWT_SECRET") ?? "",
  );
  return { id, token };
}

const req = (method: string, token: string | undefined, body?: unknown, headers: Record<string, string> = {}) =>
  new Request("http://fn.local/", {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body !== undefined ? { "content-type": "application/json" } : {}),
      "x-forwarded-for": `10.0.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`,
      ...headers,
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });

const rest = () => Deno.env.get("SUPABASE_REST_URL") ?? "";

t("health: liveness open, deep check needs the service key", async () => {
  assertEquals((await health(req("GET", undefined))).status, 200);
  const deepAnon = await health(new Request("http://fn.local/?deep=1"));
  assertEquals(deepAnon.status, 401);
  const deep = await health(
    new Request("http://fn.local/?deep=1", {
      headers: { authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}` },
    }),
  );
  const body = await deep.json();
  assertEquals([deep.status, body.data.db.ok], [200, true]);
});

t("config-bundle: ETag + 304, only client-visible keys", async () => {
  const first = await configBundle(new Request("http://fn.local/?locale=en-IN"));
  assertEquals(first.status, 200);
  const etag = first.headers.get("etag") ?? "";
  const body = await first.json();
  assert(body.data.values["flag:dro_ai"], "flags are in the bundle");
  assertEquals(body.data.values["app:ai.daily_spend_cap_minor"], undefined, "server-only keys are not");
  const again = await configBundle(
    new Request("http://fn.local/?locale=en-IN", { headers: { "if-none-match": etag } }),
  );
  assertEquals(again.status, 304);
  assertEquals((await configBundle(new Request("http://fn.local/?locale=../../x"))).status, 400);
});

t("config registry in code matches the database registry and its schemas", async () => {
  const snap = JSON.parse(await sql("select server.config_snapshot('en-IN')")) as {
    values: Record<string, { value: unknown }>;
  };
  for (const [key, def] of Object.entries(registry)) {
    const entry = snap.values[key];
    assert(entry, `config key ${key} is declared in code but missing in the database`);
    assert(def.schema.safeParse(entry.value).success, `database value for ${key} fails the code schema`);
  }
});

t("onboarding: me → confirm adult → update profile, all through RLS", async () => {
  const u = await newUser(false);
  const r1 = await me(req("GET", u.token));
  const b1 = await r1.json();
  assertEquals(r1.status, 200);
  assertEquals(b1.data.needs.adult_confirmation, true);
  assertEquals(b1.data.plan, "free");
  assertEquals(b1.data.features["closet.max_items"].limit, 40);
  assertEquals(b1.data.households.length, 1);
  assertEquals(b1.data.households[0].role, "owner");
  assertEquals(b1.data.wallets, []);

  const blocked = await me(req("PATCH", u.token, { display_name: "Aanya" }));
  assertEquals([blocked.status, (await blocked.json()).error.code], [403, "adult_confirmation_required"]);

  const c = await confirmAdult(req("POST", u.token));
  assertEquals(c.status, 200);
  assert((await c.json()).data.adult_confirmed_at);

  const p = await me(req("PATCH", u.token, { display_name: "Aanya", morning_time: "08:15" }));
  const pb = await p.json();
  assertEquals([p.status, pb.data.profile.display_name, pb.data.profile.morning_time], [200, "Aanya", "08:15:00"]);

  const sneaky = await me(req("PATCH", u.token, { status: "active", plan: "ultimate" }));
  assertEquals([sneaky.status, (await sneaky.json()).error.code], [400, "validation_failed"]);
  const badTz = await me(req("PATCH", u.token, { timezone: "Mars/Olympus" }));
  assertEquals(
    [badTz.status, (await badTz.json()).error.code],
    [400, "validation_failed"],
    "database message passes through",
  );
});

t("set-consent: versions enforced, withdrawal deletes measurements", async () => {
  const u = await newUser(true);
  const stale = await setConsent(
    req("POST", u.token, { consents: [{ consent_type: "gallery", granted: true, version: "0.1" }] }),
  );
  assertEquals([stale.status, (await stale.json()).error.code], [409, "conflict"]);

  const okRes = await setConsent(req("POST", u.token, {
    consents: [{ consent_type: "measurements", granted: true, version: "1.0" }, {
      consent_type: "gallery",
      granted: true,
      version: "1.0",
    }],
  }));
  const okBody = await okRes.json();
  assertEquals([okRes.status, okBody.data.changed, okBody.data.current.gallery.granted], [200, 2, true]);

  await sql(`insert into public.body_profiles (user_id, height_cm) values ('${u.id}', 168)`);
  await setConsent(
    req("POST", u.token, { consents: [{ consent_type: "measurements", granted: false, version: "1.0" }] }),
  );
  assertEquals(await sql(`select count(*) from public.body_profiles where user_id = '${u.id}'`), "0");

  const bad = await setConsent(
    req("POST", u.token, { consents: [{ consent_type: "dna", granted: true, version: "1.0" }] }),
  );
  assertEquals(bad.status, 400);
});

t("rate limit: confirm-adult refuses bursts with Retry-After", async () => {
  const u = await newUser(true);
  const statuses: number[] = [];
  for (let i = 0; i < 12; i++) {
    statuses.push((await confirmAdult(req("POST", u.token, undefined, { "x-forwarded-for": "10.9.9.9" }))).status);
  }
  assertEquals(statuses.filter((s) => s === 200).length, 10);
  const limited = await confirmAdult(req("POST", u.token, undefined, { "x-forwarded-for": "10.9.9.9" }));
  assertEquals(limited.status, 429);
  assert(limited.headers.get("retry-after"));
});

t("Data API guardrails: clients cannot reach server.*, other users' rows, or anything as anon", async () => {
  const a = await newUser(true);
  const b = await newUser(true);
  await sql(`insert into public.items (owner_user_id, name) values ('${b.id}', 'B private kurta')`);
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  const asA = (path: string, init: RequestInit = {}) =>
    fetch(`${rest()}${path}`, {
      ...init,
      headers: {
        apikey: anon,
        authorization: `Bearer ${a.token}`,
        "content-type": "application/json",
        ...(init.headers ?? {}),
      },
    });

  const items = await asA(`/items?owner_user_id=eq.${b.id}&select=id`);
  assertEquals([items.status, await items.json()], [200, []], "RLS hides B's items from A");

  const rpc = await asA("/rpc/consume_quota", {
    method: "POST",
    headers: { "content-profile": "server" },
    body: JSON.stringify({ p_user: a.id, p_feature_key: "dro.chats" }),
  });
  assert([401, 403, 406].includes(rpc.status), `server schema must be closed to users (got ${rpc.status})`);
  await rpc.body?.cancel();

  const plant = await asA("/items", { method: "POST", body: JSON.stringify({ owner_user_id: b.id, name: "planted" }) });
  assertEquals(plant.status, 403, "cannot write into someone else's closet");
  await plant.body?.cancel();

  const grant = await asA("/entitlement_grants", {
    method: "POST",
    body: JSON.stringify({ user_id: a.id, source: "admin" }),
  });
  assert([401, 403].includes(grant.status), "cannot grant yourself a plan");
  await grant.body?.cancel();

  const asAnon = await fetch(`${rest()}/items?select=id`, {
    headers: { apikey: anon, authorization: `Bearer ${anon}` },
  });
  assert([401, 403].includes(asAnon.status), "anon cannot read items");
  await asAnon.body?.cancel();
  const taxonomy = await fetch(`${rest()}/categories?select=slug&limit=1`, {
    headers: { apikey: anon, authorization: `Bearer ${anon}` },
  });
  assertEquals(taxonomy.status, 200, "anon can read the taxonomy");
  await taxonomy.body?.cancel();
});
