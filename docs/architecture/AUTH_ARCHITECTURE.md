# Crystallux Authentication Architecture

**Status:** Phase 1 of 4 (Tier-2 foundation) shipped 2026-04-30
**Owner:** Mary Akintunde
**Related migration:** `docs/architecture/migrations/2026-04-28-authentication.sql`
**Related webhooks:** `workflows/api/auth/clx-auth-*.json` (7 files)
**Related pages:** `site/login.html`, `site/magic-link-sent.html`, `site/magic-link-verify.html`, `site/forgot-password.html`, `site/reset-password.html`
**Related script:** `scripts/auth-bcrypt.js`

---

## 1. What this replaces

The legacy MVP dashboard at `dashboard/index.html` had three auth defects:

1. The Supabase service-role key was pasted into the browser via Settings — anyone with DevTools could lift it.
2. The Mary master token lived in URL query strings — leaks via referer headers, browser history, log files.
3. There was no concept of an account, password, role, session, or audit. Identity was "you have the URL."

This rewrite installs a real session-token system:

- Identity is an `auth_users` row (email + bcrypt hash + role + optional `client_id`).
- Sessions are `auth_sessions` rows with opaque 64-char tokens, expiry, revocation.
- The browser only ever holds an opaque session token. Bearer header `Authorization: Bearer <token>` is sent on every API call.
- All API webhooks call `validate_session(p_token)` first, then read user role + scoping out of the result. The browser never names its own `client_id`.

The old master-token URL keeps working as a documented emergency path — Phase 4 retires it.

---

## 2. Token flow

### 2.1 Email + password (primary admin path)

```
browser /login.html ──POST {email,password}──▶  /webhook/auth/login
                                                      │
                                                      ├─ lookup auth_users by lower(email)
                                                      ├─ check locked_until
                                                      ├─ bcrypt.compare(password, password_hash)
                                                      ├─ on FAIL  → register_failed_login() (5×→15min lock), 401
                                                      └─ on PASS  → randomBytes(48).base64url
                                                                     ├─ INSERT auth_sessions (7-day TTL)
                                                                     ├─ register_successful_login()
                                                                     └─ 200 { session_token, expires_at, user }

browser stores token in localStorage, redirects to admin.crystallux.org or app.crystallux.org per user.role
```

### 2.2 Magic link (alternative for clients)

```
browser /login.html ─[Send magic link]─▶  /webhook/auth/magic-link
                                                ├─ randomBytes(32).base64url, 15-min TTL
                                                ├─ INSERT auth_magic_links
                                                ├─ Send Email (placeholder) — currently returns the click_url in the response payload only
                                                └─ 200 (always, never leaks account existence)

(later) email link click ─▶ /magic-link-verify.html ─POST {token}─▶ /webhook/auth/magic-link-verify
                                                                          ├─ lookup, check used_at + expires_at
                                                                          ├─ resolve auth_users by email
                                                                          ├─ INSERT auth_sessions
                                                                          ├─ PATCH auth_magic_links SET used_at
                                                                          └─ 200 { session_token, user }
```

### 2.3 Password reset

```
/forgot-password.html ─POST {email}─▶ /webhook/auth/password-reset-request
                                            ├─ if user exists: INSERT auth_password_resets (1-hour TTL)
                                            └─ 200 (always — no existence leak)

(later) email link click ─▶ /reset-password.html ─POST {token,password}─▶ /webhook/auth/password-reset-complete
                                                                                ├─ lookup token, check used_at + expires_at
                                                                                ├─ bcrypt.hash(password, 12)
                                                                                ├─ PATCH auth_users SET password_hash, clear lock counters
                                                                                ├─ PATCH auth_password_resets SET used_at
                                                                                ├─ PATCH auth_sessions SET revoked_at  (force-logout other sessions)
                                                                                └─ 200
```

### 2.4 Session validation (every API call from a dashboard)

