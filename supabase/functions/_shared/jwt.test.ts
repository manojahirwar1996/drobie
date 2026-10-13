import { assertEquals, assertRejects } from "@std/assert";
import { b64urlEncode, signHs256, verifyJwt } from "./jwt.ts";
import { HttpError } from "./errors.ts";
import { setEnv } from "./testing.ts";

const SECRET = "test-secret-at-least-32-characters-long!!";
const now = () => Math.floor(Date.now() / 1000);

Deno.test("HS256: valid token verifies", async () => {
  const restore = setEnv({ SUPABASE_JWT_SECRET: SECRET });
  try {
    const t = await signHs256({ sub: "u1", role: "authenticated", exp: now() + 60 }, SECRET);
    assertEquals((await verifyJwt(t)).sub, "u1");
  } finally {
    restore();
  }
});

Deno.test("HS256: tampered, expired, wrong-secret and alg=none tokens are rejected", async () => {
  const restore = setEnv({ SUPABASE_JWT_SECRET: SECRET });
  try {
    const good = await signHs256({ sub: "u1", role: "authenticated", exp: now() + 60 }, SECRET);
    const [h, , s] = good.split(".");
    const tampered = `${h}.${b64urlEncode(JSON.stringify({ sub: "admin", role: "service_role", exp: now() + 60 }))}.${s}`;
    await assertRejects(() => verifyJwt(tampered), HttpError);
    const expired = await signHs256({ sub: "u1", exp: now() - 1 }, SECRET);
    await assertRejects(() => verifyJwt(expired), HttpError, "expired");
    const wrongSecret = await signHs256({ sub: "u1", exp: now() + 60 }, "another-secret-another-secret-xx");
    await assertRejects(() => verifyJwt(wrongSecret), HttpError);
    const none = `${b64urlEncode('{"alg":"none"}')}.${b64urlEncode(JSON.stringify({ sub: "u1", exp: now() + 60 }))}.`;
    await assertRejects(() => verifyJwt(none), HttpError);
    await assertRejects(() => verifyJwt("garbage"), HttpError);
  } finally {
    restore();
  }
});

Deno.test("ES256 via JWKS (new Supabase signing keys)", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const jwk = { ...(await crypto.subtle.exportKey("jwk", pair.publicKey)), kid: "k1", alg: "ES256" };
  const restore = setEnv({ SUPABASE_URL: "http://jwks.test", SUPABASE_JWKS_URL: "http://jwks.test/keys" });
  const realFetch = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response(JSON.stringify({ keys: [jwk] })))) as typeof fetch;
  try {
    const h = b64urlEncode(JSON.stringify({ alg: "ES256", kid: "k1", typ: "JWT" }));
    const p = b64urlEncode(JSON.stringify({ sub: "u2", role: "authenticated", exp: now() + 60 }));
    const sig = new Uint8Array(
      await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, pair.privateKey, new TextEncoder().encode(`${h}.${p}`)),
    );
    assertEquals((await verifyJwt(`${h}.${p}.${b64urlEncode(sig)}`)).sub, "u2");
    await assertRejects(() => verifyJwt(`${h}.${b64urlEncode(JSON.stringify({ sub: "x", exp: now() + 60 }))}.${b64urlEncode(sig)}`), HttpError);
  } finally {
    globalThis.fetch = realFetch;
    restore();
  }
});
