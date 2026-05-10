# AI Compliance Vision (Insurance MGA — Layer 2 Part A)

> **Audience:** Mary, advisors, compliance officer, future MGA partners reviewing how Crystallux runs regulated insurance operations.

## The thesis

Insurance is the most heavily regulated mass-market vertical Crystallux serves. Traditional MGAs spend the bulk of operating cost on **compliance overhead** — KYC clerks, suitability reviewers, disclosure paperwork chasers, application data-entry. The work is high-stakes (regulators have teeth), repetitive (same checks every time), and bottlenecked on humans.

The AI Compliance Engine inverts the model: **AI does every regulated check in minutes; humans only intervene when the AI is uncertain or flags risk.** A licensed compliance officer retains override authority on every decision — not optional, this is a regulatory floor.

## Operational outcomes

| Manual workflow today | With Crystallux Layer 2 |
|---|---|
| KYC verification: 1-3 days | Stripe Identity + AI review: ~5 minutes |
| Suitability assessment: 2-5 days of forms | AI conversational interview over WhatsApp: ~10 minutes of client time |
| Policy recommendation: 1-2 days advisor research | AI ranks top 3-5 carrier products: instant |
| Compliance review (KYC / suitability / disclosure / final): 3-7 days | AI review: instant. Human override path: minutes when needed |
| Application data entry: hours per app | AI auto-completes from aggregated data: instant |
| Disclosure documentation: hours per client | AI generates + e-sig orchestration: instant |

The advisor's job shifts from **paperwork** to **relationship + judgment** — they review AI outputs, exercise discretion on flagged cases, and close the deal.

## Architecture in one paragraph

Per-client journey: Stripe Identity KYC session → AI compliance review → conversational suitability interview (WhatsApp/SMS/email) → AI needs analysis → AI policy recommendation across carrier matrix → AI compliance review of suitability → required disclosures generated + e-signed via Zoho Sign → AI auto-completes carrier application from aggregated data → advisor reviews + approves → AI final compliance review → submission. Every regulated step writes to `regulatory_audit_log` (vertical_id='insurance'). Every AI decision is overridable by a `compliance_officer` role user.

## Components shipped in this build

```
                     ┌─────────────────────────────────────────────┐
                     │   AI Compliance Agent (A1.1)                │
                     │   review_type: kyc / suitability /          │
                     │                disclosure / final           │
                     │   → compliance_reviews                       │
                     │   → routes to compliance_officer if         │
                     │     requires_human_review                    │
                     └─────────────────────────────────────────────┘
                                       ▲
                                       │ called by
                       ┌───────────────┼────────────────────────────┐
                       │               │                            │
   ┌─────────────────┐ │  ┌──────────────────┐  ┌──────────────────┐│
   │ KYC Orchestrator│─┘  │ Suitability path │  │ Application path ││
   │ A1.2 + A1.3     │    │ A2.1 → A2.1b →   │  │ A4.1 → A4.2 →    ││
   │ Stripe Identity │    │ A2.2 → A2.3      │  │ (compliance) →    ││
   └─────────────────┘    └──────────────────┘  │ submit            ││
                                                └──────────────────┘│
                                                                    │
                          ┌──────────────────┐                      │
                          │ Disclosure path  │──────────────────────┘
                          │ A3.1 → A3.2 → A3.3 │
                          │ HTML → R2 → Zoho   │
                          └──────────────────┘
```

## Workflows shipped (all dormant — Mary activates per credential setup)

| ID | Workflow | Webhook | What it does |
|---|---|---|---|
| A1.1 | clx-mga-insurance-compliance-agent-v1 | POST /webhook/mga/insurance/compliance-review | The AI Compliance Agent. Routes by review_type → Claude → compliance_reviews → notify compliance_officer if needs_human |
| A1.2 | clx-mga-insurance-kyc-orchestrator-v1 | POST /webhook/mga/insurance/kyc-start | Creates Stripe Identity verification session → kyc_verifications |
| A1.3 | clx-mga-insurance-stripe-identity-callback-v1 | POST /webhook/mga/insurance/stripe-identity-callback | Stripe webhook → updates kyc_verifications → triggers A1.1 |
| A2.1 | clx-mga-insurance-suitability-interview-v1 | POST /webhook/mga/insurance/suitability-start | Generates first interview question → suitability_assessments |
| A2.1b | clx-mga-insurance-suitability-conversation-handler-v1 | POST /webhook/mga/insurance/suitability-reply | Handles each lead reply → ask-next / clarify / complete |
| A2.2 | clx-mga-insurance-needs-analysis-v1 | POST /webhook/mga/insurance/needs-analysis | Claude needs analysis → updates suitability_assessments.needs_analysis |
| A2.3 | clx-mga-insurance-policy-recommendation-engine-v1 | POST /webhook/mga/insurance/policy-recommend | Ranks top 3-5 carrier products → policy_recommendations → triggers A1.1 (suitability review) |
| A3.1 | clx-mga-insurance-disclosure-generator-v1 | POST /webhook/mga/insurance/disclosure-generate | Renders HTML templates → R2 → compliance_disclosures |
| A3.2 | clx-mga-insurance-esignature-orchestrator-v1 | POST /webhook/mga/insurance/esign-send | Zoho Sign envelope create → updates compliance_disclosures.esignature_id |
| A3.3 | clx-mga-insurance-zoho-sign-callback-v1 | POST /webhook/mga/insurance/zoho-sign-callback | Zoho webhook → marks signed + downloads PDF to private R2 |
| A4.1 | clx-mga-insurance-application-builder-v1 | POST /webhook/mga/insurance/application-build | AI auto-completes carrier app from KYC + suitability + disclosures + recommendation |
| A4.2 | clx-mga-insurance-application-final-review-v1 | POST /webhook/mga/insurance/application-approve | Advisor approves → triggers A1.1 final_compliance → submit or route to compliance_officer |

