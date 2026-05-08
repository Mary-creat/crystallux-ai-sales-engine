# Crystallux roles — canonical reference

> **Source:** `auth_users.user_role` enum (CHECK constraint in [`db/migrations/role-enum-update.sql`](../../db/migrations/role-enum-update.sql)).
> **Universal multi-vertical:** roles apply across every Crystallux vertical (insurance, real estate, mortgage, dental, consulting, construction, agencies, financial advisors, more). Some roles are vertical-scoped (advisor / mga_principal currently insurance-licensed); the rest are universal.
> **Tenant isolation:** every role except `admin` and `agent` has a `client_id` — the tenant they belong to. Cross-tenant access is impossible by design (RLS on every client-scoped table + server-side `client_id` resolution from session token).

## The 9 roles

| Role | Scope | Tenant | Phase |
|------|-------|--------|-------|
| `admin`              | universal | none (platform-wide) | shipped |
| `client`             | universal | own client_id        | shipped |
| `team_member`        | universal | own client_id        | shipped |
| `agent`              | universal | none (system actor)  | Phase 3 |
| `advisor`            | insurance-first | own client_id   | Phase 4 |
| `supervisor`         | universal | own client_id        | Phase 4+ |
| `mga_principal`      | insurance | own client_id (MGA)  | Phase 6+ |
| `compliance_officer` | regulated verticals | own client_id | Phase 6+ |
| `sub_agent`          | insurance MGA model | own client_id | Phase 6+ |

---

### `admin`

**Description:** Mary or Crystallux platform operators. Full platform visibility.
**Vertical scope:** universal.
**Tenant:** none — `client_id IS NULL`.
**CAN see:** everything across all clients (`SELECT *` via service_role).
**CAN do:** every action; activate workflows; query DB via Copilot; impersonate clients for support.
**CANNOT do:** bypass written audit trail (every admin action logs to `admin_action_log`).
**Cross-tenant:** unrestricted by design.
**Hierarchy:** top of the tree.

### `client`

**Description:** the paying SaaS tenant — the brokerage company / agency / practice that subscribed to Crystallux.
**Vertical scope:** universal.
**Tenant:** own `client_id`.
**CAN see:** their own pipeline (leads, bookings, campaigns, billing, settings) — scoped by `client_id` server-side.
**CAN do:** open Client Assistant ✦, send outreach (with the engine), manage subscription, invite team_members, configure ICP + outreach voice.
**CANNOT do:** see other clients' data, access admin pages (redirected to login), call admin webhooks (returns 403).
**Cross-tenant:** never. RLS + server-side session client_id resolution prevents leakage even if request body is tampered with.
**Hierarchy:** owns `team_member`, `advisor`, `supervisor`, `sub_agent` rows under their `client_id`.

### `team_member`

**Description:** a sub-user under a `client` (e.g., a junior person at the brokerage). Equivalent permissions to `client` but separately authenticated for audit.
**Vertical scope:** universal.
**Tenant:** own `client_id` (matches the parent client).
**CAN see / CAN do / CANNOT do:** identical to `client`.
**Hierarchy:** under `client`.

### `agent`

**Description:** the AI Sales Agent system actor. Logs every autonomous action it takes against `agent_actions` so there's a full audit trail of who-did-what (agent vs human).
**Vertical scope:** universal.
**Tenant:** none — `client_id IS NULL`. Agent acts on behalf of any client tenant via tenant-scoped function calls; the audit lives in `agent_actions` linked to the tenant context.
**CAN see:** read-only access to leads, bookings, campaigns, behavioral_signals, agent_memory — for the tenant context it's currently acting on.
**CAN do:** write to agent_* tables (decisions / actions / conversations / memory / escalations / costs). Send outreach via the existing multi-channel workflows. Mark behavioral signals as acted-on. Escalate to humans (writes to `agent_escalations`).
**CANNOT do:** read human PII outside of the lead context (no scanning team_members.email, no reading auth_users at all). Cannot modify pricing, billing, or platform config. Cannot access another tenant.
**Cross-tenant:** every read + write is gated by an explicit tenant context the agent must declare per action; the RLS allows it because service_role, but the audit record makes any leak detectable.
**Hierarchy:** non-human; reports to `client` for that tenant via escalation rules.

### `advisor`

**Description:** licensed closer at a tenant. Currently scoped to the **insurance vertical** because the role implies a licensing primitive (FSRA / LLQP) that other verticals don't share. Equivalent role names for other verticals (real-estate "agent", dental "hygienist") will be added as those verticals mature.
**Vertical scope:** insurance vertical first. Other verticals get equivalent role rows in Phase 4+.
**Tenant:** own `client_id` (matches the brokerage).
**CAN see:** leads + bookings assigned to them (`bookings.advisor_id = self`), their own productivity metrics, their own behavioral-trigger queue, their own scripts / closing intelligence library scoped to their niche.
**CAN do:** mark leads acted-on, accept/reject behavioral triggers, open Client Assistant ✦, see (their own) live-call transcripts + post-call coaching.
**CANNOT do:** see other advisors' books, see admin pages, modify billing, modify niche overlays.
**Cross-tenant:** never.
**Hierarchy:** reports to `supervisor` (and ultimately `mga_principal` in the MGA model, or `client` in the brokerage model).

### `supervisor`

**Description:** oversees advisors within one tenant. Reads-only across the team.
**Vertical scope:** universal.
**Tenant:** own `client_id`.
**CAN see:** roll-up of all advisors' productivity, leaderboard, at-risk callouts, team-level pipeline metrics, their own dashboard view (the `#teamProductivitySection` panel).
**CAN do:** issue coaching prompts (writes to `agent_decisions` with `reason='coaching'`), reorder advisor task queues, escalate red-flag advisors to `client` or `mga_principal`.
**CANNOT do:** see another tenant's advisors. Cannot access admin pages. Cannot modify billing.
**Cross-tenant:** never.
**Hierarchy:** reports to `client` or `mga_principal`.

