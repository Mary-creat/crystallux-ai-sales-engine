# Role-gate audit — webhook security review

**Generated:** 2026-05-08
**Scope:** every workflow JSON under `workflows/api/admin/` and `workflows/api/client/` plus the new copilot workflows.
**Source-of-truth:** [`docs/architecture/ROLES.md`](../architecture/ROLES.md).

## Methodology

For each webhook, confirmed two things:

1. **Session validation** — does the workflow call `validate_session` RPC against `auth_sessions` to resolve the session token? (i.e. trust the token, not the body)
2. **Role gate** — does the workflow then check `user_role` against an allowlist before granting access?

Anything missing either of these is a tenant-isolation gap.

## Results

| File | validate_session | user_role gate | Status |
|------|------------------|----------------|--------|
| `api/admin/clx-admin-audit-log.json`           | ✓ | ✓ admin | PASS |
| `api/admin/clx-admin-billing-summary.json`     | ✓ | ✓ admin | PASS |
| `api/admin/clx-admin-client-detail.json`       | ✓ | ✓ admin | PASS |
| `api/admin/clx-admin-list-clients.json`        | ✓ | ✓ admin | PASS |
| `api/admin/clx-admin-list-leads.json`          | ✓ | ✓ admin | PASS |
| `api/admin/clx-admin-market-intelligence.json` | ✓ | ✓ admin | PASS |
| `api/admin/clx-admin-onboarding-pipeline.json` | ✓ | ✓ admin | PASS |
| `api/admin/clx-admin-system-health.json`       | ✓ | ✓ admin | PASS |
| `api/admin/clx-admin-workflow-status.json`     | ✓ | ✓ admin | PASS |
| `api/client/clx-client-activity.json`          | ✓ | ✓ client/team_member | PASS |
| `api/client/clx-client-billing.json`           | ✓ | ✓ client/team_member | PASS |
| `api/client/clx-client-bookings.json`          | ✓ | ✓ client/team_member | PASS |
| `api/client/clx-client-campaigns.json`         | ✓ | ✓ client/team_member | PASS |
| `api/client/clx-client-copilot-ask.json`       | ✓ | ✓ client/team_member/advisor/supervisor/mga_principal | PASS |
| `api/client/clx-client-copilot-transcribe.json`| ✓ | ✓ client/team_member/advisor/supervisor/mga_principal | PASS |
| `api/client/clx-client-leads.json`             | ✓ | ✓ client/team_member | PASS |
| `api/client/clx-client-overview.json`          | ✓ | ✓ client/team_member | PASS |
| `api/client/clx-client-performance.json`       | ✓ | ✓ client/team_member | PASS |
| `api/client/clx-client-replies.json`           | ✓ | ✓ client/team_member | PASS |
| `api/client/clx-client-settings.json`          | ✓ | ✓ client/team_member | PASS |

**Summary: 20/20 webhooks pass.** No role-gate gaps detected.

## Critical pattern: client_id from session, not body

Every client webhook reads `client_id` from the validated session row, never from the request body:

```js
// In Check Tenant code node:
const row = ...; // result from validate_session
return { json: { ok: true, client_id: row.client_id, ... } };

// Downstream queries use $json.client_id (from this code node's output),
// NOT $('Webhook').item.json.body.client_id (which would be unsafe).
```

Verified manually in commit `ce5f9af` and reinforced in commits `b5660d1` (admin) + `187430a` (client) when the parallel-branch Merge fix landed. The audit-time spot-check during the dashboard audit (commit `de446f5`) included a tenant-isolation Playwright test that POSTed a manipulated `client_id` in the body — server correctly ignored it and used the session client_id.

## What this audit does NOT cover

- **The 9 protected v2/v3 production workflows** (Lead Research, Campaign Router, Outreach Generation, etc.) — these are scheduled, not webhook-triggered, so they have no public auth surface. They run as service_role.
- **Public webhooks** without auth (Stripe webhook, Vapi webhook, Calendly webhook) — these use HMAC signature verification instead of session tokens. Stripe webhook verified ✓; Vapi webhook is dormant; Calendly ingestion is part of `clx-booking-v2` (production-active).
- **Internal-only webhooks** that workflows call each other through (`clx-email-send`, `clx-auth-welcome`) — these use a shared `INTERNAL_EMAIL_SECRET` env var, validated in the workflow's first code node. Not exposed to public callers.

## Recommendations for new webhooks

When adding a new client-facing webhook, copy the pattern from `clx-client-overview.json`:

1. **Webhook node** — body validation in code (extract token from Authorization header).
2. **Validate Session HTTP node** — `POST .../rpc/validate_session` with the token.
3. **Check Tenant code node** — verify `user_role IN <allowlist>`, extract `client_id` from session row, fail with 403 otherwise.
4. **IF Tenant OK node** — branch on the OK boolean.
5. **Downstream queries** — use the `client_id` from the Check Tenant node's output, never from the webhook body.
6. **Merge node before Shape Response** — when there are parallel HTTP queries.

## Cross-references

- Roles canon: [`docs/architecture/ROLES.md`](../architecture/ROLES.md)
- Auth schema: [`docs/architecture/migrations/2026-04-28-authentication.sql`](../architecture/migrations/2026-04-28-authentication.sql)
- Tenant-isolation Playwright test: [`tests/audit/dashboard-audit.js`](../../tests/audit/dashboard-audit.js) → `testTenantIsolation()`
- Role-enum migration: [`db/migrations/role-enum-update.sql`](../../db/migrations/role-enum-update.sql)
