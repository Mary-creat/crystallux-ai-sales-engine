# docs/operations/ — Operational Playbooks Index

Process documents for running Crystallux day-to-day: support, onboarding, check-ins, retention, renewals, incidents, legal templates, hiring.

Every file is copy-ready. Mary customises names and specifics; no outlines requiring drafting.

---

## Files in this folder

### Client-facing operational flows

- **[SUPPORT_FLOW.md](./SUPPORT_FLOW.md)** — info@crystallux.org management, SLAs, triage, 10 response templates for common issues, tool progression.
- **[ONBOARDING_CALL_SCRIPT.md](./ONBOARDING_CALL_SCRIPT.md)** — 30-minute post-contract kickoff call with pre-call email, agenda, post-call checklist, objection handling.
- **[WEEKLY_CHECK_IN.md](./WEEKLY_CHECK_IN.md)** — 15-minute weekly client rhythm with agenda, metrics format, "results aren't what I expected" framework, follow-up template.
- **[CLIENT_SUCCESS_PLAYBOOK.md](./CLIENT_SUCCESS_PLAYBOOK.md)** — milestone-based retention tracking by week/month, 8 early-warning-of-churn signals with intervention playbook, QBR format for month 3+.
- **[RENEWAL_CHURN_PREVENTION.md](./RENEWAL_CHURN_PREVENTION.md)** — 90/60/30 day pre-renewal sequence, downgrade handling, churn handling, 3/6/12-month reactivation sequences with templates.
- **[PAYMENT_FOLLOW_UP.md](./PAYMENT_FOLLOW_UP.md)** — day 0/3/7/14/30 failed-payment recovery, pre-expiry card reminder, reactivation terms.

### Legal templates (all require lawyer review — noted at top of each)

- **[CLIENT_CONTRACT_TEMPLATE.md](./CLIENT_CONTRACT_TEMPLATE.md)** — Master Services Agreement. 19 clauses + Exhibit A (Services Config) + Exhibit B (SLA reference). Ontario jurisdiction, ADRIC arbitration, 12-month Founding Rate lock.
- **[TERMS_OF_SERVICE.md](./TERMS_OF_SERVICE.md)** — crystallux.org public-facing ToS. 17 clauses covering acceptance, service description, CASL/PIPEDA obligations, fees, privacy cross-reference, IP, warranty disclaimer, liability cap, indemnification, modifications, termination, Ontario governing law.
- **[PRIVACY_POLICY.md](./PRIVACY_POLICY.md)** — PIPEDA-compliant privacy policy. 16 clauses including Privacy Officer identification, 9 third-party service-provider disclosures with international-transfer language, 5 PIPEDA rights with exercise instructions, Quebec Law 25 addendum.

### Technical operations

- **[INCIDENT_RESPONSE.md](./INCIDENT_RESPONSE.md)** — P0/P1/P2/P3 severity definitions + response SLAs + 4 communication templates + post-mortem template + on-call rotation + status-page setup.

### Team + growth

- **[VA_ONBOARDING_RUNBOOK.md](./VA_ONBOARDING_RUNBOOK.md)** — first-VA hire: role definition, $10-25/hr compensation range, sourcing, 40-hour first-week training plan, ongoing management cadence, access management.
- **[WEEKLY_BUSINESS_REVIEW.md](./WEEKLY_BUSINESS_REVIEW.md)** — Monday planning + Friday review templates, weekly/monthly/quarterly metrics dashboards, red-flag triggers, anti-patterns.
- **[HIRING_PLAN.md](./HIRING_PLAN.md)** — trigger-based hire sequence: VA (5 clients), Sales Rep (10), Technical Contractor (15), CSM (20), Content/Marketing (30). Budgets, interview processes, anti-patterns.

---

## Suggested deployment order (first 30 days)

### Pre-first-client (before a contract is signed)

1. **CLIENT_CONTRACT_TEMPLATE.md** → lawyer review (7-14 days) → finalise
2. **TERMS_OF_SERVICE.md** + **PRIVACY_POLICY.md** → lawyer review → publish on crystallux.org
3. **SUPPORT_FLOW.md** → set up info@crystallux.org auto-responder, Gmail labels
4. **INCIDENT_RESPONSE.md** → configure Slack webhook alerts from clx-error-monitor-v1

### First 3 clients (weeks 2-3)

5. **ONBOARDING_CALL_SCRIPT.md** → Mary runs kickoff calls using the script
6. **WEEKLY_CHECK_IN.md** → first weekly check-in on day 7 for every client
7. **CLIENT_SUCCESS_PLAYBOOK.md** → milestone tracking begins week 1

### Month 1 retention infrastructure (weeks 3-4)

8. **RENEWAL_CHURN_PREVENTION.md** → activates after first month's data; put month-9 calendar reminders in place for all founding clients
9. **PAYMENT_FOLLOW_UP.md** → activated automatically via clx-stripe-webhook-v1 once Stripe is live

### Month 2+ (scaling)

10. **VA_ONBOARDING_RUNBOOK.md** → hire VA at 5 concurrent clients
11. **WEEKLY_BUSINESS_REVIEW.md** → Monday + Friday rhythm starts day 1 of business, not "eventually"
12. **HIRING_PLAN.md** → consulted at every trigger threshold

---

## Cross-references

- Commercial collateral: see `../commercial/README.md`
- Mary's own outbound cadence: see `../mary-outreach/README.md`
- Master activation checklist: see `../MARY_ACTIVATION_CHECKLIST.md` (Phase 10: Commercial & Operational Activation)
- Vertical-specific operational notes: see `../verticals/{vertical}/README.md`

---

## Principles applied across every file

- **Copy-ready.** No outlines; every template is ready to send.
- **Canadian context.** PIPEDA in data handling, CASL in outreach, Ontario jurisdiction, GST/HST in billing.
- **Specific numbers.** SLAs with hours and days, budgets with CAD ranges, metrics with thresholds.
- **Trigger-based, not time-based.** Hiring, renewals, and interventions are gated on metrics, not calendar.
- **Mary-protective.** Every template reduces Mary's cognitive load: deterministic sequences, escalation rules, fall-back options.

---

## Legal disclaimer summary

Files that explicitly require Canadian lawyer review before production use:

- `CLIENT_CONTRACT_TEMPLATE.md` — Ontario business lawyer, $500-1,500
- `TERMS_OF_SERVICE.md` — same lawyer, usually bundled with Contract review
- `PRIVACY_POLICY.md` — PIPEDA-specialist lawyer (can be same lawyer if they do privacy work), $500-1,500 privacy-specific

Combined bundle review cost estimate: **$1,000-2,500** for all three at a capable small-business Canadian law firm. One-time fee, annual update recommended.

No other operations files have formal legal-review requirements, but all reference Canadian compliance context (CASL, PIPEDA, provincial regulatory rules).
