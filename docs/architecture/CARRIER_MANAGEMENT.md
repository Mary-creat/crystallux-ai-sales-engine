# Carrier Management — Architecture

> **Status:** BUILT 2026-05-15. DORMANT until Mary applies the migration + activates the workflows after first carrier approval. Lives inside `admin.crystallux.org` at `/pages/carriers/*` — not a separate domain.

## Why this exists

Crystallux Financial Services (the MGA arm of Crystallux Inc.) places insurance business through 20–25 Canadian carriers. The carrier relationship has a full operational lifecycle:

1. **Identify** target carriers (`not_applied`).
2. **Apply** for an MGA appointment (`pending`).
3. **Sign** the MGA agreement (`approved`).
4. **Activate** with an agent code (`active`) — only now can we place business.
5. **Submit** policy applications per client.
6. **Track** commission expectations vs. payments.
7. **Reconcile** monthly carrier statements against expected commissions.
8. **Maintain** the relationship (suspended / terminated lifecycle as needed).

Steps 1–4 are appointment-lifecycle management. Step 5 is submission tracking. Steps 6–7 are commission ops. Each gets its own page in the admin console.

## Two carrier tables, two purposes

| Table | Layer | Purpose | Source |
|---|---|---|---|
| `insurance_carriers` | **Layer 2** (`vertical_id='insurance'`) | Product/availability registry. Which products, which provinces, AI-compliance-ready, digital-quote-ready, etc. Used by the policy-recommendation engine. | `db/migrations/carrier-integration-schema.sql` |
| `carriers` | **Layer 1** (no `vertical_id`, tenant-scoped on `client_id`) | Operational relationship. Appointment status, agent code, contracted product lines, expected commission %. Per-tenant. | `db/migrations/carrier-management-schema.sql` (this build) |

**Soft FK:** `carriers.carrier_code` ↔ `insurance_carriers.carrier_code`. When the insurance vertical wants "which carriers can I actually place with right now?", it joins the two on carrier_code filtered by `carriers.appointment_status='active'`.

This separation lets non-insurance verticals (mortgages, investments, etc.) reuse the operational ops layer without inheriting insurance-specific schema. The mortgage vertical will add `mortgage_lenders` (Layer 2 product registry) and use the same `carriers` table for ops.

## Schema (Layer 1 ops)

### `carriers`

The operational relationship per tenant.

| Column | Purpose |
|---|---|
| `client_id` (FK clients) | Tenant scope — each MGA tenant owns its own carrier appointments |
| `carrier_code` | Internal stable ID (e.g. `MANULIFE`, `SUNLIFE`). Soft-FK to `insurance_carriers.carrier_code`. |
| `carrier_name`, `carrier_type` | Human label + classification (`life`/`p_and_c`/`health`/`specialty`/`mga_wholesaler`/`digital_direct`) |
| `appointment_status` | `not_applied` → `pending` → `approved` → `active` → `suspended` / `terminated` |
| `appointment_applied_at`, `appointment_approved_at`, `appointment_effective_at`, `appointment_terminated_at` | Lifecycle timestamps |
| `agent_code` | Our agent/advisor code with this carrier (e.g. their internal account number for us) |
| `contracted_lines` (jsonb) | Product lines we're appointed to write (`["term_life","critical_illness",...]`) |
| `province_authorized` (jsonb) | Provinces we're appointed in (filter for compliance) |
| `contact_*` | Carrier rep details for this MGA relationship |
| `expected_commission_pct` | Standard commission rate this carrier pays us; used by the commission calculator |

### `carrier_submissions`

One row per policy application sent to a carrier.

| Column | Purpose |
|---|---|
| `carrier_id`, `lead_id`, `advisor_id`, `policy_application_id` | Joins back to leads, advisors, policy applications |
| `product_line` | Specific product (must be in `carriers.contracted_lines` for the carrier) |
| `submission_status` | `in_progress` → `submitted` → `underwriting` → `approved`/`declined` → `issued`/`not_taken`/`withdrawn` |
| `submitted_at`, `underwriting_decision_at`, `policy_issued_at` | Status-transition timestamps (auto-set by tracker workflow) |
| `policy_number`, `applicant_name`, `face_amount_cents`, `annual_premium_cents` | Application detail |
| `expected_commission_cents` | Set by the commission calculator |

### `carrier_commissions`

Expected vs. received commission rows.

| Column | Purpose |
|---|---|
| `submission_id` (FK) | Each submission has 1+ commission rows (first_year + renewals + trail) |
| `commission_type` | `first_year` / `renewal` / `trail` / `bonus` / `clawback` |
| `commission_year` | Year 1 for first_year, 2/3/... for renewals |
| `expected_amount_cents`, `expected_at` | What we expect to be paid, when |
| `received_amount_cents`, `received_at` | Backfilled by reconciliation workflow |
| `reconciliation_id` (FK) | Which reconciliation marked this row received |
| `status` | `expected` → `received` / `underpaid` / `overpaid` / `disputed` / `written_off` |

