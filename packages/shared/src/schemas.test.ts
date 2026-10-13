import { assert, assertEquals } from "@std/assert";
import { accessGrantInsert, consentInput, itemInsert, itemUpdate, setConsentsRequest, wearLogInsert } from "./schemas.ts";
import { CONSENT_TYPES, GRANT_SCOPES, ITEM_STATES, PLACE_KINDS } from "./enums.ts";

const migrationsDir = new URL("../../../supabase/migrations/", import.meta.url);
async function migrationsSql(): Promise<string> {
  let sql = "";
  for await (const e of Deno.readDir(migrationsDir)) {
    if (e.name.endsWith(".sql")) sql += await Deno.readTextFile(new URL(e.name, migrationsDir));
  }
  return sql;
}

Deno.test("enums match the database definitions", async () => {
  const sql = await migrationsSql();
  const quoted = (xs: readonly string[]) => xs.map((x) => `'${x}'`).join(", ");
  assert(sql.includes(`create type public.item_state as enum (\n  ${quoted(ITEM_STATES)}`), "item_state enum drifted");
  assert(sql.includes(quoted(GRANT_SCOPES)), "grant_scope enum drifted");
  assert(sql.includes(quoted(PLACE_KINDS)), "places.kind check drifted");
  for (const c of CONSENT_TYPES) assert(sql.includes(`'${c}'`), `consent type ${c} missing in SQL`);
});

Deno.test("itemInsert accepts a minimal item and an offline id", () => {
  const r = itemInsert.safeParse({ id: "0192a3b4-c5d6-7e8f-9a0b-1c2d3e4f5a6b", name: "Blue kurta" });
  assert(r.success);
});

Deno.test("itemInsert rejects unknown fields (no smuggling owner or counters)", () => {
  for (const extra of [{ owner_user_id: crypto.randomUUID() }, { wear_count: 9 }, { search: "x" }]) {
    assertEquals(itemInsert.safeParse({ name: "x", ...extra }).success, false);
  }
});

Deno.test("item holder only when lent", () => {
  assertEquals(itemInsert.safeParse({ name: "x", state: "clean", holder_name: "Riya" }).success, false);
  assert(itemInsert.safeParse({ name: "x", state: "lent", holder_name: "Riya", due_back_on: "2026-11-01" }).success);
});

Deno.test("itemUpdate needs at least one field", () => {
  assertEquals(itemUpdate.safeParse({}).success, false);
  assert(itemUpdate.safeParse({ state: "worn" }).success);
});

Deno.test("consents: valid types, one per type", () => {
  assert(consentInput.safeParse({ consent_type: "gallery", granted: true, version: "1.0" }).success);
  assertEquals(consentInput.safeParse({ consent_type: "dna", granted: true, version: "1.0" }).success, false);
  const dup = { consent_type: "gallery", granted: true, version: "1.0" };
  assertEquals(setConsentsRequest.safeParse({ consents: [dup, dup] }).success, false);
});

Deno.test("wear log needs items", () => {
  assertEquals(wearLogInsert.safeParse({ worn_on: "2026-10-13", item_ids: [] }).success, false);
});

Deno.test("access grant rules mirror the database checks", () => {
  const id = crypto.randomUUID();
  assert(accessGrantInsert.safeParse({ grantee_user_id: id, scope: "closet_read", purpose: "friend" }).success);
  assertEquals(
    accessGrantInsert.safeParse({ grantee_user_id: id, scope: "support_view", purpose: "support" }).success,
    false,
    "support grants must expire",
  );
  assertEquals(
    accessGrantInsert.safeParse({ grantee_user_id: id, grantee_household_id: id, scope: "item_read", purpose: "family" })
      .success,
    false,
  );
});
