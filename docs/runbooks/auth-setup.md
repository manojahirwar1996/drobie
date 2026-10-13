# Sign-in setup checklist (Step 3)

The code side is done: profile, household, starter places and free plan are created on signup; there are the `confirm-adult` and `set-consent` functions; and the JWT is verified in every function. What's left is settings in the dashboards. Do each environment (staging, then production).

## Supabase dashboard → Authentication

- [ ] **Providers:** Email on (password, OTP, magic link); Google on; Apple on. **Phone/SMS off** (no phone sign-in, SRS §3).
- [ ] **Email:** confirm email ON; secure email change ON; OTP and magic-link expiry **600 s** (10 minutes).
- [ ] **SMTP:** custom SMTP via **Resend** (host `smtp.resend.com`, port 465, user `resend`, password = Resend API key), sender `hello@drobie.app` with the domain verified in Resend (SPF + DKIM on drobie.app).
- [ ] **Sessions:** access token (JWT) expiry **3600 s**; refresh token rotation ON; reuse interval 10 s.
- [ ] **MFA:** TOTP enabled. Staff accounts must enrol, because admin functions require `aal2`.
- [ ] **URL configuration:** Site URL `https://drobie.app`; redirect URLs `drobie://auth-callback`, `https://drobie.app/auth/callback` (add `exp://…` dev URLs only on staging).
- [ ] **Rate limits:** keep the defaults or tighten them: emails sent per hour, OTP verifications and sign-ups per IP.
- [ ] **JWT signing keys:** prefer the asymmetric signing keys. Functions verify ES256/RS256 through JWKS automatically and fall back to `SUPABASE_JWT_SECRET` for the legacy HS256 secret.
- [ ] **Data API → Exposed schemas:** `public`, `graphql_public`, `server`. Never expose `private` or `audit`.

## Google Cloud (OAuth)

- [ ] OAuth consent screen: app name "drobie", support email, privacy policy and terms URLs on drobie.app, authorised domain drobie.app.
- [ ] OAuth clients: one **Web** client (its ID and secret go into Supabase), one **Android** client per signing key (debug, upload, Play app signing SHA-1), and one **iOS** client.
- [ ] Authorised redirect URI on the web client: `https://<project>.supabase.co/auth/v1/callback`.

## Apple Developer

- [ ] Enable "Sign in with Apple" on the app ID.
- [ ] Create a Services ID (web) with return URL `https://<project>.supabase.co/auth/v1/callback`.
- [ ] Create a key for Sign in with Apple. In Supabase, enter the Services ID, Team ID, Key ID and private key. Note: Apple's client secret expires every 6 months; set a reminder to rotate it.
- [ ] App Store rule: if Google sign-in is offered on iOS, Sign in with Apple must be offered too.

## Function secrets (`supabase secrets set …`)

`SUPABASE_JWT_SECRET` (legacy HS256 only), `LOG_SALT` (random), `ALLOWED_ORIGINS` (`https://drobie.app,https://admin.drobie.app`), `BUILD_SHA` (set by CI on deploy), and later `ANTHROPIC_API_KEY`, `R2_*`, `RAZORPAY_*`, `REVENUECAT_*`.

## App side (for the mobile team)

- Store the refresh token only in **iOS Keychain / Android Keystore** (expo-secure-store), never in AsyncStorage.
- On first launch after sign-in, call `GET /me`. If `needs.adult_confirmation` is true, show the 18+ screen and call `POST /confirm-adult`.
- Ask for terms and privacy through `POST /set-consent`, using the versions from `config-bundle`. If the versions change, ask again.
