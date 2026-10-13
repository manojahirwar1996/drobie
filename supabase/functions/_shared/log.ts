// Structured JSON logs with a request id and a hashed user id. No PII: known
// sensitive keys are dropped and email addresses / phone numbers in strings
// are masked before anything is written.
import { envOptional } from "./env.ts";

type Level = "debug" | "info" | "warn" | "error";
export type LogFields = Record<string, unknown>;

const SENSITIVE_KEYS = new Set([
  "authorization",
  "apikey",
  "password",
  "token",
  "access_token",
  "refresh_token",
  "email",
  "phone",
  "name",
  "display_name",
  "holder_name",
  "address",
  "measurements",
  "secret",
  "cookie",
]);
const EMAIL = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
const PHONE = /(?:\+?91[-\s]?)?\b[6-9]\d{9}\b/g;

export function scrub(value: unknown, depth = 0): unknown {
  if (depth > 6) return "[depth]";
  if (typeof value === "string") return value.replace(EMAIL, "[email]").replace(PHONE, "[phone]");
  if (Array.isArray(value)) return value.slice(0, 50).map((v) => scrub(v, depth + 1));
  if (value instanceof Error) return { name: value.name, message: scrub(value.message, depth + 1) };
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) {
      out[k] = SENSITIVE_KEYS.has(k.toLowerCase()) ? "[redacted]" : scrub(v, depth + 1);
    }
    return out;
  }
  return value;
}

/** Stable pseudonymous id for logs (salted SHA-256, 16 hex chars). */
export async function hashUserId(userId: string): Promise<string> {
  const salt = envOptional("LOG_SALT") ?? "drobie";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${salt}:${userId}`));
  return Array.from(new Uint8Array(digest).slice(0, 8), (b) => b.toString(16).padStart(2, "0")).join("");
}

export interface Logger {
  debug(msg: string, fields?: LogFields): void;
  info(msg: string, fields?: LogFields): void;
  warn(msg: string, fields?: LogFields): void;
  error(msg: string, fields?: LogFields): void;
  with(fields: LogFields): Logger;
}

export type LogSink = (line: string, level: Level) => void;
const defaultSink: LogSink = (line, level) => {
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
};

export function createLogger(base: LogFields = {}, sink: LogSink = defaultSink): Logger {
  const write = (level: Level, msg: string, fields?: LogFields) => {
    const record = { ts: new Date().toISOString(), level, msg, ...base, ...(fields ? (scrub(fields) as LogFields) : {}) };
    sink(JSON.stringify(record), level);
  };
  return {
    debug: (m, f) => write("debug", m, f),
    info: (m, f) => write("info", m, f),
    warn: (m, f) => write("warn", m, f),
    error: (m, f) => write("error", m, f),
    with: (fields) => createLogger({ ...base, ...(scrub(fields) as LogFields) }, sink),
  };
}
