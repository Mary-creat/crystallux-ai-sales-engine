# Test accounts (private)

> **Mary:** keep this file out of any public-facing context. The
> credentials below are real and are used by the audit harness.

## Test client login

| Field      | Value                                          |
|------------|------------------------------------------------|
| Email      | `testclient@crystallux.org`                    |
| Password   | `TestPass2026#`                                |
| Role       | `client`                                       |
| Bound to   | Crystallux Insurance Network                   |
| Client id  | `6edc687d-07b0-4478-bb4b-820dc4eebf5d`         |
| Migration  | [db/migrations/test-client-account.sql](../../db/migrations/test-client-account.sql) |

## Admin login (production)

| Field      | Value                                          |
|------------|------------------------------------------------|
| Email      | `info@crystallux.org`                          |
| Password   | `Crystallux2026#`                              |
| Role       | `admin`                                        |

> The audit harness reads credentials from env vars
> (`CLX_ADMIN_EMAIL`, `CLX_ADMIN_PASSWORD`, `CLX_CLIENT_EMAIL`,
> `CLX_CLIENT_PASSWORD`) before falling back to the values above.
> Set those before invoking the harness if you'd rather not bake the
> defaults into shell history.

## Apply

The migration creates the test-client row in `auth_users` and is
idempotent (`ON CONFLICT (email) DO UPDATE`):

```bash
psql "$SUPABASE_URL_OR_DSN" -f db/migrations/test-client-account.sql
```

Or paste it into the Supabase SQL editor.

## Run audit

```bash
cd tests/audit
npm install                  # one-time: pulls Playwright + chromium
npx playwright install chromium
node dashboard-audit.js all  # or admin / client
```

Reports land in `docs/audit/`:
- `admin-audit-report.md`
- `client-audit-report.md`
- `audit-summary.md`
- screenshots in `docs/audit/screenshots/{admin,client}/`

## Rotate the test password

```sql
UPDATE auth_users
SET password_hash = crypt('NewPasswordHere#', gen_salt('bf'))
WHERE email = 'testclient@crystallux.org';
```

After rotating, update this file and the env-var override.
