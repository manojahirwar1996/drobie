// S3 SigV4 query-string presigning with WebCrypto (no SDK). Cloudflare R2 is
// S3-compatible (region "auto"). Keys are always under the owner's prefix and
// never accepted from the client.
import { env } from "./env.ts";
import { badRequest } from "./errors.ts";

const enc = new TextEncoder();
const hex = (b: ArrayBuffer) => Array.from(new Uint8Array(b), (x) => x.toString(16).padStart(2, "0")).join("");
const sha256 = async (s: string) => hex(await crypto.subtle.digest("SHA-256", enc.encode(s)));
async function hmac(key: ArrayBuffer | Uint8Array<ArrayBuffer>, data: string): Promise<ArrayBuffer> {
  const k = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return crypto.subtle.sign("HMAC", k, enc.encode(data));
}

/** RFC 3986 encoding as S3 expects (keep `/` in paths). */
export const s3Encode = (s: string, keepSlash = false) =>
  encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`).replace(keepSlash ? /%2F/g : /$^/, "/");

export interface PresignInput {
  method: "GET" | "PUT";
  host: string;
  /** Absolute path, e.g. `/bucket/u/<uuid>/item_photo/<uuid>/master.webp` */
  path: string;
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
  expiresSeconds: number;
  now?: Date;
  /** Extra signed query params, e.g. response-content-type. */
  query?: Record<string, string>;
  /** Signed headers beyond host (e.g. content-type for PUT). */
  headers?: Record<string, string>;
}

export async function presign(i: PresignInput): Promise<string> {
  if (i.expiresSeconds < 1 || i.expiresSeconds > 604800) throw new Error("expiry out of range");
  const now = i.now ?? new Date();
  const amzDate = now.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const day = amzDate.slice(0, 8);
  const scope = `${day}/${i.region}/s3/aws4_request`;
  const headers: Record<string, string> = { host: i.host };
  for (const [k, v] of Object.entries(i.headers ?? {})) headers[k.toLowerCase()] = v.trim();
  const signedHeaders = Object.keys(headers).sort().join(";");

  const q: Record<string, string> = {
    "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
    "X-Amz-Credential": `${i.accessKeyId}/${scope}`,
    "X-Amz-Date": amzDate,
    "X-Amz-Expires": String(i.expiresSeconds),
    "X-Amz-SignedHeaders": signedHeaders,
    ...(i.query ?? {}),
  };
  const canonicalQuery = Object.keys(q).sort().map((k) => `${s3Encode(k)}=${s3Encode(q[k] as string)}`).join("&");
  const canonicalHeaders = Object.keys(headers).sort().map((k) => `${k}:${headers[k]}\n`).join("");
  const canonicalRequest = [i.method, s3Encode(i.path, true), canonicalQuery, canonicalHeaders, signedHeaders, "UNSIGNED-PAYLOAD"].join("\n");
  const stringToSign = ["AWS4-HMAC-SHA256", amzDate, scope, await sha256(canonicalRequest)].join("\n");

  let key: ArrayBuffer = await hmac(enc.encode(`AWS4${i.secretAccessKey}`), day);
  for (const part of [i.region, "s3", "aws4_request"]) key = await hmac(key, part);
  const signature = hex(await hmac(key, stringToSign));
  return `https://${i.host}${s3Encode(i.path, true)}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const KEY_RE = new RegExp(`^u/(${UUID})/[a-z_]+/${UUID}/[a-z0-9_]+\\.[a-z0-9]+$`);

/** Object key for a user's file: u/<user>/<purpose>/<media_id>/<variant>.<ext> — names never appear in keys. */
export function userObjectKey(userId: string, purpose: string, mediaId: string, variant: string, ext: string): string {
  const key = `u/${userId}/${purpose}/${mediaId}/${variant}.${ext}`;
  if (!KEY_RE.test(key)) throw badRequest("invalid object key");
  return key;
}

/** Presign against R2 for an object that must belong to `ownerId`. */
export async function presignR2(method: "GET" | "PUT", ownerId: string, key: string, expiresSeconds: number, contentType?: string) {
  const m = KEY_RE.exec(key);
  if (!m || m[1] !== ownerId) throw badRequest("object does not belong to this user");
  return await presign({
    method,
    host: `${env("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com`,
    path: `/${env("R2_BUCKET")}/${key}`,
    accessKeyId: env("R2_ACCESS_KEY_ID"),
    secretAccessKey: env("R2_SECRET_ACCESS_KEY"),
    region: "auto",
    expiresSeconds,
    ...(method === "PUT" && contentType ? { headers: { "content-type": contentType } } : {}),
  });
}
