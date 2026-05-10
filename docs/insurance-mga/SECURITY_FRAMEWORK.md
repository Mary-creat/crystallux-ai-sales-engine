# Security Framework (Insurance MGA — Layer 2 Part B)

> **Audience:** anyone touching the insurance-mga code path. Codifies the security posture for an MGA that handles regulated PII (SIN, license numbers, banking, medical underwriting answers).

## Authentication

Every Layer 2 webhook validates the session token via `validate_session` RPC before returning data. Pattern repeated across all 22 session-token-protected workflows:

```
1. Extract `Authorization: Bearer <token>` from header
2. POST /rpc/validate_session
3. Check role membership (allowlist per webhook)
4. If allowlist mismatch → 403 + audit log
5. Carry user_id + user_role through the rest of the workflow
```

Allowlists per audience:

| Webhook audience | Roles allowed |
|---|---|
| Advisor pages | `advisor`, `sub_agent`, `mga_principal`, `admin` |
| MGA principal pages | `mga_principal`, `admin` |
| Compliance pages | `mga_principal`, `compliance_officer`, `admin` |
| Internal-only (cross-workflow) | INTERNAL_EMAIL_SECRET (no session) |
| Public webhooks (Stripe, Zoho, Twilio) | HMAC-verified signature |

## Authorization (row-level)

Server-side filtering enforces "advisors see only their book" without relying on Postgres RLS user mapping (n8n connects as service_role; user identity lives in the validated session payload):

- `advisor` / `sub_agent` → queries scope `WHERE assigned_advisor_id = session_user_id` (leads) and `WHERE advisor_id = session_user_id` (applications, commissions, reviews).
- `mga_principal` → sees all advisors under their tree (Phase 5b adds hierarchy expansion via `mga_hierarchy`; current MVP returns all if role=`mga_principal`).
- `compliance_officer` → read-only across all data.

## Data protection

### Encryption at rest

Sensitive PII columns are stored encrypted at the application layer using **AES-256-GCM** with a key from `LICENSE_ENCRYPTION_KEY` env var (base64-encoded 256-bit key):