### `mga_principal`

**Description:** insurance MGA agency principal. The role exists specifically for the Crystallux MGA business line — see `BUSINESS_PLAN.md §5`.
**Vertical scope:** insurance only.
**Tenant:** own `client_id` (the MGA tenant). Sub-agents under the MGA share that `client_id`.
**CAN see:** rollup across all `advisor` + `sub_agent` rows under their MGA. Override commission ledger. Carrier contract list. CE tracking for their sub-agents. Compliance documents.
**CAN do:** invite sub-agents, configure carrier contracts, approve / decline behavioral-trigger queue items at the MGA level, generate the daily principal briefing email.
**CANNOT do:** see another MGA's data (cross-tenant). Cannot impersonate sub-agents. Cannot bypass FSRA / RIBO compliance gates.
**Cross-tenant:** never.
**Hierarchy:** top of the MGA tenant tree; supervises `advisor` + `sub_agent` rows.

### `compliance_officer`

**Description:** dedicated audit / compliance role for regulated verticals (insurance FSRA + RIBO; future: dental CDA, legal LSO). Read-only with full visibility into the audit log.
**Vertical scope:** regulated verticals only.
**Tenant:** own `client_id`.
**CAN see:** every action taken by every user in their tenant (writes to `admin_action_log` and `agent_actions` are visible). Compliance documents (KYC, E&O, sub-agent contracts). FSRA-relevant transcripts and recordings (with consent gates).
**CAN do:** export audit reports (PDF generation), flag actions for review, freeze agent autonomous-mode for a specific lead pending review.
**CANNOT do:** modify any data (read-only by policy). Cannot see other tenants.
**Cross-tenant:** never.
**Hierarchy:** parallel to `client` / `mga_principal`; reports to external regulator on behalf of the tenant.

### `sub_agent`

**Description:** junior advisor under supervision in the insurance MGA model. Reduced autonomy compared to `advisor` — many actions require `supervisor` or `mga_principal` approval.
**Vertical scope:** insurance MGA model only (Phase 6+).
**Tenant:** own `client_id` (the MGA's).
**CAN see:** their own assigned leads, their own bookings, their own productivity self-view, their own scripts library (FSRA-tuned).
**CAN do:** send outreach (logged + reviewable), book meetings, mark leads acted-on, request supervisor escalation.
**CANNOT do:** auto-send any high-sensitivity outreach (always queue for supervisor review). Cannot see other sub-agents' books. Cannot access carrier contract details (only `mga_principal` + `compliance_officer`).
**Cross-tenant:** never.
**Hierarchy:** reports to `advisor` or `supervisor` or directly to `mga_principal`.

---

## RLS pattern (server-side enforcement)

Every client-scoped table has the same pattern:

```sql
ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;

-- service_role bypasses everything (used by n8n)
CREATE POLICY <table>_service_role
  ON <table> FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- Anon never reads directly (workflows route via service_role with
-- client_id pulled from validated session row)
```

The actual tenant scoping happens **inside workflows**: every webhook reads `client_id` from the session row (via `validate_session` RPC) and uses that for downstream queries. The session row is the source of truth — request body is never trusted.

## Webhook role gates (what's enforced today)

Every admin webhook runs:
```js
if (row.user_role !== 'admin') return { json: { ok: false, status: 403, error: 'Admin access required' } };
```

Every client webhook runs:
```js
const allowedRoles = ['client', 'team_member'];
if (allowedRoles.indexOf(row.user_role) === -1) return { json: { ok: false, status: 403, error: 'Tenant access required' } };
```

Phase 4 advisor webhooks will run:
```js
const allowedRoles = ['advisor', 'supervisor', 'mga_principal'];
```

The `client/copilot/ask` and `client/copilot/transcribe` webhooks added in this session use a broader allowlist — `['client','team_member','advisor','supervisor','mga_principal']` — because the Assistant should work for any tenant role.

## Reporting hierarchy

```
                       ┌─────────────────┐
                       │     admin       │   (platform-wide; no client_id)
                       └─────────────────┘
                                 ▲
                                 │ (impersonate / support)
                                 │
              ┌──────────────────┴──────────────────┐
              │                                     │
       ┌──────▼──────┐                       ┌──────▼──────┐
       │   client    │                       │mga_principal│
       │  (tenant)   │                       │  (tenant)   │
       └──────┬──────┘                       └──────┬──────┘
              │                                     │
        ┌─────┼─────┐                  ┌────────────┼────────────┐
        ▼     ▼     ▼                  ▼            ▼            ▼
  team_   advisor supervisor      compliance_   advisor      sub_agent
  member                          officer
                                                  │
                                                  ▼
                                              sub_agent

      ┌────────────┐
      │   agent    │   (universal system actor; no client_id; acts on behalf of any tenant)
      └────────────┘
```

## Cross-references

- Migration: [`db/migrations/role-enum-update.sql`](../../db/migrations/role-enum-update.sql)
- Auth schema: [`docs/architecture/migrations/2026-04-28-authentication.sql`](migrations/2026-04-28-authentication.sql)
- Dashboard role gating: [`OPERATIONS_HANDBOOK.md`](OPERATIONS_HANDBOOK.md) §26
- AI Agent vision: [`docs/agent/AGENT_VISION.md`](../agent/AGENT_VISION.md)
- MGA business line: [`BUSINESS_PLAN.md`](BUSINESS_PLAN.md) §5
