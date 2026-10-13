# drobie API (Edge Functions)

Base URL: `https://<project>.supabase.co/functions/v1/<function>`

**Every request** sends `Authorization: Bearer <user access token>` and `apikey: <anon key>`, except `health` and `config-bundle`, which work before sign-in. The app should also send `x-app-version` (semver), `x-platform` (`ios` / `android` / `web`) and, optionally, `x-request-id`.

**Every response** is JSON: `{ "data": … }` on success, or `{ "error": { "code", "message", "details"? } }` on failure. The `x-request-id` header is always echoed back; quote it in bug reports.

## Error codes

| HTTP | `code` | Meaning for the app |
| --- | --- | --- |
| 400 | `bad_request`, `validation_failed` | Fix the input. `details.issues` lists `{ path, message }`. |
| 401 | `unauthorized` | Refresh the session or sign in again. |
| 402 | `upgrade_required` | Not enough credits. |
| 403 | `forbidden` | Not allowed. |
| 403 | `adult_confirmation_required` | Show the 18+ confirmation, then retry. |
| 403 | `account_inactive` | Account is suspended or banned. |
| 403 | `limit_reached` | Plan limit hit (e.g. items). `details.limit` is the feature key. Show the paywall. |
| 403 | `upgrade_required` | Feature not in the plan. |
| 409 | `conflict` | Duplicate, or the consent text changed (refresh config and re-ask). |
| 409 / 422 | `idempotency_conflict` | Same `Idempotency-Key`: either still running, or used for a different body. |
| 413 | `payload_too_large` | Body over the limit. |
| 429 | `rate_limited` | Wait for `Retry-After` seconds. |
| 429 | `quota_exceeded` | Daily or monthly allowance used. `details` has `limit` and `used`. |
| 429 | `budget_exceeded` | Smart (paid AI) answers are paused; quick answers still work. |
| 5xx | `upstream_unavailable`, `internal` | Retry with backoff. |

POSTs that create things accept `Idempotency-Key` (8–128 chars of `A-Z a-z 0-9 _ -`). A retry with the same key and body returns the stored response with the header `idempotent-replayed: true`.

## Endpoints (Step 3)

### `GET /health`
No auth. Returns `{ data: { status: "ok", build } }`. `?deep=1` (service key only) also checks the database.

### `GET /config-bundle?locale=en-IN`
No auth. Returns `{ data: { version, locale, values: { "<namespace>:<key>": { value, targeting } } } }`. This covers flags, copy, the minimum app version, upload limits, consent versions and the free-looks offer.

- Send `If-None-Match` with the last `ETag` you received. An unchanged config returns `304`.
- Fetch it at launch and every few hours, and cache the last good bundle offline.
- Keys the app doesn't recognise are ignored. Missing keys fall back to the defaults bundled in the app.

### `GET /me`
Signed in. One call after sign-in returns:

```json
{ "data": {
  "profile": { "id": "…", "display_name": "…", "country": "IN", "locale": "en-IN", "timezone": "Asia/Kolkata",
               "morning_time": "07:30:00", "adult_confirmed_at": null, "status": "active", "inbound_email_token": "…" },
  "households": [{ "role": "owner", "household": { "id": "…", "name": "My home", "kind": "personal" } }],
  "plan": "free",
  "features": { "closet.max_items": { "type": "limit", "enabled": true, "limit": 40 },
                "dro.chats": { "type": "quota", "period": "day", "enabled": true, "limit": 5 } },
  "consents": { "terms": { "granted": true, "version": "1.0", "recorded_at": "…" } },
  "wallets": [{ "credit_type": "studio_credits", "currency": "CRD", "balance": 0 }],
  "needs": { "adult_confirmation": true }
} }
```

The app must never hard-code plans or limits. It reads them from `features`.

### `PATCH /me`
Signed in, 18+ confirmed. The body can only contain these fields: `display_name`, `handle`, `city`, `locale`, `timezone` (IANA), `morning_time` (`HH:MM`), `vibe`, `settings`. Any other field is rejected with `validation_failed`. Returns `{ data: { profile } }`.

### `POST /confirm-adult`
Signed in. Records the 18+ confirmation and is safe to repeat. Returns `{ data: { adult_confirmed_at } }`. Limited to 10 calls per burst.

### `POST /set-consent`
Signed in (works before the 18+ step, because terms and privacy come first).

```json
{ "consents": [{ "consent_type": "gallery", "granted": true, "version": "1.0" }] }
```

`version` must equal `config-bundle → app:consent_versions[type]`; if it doesn't, the request fails with `409 conflict`. Withdrawing `measurements` deletes the stored measurements. Returns `{ data: { recorded, changed, current } }`.

Consent types: `terms`, `privacy`, `email_import`, `gallery`, `calendar`, `measurements`, `marketing`, `avatar`, `location`.

## Direct Data API use from the app

For plain reads and writes of their own rows (items, places, wear logs, device tokens, notification preferences), the app can use supabase-js on `public` tables. RLS and column grants enforce the rules, and `@drobie/shared` has the Zod schema for every write. List reads must filter by `owner_user_id` / `household_id` explicitly (see `docs/DATABASE.md`).

The `server` schema exists in the Data API, but only the service role can use it. App calls to it are refused, and an end-to-end test checks this.
