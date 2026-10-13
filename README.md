# drobie

AI wardrobe app with dro ("hey dro"), by Drobie Labs. Private repo. Start with `CLAUDE.md`, then the specs in `docs/`.

## Status

| Step (BACKEND_PROMPTS) | State |
| --- | --- |
| 1: Monorepo, tooling, CI | **Done.** pnpm + Turborepo, strict TypeScript, ESLint/Prettier, Deno fmt/lint/check, `@drobie/shared` (enums + Zod schemas), full CI in `.github/workflows/ci.yml`. |
| 2: Database foundation | **Done.** See `docs/DATABASE.md`. |
| 3: Auth, profiles, account lifecycle | **Code done** (`me`, `confirm-adult`, `set-consent`, signup trigger). Dashboard settings: `docs/runbooks/auth-setup.md`. |
| 4: Shared function library | **Done.** `supabase/functions/_shared`. |
| 5–14 | Not started. Next: Step 5 (photo storage on R2). |

Tests: 167 pgTAP + 4 concurrency checks, 38 unit tests, 7 end-to-end tests (functions → PostgREST → Postgres with RLS). API contracts: `docs/API.md`.

## Run it locally

```bash
pnpm install
supabase start && supabase db reset     # database + seed
pnpm db:test                            # pgTAP + concurrency
pnpm test:functions                     # Deno unit tests
supabase functions serve                # functions on http://127.0.0.1:54321/functions/v1/<name>

# without Docker (any Postgres 15+ with pgvector, pgmq, pg_cron, pgTAP; plus postgrest + deno)
PGUSER=postgres bash scripts/db/test-local.sh
PGUSER=postgres bash scripts/dev/e2e.sh          # end-to-end through a local PostgREST
PGUSER=postgres bash scripts/db/explain-hot-paths.sh
```

Test users (local only): `alice@drobie.test`, `bob@drobie.test`, `carol@drobie.test`, password `drobie-local-123`.

## Layout

```
apps/            mobile (Expo), admin (Next.js), web: placeholders until their steps
packages/shared  enums + Zod schemas for every write shape (used by app and functions)
packages/rules   rules engine (Step 9)
supabase/migrations   one SQL file per change, never edited after merge
supabase/functions    Edge Functions (Deno); _shared = the common library
supabase/tests        pgTAP (00000_test_helpers.sql runs first)
supabase/seed.sql     local test users only
scripts/db, scripts/dev   local test runners, concurrency test, query plans, end-to-end
docs                  specs + DATABASE, API, DECISIONS, runbooks
```
