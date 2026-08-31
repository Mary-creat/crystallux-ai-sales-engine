# Crystallux — readiness matrix

**The single authoritative record of what is finished.** There is no second
planning document; anything that contradicts this file is out of date.

Measured against production on **2026-08-31** — live Supabase row counts, live
HTTP probes, and the GitHub Actions deploy log. Companion audits:
[infrastructure](../audit/2026-08-28-master-architecture-audit.md),
[products](PRODUCT_REGISTRY.md). Owner queue:
[`OWNER_ACTIONS_REQUIRED.md`](OWNER_ACTIONS_REQUIRED.md). Decisions:
[`ARCHITECTURE_DOCTRINE.md`](ARCHITECTURE_DOCTRINE.md).

**`DONE` means production-tested successfully.** Not "the code exists", not "the
endpoint answers". Where something is deployed but has never carried a real
transaction it is `LIVE_UNPROVEN` — the most common status here, and the honest
one.

| Status | Meaning |
|---|---|
| `DONE` | Exercised in production and observed to work |
| `LIVE_UNPROVEN` | Deployed and reachable; never carried a real transaction |
| `PARTIAL` | Some components work, others demonstrably do not |
| `BLOCKED_OWNER` | Waiting on a credential, a payment, or an authorisation |
| `BLOCKED_EXTERNAL` | Waiting on a third party — platform review, provider approval |
| `DEFERRED` | Intentionally postponed |

---

# WHAT IS FINISHED

Production-tested, not merely shipped:

- **CI validates the whole estate** — 326 workflows and 118 SQL files on every
  push. Was 50 files and neither validator.
- **Deployment is reproducible** — update-by-id, changed files only, never
  creates, never activates. Four successful runs, 131+ updates, 0 failures. The
  previous version POSTed every workflow on every push — POST *creates* — and
  reported success while deploying nothing.
- **Auth fails closed** — 126 of 126 `validate_session` fetches guarded.
  Verified by probe: endpoints that answered a bad token with an empty `200`
  now answer `401` with a body.