### `carrier_reconciliations`

Monthly statement-matching per carrier.

| Column | Purpose |
|---|---|
| `reconciliation_period` | `YYYY-MM` |
| `statement_amount_cents` | What the carrier paid us this month |
| `matched_commissions_cents` | Sum of `carrier_commissions` rows in the period (computed by the reconciliation workflow) |
| `status` | `pending` / `partial` / `matched` (within 5%) / `discrepancy` / `disputed` |
| `statement_url` | Where the PDF lives (Cloudflare R2 / Supabase Storage when wired) |
| `reconciled_by`, `reconciled_at` | Audit trail |

UNIQUE constraint on `(carrier_id, reconciliation_period)` prevents double-recording the same month.

## Workflows

All under `workflows/api/carriers/`. All `active: false`. Auth: admin session via existing `validate_session` RPC.

| Workflow | Trigger | Purpose |
|---|---|---|
| `clx-carriers-status-check-v1` | Cron Mon 08:00 + POST `/api/carriers/status-check` | Returns appointment funnel counts, stale-pending list (>30 days), full carrier table enriched with 90-day submission counts + premium volume per carrier. Powers `overview.html`. |
| `clx-carriers-update-v1` | POST `/api/carriers/update` | Admin PATCH on a carrier row. Whitelisted columns. Powers `appointments.html` edits. |
| `clx-carriers-submission-tracker-v1` | POST `/api/carriers/submission` | Create or update a `carrier_submissions` row. Auto-sets transition timestamps based on the new status. Powers `submissions.html` form. |
| `clx-carriers-commission-calculator-v1` | POST `/api/carriers/commission-calc` | Given submission_id, looks up parent carrier's `expected_commission_pct`, multiplies by annual premium, upserts `carrier_commissions` at `status='expected'`. Accepts `override_pct` for carrier-specific deviations. Powers `commissions.html` calculator. |
| `clx-carriers-reconciliation-v1` | POST `/api/carriers/reconciliation` | Given (carrier_id, period, statement_amount_cents), creates `carrier_reconciliations` row, sums expected commissions in the period, computes match status (matched within 5% / partial / discrepancy), bulk-PATCHes matched commission rows to `status='received'`. Powers `reconciliation.html` form. |

## Frontend

All under `admin-dashboard/pages/carriers/`. All gated by `clxAuth.require(['admin'])`. Sub-nav across the 5 pages.

| Page | What Mary sees |
|---|---|
| `overview.html` | Stat grid + stale-pending banner + full carrier table |
| `appointments.html` | Per-row edit form for appointment lifecycle, agent code, commission %, contact info |
| `submissions.html` | Pipeline table + "+ New submission" form |
| `commissions.html` | Recalc form + outstanding commissions list (list endpoint pending) |
| `reconciliation.html` | Statement record form + match result + reconciliation history (list endpoint pending) |

## What's intentionally incomplete

For commit-scope reasons, list-style GET endpoints aren't built for every table yet. The frontend pages render data from `/api/carriers/status-check` (the only GET that exists), and individual write endpoints power the forms. List endpoints needed to fully populate the pages:

- `GET /api/carriers/submissions/list` (filterable by carrier, status, date range)
- `GET /api/carriers/commissions/outstanding` (sorted by expected_at)
- `GET /api/carriers/reconciliations/list` (sorted by period DESC)

These are noted in each affected page with a graceful empty-state message pointing to direct Supabase reads as the interim. Add in a follow-up commit when Mary needs them.

## Tenant scope

Every table has `client_id` referencing `clients`. The seed runs under the Crystallux Financial Services tenant (`6edc687d-07b0-4478-bb4b-820dc4eebf5d`). When another MGA tenant onboards onto the platform, they get their own `client_id` and their own seed of 23 carriers (currently the seed only handles the one tenant — multi-tenant seed expansion would be a follow-up workflow that copies the canonical list per new tenant).

## See also

- [`docs/handbook/CARRIER_OPS_GUIDE.md`](../handbook/CARRIER_OPS_GUIDE.md) — Mary's day-to-day playbook for the carrier ops console.
- [`db/migrations/carrier-management-schema.sql`](../../db/migrations/carrier-management-schema.sql) — the schema + seed.
- [`db/migrations/carrier-integration-schema.sql`](../../db/migrations/carrier-integration-schema.sql) — the Layer 2 product-availability schema this build sits beside.
- [`workflows/api/carriers/`](../../workflows/api/carriers/) — the 5 workflows.
- [`admin-dashboard/pages/carriers/`](../../admin-dashboard/pages/carriers/) — the 5 frontend pages.
