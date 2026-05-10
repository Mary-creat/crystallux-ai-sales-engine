# MGA Operations Vision (Insurance — Layer 2 Part B)

> **Audience:** Mary, MGA principal, advisors, future MGA operators reviewing how Crystallux runs the operational backbone of an insurance MGA.

## The thesis

A traditional insurance MGA is bottlenecked on three operational lifts:

1. **Agent onboarding** — license verification, E&O proof, background checks, carrier appointments. Today: 4-8 weeks per advisor. With Crystallux: ~3-5 days, gated only on Certn turnaround.
2. **Commission accuracy** — per-policy splits across carrier ↔ MGA ↔ advisor ↔ sub-agent get hand-keyed into spreadsheets that grow chaotic at scale. Crystallux: every issued policy auto-creates a `commission_ledger` row from the binding `carrier_appointments` split row, payouts batch monthly with full audit.
3. **License + E&O monitoring** — advisors get suspended for missing renewal dates that sat unflagged in someone's calendar. Crystallux: daily monitor flips `renewal_status` at 60/30/14/7/1-day thresholds and pings advisor + escalates to MGA principal.

**Layer 2 Part B builds the operational backbone. Layer 2 Part A built the AI compliance engine. Together they remove the entire manual middle of MGA operations.**

## What's in Part B

### MGA hierarchy + advisor lifecycle

- `mga_hierarchy` — principal/parent/child relationships with `effective_date` + `end_date` for clean termination accounting.
- `advisor_onboarding` — structured 5-step lifecycle (license / E&O / background / training / contract). Status transitions are explicit, idempotent, auditable. The `clx-mga-insurance-onboarding-completion-v1` workflow refuses to flip `status='approved'` until ALL gates pass — no shortcut path.
- `advisor_licenses` — per-jurisdiction license tracking with **encrypted license number** (AES-256-GCM, key in `LICENSE_ENCRYPTION_KEY` env), `_last4` for display, daily renewal-status monitor.
- `advisor_eo_insurance` — E&O coverage rows; minimum $2M enforced at the `clx-mga-insurance-eo-insurance-verification-v1` validation step.

### Commission ledger

- `carrier_appointments` — per-advisor per-carrier authorization with `commission_split_carrier` + `commission_split_mga` + `commission_split_advisor` percentages enforced to sum to 100 at insert time.
- `commission_ledger` — one row per issued policy. Auto-calculated by `clx-mga-insurance-commission-calculate-v1` when `policy_applications.submission_status='issued'` flips. Splits in cents (integer math, no floating-point drift).
- Monthly batch (`clx-mga-insurance-commission-payout-batch-v1`) on the 15th: aggregates pending entries → `payout_status='processing'` + emits CSV-friendly summary into `admin_action_log` for Mary to execute manual bank transfers (Phase 5 MVP). Phase 6 wires to a payment-rail integration.
- Disputes (`clx-mga-insurance-commission-dispute-v1`): advisor flags an entry → `payout_status='held'` → mga_principal notified.

### Comprehensive review management (the core differentiator)

Layer 2 Part B's biggest contribution is treating the **policy review** as a first-class object with 7 distinct types and a unified video-driven engagement layer. Full detail in [`REVIEW_MANAGEMENT_VISION.md`](REVIEW_MANAGEMENT_VISION.md). Summary:

- 7 review types: `pre_issuance` / `annual` / `triggered_event` / `renewal` / `claim` / `compliance_audit` / `complaint`
- Behavioral signal → review pipeline: a `birthday` signal becomes an annual review with celebratory video; a `marriage` signal becomes a triggered_event review with congratulatory video; a `claim_filed` event becomes an urgent claim review with supportive video.
- Daily scheduler (`clx-mga-insurance-review-scheduler-v1`) creates annual + renewal + audit reviews automatically. Triggered reviews fire on demand from BI signals via `clx-mga-insurance-review-triggered-event-v1`.
- Daily overdue monitor escalates 30+ day overdue reviews to MGA principal.

### Frontend

`insurance-mga-dashboard/` — separate top-level Cloudflare Pages site (mirror of `admin-dashboard/` and `client-dashboard/` patterns). Plain HTML + plain JS, no framework. 9 pages total:
- `login.html` (role-gated to advisor/sub_agent/mga_principal/compliance_officer/admin)
- `advisor/{overview, leads, reviews, applications, commissions}.html`
- `principal/{overview, advisors, compliance}.html`

Vertical badge ("Insurance MGA") visible in topbar on every page — visual reinforcement of the multi-vertical architecture.