## Decision authority hierarchy

```
1. AI compliance agent             — first-line review on every regulated event
2. Compliance officer (human)      — overrides AI, mandatory on requires_human_review
3. MGA principal                   — overrides compliance officer in extremis
4. FSRA Ontario                    — final authority (regulator)
```

Every override is logged to `regulatory_audit_log` with `performed_by_user_id` + `performed_by_role`. The audit trail is the regulator-facing record — never deleted, soft-FK columns survive related-row deletion.

## Why a multi-vertical foundation matters

Crystallux is a multi-vertical platform. Layer 2 Part A is **insurance-vertical-specific**, but the schema and workflow patterns are vertical-tagged via `vertical_id` so future Layer 2 modules (mortgage MGA, real estate brokerage, group benefits MGA) plug into the same tables without schema migration. See [`docs/architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md`](../architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md) for the full strategy.

## What this enables for the MGA business

1. **Carrier partnerships.** Carriers need proof of compliance discipline before granting MGA agreements. The audit trail + AI review depth + compliance-officer-override workflow is what carriers ask for; before this build it lived in spreadsheets.
2. **Sub-agent scale.** Mary's 10 LLQP-licensed agents can each run 2-3× their previous volume because the paperwork load is gone. AI does suitability + disclosure + application; advisors close.
3. **Regulator confidence.** FSRA can request the regulatory_audit_log for any client; we hand them a clean append-only record with AI reasoning + human overrides timestamped.
4. **Cross-vertical foundation.** Same engine extends to mortgage MGA (FINTRAC framework) and real estate brokerage (RECO framework) without rebuilding compliance plumbing.

## What's NOT in this build (deferred — explicitly)

- **PEP / sanctions screening automation** — Phase 6. KYC verifications mark `pep_screening_result = 'manual_review_pending'` until then; A1.1 routes anything to compliance officer.
- **Carrier API integration** — Phase 6. A2.3 uses a static carrier-product matrix in JS; A4.1 produces a generic application schema. Real submissions remain manual until carrier APIs land.
- **Background checks (Certn)** — Phase 5b (Layer 2 Part B agent onboarding).
- **Per-carrier application templates** — Phase 6.
- **PDF generation** — Phase 5b. Disclosures render as HTML stored in R2; e-signature signs the rendered HTML. PDF conversion happens at signing time via Zoho Sign.
- **Compliance officer dashboard** — Phase 5c (Layer 2 Part C insurer-facing mode). Until then, compliance officers receive email notifications and review via direct Supabase queries.

## Cost envelope (operational)

Per fully-processed client (KYC → suitability → disclosure → recommendation → application):

| Component | Estimated cost |
|---|---|
| Stripe Identity verification | $1.50 |
| Zoho Sign (per envelope, 3 typical) | $0.20 (flat $8/mo subscription amortised) |
| Claude tokens (compliance + needs + recommendation + app build, ~30K combined) | ~$0.10 |
| R2 storage (disclosure HTML + signed PDF, lifetime) | <$0.01 |
| **Total per client** | **~$1.85** |

Compare to traditional MGA per-client compliance overhead at $80-200 (1-2 hours of clerk time × loaded cost). **Two-orders-of-magnitude reduction.**

## Cross-references

- Schema: [`db/migrations/insurance-mga-schema.sql`](../../db/migrations/insurance-mga-schema.sql)
- Multi-vertical architecture: [`docs/architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md`](../architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md)
- Regulatory framework: [`REGULATORY_FRAMEWORK.md`](REGULATORY_FRAMEWORK.md)
- Workflows: `workflows/api/insurance-mga/clx-mga-insurance-*-v1.json`
- Disclosure templates: `documents/templates/insurance/*.html`
- AI Agent foundation (universal): [`docs/agent/AGENT_VISION.md`](../agent/AGENT_VISION.md)
