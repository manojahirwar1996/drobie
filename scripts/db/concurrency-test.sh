#!/usr/bin/env bash
# Real concurrency checks with parallel connections (pgTAP runs in one session,
# so it cannot prove these). Usage: scripts/db/concurrency-test.sh [db]
set -euo pipefail
DB="${1:-drobie}"
P=(psql -X -q -At -v ON_ERROR_STOP=1 -d "$DB")
N=30
fail=0

uid=$("${P[@]}" -c "select tests.create_user('race-$(date +%s%N)@c.test')" | head -1)

# 1) quota: free plan allows 5 dro chats/day; 30 parallel attempts → exactly 5 ok
seq $N | xargs -P $N -I{} "${P[@]}" -c "select (private.consume_quota('$uid', 'dro.chats') ->> 'ok')" > /tmp/drobie_quota.out
ok=$(grep -c '^true$' /tmp/drobie_quota.out || true)
if [ "$ok" = "5" ]; then echo "pass     concurrency: quota 5/$N granted"; else echo "FAIL     concurrency: quota granted $ok (want 5)"; fail=1; fi

# 2) wallet: 10 credits, 30 parallel spends of 3 → exactly 3 succeed, balance 1
"${P[@]}" -c "select private.grant_credits('$uid', 10, 'race', 'race:grant:$uid')" >/dev/null
seq $N | xargs -P $N -I{} sh -c "psql -X -q -At -d '$DB' -c \"select private.spend_credits('$uid', 3, 'race', 'race:spend:$uid:{}')\" >/dev/null 2>&1 && echo ok || echo no" > /tmp/drobie_wallet.out
ok=$(grep -c '^ok$' /tmp/drobie_wallet.out || true)
bal=$("${P[@]}" -c "select balance from private.wallets where user_id = '$uid'")
if [ "$ok" = "3" ] && [ "$bal" = "1" ]; then echo "pass     concurrency: wallet 3 spends, balance 1"; else echo "FAIL     concurrency: wallet spends=$ok balance=$bal (want 3, 1)"; fail=1; fi

# 3) item limit: free plan 40 items; with 38 present, 30 parallel inserts → exactly 2 succeed
"${P[@]}" -c "insert into public.items (owner_user_id, name) select '$uid', 'pre ' || g from generate_series(1, 38) g" >/dev/null
seq $N | xargs -P $N -I{} sh -c "psql -X -q -At -d '$DB' -c \"insert into public.items (owner_user_id, name) values ('$uid', 'race {}')\" >/dev/null 2>&1 && echo ok || echo no" > /tmp/drobie_items.out
cnt=$("${P[@]}" -c "select count(*) from public.items where owner_user_id = '$uid' and deleted_at is null")
if [ "$cnt" = "40" ]; then echo "pass     concurrency: item limit held at 40"; else echo "FAIL     concurrency: $cnt items (want 40)"; fail=1; fi

# 4) ledger still balances after all of it
bad=$("${P[@]}" -c "select count(*) from (select transaction_id, currency from private.ledger_entries group by 1, 2 having sum(amount_minor) <> 0) t")
if [ "$bad" = "0" ]; then echo "pass     concurrency: ledger balanced"; else echo "FAIL     concurrency: $bad unbalanced transactions"; fail=1; fi

# clean up the race user (cascade)
"${P[@]}" -c "set session_replication_role = replica; delete from private.ledger_entries e using private.ledger_accounts a where a.id = e.account_id and a.owner_user_id = '$uid'; delete from private.ledger_accounts where owner_user_id = '$uid'; delete from auth.users where id = '$uid'" >/dev/null 2>&1 || true
exit $fail