## Component shipped (operational diagram)

```
Onboarding flow
─────────────────────────────────────────────────────────────────
mga_principal → onboarding-start → advisor created (status=pending)
  ↓
advisor → license-verification (encrypts) → E&O verification → wait
  ↓
mga_principal → carrier-appointment-create (one or more)
  ↓
mga_principal → onboarding-completion (gates on ALL steps) → status=approved → user activated

Commission flow
─────────────────────────────────────────────────────────────────
policy_applications.submission_status='issued' (Part A workflow)
  → commission-calculate (reads carrier_appointments split %)
  → commission_ledger row inserted
  → policy_applications.commission_ledger_id linked
  → audit log

Monthly batch (15th 06:00 UTC):
  → commission-payout-batch
  → aggregates by advisor + by principal
  → marks pending → processing
  → CSV emitted to admin_action_log (Mary executes manually)

Review flow (the core loop)
─────────────────────────────────────────────────────────────────
Daily 05:00 UTC: review-scheduler scans in-force policies
  → creates annual / renewal / compliance_audit reviews
  → fires video generator for each (annual + renewal only)

Behavioral signal lands (BI pipeline):
  → review-triggered-event maps signal_type → trigger
  → creates triggered_event review (priority=high, due in 7d)
  → fires video generator immediately

Video generator pipeline:
  → looks up matching video_review_templates row
  → Claude personalizes script with lead context
  → chains existing clx-video-script-generator-v1 (commit 25c0886)
  → HeyGen renders video → R2 stores → landing page ready
  → video-deliver sends WhatsApp/email with personal intro
  → engagement-tracker updates video_engagement_status as client interacts

Daily 09:00 ET: review-followup
  → 'sent' >3d no engagement → AI WhatsApp nudge
  → 'viewed' >7d no reply → AI personal followup
  → 'replied' >7d no booking → notify advisor
```

## What's NOT in Part B (deferred)

- **Background check automation** — Certn integration. Currently `background_check_status='pending'` and Mary updates manually. Phase 5b activates Certn webhook → automatic flip when results come back.
- **Real payment rail** — commission payout batch emits CSV; Mary executes bank transfers manually. Phase 6 wires to Stripe Connect or Wise.
- **Per-province license variants** — current MVP works for Ontario (FSRA). Quebec / BC / AB jurisdictions need their own renewal calendars + CE rules. Phase 5b ships the per-province extension.
- **MGA hierarchy expansion in webhooks** — current `clx-mga-insurance-advisor-leads-v1` returns advisor's own leads OR all leads if `mga_principal`. Sub-hierarchy expansion (mga_principal sees only their tree, not the whole org if multi-MGA) lands in Phase 5b once `mga_hierarchy` is populated.
- **Insurer-facing dashboard + production reports** — Layer 2 Part C (final session of the trilogy).

## Numbers (cost envelope)

| Operational lift | Traditional MGA | Crystallux Layer 2 Part B |
|---|---|---|
| Onboard 1 advisor | $400-800 (clerk time + admin overhead) | $25 (Stripe Identity + Zoho contract) |
| Calculate 1 month of commissions | 8-12 hours bookkeeper | 0 (auto-populated) |
| Send 1 annual policy review | $40-80 (advisor time + materials) | $0.40 (HeyGen + Claude tokens) |
| Catch a license expiring in 14 days | manual calendar / hope | automatic email + dashboard alert |
| Process a triggered behavioral review (birthday/baby/marriage) | impossible to scale manually | $0.40, instantaneous |

## Cross-references

- Schema: [`db/migrations/insurance-mga-operations-schema.sql`](../../db/migrations/insurance-mga-operations-schema.sql)
- Review system deep-dive: [`REVIEW_MANAGEMENT_VISION.md`](REVIEW_MANAGEMENT_VISION.md)
- Video engagement deep-dive: [`VIDEO_ENGAGEMENT_STRATEGY.md`](VIDEO_ENGAGEMENT_STRATEGY.md)
- Security framework: [`SECURITY_FRAMEWORK.md`](SECURITY_FRAMEWORK.md)
- Layer 2 Part A (compliance engine): [`AI_COMPLIANCE_VISION.md`](AI_COMPLIANCE_VISION.md)
- Multi-vertical architecture: [`../architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md`](../architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md)
- Workflows: `workflows/api/insurance-mga/clx-mga-insurance-*-v1.json` (29 in this commit)
- Frontend: `insurance-mga-dashboard/` (9 pages + shared)
