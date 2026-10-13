# drobie

AI wardrobe app with dro ("hey dro"), by Drobie Labs. Private repo. Start with `CLAUDE.md`, then the specs in `docs/`.

## Status

| Step (BACKEND_PROMPTS) | State |
| --- | --- |
| 2: Database foundation | **Done.** Migrations, RLS, seed, 150 pgTAP tests + concurrency checks, all green. See `docs/DATABASE.md`. |
| 1: Monorepo, tooling, CI | Partial: Supabase project, DB scripts and the database CI workflow. pnpm/Turborepo apps and packages come next. |
| 3–14 | Not started. |

## Run the database locally

```bash
# with Docker + Supabase CLI
supabase start
supabase db reset        # migrations + seed
supabase test db         # pgTAP suite
bash scripts/db/concurrency-test.sh postgresql://postgres:postgres@127.0.0.1:54322/postgres

# without Docker (any Postgres 15+ with pgvector, pgmq, pg_cron, pgTAP)
PGUSER=postgres bash scripts/db/test-local.sh
PGUSER=postgres bash scripts/db/explain-hot-paths.sh   # query plans at ~100k items
```

Test users (local only): `alice@drobie.test`, `bob@drobie.test`, `carol@drobie.test`, password `drobie-local-123`.

## Layout

```
supabase/migrations   one SQL file per change, never edited after merge
supabase/tests        pgTAP (00000_test_helpers.sql runs first)
supabase/seed.sql     taxonomy, plans (placeholder prices), config keys, dictionary, local test users
scripts/db            local test runner, concurrency test, hot-path EXPLAINs, Supabase shim for Docker-less runs
docs                  BRD, FRS, SRS, TECH_DESIGN, PLATFORM_ARCHITECTURE, DATABASE, DECISIONS
```
