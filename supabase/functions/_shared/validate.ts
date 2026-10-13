import type { z } from "zod";
import { HttpError } from "./errors.ts";

/** Parse untrusted input; on failure answer 400 with field-level issues (no echo of values). */
export function parse<S extends z.ZodTypeAny>(schema: S, input: unknown): z.output<S> {
  const r = schema.safeParse(input);
  if (!r.success) {
    const issues = r.error.issues.slice(0, 20).map((i) => ({ path: i.path.join("."), message: i.message }));
    throw new HttpError(400, "validation_failed", "some fields are not valid", { issues });
  }
  return r.data;
}
