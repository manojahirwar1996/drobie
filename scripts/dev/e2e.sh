#!/usr/bin/env bash
# End-to-end: Edge Function handlers → real PostgREST → real Postgres with RLS.
# Needs: a database built by scripts/db/test-local.sh, the `postgrest` binary,
# Deno, psql. With the Supabase CLI you can instead run `supabase start` and
# `supabase functions serve` and point the same tests at it.
set -euo pipefail
cd "$(dirname "$0")/../.."
DB="${DB:-drobie}"
PORT="${PGRST_PORT:-54399}"
SECRET="e2e-jwt-secret-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
DENO="${DENO_CMD:-deno}"   # sandbox: DENO_CMD=dtest (vendored deps)

ANON=$($DENO eval "import { signHs256 } from './supabase/functions/_shared/jwt.ts'; console.log(await signHs256({ role: 'anon', exp: Math.floor(Date.now()/1000) + 3600 }, '$SECRET'))")
SERVICE=$($DENO eval "import { signHs256 } from './supabase/functions/_shared/jwt.ts'; console.log(await signHs256({ role: 'service_role', exp: Math.floor(Date.now()/1000) + 3600 }, '$SECRET'))")

PGRST_DB_URI="postgres://authenticator:authenticator-local@127.0.0.1:5432/$DB" \
PGRST_DB_SCHEMAS="public,server" PGRST_DB_ANON_ROLE="anon" PGRST_JWT_SECRET="$SECRET" \
PGRST_DB_EXTRA_SEARCH_PATH="public,extensions" PGRST_SERVER_PORT="$PORT" PGRST_LOG_LEVEL="warn" \
  postgrest > /tmp/drobie-postgrest.log 2>&1 &
PGRST_PID=$!
trap 'kill $PGRST_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do curl -sf "http://127.0.0.1:$PORT/" -o /dev/null && break; sleep 0.2; done

E2E=1 SUPABASE_URL="http://127.0.0.1:$PORT" SUPABASE_REST_URL="http://127.0.0.1:$PORT" \
SUPABASE_ANON_KEY="$ANON" SUPABASE_SERVICE_ROLE_KEY="$SERVICE" SUPABASE_JWT_SECRET="$SECRET" \
E2E_DB="$DB" LOG_SALT="e2e" \
  $DENO test --allow-env --allow-net --allow-read --allow-run supabase/functions/tests/
