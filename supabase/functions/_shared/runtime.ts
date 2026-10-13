// Per-instance singletons (one per warm function instance).
import { ConfigClient } from "./config.ts";
import { serviceDb } from "./db.ts";
import { createLogger } from "./log.ts";

export const config = new ConfigClient(() => serviceDb(), createLogger({ component: "config" }));

/** Version of this function bundle, set at deploy time (git sha). */
export const BUILD = Deno.env.get("BUILD_SHA") ?? "dev";
