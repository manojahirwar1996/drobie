/** Typed access to function secrets. Read lazily so tests can set them. */
export function env(name: string): string {
  const v = Deno.env.get(name);
  if (v === undefined || v === "") throw new Error(`missing environment variable ${name}`);
  return v;
}

export function envOptional(name: string): string | undefined {
  const v = Deno.env.get(name);
  return v === undefined || v === "" ? undefined : v;
}

export const supabaseUrl = () => env("SUPABASE_URL");
/** PostgREST base. Hosted/CLI: `${SUPABASE_URL}/rest/v1`; tests may point straight at PostgREST. */
export const restUrl = () => envOptional("SUPABASE_REST_URL") ?? `${supabaseUrl()}/rest/v1`;
export const anonKey = () => env("SUPABASE_ANON_KEY");
export const serviceRoleKey = () => env("SUPABASE_SERVICE_ROLE_KEY");