- **Code-node environment access** — 57 nodes across 53 workflows moved from
  `process.env` (which n8n's sandbox does not expose) to `$env`. Verified live
  across Messaging, MGA, Agentic and Video.
- **Vertical context** — 8 verticals configured, `get_vertical_context()`
  resolving, 11 of 11 checks passed, no regression in the 8 consumers.
- **Agent policy gate** — fail-closed, 35 tests, in CI.
- **MCP bypass closed** — 5 sensitive tools handed to the executor, 28 tests.
- **Tenant isolation** — `client_id` derives from the validated session row,
  never the request body. Verified in code and by probe.

# WHAT IS LIVE BUT UNPROVEN

Deployed, reachable, never used in anger. This is most of the platform:

- Sales Engine discovery → scoring → outreach (no lead since 2026-05-28, no send
  since 2026-06-08)
- Smart Quote — 7 industry estimators, 60 pricing artefacts, **0 completed quotes**
- LUXI — 8 auctions, **0 orders, 0 bids, 0 events, ever**
- MGA — 85 endpoints live, `carrier_quotes` 0, `policy_applications` 0
- Agent runtime — 1 personality seeded, **0 decisions, 0 actions, 0 memory**
- Copilot — 6 endpoints, 0 chat rows
- Stripe grant path — built this week, no purchase has run through it

# WHAT BLOCKS SALES ENGINE PILOT

Three things, in order:

1. **No Stripe Price for Sales Engine.** `STRIPE_PRICE_SALES_ENGINE` is declared
   and empty, so purchase → entitlement cannot complete. **Owner.**
2. **Onboarding migration not applied.** `client_icp_profiles` is 0 rows, so no
   tenant has an ICP. **Owner.**
3. **Discovery proof not run.** Needs `INTERNAL_EMAIL_SECRET`, which lives in the
   container and correctly not with me.

Everything else a pilot needs exists and is deployed.

# WHAT BLOCKS FULL SELF-SERVE LAUNCH

- **Entitlement is enforced nowhere in the request path yet.** The functions
  exist; no endpoint calls them. A valid session still reaches `client/*`
  regardless of purchase.
- **No email send has succeeded since 2026-06-08** — 13 sends ever, all to a
  test inbox.
- **Attribution cannot be reconstructed** — `campaigns` 0, `deals` 0.
- **Reply, follow-up and booking have never carried a real event.**

# WHAT CAN WAIT UNTIL AFTER REVENUE

UGC, Studio, Theatre, six of seven avatars, social publishing (six stub
publishers, blocked on platform review anyway), voice, video rendering, agentic
activation, and MCP external access. None blocks a first paying customer.

---

## Core platform

| Area | Product | Status | What exists | Tested | Not tested | Blocker | Owner? | Next action | Launch blocker? |
|---|---|---|---|---|---|---|---|---|---|
| Auth | Core | `DONE` | 9 workflows, `validate_session`, 167 sessions | Login flows; fail-closed verified on 126 fetches | Reset under load | — | no | — | no |
| Tenant isolation | Core | `DONE` | `client_id` from session row; RLS 208/208 | Code-traced and probed; `client/*` filters on session tenant | Two live sessions cross-tenant | — | no | — | no |
| Billing | Core | `LIVE_UNPROVEN` | Live Stripe keys, webhook, events log | Signature path exists | **No payment ever ran through it** | No Sales Engine Price | **yes** | Create the Price | **YES** |
| Product entitlement | Core | `PARTIAL` | `check_product_entitlement`, `validate_session_for_product` live | Verified present; return false correctly | **No endpoint calls them** | Not wired | no | Wire `client/*` | **YES** (self-serve) |
| Stripe grant | Core | `LIVE_UNPROVEN` | Grant path added; `grant_product` idempotent | Fail-closed logic; allow-list refuses typos | No real purchase | No Price ID | **yes** | Create the Price | **YES** |
| Stripe revoke | Core | `LIVE_UNPROVEN` | Suspend, clear products, revoke sessions | — | No real cancellation | — | no | — | no |
| Audit | Core | `PARTIAL` | `admin_action_log` 100 rows | — | **Every row automated; `action` NULL. No human action audited** | Two schemas in one table | no | Reconcile, then log privileged actions | no |
| CI / deploy | Core | `DONE` | Validate + deploy, update-by-id | 4 runs, 131+ updates, 0 failures | Rollback of a bad deploy | — | no | — | no |
| Migrations | Core | `PARTIAL` | 118 files, all parse; ledger below | 9 applied and verified | **18 live tables have no `CREATE` in the repo, `leads` included** | — | no | Capture the 18 | no |
| Credentials | Core | `BLOCKED_OWNER` | Supabase, Claude, Apollo, Postmark, Twilio, Maps bound | Supabase binding survives CI PUT | `Cloudflare R2` missing → 4 workflows on old code | Credential absent | **yes** | Create it | no |
| Provider routing | Core | `PARTIAL` | Per-vertical sources, Apollo quota gate | Config verified | **Apollo: 0 leads ever**; all 2,518 from Google Maps | — | no | Apollo is one provider, not the architecture | no |

## Agentic

| Area | Product | Status | What exists | Tested | Not tested | Blocker | Owner? | Next action | Launch blocker? |
|---|---|---|---|---|---|---|---|---|---|
| Copilot | Agentic | `LIVE_UNPROVEN` | 6 endpoints | Answer, gated | 0 chat rows ever | Static `MARY_MASTER_TOKEN` | no | — | no |
| Agent personality | Agentic | `DONE` | 1 row: construction, `recommend_only`, MAXI, 8 gated | Verified live; vertical resolves | — | — | no | — | no |
| Decision engine | Agentic | `LIVE_UNPROVEN` | 9 workflows, 16 tables | — | **Never executed** — exits at `agent_channels_enabled` 0 | 4 empty gate tables; trigger `(DEACTIVATED)` | **yes** | Activation decision | no |
| Action executor | Agentic | `DONE` | Fail-closed gate on the only path to a send | **35 tests** — sensitive classes blocked, approval validated not trusted, tenant mismatch refused | Never run on a real decision | — | no | — | no |
| Policy gate | Agentic | `DONE` | Risk keyed on capability, not product | 35 tests in CI, reading shipped `jsCode` | — | — | no | — | no |
| Product routing | Agentic | `PARTIAL` | MCP maps tool → product | — | **No router layer exists** | — | no | Not needed pre-revenue | no |
| MCP | Agentic | `PARTIAL` | Two gateways; `agent-tools` canonical | **28 tests**; no node may call a sender directly; probe confirms fail-closed | Never carried an authorised call | `MCP_WEBHOOK_SECRET` absent from container | **yes** | Defer — 5 calls ever | no |
| Memory | Agentic | `LIVE_UNPROVEN` | Table + retrieve tool | — | 0 rows | Runtime inactive | no | — | no |
| Escalation | Agentic | `LIVE_UNPROVEN` | Endpoint live, left direct as the safety valve | — | 0 rows | — | no | — | no |
| `agent_channels_enabled` | Agentic | `BLOCKED_OWNER` | Table exists | — | **0 rows — this is what keeps the runtime inert** | Activation is an owner call | **yes** | Decide | no |
| `behavioral_triggers` | Agentic | `LIVE_UNPROVEN` | Table exists | — | 0 rows | Nothing upstream runs | no | — | no |
| `agent_schedules` | Agentic | `LIVE_UNPROVEN` | Table exists | — | 0 rows | — | no | — | no |
| Sentinel sees agents | Agentic | `DEFERRED` | — | — | Not built | Workflow-health first | no | After that | no |

## Sales Engine — commercial status: **INTERNAL READY**

| Area | Status | What exists | Tested | Not tested | Blocker | Owner? | Next action | Launch blocker? |
|---|---|---|---|---|---|---|---|---|
| Signup | `LIVE_UNPROVEN` | Signup workflow; webhook creates client + user | Endpoints answer | No real signup | — | no | — | no |
| Tenant creation | `LIVE_UNPROVEN` | Webhook creates `clients` | 4 clients exist | Not via a real purchase | — | no | — | no |
| Entitlement | `BLOCKED_OWNER` | Grant + check functions live | Functions verified | **0 of 3 users hold any product** | No Stripe Price | **yes** | Create the Price | **YES** |
| Onboarding | `BLOCKED_OWNER` | `upsert_client_icp_from_onboarding()` | Validated; refuses unconfigured vertical and unknown client | Not applied | Migration pending | **yes** | Apply it | **YES** |
| `client_icp_profiles` | `BLOCKED_OWNER` | Table + connector | — | **0 rows** | Depends on onboarding | **yes** | Apply onboarding | **YES** |
| Vertical context | `DONE` | 8 verticals, `get_vertical_context()` | 11/11 checks; 4 verticals proven differentiated in titles, tone, signals, terminology, channel, cadence, compliance | — | — | no | — | no |
| Discovery (house) | `PARTIAL` | `clx-b2c-discovery-v2.1` schedule path | 2,378 house leads historically | **No lead since 2026-05-28** | Schedules not running | **yes** | Restart or retire | no |
| Discovery (tenant) | `LIVE_UNPROVEN` | `discovery/tenant-scan` deployed and registered | Probed `401` — fail-closed, correct | Never run with a valid secret | Needs `INTERNAL_EMAIL_SECRET` | **yes** | Run the proof | **YES** |
| Person resolution | `PARTIAL` | Per-vertical title keywords | Config verified | **Apollo: 0 leads ever** | — | no | Email scraper found 881 emails without it | no |
| Signals | `LIVE_UNPROVEN` | Types + weights on all 8 verticals | Config verified | `market_signals` 0 | — | no | — | no |
| Intent | `LIVE_UNPROVEN` | hot/warm/cold rules per vertical | Config verified | Never computed | — | no | — | no |
| Scoring | `DONE` | Scoring v2 | **831 of 2,518 score ≥50**; avg 25.7, max 82 | Not at volume on tenant-owned leads | — | no | — | no |
| Research | `LIVE_UNPROVEN` | Research v2 | Unblocked by the `$env` fix | Never run since | — | no | — | no |
| Outreach generation | `LIVE_UNPROVEN` | Generation v2, reads `niche_overlays` | Differentiation proven at config level | No draft end to end | — | no | 4-vertical draft test | no |
| Email send | `PARTIAL` | Postmark + Gmail bound | 13 sends ever, all to test inbox | **Nothing since 2026-06-08** | — | **yes** | One test send | **YES** |
| Replies | `LIVE_UNPROVEN` | Reply ingestion v1 (protected) | — | `outreach_log` 0 | Nothing to reply to | no | — | no |
| Follow-up | `LIVE_UNPROVEN` | Follow-up v2, per-vertical cadence | Config verified | 0 rows | — | no | — | no |
| Booking | `LIVE_UNPROVEN` | Booking v2 (protected), Calendly | — | `bookings` 0 | — | no | — | no |
| Attribution | `PARTIAL` | Lead provenance columns | Source attribution works — every lead traceable | **`campaigns` 0, `deals` 0 — chain cannot be reconstructed** | No campaign has run | no | One campaign row per send | **YES** (for selling) |
| Reporting | `LIVE_UNPROVEN` | Dashboards, per-vertical labels | Pages render | No data | — | no | — | no |

## Smart Quote — commercial status: **INTERNAL READY**

| Area | Status | What exists | Tested | Not tested | Blocker | Owner? | Next action | Launch blocker? |
|---|---|---|---|---|---|---|---|---|
| Onboarding / intake | `LIVE_UNPROVEN` | 7 active industry templates | Endpoints probed, validate input | No real intake | — | no | — | no |
| Estimator | `LIVE_UNPROVEN` | 7 industries | 30 rules + 30 addons, **4–5 per industry** — genuinely multi-industry | Never computed a live estimate | — | no | — | no |
| Pricing | `LIVE_UNPROVEN` | Rules + addons | Config verified | — | — | no | — | no |
| Quote completion | `PARTIAL` | drafts → completed | — | **1 draft stuck since 2026-05-22; `quote_completed` 0** | Draft has NULL `client_id` | no | Finish one quote | no |
| Document | `DEFERRED` | `pdf_url` column | — | No quote has existed to render | Depends on completion | no | — | no |
| Accept / decline | `LIVE_UNPROVEN` | `public/quote/respond` | Probed: validates, rejects bad id | Never had a real quote | — | no | — | no |
| Follow-up | `LIVE_UNPROVEN` | 6-hour cron | — | 0 rows | — | no | — | no |
| Booking | `PARTIAL` | — | — | **Not wired** from completion to booking | — | no | — | no |

The 50 `marketplace_quotes` belong to the MGA site's auto-insurance comparison
widget — 2 leads, 25 carrier rows each — **not** Smart Quote.

## MGA — commercial status: **INTERNAL READY**

| Area | Status | What exists | Tested | Not tested | Blocker | Owner? | Next action | Launch blocker? |
|---|---|---|---|---|---|---|---|---|
| Advisor onboarding | `LIVE_UNPROVEN` | 5 advisor + onboarding endpoints | Gates probed | `advisor_onboarding` 0 | — | no | — | no |
| Carrier operations | `LIVE_UNPROVEN` | CRUD, appointments | — | `carrier_quotes` 0 | — | no | — | no |
| Compliance | `LIVE_UNPROVEN` | Review conduct/documentation, disclosures | Endpoints answer | `compliance_disclosures` 0 | — | no | — | no |
| Suitability | `LIVE_UNPROVEN` | Start/reply handler | — | Never run | — | no | — | no |
| Quote / recommendation | `LIVE_UNPROVEN` | `quote-engine`, `policy-recommend` v1+v2 | `401` fail-closed verified | Never produced a recommendation | — | no | — | no |
| Document generation | `BLOCKED_OWNER` | Disclosure + review-doc generators | — | Cannot publish | **`Cloudflare R2` missing** — 3 MGA workflows on old code | **yes** | Create the credential | no |
| Commission / override | `LIVE_UNPROVEN` | Calculator, reconciliation, dispute | — | Never run | — | no | — | no |
| Portals | `LIVE_UNPROVEN` | Insurer accounts, users, white-label | Hosts serve 200 | No insurer onboarded | — | no | — | no |

## LUXI — commercial status: **INTERNAL READY**

| Area | Status | What exists | Tested | Not tested | Blocker | Owner? | Next action | Launch blocker? |
|---|---|---|---|---|---|---|---|---|
| Tenant subscription | `LIVE_UNPROVEN` | 1 commerce tenant on `clients` | — | No subscription | No LUXI Price | **yes** | — | no |
| Entitlement | `PARTIAL` | `luxi` in allow-list | Grant function exists | Never granted | — | no | — | no |
| Products / inventory | `LIVE_UNPROVEN` | 2 products, 2 inventory items | — | Never sold | — | no | — | no |
| Auctions | `LIVE_UNPROVEN` | 8 auctions | Admin endpoints fail closed | **0 bids** | — | no | — | no |
| Bids / Buy Now / anti-snipe | `LIVE_UNPROVEN` | Proxy bid, saved cards, 3DS recovery | — | Never exercised | — | no | — | no |
| Stripe / payment | `LIVE_UNPROVEN` | Live keys | — | **0 orders, ever** | Needs one real sale | **yes** | Sell one thing | no |
| Orders / fulfilment | `LIVE_UNPROVEN` | Immutable ledger, reservations, Eazer-ready | Stock invariant enforced in SQL, not app code | Never ran | — | no | — | no |
| Live commerce | `BLOCKED_OWNER` | On-air strip, restream control | — | — | Restream account | **yes** | — | no |

## Sentinel — commercial status: **PILOT READY** (monitoring)

| Area | Status | What exists | Tested | Not tested | Blocker | Owner? | Next action | Launch blocker? |
|---|---|---|---|---|---|---|---|---|
| Subscription | `LIVE_UNPROVEN` | Product in allow-list | — | Never sold | No Price | **yes** | — | no |
| Vendor health | `DONE` | Scheduled collector | **47,674 rows**, ~480/day, writing continuously | — | — | no | — | no |
| Workflow health | `BLOCKED_OWNER` | Collector active; error handling fixed | Root cause proven — `continueOnFail` sat inside `parameters.options` where n8n never reads it, and `N8N_API_KEY` is absent from the container, so the header was omitted and the API answered `'X-N8N-API-KEY' header required` | Still **0 rows** | Credential not binding after 3 UI fixes | **yes** | Count duplicate collector workflows | no |
| Incidents / alerting | `DONE` | `sentinel_alerts` | **879 alerts**; 7 briefings/day | — | 6 duplicate briefing workflows | **yes** | Delete the 6 | no |
| Remediation | `LIVE_UNPROVEN` | Auto-remediation phase 4 | — | Never fired | — | no | — | no |
| Dashboards | `DONE` | `admin/sentinel.html` | In daily use | — | — | no | — | no |
| Agent / MCP monitoring | `DEFERRED` | — | — | Not built | Workflow health first | no | — | no |

## Other products

| Product | Commercial | Status | Evidence | Launch blocker? |
|---|---|---|---|---|
| **AVA** | NOT READY | `PARTIAL` | Registered persona, insurance vertical; `active=false`, no HeyGen or voice id | no |
| **MAXI** | INTERNAL READY | `PARTIAL` | 22-industry catalogue, 168 value props, FK-mapped to 5 operable verticals, 17 NULL by design. Marketing surface, not vertical intelligence ([ADR-002](ARCHITECTURE_DOCTRINE.md)) | no |
| **CIRO** | NOT READY | `LIVE_UNPROVEN` | Comms/alerts pages, endpoints live, no data | no |
| **Creative / Content** | NOT READY | `PARTIAL` | 19 workflows, **10 are stubs**; `content_pieces` 0 | no |
| **UGC** | DEFERRED | `DEFERRED` | Not started. Must consume shared Media, not a new stack | no |
| **Studio** | DEFERRED | `DEFERRED` | Not started | no |
| **Theatre** | DEFERRED | `DEFERRED` | Not started | no |

---

## Applied migrations — verified in production

The repo has never had a migration ledger. This is it. **Do not re-run these.**

| Migration | Verified |
|---|---|
| `vertical-context-1-columns.sql` | `niche_overlays` at 24 columns |
| `vertical-context-2-maxi-fk.sql` | FK + partial index present |
| `vertical-context-3-maxi-mapping.sql` | 5 of 22 mapped, 17 NULL by design |
| `vertical-context-4-function.sql` | `get_vertical_context()` resolving |
| `vertical-context-5-seed.sql` | 8 of 8 verticals populated |
| `agent-runtime-first-personality.sql` | 1 personality, `recommend_only`, 0 decisions |
| `lead-ownership-1-provenance.sql` | house 2,378 / tenant 140, trigger present |
| `lead-ownership-2-insert-rpc.sql` | 11-arg and 12-arg, both `jsonb` |
| `entitlement-1-check-function.sql` | 3 functions present, all fail closed |

**Pending:** `onboarding-1-icp-from-onboarding.sql`.
