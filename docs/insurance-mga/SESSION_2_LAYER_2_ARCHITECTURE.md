# Session 2 — Layer 2 (insurance MGA) additions

> Insurance-specific content templates + training topics + 7 needs
> calculators + 30-day onboarding curriculum. All tables tagged
> `vertical_id='insurance'`. Builds on top of the Layer 1 universal
> framework landed in Session 2 Commit A (7d13852).

## What landed (Layer 2 / insurance)

### Schemas (2)

| File | Tables | Purpose |
|---|---|---|
| `db/migrations/insurance-content-library-schema.sql` | `insurance_content_templates` | Per-vertical content topic templates the universal content topic generator pulls from when `client.vertical='insurance'`. |
| `db/migrations/insurance-onboarding-curriculum-schema.sql` | `insurance_onboarding_curriculum`, `advisor_onboarding_progress` | 30-day structured advisor onboarding. Supervisor signoff required for graduation. |

Both schemas: `vertical_id text NOT NULL DEFAULT 'insurance'` on every table.

### Workflows (12 new in `workflows/api/insurance-mga/`)

| Workflow | Webhook | Auth |
|---|---|---|
| `clx-mga-insurance-content-library-seed-v1` | POST `/webhook/mga/insurance/content-library-seed` | INTERNAL_EMAIL_SECRET |
| `clx-mga-insurance-training-topics-seed-v1` | POST `/webhook/mga/insurance/training-topics-seed` | INTERNAL_EMAIL_SECRET |
| `clx-mga-insurance-onboarding-curriculum-seed-v1` | POST `/webhook/mga/insurance/onboarding-curriculum-seed` | INTERNAL_EMAIL_SECRET |
| `clx-mga-insurance-onboarding-advance-v1` | POST `/webhook/mga/insurance/onboarding-advance` | Session token (own advisor row) |
| `clx-mga-insurance-onboarding-status-v1` | POST `/webhook/mga/insurance/onboarding-status` | Session token |
| `clx-mga-insurance-calculator-income-replacement-v1` | POST `/webhook/mga/insurance/calculator/income-replacement` | Session token |
| `clx-mga-insurance-calculator-mortgage-debt-v1` | POST `/webhook/mga/insurance/calculator/mortgage-debt` | Session token |
| `clx-mga-insurance-calculator-dependent-support-v1` | POST `/webhook/mga/insurance/calculator/dependent-support` | Session token |
| `clx-mga-insurance-calculator-final-expenses-v1` | POST `/webhook/mga/insurance/calculator/final-expenses` | Session token |
| `clx-mga-insurance-calculator-education-v1` | POST `/webhook/mga/insurance/calculator/education` | Session token |
| `clx-mga-insurance-calculator-business-key-person-v1` | POST `/webhook/mga/insurance/calculator/business-key-person` | Session token |
| `clx-mga-insurance-calculator-total-needs-v1` | POST `/webhook/mga/insurance/calculator/total-needs` | Session token |

All `active: false`. All queries / inserts include `vertical_id='insurance'`.

### Calculators (math summary)

- **Income replacement:** real-rate PV of `annual_income × years_to_replace` discounted at `(1+return)/(1+inflation) − 1`.
- **Mortgage + debt:** `mortgage_balance + other_debt`.
- **Dependent support:** `annual_support × num_dependents × years_per_dependent`.
- **Final expenses:** `funeral + estate_closing + uncovered_medical` (sensible defaults: $15,000 funeral / $5,000 estate).
- **Education:** `annual_cost × (1+inflation)^years_until_start × years_attending × num_children`.
- **Business / key person:** `(salary + annual_revenue_contribution) × years_to_replace + replacement_search_cost`.
- **Total needs summary:** `sum of the 5 component needs − existing_coverage` (clamped to ≥ 0). Returns full breakdown for transparency.

Every response includes:
```
disclaimer: "This is an educational estimate only. Final recommendation must be reviewed and approved by a licensed advisor."
```

### 30-day onboarding curriculum

Days 1–3: licensing + E&O + MGA agreement.
Days 4–7: AML + privacy + replacement disclosure + suitability documentation.
Days 8–14: product training (term, whole, UL, CI, disability, health, P&C).
Days 15–21: discovery + KYC + suitability + objections + closing + practice presentation #1.
Days 22–28: application data + e-signature + underwriting + post-issuance + commissions + practice presentation #2.
Days 29–30: first client preparation + supervisor signoff.

Mandatory unless flagged `is_mandatory=false` (only P&C overview is optional).

### Frontend pages (2)

- `insurance-mga-dashboard/advisor/calculators.html` — tabbed UI; clxApi.mgaPost('calculator/<key>', payload).
- `insurance-mga-dashboard/advisor/onboarding.html` — visual 30-day curriculum + per-day status + start/complete buttons.

Sidebar (`shared/nav.html`) extended with both entries under the Advisor section.

## Layer 2 purity audit

- ✅ Every new table has `vertical_id text NOT NULL DEFAULT 'insurance'`.
- ✅ Every new workflow lives under `workflows/api/insurance-mga/`.
- ✅ Every workflow name starts with `clx-mga-insurance-`.
- ✅ Every webhook path starts with `/webhook/mga/insurance/`.
- ✅ Every Supabase write sets `vertical_id: 'insurance'`.
- ✅ Layer 2 frontend pages call Layer 2 endpoints via `clxApi.mgaPost`. They do NOT call Layer 1 endpoints (which would use `clxApi.postApi`).
- ✅ Layer 2 workflows reference Layer 1 tables (`training_topics` for the topics seed; that's the Layer 1 universal table receiving an insurance-specific topic set) but never reference Layer 2 tables from Layer 1.

## Mary's deployment steps

See `docs/audit/blockers.md` section 22-25.

1. Apply 2 new schemas.
2. Re-import 12 new workflows.
3. Run 3 seed workflows (content-library, training-topics, onboarding-curriculum).
4. Smoke test:
   - Open `insurance-mga-dashboard/advisor/calculators.html` → use Income Replacement with annual_income=$75,000 (7,500,000 cents) / years=15 → expect a coverage estimate.
   - Open `insurance-mga-dashboard/advisor/onboarding.html` → expect 30 days listed (after seed).
