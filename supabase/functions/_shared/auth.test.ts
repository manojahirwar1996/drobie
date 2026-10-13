import { assertEquals } from "@std/assert";
import { requireUser, roleSatisfies } from "./auth.ts";
import { defineHandler, ok } from "./http.ts";
import { signHs256 } from "./jwt.ts";
import { setEnv } from "./testing.ts";

Deno.test("role hierarchy mirrors private.has_admin_role", () => {
  assertEquals(roleSatisfies(["super_admin"], "finance"), true);
  assertEquals(roleSatisfies(["admin"], "support"), true);
  assertEquals(roleSatisfies(["admin"], "finance"), false);
  assertEquals(roleSatisfies(["support"], "admin"), false);
  assertEquals(roleSatisfies([], "analyst"), false);
});

Deno.test("requireUser: only signed-in users with a valid subject", async () => {
  const SECRET = "test-secret-at-least-32-characters-long!!";
  const restore = setEnv({ SUPABASE_JWT_SECRET: SECRET });
  try {
    const exp = Math.floor(Date.now() / 1000) + 60;
    const h = defineHandler("who", { methods: ["GET"] }, async (ctx) => ok((await requireUser(ctx)).id));
    const call = (auth?: string) =>
      h(new Request("http://x", { method: "GET", headers: auth ? { authorization: auth } : {} }));
    assertEquals((await call()).status, 401);
    assertEquals(
      (await call(`Bearer ${await signHs256({ role: "anon", exp }, SECRET)}`)).status,
      401,
      "anon key is not a user",
    );
    assertEquals((await call(`Bearer ${await signHs256({ role: "service_role", exp }, SECRET)}`)).status, 401);
    const id = crypto.randomUUID();
    const res = await call(`Bearer ${await signHs256({ sub: id, role: "authenticated", exp }, SECRET)}`);
    assertEquals(await res.json(), { data: id });
  } finally {
    restore();
  }
});