```
admin.crystallux.org / app.crystallux.org page ─▶  /webhook/auth/validate-session
                                                         ├─ extract Bearer token from Authorization header
                                                         ├─ validate_session(p_token) — RPC, single SELECT
                                                         ├─ if 0 rows: 401
                                                         ├─ touch_session() — sliding expiry +7 days
                                                         └─ 200 { user: { id, email, role, client_id }, expires_at }
```

### 2.5 Logout

```
dashboard ─▶ /webhook/auth/logout  (Authorization: Bearer <token>)
              └─ revoke_session(p_token), 200
```

---

## 3. Schema

| Table | Purpose | Key columns |
|---|---|---|
| `auth_users` | Identity + role | `email` (unique, lower-cased index), `password_hash` (bcrypt cost 12), `user_role IN ('admin','client','team_member')`, `client_id` (FK to `clients(id)`, NULL for admin), `failed_login_attempts`, `locked_until` |
| `auth_sessions` | Issued tokens | `session_token` (64-char base64url), `expires_at`, `revoked_at`, `user_id` (FK), `ip_address`, `user_agent`, `last_activity_at` |
| `auth_magic_links` | One-time email links | `email`, `token` (32-byte base64url), `expires_at` (15 min), `used_at` |
| `auth_password_resets` | Reset tokens | `user_id` (FK), `token` (32-byte base64url), `expires_at` (1 hour), `used_at` |

A `CHECK` constraint on `auth_users` enforces:
- `admin` rows MUST have `client_id IS NULL`
- `client` and `team_member` rows MUST have `client_id IS NOT NULL`

This makes "an admin with a client_id" un-representable, which is the most dangerous accidental state.

---

## 4. RPC contracts

| Function | Purpose | Caller |
|---|---|---|
| `validate_session(p_token TEXT)` | Returns 0 or 1 row with `user_id, email, user_role, client_id, expires_at`. Excludes revoked/expired. | every API webhook, on every request |
| `touch_session(p_token TEXT, p_extend_seconds INT)` | Sliding-window extend (`expires_at = max(now, expires_at) + extend`). Updates `last_activity_at`. | `validate-session` (after match) |
| `revoke_session(p_token TEXT)` | Sets `revoked_at = now()`. | `logout`, `password-reset-complete` |
| `register_failed_login(p_email TEXT)` | +1 attempt counter; locks 15 min when ≥5. | `login` (failure path) |
| `register_successful_login(p_user_id UUID)` | Reset counter, clear lock, stamp `last_login_at`. | `login`, `magic-link-verify` (success path) |

All five are `SECURITY DEFINER` and `EXECUTE` is granted only to `service_role`.

---

## 5. Security properties

| Property | How enforced |
|---|---|
| Tokens never appear in URLs | Sessions live in `localStorage`. URLs only carry magic-link/reset tokens which are single-use and short-lived. |
| Passwords stored hashed | bcrypt cost-12, generated by `scripts/auth-bcrypt.js` for the seed and by webhooks at runtime. n8n needs `NODE_FUNCTION_ALLOW_EXTERNAL=bcryptjs` env var. |
| Session expiration enforced server-side | `validate_session` SQL filter `expires_at > now() AND revoked_at IS NULL`. Browser cannot forge expiry. |
| Failed-login lockout | `register_failed_login` increments + locks 15 min at 5×. UI surfaces lock with `423 Locked`. |
| Magic link expiry | 15 min. Single-use (`used_at` set on consumption). |
| Reset link expiry | 1 hour. Single-use. Reset always revokes existing sessions (force-logout everywhere). |
| No existence leak | Magic-link and password-reset endpoints always 200 regardless of whether the email matches a row. |
| Account-existence not implied by login error | Both wrong-password and unknown-email return generic `Invalid credentials`. |
| Cross-tenant isolation | `client_id` is read from the **session row**, never from the request body. API webhooks that filter by client must use the session-resolved id. |
| Audit | Server logs every login/logout/reset via n8n execution log + the lock counters on `auth_users`. Phase 4 adds a dedicated `admin_action_log` row per state-changing call. |
| CSP | `connect-src 'self' https://automation.crystallux.org`; no third-party scripts. |
| CORS (dashboards) | n8n webhook responses set `Access-Control-Allow-Origin` to `https://admin.crystallux.org` or `https://app.crystallux.org` per request origin. To configure in Phase 2 webhook authoring. |

