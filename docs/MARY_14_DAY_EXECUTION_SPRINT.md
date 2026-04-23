# Mary's 14-Day Execution Sprint

**Purpose:** day-by-day sequence to turn scaffolding into a live, paying business within two weeks. Every task has time estimate and owner. Everything not listed here is explicitly deferred to the 30-day plan.

**Sprint goal:** 2 signed paying clients (consulting + real_estate) by end of day 14, invoiced through Stripe, with live email + LinkedIn outreach running.

---

## Day 1 — Legal foundation + banking

**Time budget:** 4 hours

| Task | Time | Owner | Why |
|---|---:|---|---|
| Open dedicated Crystallux business bank account (Canadian chartered bank, business operating account) | 90 min | Mary | Separate business money from personal, required for Stripe payout. RBC / BMO / TD Business Banking — book 11am branch appointment. |
| Capture Business Number (BN) from CRA if not already done | 30 min | Mary | Required for Stripe Canadian business verification. [canada.ca/business-number](https://www.canada.ca/en/services/taxes/business-number.html) |
| Review `docs/MARY_MINIMUM_DOCS_PACKAGE.md` § Contract template outline | 45 min | Mary | Decide which fields to customise before sending to lawyer |
| Request quote from 2 Canadian small-business lawyers for contract + ToS + Privacy Policy review | 30 min | Mary | Budget $500-1,500 for one-time review. Avoid $200/hr billables for first-pass drafts; use Clerky-style templates reviewed by lawyer. |
| Register `crystallux.org` business email + signature + auto-responder | 45 min | Mary | Professional intake channel. Set auto-responder from `docs/MARY_MINIMUM_DOCS_PACKAGE.md` § Support template. |

**End-of-day check:** business bank account application submitted, BN confirmed, contract quote requested.

---

## Day 2 — Stripe + landing page scaffolding

**Time budget:** 5 hours

| Task | Time | Owner | Why |
|---|---:|---|---|
| Complete Stripe account application using BN + business address | 60 min | Mary | Stripe verification is 2-5 business days; started day 2 = done by day 7 latest. |
| Create all Stripe Products + Prices per `docs/STRIPE_PRODUCTS_SPEC.md` | 60 min | Mary | 11 products across 4 active verticals + upsells. |
| Copy Stripe Price IDs into `.env` | 15 min | Mary | Feeds clx-stripe-provision-v1. |
| Draft pricing page content from `docs/MARY_MINIMUM_DOCS_PACKAGE.md` § Pricing page | 60 min | Mary | Single-page HTML, 4 active verticals, "book a call" CTA linking to Calendly. |
| Buy + park crystallux.org (if not already owned) | 30 min | Mary | Needed for landing page + email + Stripe portal branding. |
| Commission a landing page (Webflow / Carrd / Framer — no custom code) | 60 min | Mary or contractor | 3-page site: Home (value prop) · Pricing · Book a Call. Use copy from the min-docs package verbatim. |

**End-of-day check:** Stripe products created, landing page draft linked, first commercial asset live.

---

## Day 3 — Terms + Privacy + Contract drafts sent to lawyer

**Time budget:** 3 hours

| Task | Time | Owner |
|---|---:|---|
| Send lawyer: contract template + ToS draft + Privacy Policy draft from `MARY_MINIMUM_DOCS_PACKAGE.md` | 30 min | Mary |
| Set one-week SLA with lawyer for review turnaround | 15 min | Mary |
| Provision landing-page copy v1 (home + pricing + book-a-call) | 90 min | Mary or contractor |
| Connect Calendly to crystallux.org/book-a-call (15-min discovery call) | 30 min | Mary |

**End-of-day check:** legal docs with lawyer, landing page v1 live, Calendly booking flow tested end-to-end with own email.

---

## Day 4 — Supabase migrations + workflow import

**Time budget:** 4 hours

| Task | Time | Owner |
|---|---:|---|
| Apply all 6 pending Supabase migrations in order per `MARY_ACTIVATION_CHECKLIST.md` Phase 1 | 60 min | Mary / automation |
| Run verification queries; confirm 8 niche_overlays rows | 15 min | Mary |
| Import new workflows into n8n (phase 5a from activation checklist — 12 new) | 60 min | Mary |
| Re-import modified workflows (phase 5b — 8 modified) | 45 min | Mary |
| Confirm all workflows active=false except clx-lead-import | 15 min | Mary |
| Create n8n credentials: Apollo, Anthropic API, Stripe (placeholder pending Stripe activation) | 45 min | Mary |

**End-of-day check:** schema + workflows mirror the repo on production infra. Spot-check: fire the `clx-form-intake-v1` manual webhook and verify a row lands in `leads`.

---

## Day 5 — Email channel activation + first outbound campaign prep

**Time budget:** 5 hours

| Task | Time | Owner |
|---|---:|---|
| Activate `clx-outreach-sender-v2` (email sender) — leave TESTING MODE redirect in place | 30 min | Mary |
| Draft the first Crystallux outbound campaign: 50 consulting prospects via Apollo lookup | 60 min | Mary |
| Load the 50 prospects into `leads` via form intake or direct SQL INSERT | 45 min | Mary |
| Manually trigger lead-research → scoring → signal-detection → campaign-router pipeline per lead | 60 min | Mary |
| Verify outreach emails land in `adesholaakintunde+clxtest@gmail.com` TESTING MODE inbox | 30 min | Mary |
| Read every generated email, flag any that need prompt tuning | 60 min | Mary |

**End-of-day check:** 50 test emails generated in test inbox, review complete, any copy issues documented for Anthropic prompt tuning.

---

## Day 6 — Remove TESTING MODE for first live batch + send

**Time budget:** 3 hours

| Task | Time | Owner |
|---|---:|---|
| Pick first 10 high-quality consulting prospects from the 50-lead batch | 30 min | Mary |
| For this batch only, edit `clx-outreach-sender-v2` Build Gmail Raw Message node: change redirect to `data.email` | 30 min | Mary |
| Manually trigger sender for those 10 leads | 15 min | Mary |
| Verify emails sent to real prospects (check Gmail sent folder) | 15 min | Mary |
| **Re-enable TESTING MODE redirect** after the batch for safety | 15 min | Mary |
| Track replies in `clx-reply-ingestion-v1` dashboard panel | 60 min | Mary |

**End-of-day check:** 10 live outbound emails sent to Crystallux's own ICP; redirect restored; reply-monitoring armed.

---

## Day 7 — Stripe activation (assuming verification completed)

**Time budget:** 3 hours

| Task | Time | Owner |
|---|---:|---|
| Confirm Stripe Live mode active | 15 min | Mary |
| Copy webhook signing secret from Stripe Dashboard to `.env` `STRIPE_WEBHOOK_SECRET` | 15 min | Mary |
| Configure webhook endpoint in Stripe pointing at `/webhook/stripe` | 15 min | Mary |
| Bind `Stripe` credential to `clx-stripe-provision-v1` (Create Customer + Create Subscription nodes) | 30 min | Mary |
| Activate `clx-stripe-webhook-v1` and `clx-stripe-provision-v1` | 15 min | Mary |
| Test end-to-end: Stripe Dashboard → create test customer on Mary's card → refund after | 60 min | Mary |
| Verify test subscription row lands in `clients` with trialing status | 15 min | Mary |

**End-of-day check:** billing infra is live. Any signed client today can be provisioned in under 60 seconds.

---

## Day 8 — First discovery calls + follow-up sequence

**Time budget:** 4 hours (plus any booked calls)

| Task | Time | Owner |
|---|---:|---|
| Execute any booked calls from day-6 outbound using `docs/client-outreach/consulting-first-call-script.md` | Per call | Mary |
| Activate `clx-follow-up-v2` so day-3 sequences start arriving | 15 min | Mary |
| Review day-6 reply rate; if <10%, flag prompt tuning for day 9 | 30 min | Mary |

**End-of-day check:** first set of real-prospect discovery calls executed; follow-up cadence live.

---

## Day 9 — Real estate outbound wave + case study prep

**Time budget:** 5 hours

| Task | Time | Owner |
|---|---:|---|
| Pull 50 real_estate prospects via Apollo in target farm areas (e.g., GTA + Calgary) | 45 min | Mary |
| Load into leads with vertical='real_estate'; run pipeline | 60 min | Mary |
| Review generated real_estate outreach in test inbox; flag any RECO-compliance concerns | 45 min | Mary |
| Prepare first case study template (even if no client signed yet — use Crystallux's own early metrics as the proof point) | 90 min | Mary |
| Send first 10 real_estate prospects live | 30 min | Mary |

**End-of-day check:** 10 real_estate live sends; case study skeleton ready to populate with first client data.

---

## Day 10 — Lawyer return: finalise ToS + Privacy + Contract

**Time budget:** 3 hours

| Task | Time | Owner |
|---|---:|---|
| Receive lawyer comments on 3 legal docs | — | Lawyer |
| Implement lawyer edits; finalise ToS and Privacy Policy on crystallux.org | 60 min | Mary or contractor |
| Save signed contract template as PDF template | 30 min | Mary |
| Add contract-request link to landing page + pricing page | 30 min | Mary |
| Send first signed contract to hottest discovery call from day 8 | 30 min | Mary |

**End-of-day check:** legal foundation 100% live. First contract in-flight.

---

## Day 11 — First client closes + onboarding

**Time budget:** 5 hours

| Task | Time | Owner |
|---|---:|---|
| Signed contract returned from client #1 | — | Client |
| Provision via `clx-stripe-provision-v1` webhook POST (see `OPERATIONS_HANDBOOK §21.8`) | 30 min | Mary |
| Confirm Stripe trial subscription active; welcome email sent via workflow | 30 min | Mary |
| Run onboarding call using `docs/MARY_MINIMUM_DOCS_PACKAGE.md` § Onboarding call script | 60 min | Mary |
| Create client-scoped dashboard token + share URL with client | 15 min | Mary |
| First-client outbound campaign: 50 of their target prospects loaded within 24h | 120 min | Mary |

**End-of-day check:** first paying client signed, onboarded, dashboard live, their first outbound batch loading.

---

## Day 12 — LinkedIn channel activation

**Time budget:** 4 hours

| Task | Time | Owner |
|---|---:|---|
| Complete Unipile signup + connect Mary's LinkedIn account | 60 min | Mary |
| Add `UNIPILE_API_KEY`, `UNIPILE_ACCOUNT_ID` to `.env` | 15 min | Mary |
| Create n8n `Unipile` credential; bind to `clx-linkedin-outreach-v1` Unipile Send Invite node | 30 min | Mary |
| Replace `TODO_UNIPILE_ACCOUNT_ID` in node body | 15 min | Mary |
| Add `linkedin` to first-client's `channels_enabled` | 15 min | Mary |
| Manual webhook test: single consulting lead, `preferred_channel='linkedin'` | 45 min | Mary |
| Confirm `linkedin_outreach_log` + `outreach_log` rows created | 15 min | Mary |
| Activate `clx-linkedin-outreach-v1` Schedule Trigger | 15 min | Mary |

**End-of-day check:** LinkedIn outreach live for first-client.

---

## Day 13 — Second client close + retrospective

**Time budget:** 5 hours

| Task | Time | Owner |
|---|---:|---|
| Close second prospect (consulting or real_estate) — contract + Stripe provision | 90 min | Mary |
| Run onboarding call | 60 min | Mary |
| Populate case study template with client #1 week-1 data (leads loaded, first replies, first booked meeting) | 90 min | Mary |
| 14-day retrospective: what worked, what didn't, what to automate next | 30 min | Mary |
| Update `MARY_30_DAY_COMMERCIALIZATION_PLAN.md` based on retro findings | 30 min | Mary |

**End-of-day check:** two paying clients, first case study v1, learnings captured.

---

## Day 14 — Buffer / catch-up / first revenue milestone

**Time budget:** flexible

| Task | Time | Owner |
|---|---:|---|
| Any overflow from days 1-13 | As needed | Mary |
| First MRR snapshot: confirm $3,494 MRR ($1,997 + $1,497) from first 2 clients | 15 min | Mary |
| Post first "founding client signed" update on LinkedIn / Twitter (optional) | 30 min | Mary |
| Confirm 30-day plan is on-track; adjust if not | 60 min | Mary |

**End-of-day check:** $3K+ MRR locked in, sprint complete, 30-day plan updated.

---

## Daily guardrails (apply every day)

- TESTING MODE redirect stays in place except for deliberate, small live-batch windows. Restore immediately after.
- `git status` clean each morning; every day's docs/workflow edits committed same-day.
- Mitch Insurance `do_not_contact=true` guardrail confirmed weekly via dashboard.
- No live API activations outside the specific day's task list.

---

## Failure modes + contingency

| Failure | Impact | Contingency |
|---|---|---|
| Stripe verification takes >5 business days | Day 7-8 provisioning blocked | Use Stripe Test mode for client-#1 onboarding, migrate to Live mode upon approval |
| Lawyer turnaround >7 days | Day 10-11 contract blocked | Use Canadian-law-firm-reviewed template (Clerky / Stripe Atlas equivalent) for client #1, have lawyer finalise in parallel |
| No replies on day-6 outbound | Day 8 discovery calls empty | Tune prompts, widen ICP, send second batch day 7 |
| Unipile LinkedIn lockdown | Day 12 LinkedIn blocked | Proceed email-only until Unipile issue resolved; LinkedIn is a force-multiplier, not a blocker |
| First client demands custom copy | Day 11 onboarding delayed | Standard 48h copy revision window is in contract ToS; honour but don't expand scope |
