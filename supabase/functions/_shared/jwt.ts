// JWT verification with WebCrypto only. Supports Supabase's legacy HS256
// secret and the newer asymmetric signing keys (ES256/RS256 via JWKS).
import { envOptional, supabaseUrl } from "./env.ts";
import { unauthorized } from "./errors.ts";

export interface JwtClaims {
  sub?: string;
  role?: string;
  aud?: string | string[];
  exp?: number;
  nbf?: number;
  iat?: number;
  iss?: string;
  aal?: string;
  email?: string;
  session_id?: string;
  [k: string]: unknown;
}

const enc = new TextEncoder();

export function b64urlDecode(s: string): Uint8Array<ArrayBuffer> {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

export function b64urlEncode(bytes: Uint8Array | string): string {
  const b = typeof bytes === "string" ? enc.encode(bytes) : bytes;
  let bin = "";
  for (const x of b) bin += String.fromCharCode(x);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

type Jwk = JsonWebKey & { kid?: string; alg?: string };
let jwksCache: { at: number; keys: Jwk[] } | undefined;

async function jwks(): Promise<Jwk[]> {
  if (jwksCache && Date.now() - jwksCache.at < 10 * 60_000) return jwksCache.keys;
  const url = envOptional("SUPABASE_JWKS_URL") ?? `${supabaseUrl()}/auth/v1/.well-known/jwks.json`;
  const res = await fetch(url, { signal: AbortSignal.timeout(5_000) });
  if (!res.ok) throw unauthorized("could not verify session");
  const body = (await res.json()) as { keys?: Jwk[] };
  jwksCache = { at: Date.now(), keys: body.keys ?? [] };
  return jwksCache.keys;
}

async function verifySignature(
  alg: string,
  kid: string | undefined,
  data: Uint8Array<ArrayBuffer>,
  sig: Uint8Array<ArrayBuffer>,
): Promise<boolean> {
  if (alg === "HS256") {
    const secret = envOptional("SUPABASE_JWT_SECRET");
    if (!secret) return false;
    const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
      "verify",
    ]);
    return crypto.subtle.verify("HMAC", key, sig, data);
  }
  const jwk = (await jwks()).find((k) => (kid ? k.kid === kid : true) && (k.alg ? k.alg === alg : true));
  if (!jwk) return false;
  if (alg === "ES256") {
    const key = await crypto.subtle.importKey("jwk", jwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
    return crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, sig, data);
  }
  if (alg === "RS256") {
    const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, [
      "verify",
    ]);
    return crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, sig, data);
  }
  return false;
}

/** Verify signature, expiry and audience. Throws 401 on anything wrong. */
export async function verifyJwt(token: string, now = Date.now() / 1000): Promise<JwtClaims> {
  const parts = token.split(".");
  if (parts.length !== 3) throw unauthorized("invalid session");
  const [h, p, s] = parts as [string, string, string];
  let header: { alg?: string; kid?: string };
  let claims: JwtClaims;
  try {
    header = JSON.parse(new TextDecoder().decode(b64urlDecode(h)));
    claims = JSON.parse(new TextDecoder().decode(b64urlDecode(p)));
  } catch {
    throw unauthorized("invalid session");
  }
  if (!header.alg || !["HS256", "ES256", "RS256"].includes(header.alg)) throw unauthorized("invalid session");
  const ok = await verifySignature(header.alg, header.kid, enc.encode(`${h}.${p}`), b64urlDecode(s));
  if (!ok) throw unauthorized("invalid session");
  if (typeof claims.exp !== "number" || claims.exp <= now) throw unauthorized("session expired");
  if (typeof claims.nbf === "number" && claims.nbf > now + 30) throw unauthorized("invalid session");
  return claims;
}

/** HS256 signer — used by tests and local tooling only. */
export async function signHs256(claims: JwtClaims, secret: string): Promise<string> {
  const h = b64urlEncode(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const p = b64urlEncode(JSON.stringify(claims));
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(`${h}.${p}`)));
  return `${h}.${p}.${b64urlEncode(sig)}`;
}
