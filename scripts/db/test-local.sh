#!/usr/bin/env bash
# Rebuild a throwaway database from migrations + seed and run the pgTAP suite,
# without Docker. With Docker available, prefer: supabase db reset && supabase test db
set -euo pipefail
cd "$(dirname "$0")/../.."
DB="${DB:-drobie}"
PSQL=(psql -X -v ON_ERROR_STOP=1 -q -d "$DB")
dropdb --if-exists --force "$DB"
createdb "$DB"
"${PSQL[@]}" -f scripts/db/supabase-shim.sql >/dev/null
for f in supabase/migrations/*.sql; do
  echo "migrate  $(basename "$f")"
  "${PSQL[@]}" -f "$f" >/dev/null
done
if [ "${SKIP_SEED:-0}" != "1" ]; then
  echo "seed     supabase/seed.sql"
  "${PSQL[@]}" -f supabase/seed.sql >/dev/null
fi
fail=0
for t in supabase/tests/database/*.sql; do
  out=$(psql -X -q -At -d "$DB" -f "$t" 2>&1) || true
  if echo "$out" | grep -qE "^not ok|ERROR|Looks like you|planned [0-9]+ tests? but ran"; then
    echo "FAIL     $(basename "$t")"; echo "$out" | grep -E "not ok|ERROR|#" | head -40; fail=1
  else
    n=$(echo "$out" | grep -cE "^ok ") || true
    echo "pass     $(basename "$t") ($n)"
  fi
done
if [ -f scripts/db/concurrency-test.sh ] && [ "${SKIP_CONCURRENCY:-0}" != "1" ]; then
  bash scripts/db/concurrency-test.sh "$DB" || fail=1
fi
exit $fail