---

## 6. n8n configuration prerequisites

Before importing the workflows in `workflows/api/auth/`:

1. **bcryptjs** must be allowed in Code nodes. On the n8n VPS:
   ```
   sudo systemctl edit n8n   # or your unit
   # add under [Service]:
   Environment="NODE_FUNCTION_ALLOW_EXTERNAL=bcryptjs"
   sudo systemctl daemon-reload && sudo systemctl restart n8n
   ```
2. The httpHeaderAuth credential **`Supabase Crystallux`** must already exist in n8n with header `Authorization: Bearer <SERVICE_ROLE_KEY>` and `apikey: <SERVICE_ROLE_KEY>`. The workflows reference this credential by name, never by ID (matches the existing convention).
3. Apply migration `2026-04-28-authentication.sql` to the Supabase project before activating any workflow.

---

## 7. Seeding Mary

The migration creates a placeholder admin row. To set the real password:

```bash
# at the repo root
npm i bcryptjs --no-save
node scripts/auth-bcrypt.js 'YourTempPassw0rd-2026!'
# copy the printed hash, then run against Supabase:
#   UPDATE auth_users
#      SET password_hash = '<hash>',
#          failed_login_attempts = 0,
#          locked_until = NULL
#    WHERE email = 'info@crystallux.org';
```

After the first successful login, run the password-reset flow from `/forgot-password.html` to install a fresh hash; the seed value is then irrelevant.

---

## 8. What is deferred

| Item | Phase | Notes |
|---|---|---|
| Real email delivery for magic-link + password-reset | 1.1 (this week) | Replace the `Send Email (placeholder)` Code node with Postmark/SendGrid/SMTP. The Code node currently returns the click_url in its node output so you can copy it for testing. |
| Admin dashboard at `admin.crystallux.org` | 2 | Will consume the validate-session webhook |
| Client dashboard at `app.crystallux.org` | 3 | Will consume the validate-session webhook + admin-shaped data webhooks |
| Admin/client API webhooks (lists, details) | 2/3 | New folders `workflows/api/admin/` and `workflows/api/client/` |
| Admin-action audit log | 4 | New table `admin_action_log` (placeholder; touched by every state-changing call) |
| Retire master-token URL access | 4 | Once dashboards are live and Mary is using the new login |
| HttpOnly cookie tokens (replace localStorage) | 4 | Requires same-origin or `SameSite=None` cross-site set-cookie via the n8n response, plus a refresh-token endpoint |
| Rate limiting | 4 | n8n queue limits + Cloudflare WAF rules; today only the lockout counter applies |

---

## 9. Why this design

- **Server-side token validation, no JWT decoding in the browser.** Easier to revoke. No public-key distribution. No "30-day JWT can't be killed" footgun.
- **bcrypt cost 12.** OWASP-recommended for general use; ~250ms verify on the n8n VPS — slow enough to deter brute force, fast enough that legitimate logins feel instant.
- **Sliding expiry.** Sessions extend by 7 days every time the user touches the API. Inactive accounts auto-logout. Active users never get logged out mid-session.
- **`client_id` from session, not request.** This is the single most important property. A client cannot ask the API for another client's data because the API never reads `client_id` from their request body — it always reads it from the session row.
- **Single-use, short-lived links.** Magic links and reset links carry their own short TTLs and consume on first use. Replays fail.
- **Idempotent privacy.** Endpoints never tell an attacker whether an email is registered.