- `advisor_licenses.license_number_encrypted` (companion `license_number_last4` for display)
- `advisor_eo_insurance.policy_number_encrypted` (companion `policy_number_last4` for display)
- (Future Phase 5b: SIN, banking — not in this commit's scope)

Encryption code lives in the workflow Code nodes (n8n's `crypto` builtin allowed via `NODE_FUNCTION_ALLOW_BUILTIN=crypto`). Plaintext values **never** sit on disk except via the encrypted columns.

Fail-safe: if `LICENSE_ENCRYPTION_KEY` is unset, the workflow tags the value as `PLAINTEXT_NO_KEY:<base64>` so Mary can detect the misconfiguration via grep. Phase 5b: enforce key presence at workflow startup (refuse to insert).

### Display-side redaction

API responses **never** return the encrypted columns. The `_last4` companion columns are returned for advisor-facing display:

- `clx-mga-insurance-advisor-overview-v1` returns `license_number_last4` only
- `clx-mga-insurance-principal-advisors-and-compliance-v1` returns advisor-level summary; full license details require dedicated detail endpoint with role check

Banking + SIN never appear in any API response — only the last 4 digits.

### TLS + HSTS

`_headers` enforces:

- HTTPS-only (HSTS: `max-age=31536000; includeSubDomains`)
- `frame-ancestors 'none'` (clickjacking)
- `connect-src 'self' https://automation.crystallux.org` (CSP — locks down API host)
- `Permissions-Policy: geolocation=(), microphone=(), camera=()` (no inadvertent device access)

## Audit trail

Every business event writes to `regulatory_audit_log` (vertical_id='insurance'). Soft FKs (no REFERENCES) so audit records survive related-row deletion — append-only by design. The `event_type` enumeration covers:

```
advisor_onboarding_started / advisor_onboarding_approved
license_verified / license_renewal_status_change
eo_insurance_verified
carrier_appointment_created
commission_calculated / commission_disputed
ce_hours_recorded
review_scheduled / review_triggered_by_signal / review_conducted
review_marked_overdue / review_escalated_overdue
review_video_requested / review_video_delivered / review_video_engagement
review_followup_dispatched
claim_filed / complaint_filed
```

A regulator request becomes a single SQL: `SELECT event_type, performed_by_role, occurred_at, event_data FROM regulatory_audit_log WHERE vertical_id='insurance' AND advisor_id=$1 ORDER BY occurred_at;`

Retention: 7 years (FSRA + FINTRAC minimum). Schema does not auto-delete; deletion is a manual compliance-officer action after retention.

## Credential management

**Hardcoded secrets are forbidden.** Every credential reference goes through:

1. **n8n env vars** (`/root/.n8n/.env`) — for workflow runtime: `LICENSE_ENCRYPTION_KEY`, `INTERNAL_EMAIL_SECRET`, `STRIPE_SECRET_KEY`, `HEYGEN_API_KEY`, `ANTHROPIC_API_KEY`, `R2_*`, `TWILIO_*`, etc.
2. **n8n credential vault** (UI-side) — for typed credentials: `Supabase Crystallux Custom`, `Stripe Crystallux`, `Twilio Crystallux`, `Cloudflare R2`, etc.

Credential references in workflow JSONs use **name only** (no `id`) — n8n resolves by name during import. This is the canonical pattern from `CLAUDE.md` and is enforced via the validation greps in the commit script.

## Input validation

Every webhook validates inputs at the Code node before any database write:

- **Required field checks** — return 400 if missing
- **Type coercion + range** — `parseInt`, `parseFloat`, `Math.min/max` clamps
- **Coverage minimums** — E&O policy must be ≥ $2M (200,000,000 cents)
- **Commission split validation** — `commission_split_*` fields must sum to 100 (±0.01)
- **Enum allowlist** — `review_type`, `priority`, `status`, etc. checked against valid lists
- **String length caps** — `notes`, `description`, `message` capped at sane bounds (200-4000 chars)

SQL injection is prevented by the Supabase REST API + n8n's parameterized JSON body construction. No string concatenation into SQL anywhere.

## Rate limiting + abuse prevention

Phase 5 MVP relies on:
- Cloudflare WAF rate limits at the edge (`automation.crystallux.org`)
- Supabase RLS + service-role-only policies (defence in depth — even a stolen workflow can't bypass)
- Audit log surveillance — anomalous patterns flagged via daily review

Phase 5b: per-endpoint rate limits inside n8n via a Redis-backed counter (already-existing infrastructure per `docs/setup/redis-security.md`).

## What's NOT in this build (Phase 5b/6)

- **Certn background check integration** — currently `background_check_status='pending'` is set manually. Phase 5b automates.
- **Per-province key rotation** — `LICENSE_ENCRYPTION_KEY` is single key for all jurisdictions. Phase 6 adds per-jurisdiction key with rotation playbook.
- **SIN encryption** — schema doesn't capture SIN yet. Phase 5b adds when carrier APIs require it.
- **Banking encryption** — same — Phase 5b adds with payment rail integration.
- **PEP / sanctions automation** — already deferred from Layer 2 Part A; same status.

## Compliance officer veto

Just as in Layer 2 Part A, the `compliance_officer` role retains override authority on every AI decision in Part B:

- AI flags review for human attention → compliance officer reviews via `/principal/compliance.html`
- Material complaint filed → both `mga_principal` AND `compliance_officer` notified; compliance officer can flag for FSRA notification
- License irregularity → automatically escalated to compliance officer queue

This is a **regulatory floor**, not optional.

## Cross-references

- Layer 2 Part A regulatory framework: [`REGULATORY_FRAMEWORK.md`](REGULATORY_FRAMEWORK.md)
- Vision: [`MGA_OPERATIONS_VISION.md`](MGA_OPERATIONS_VISION.md)
- Schema: [`../../db/migrations/insurance-mga-operations-schema.sql`](../../db/migrations/insurance-mga-operations-schema.sql)
- Existing Supabase RLS setup: [`../setup/supabase-rls-setup.md`](../setup/supabase-rls-setup.md)
- Existing Redis security: [`../setup/redis-security.md`](../setup/redis-security.md)
