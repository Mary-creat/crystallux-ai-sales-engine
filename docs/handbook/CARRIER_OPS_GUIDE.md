# Carrier Operations Guide

> Day-to-day playbook for the **Carriers** section of `admin.crystallux.org`. Read once when you first activate; reference per task afterward.

## The five pages, in the order you'll use them

1. **Overview** (`/pages/carriers/overview.html`) — start of day. Stat grid, stale-pending banner, full carrier list.
2. **Appointments** (`/pages/carriers/appointments.html`) — when a carrier emails you ("we approved your MGA agreement" / "your agent code is X").
3. **Submissions** (`/pages/carriers/submissions.html`) — every time an advisor sends an application to a carrier.
4. **Commissions** (`/pages/carriers/commissions.html`) — when a policy gets issued, run the calculator to record what the carrier owes you.
5. **Reconciliation** (`/pages/carriers/reconciliation.html`) — once a month, when each carrier's statement arrives.

## Lifecycle walkthrough — first carrier appointment

### Step 0 — Pre-flight

Run the migration once: `psql "$DATABASE_URL" -f db/migrations/carrier-management-schema.sql`. This creates the 4 tables and seeds 23 Canadian carriers under the Crystallux Financial Services tenant. PolicyMe / Walnut / Apollo are pre-seeded at `pending` (your priority targets); the other 20 are at `not_applied`.

Then import the 5 workflows from `workflows/api/carriers/` into n8n and activate them. The Carriers page won't load anything until the workflows are active.

### Step 1 — Apply for an appointment

You decide to apply to Manulife.

1. Go to **Appointments**. Find Manulife in the table. Click **Edit**.
2. Change `appointment_status` from `not_applied` to `pending`.
3. Set `appointment_applied_at` to today.
4. Add contact email / phone if you have them.
5. Save.

The Overview page will now show Manulife in the "Pending applications" stat.

### Step 2 — Wait. Watch for stale.

If Manulife sits in `pending` for more than 30 days, it'll show up in the **stale-pending banner** on the Overview page (also surfaced as part of the weekly Monday 08:00 cron — eventually we'll route this into Sentinel alerts). Follow up with your Manulife rep.

### Step 3 — Get approved

Manulife sends the MGA agreement. You sign. They issue your agent code.

1. **Appointments** → find Manulife → **Edit**.
2. Change `appointment_status` to `approved`. Set `appointment_approved_at` to today.
3. Wait for the agent code (sometimes same day, sometimes a week later).
4. When the agent code arrives, **Edit** again: paste the agent code into `agent_code`, change `appointment_status` to `active`, set `appointment_effective_at` to today, and set `expected_commission_pct` (e.g. `50` for 50% first-year on term life).
5. Save.

Manulife is now in the "Active appointments" stat on Overview. You can start placing business.

### Step 4 — Submit your first application

Advisor sends Mrs. Smith's 20-year term life application to Manulife.

1. **Submissions** → click **+ New submission**.
2. Select carrier = Manulife, product_line = term_life, status = submitted (or in_progress if they're still preparing it).
3. Enter applicant name, face amount, annual premium.
4. Click **Save submission**.

When Manulife sends underwriting decisions, come back to update the row's `submission_status` to `approved` or `declined` (auto-sets `underwriting_decision_at`). When the policy issues, set status to `issued` with `policy_number` (auto-sets `policy_issued_at`).

### Step 5 — Record expected commission

Once a policy is `issued`, you know roughly what commission to expect.

1. **Commissions** → paste the submission ID into the calculator form.
2. (Optional) override commission % if Manulife is paying a different rate than your standard.
3. Click **Calculate**. The system shows you the math (premium × commission_pct = expected_amount) and writes a `carrier_commissions` row at `status='expected'`.

If you have multi-year trail commissions to track, repeat with `commission_type='renewal'` and `commission_year=2`/3/etc — currently this requires direct Supabase edits since the form only handles `first_year` (follow-up improvement).

### Step 6 — Reconcile the monthly statement

End of month, Manulife sends you their commission statement: e.g. $14,250 for May 2026.

1. **Reconciliation** → select carrier = Manulife, period = `2026-05`, statement amount = `14250`, statement URL (link to the PDF).
2. Click **Record**.

The system:
- Sums all `carrier_commissions` rows for Manulife where `expected_at` falls in May 2026.
- Compares your expected total against the statement amount.
- If within 5%: marks `status='matched'`. Bulk-PATCHes the matched commission rows to `received`.
- If >5% over: marks `partial` (extra payments — investigate).
- If >5% under: marks `discrepancy` (Manulife shorted you — follow up).

The result banner shows you the delta + how many commission rows were marked received.

## When something goes wrong

| Symptom | What it means | Fix |
|---|---|---|
| Stale-pending banner stuck on a carrier | Application sat past 30 days | Call/email the carrier rep; if they declined, update status to `terminated` with reason. |
| Commission `status='underpaid'` | Carrier paid less than you calculated | Either your `expected_commission_pct` is wrong (carrier paying less than standard) or carrier owes you money. Investigate. |
| Reconciliation `status='discrepancy'` | Statement materially under expectations | Pull the carrier's payment detail; usually means a chargeback or NSF or an issued policy not_taken. |
| Carrier disappears from "Active" dropdown | Appointment got `suspended` or `terminated` somehow | Check `appointment_status` on the carrier row. |

## Monthly cadence

- **1st of month**: each carrier statement should arrive within 5 business days. Record each via Reconciliation.
- **Mid-month**: any reconciliations stuck at `discrepancy` should be resolved this week.
- **Last week**: check Submissions pipeline — any `submitted` rows from >60 days ago that haven't reached `underwriting_decision` need a status update (carrier follow-up).

## Activation checklist

- [ ] Run `carrier-management-schema.sql` in Supabase.
- [ ] Verify 23 carriers seeded (20 `not_applied` + 3 `pending`).
- [ ] Import 5 workflow JSONs from `workflows/api/carriers/` into n8n.
- [ ] Activate the 5 workflows.
- [ ] Open `admin.crystallux.org/pages/carriers/overview.html` — should show 23 carriers.
- [ ] Run smoke test: edit a carrier on Appointments, save, refresh — change persists.

Built but DORMANT until activation. See `docs/architecture/CARRIER_MANAGEMENT.md` for technical detail.
