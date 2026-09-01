# Crystallux — readiness matrix

**The single authoritative record of what is finished.** There is no second
planning document; anything that contradicts this file is out of date.

Measured against production on **2026-09-01** — live Supabase row counts and
live HTTP probes, read directly from the database rather than inferred from
workflow definitions. Companion audits:
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

Deployed, reachable, never used in anger:

- Smart Quote — 7 industry estimators, 60 pricing artefacts, **0 completed quotes**
- LUXI — 8 auctions, **0 orders, 0 bids, 0 events, ever**
- MGA — 85 endpoints live, `carrier_quotes` 0, `policy_applications` 0
- Copilot — 6 endpoints, one real question answered, 0 persisted chat rows
- Stripe grant path — built, no purchase has run through it

The Sales Engine middle pipeline is no longer on this list. See below.

# SALES ENGINE — THE MIDDLE PIPELINE IS PROVEN

Measured in production on **2026-09-01** against the test tenant
(`6edc687d-…`, 79 leads). This supersedes every earlier statement in this file
that research, scoring or signals had never run.

| Stage | Evidence in production | Status |
|---|---|---|
| Research | **37 tenant leads** researched between `20:45:44Z` and `21:31:23Z` on 2026-08-31; grounded `research_summary` and `research_angle` on all 37 | `DONE` |
| Scoring | **37 of 37** carry `score_components` written `21:46Z`; inspected scores 62–72, with `ai_base_score`, `deterministic_bonus` and `basis: "model judgement, not arithmetic"` | `DONE` |
| Signals | **19** carry a `detected_signal` with `signal_confidence` | `PARTIAL` — written to the lead row; `market_signals` is still 0 |
| Why Now | `agent_decisions.context_used.capability_used = "assess_why_now"`, resolved through the canonical MCP gateway, `correlation_id` present | `DONE` |
| Next Best Action | `decision_type` `escalate` then `wait`, each with reasoning citing the composite score and the autonomy rule | `DONE` |
| Draft | 24 tenant leads carry `email_subject` and `email_body`; newest generated `2026-08-31T11:32Z` | `PARTIAL` — see the ordering defect below |
| Reply / Follow-up / Booking | `outreach_log` 0, `bookings` 0 | `LIVE_UNPROVEN` |
| Attribution | `campaigns` 0, `deals` 0 | `LIVE_UNPROVEN` |

**Lead Research v2 and Lead Scoring v2 are ACTIVE in production**, running on
their 15-minute schedules, scoped to `lead_pool=eq.tenant` (commit `ade85de`).
The scoping is confirmed behaviourally: 37 tenant leads were researched while
**483 house leads sitting in `New Lead` were left untouched**. The house pool
was never swept. Research produced nothing after `21:31Z` because it had
drained the tenant queue — not because it stopped working.

## The two ordering defects that remain

**1. Drafts are generated for unresearched leads.** Among the 24 tenant leads
holding a draft are leads with `researched_at = NULL`, generated at `08:32Z`
and `11:32Z`. `clx-outreach-generation-v2` consumes
`lead_status = 'Campaign Assigned'` and filters on **status alone** — no
`lead_pool`, no `research_summary IS NOT NULL`. Same defect class as the one
that put 1,373 leads in front of a scorer with nothing to reason about.

**2. The chain terminates at `Signal Detected`.** There are 0 leads at
`Campaign Assigned` anywhere in production, and the 37 scored tenant leads have
sat at `Signal Detected` since `21:46Z` without advancing. Nothing promotes a
scored lead into the campaign stage. That is why draft → send → reply →
follow-up → booking cannot yet be proven end to end — and, incidentally, why no
accidental send is possible today.

## Outbound state — one real send, then closed

One real email left the platform on **2026-08-31 at `08:02:21Z`**, to
**Haven Salon** (`house` pool, `client_id` NULL, no research). That is the
incident behind commits `1c24eaf` and `221d729`. No send has occurred since.

Outbound is off for four independent reasons — three by design, one by
accident:

1. `campaigns` is empty, so `Sender Eligibility Guard` can authorise no
   client/channel pair.
2. The tenant's `autonomy_level` is `recommend_only`, which is not in
   `AUTONOMY_MAY_EXECUTE`.
3. `Get Outreach Ready Leads` filters `research_summary=not.is.null`, and the
   4 tenant leads at `Outreach Ready` have none — the fetch returns `[]`.
4. **Accidental, and it must be fixed before any send is expected to work:**
   the fetch's query string is malformed —
   `…&limit=5,lead_pool,research_summary,scoring_reason,score_components`.
   Those four fields were appended *after* `limit` instead of into `select`,
   so `lead_pool`, `research_summary`, `scoring_reason`, `score_components`
   and `lead_score` are **never selected**. `Sender Eligibility Guard` then
   evaluates `scoreIsValid()` and `REQUIRED_POOL` against `undefined` and
   refuses every lead. PostgREST tolerates the malformed `limit` and answers
   `200`, so this fails closed *silently and permanently* — the guard reads as
   a working policy while actually refusing on missing data. **Not patched:**
   the sender is protected and outbound is deliberately off, so repairing it is
   a deliberate step for when sends are wanted, not a drive-by fix.


## Every path that can send — measured 2026-09-01

The sender's eligibility guard was treated as *the* boundary between the
platform and a real person's inbox. It is not. There are **four** send
paths and the guard sits on one of them.

| Path | Guarded by | Repo `active` | Live `active` |
|---|---|---|---|
| `clx-outreach-sender-v2` → Gmail | `Sender Eligibility Guard` | `false` | **was running 2026-08-31 17:01Z** |
| `clx-follow-up-v2` → **Gmail directly** | nothing | `false` | **UNVERIFIED** |
| `clx-booking-v2` → **Gmail directly** | nothing | `false` | **UNVERIFIED** |
| `clx-booking-create-v1` → Cal.com, then internal `/webhook/email/send` | shared secret only | `false` | **UNVERIFIED** |

Follow Up v2 and Booking v2 each hold their own `Send ... Email` node
posting straight to `gmail.googleapis.com`. Neither consults entitlement,
autonomy, `campaigns`, `lead_pool` or ownership. Hardening the sender did
not harden them, and no amount of further work on the sender will.

**Their live state cannot be read from this machine** — the local
`N8N_API_KEY` is the one minted 2026-04-06 and answers `401`. Until the
working key is available here, "outbound is off" rests on the repo saying
`active: false`, which is precisely the kind of inference that has been
wrong three times this sprint.

### Consent has no writer

**Nothing in the estate ever sets `unsubscribed = true` or
`do_not_contact = true`.** Both columns are written only at lead creation,
always as `false`. Three send paths filter on them correctly, so the
filters are real — they simply guard a flag no code can raise.

There is no STOP handler. `clx-reply-ingestion-v1` is the only inbound
reader and it does not inspect the body: a reply reading "STOP" is written
as `lead_status = 'Replied'`, which makes the lead **eligible for
`Get Replied Leads` in Booking v2**, which may then email it a Calendly
link. Both outbound templates print "reply STOP to unsubscribe" and the
booking one carries a CASL notice. The instruction is real; the mechanism
behind it does not exist.

### Follow-up cannot stop, and does not go where it says

- **The re-arm writes the wrong column.** `Build Follow Up Email` computes
  `next_followup_scheduled_at`; `Get Due Follow-ups` filters on
  `followup_scheduled_at`. The column the fetch reads is never advanced,
  so a lead re-qualifies on every hourly tick until `followup_count`
  caps at 3.
- **The stop signal cannot land.** At count >= 3 the node sets the next
  date to `null`, but `update_lead` applies
  `COALESCE(p_fields->>'next_followup_scheduled_at', l.next_followup_scheduled_at)`
  — a null is coalesced away and the old value survives.
- **A reply does not cancel a follow-up already in flight.** After the
  60-second `Wait`, `Build Follow Up Email` re-reads the row fetched
  *before* the wait and re-checks `do_not_contact`, `unsubscribed` and
  `total_emails_sent` — but not `reply_detected`.
- **`clx-follow-up-v2` still ships a hardcoded test recipient.**
  `Build Follow Up Gmail Raw` contains
  `const to = 'adesholaakintunde+clxtest@gmail.com'; // TESTING MODE. remove before production`,
  overriding the lead's address on every send. Booking v2 was fixed for
  this; follow-up was not.

### Reply intelligence does not exist

There is no reply classifier. `clx-booking-v2` runs a **binary** interest
detector emitting `interest_detected` plus `confidence`, `signal_type` and
`recommended_action` — and **no node reads those last three**. The
consequences are not neutral: a pricing question and "send me details"
both count as interested and trigger a booking email, while "not now,
maybe later" and a wrong-person reply both collapse into `Not Interested`.
`WRONG_PERSON`, `QUESTION`, `ALREADY_HAS_PROVIDER` and `UNSUBSCRIBE` have
no representation at all.

### Booking writes two disconnected stores

`clx-booking-v2` writes only `leads` via `update_lead`. `bookings` is
written by `clx-booking-create-v1` alone, which never touches `leads` — so
a booking it creates is invisible to `Get 48h-No-Booking Leads`, which
filters `meeting_scheduled=eq.false`. The client dashboard reads a third
table, `appointment_log`. Its Cal.com call also happens **before** the
local insert and performs no tenant check, so a failed insert orphans a
real calendar invite with no local record.
## `Signal Detected` does not mean a signal was detected — 2026-09-01

Measured live at 16:02Z, while the recovered batch was flowing through:
**79 tenant leads hold `lead_status = 'Signal Detected'` and only 19 have a
`detected_signal`.** Three of the 60 empty ones were written at 16:01:50,
16:01:55 and 16:02:00 — during the run, not historically.

The repo is right and production is not. `Prep Update Signal` in
`clx-business-signal-detection-v2` reads:

```js
// Only claim a signal was detected when one actually was. Marking a
// failed parse as 'Signal Detected' is how the funnel counted 284
// errors as buying intent.
lead_status: item.detected_signal ? 'Signal Detected' : 'Scored'
```

Two independent symptoms say live is running something else:

1. Leads arrive at `Signal Detected` with `detected_signal` NULL.
2. `signal_confidence` is NULL on all 60, though the shipped code defaults
   it to `'Low'` and `update_lead` allowlists the column
   (`v2.2.1_fix_update_lead_rpc.sql:70`). A value the code cannot leave
   null is null in production.

The shape is familiar: `Parse Signal Response` hardcodes the status and
`Prep Update Signal` is the node that overrides it correctly — the same
"the node that writes the status discards the node that decides it"
defect fixed for research in `92bd9fe`. The fix appears to have been made
here and never to have reached the server.

**What this invalidates.** Any count of "leads with a signal" taken from
`lead_status` is wrong, including several reported during this sprint.
The field is the evidence; the status is not. It also means promotion
gating on `Signal Detected` gates on almost nothing — worth adding
`detected_signal IS NOT NULL` to `Promotion Eligibility Guard`, which is
a one-line change and an owner call because it narrows promotion.

**Why it cannot be closed from here.** Drift is provable from the
database; the running definition is not readable without a working
`N8N_API_KEY`. This is the third open item blocked on that one credential,
after the live active-state of the two Gmail-direct senders and
verification that any deploy landed.

## What gates the pilot — and what does not

**Google Places — `BLOCKED_OWNER / FRESH_DISCOVERY` only.** The n8n credential
must send `X-Goog-Api-Key`; 115 `403 PERMISSION_DENIED` errors are logged from
the `06:07Z` tenant scan. This blocks proving *fresh* discovery. It does **not**
block the middle pipeline, which had 79 tenant leads to work with and has now
used them.

**Stripe — `BLOCKED_OWNER / COMMERCIAL` only.** `STRIPE_PRICE_SALES_ENGINE` is
declared and empty, so purchase → entitlement cannot complete. This gates the
*commercial* proof. It does not gate technical pilot readiness: entitlement
enforcement is already proven live on 11 of 11 endpoints.

**`ANTHROPIC_API_KEY` in the n8n container is proven working.** 37 grounded
summaries and 37 scores were produced through `$env` in live nodes. That
hypothesis is closed.

**`client_icp_profiles` is not empty.** One row —
`cd80cca0-f0cf-4fb9-a4ff-3686bd115411`, test tenant, created
`2026-08-31T06:05:35Z`. The earlier "0 rows / BLOCKED_OWNER" line contradicted
the onboarding row in this same file and was stale.

# WHAT BLOCKS FULL SELF-SERVE LAUNCH

- **Entitlement is enforced nowhere in the request path yet.** The functions
  exist; no endpoint calls them. A valid session still reaches `client/*`
  regardless of purchase.
- **One real send, ever, outside the test inbox** — Haven Salon,
  2026-08-31 `08:02:21Z`, a house lead with no owner and no research. That is
  the incident the eligibility guard was written for, not a proof of send.
- **Attribution cannot be reconstructed** — `campaigns` 0, `deals` 0.
- **Reply, follow-up and booking have never carried a real event.**

# WHAT CAN WAIT UNTIL AFTER REVENUE

UGC, Studio, Theatre, six of seven avatars, social publishing (six stub
publishers, blocked on platform review anyway), voice, video rendering, and
MCP external access. Agentic activation is no longer on this list — read-only
and controlled-action are both proven. None of the rest blocks a first paying
customer.

---

## Why 1,373 leads scored zero — the finding behind the finding

Cleaning the false scores exposed the actual defect, and it is not in the
scorer. The correlation is close to perfect:

| | Scored successfully | Scoring failed |
|---|---:|---:|
| **Has research** | **741** | **0** |
| **No research** | 404 | **1,373** |

Not one researched lead failed to score. Every one of the 1,373 failures had
`research_summary` NULL. The scorer was handed leads with nothing to reason
about, the model returned something unparseable, and the catch block wrote a
zero.

**Re-scoring them is therefore the wrong remedy.** They are not unscored leads
waiting for a scorer; they are unresearched leads that should never have
reached one. The order is discover → research → score, and
`clx-lead-research-v2` consumes `lead_status = New Lead` while
`clx-lead-scoring-v2` consumes `Researched`. Something routed 1,373 leads past
the middle step.

Putting them right means **researching** 1,373 leads, one Claude call each, on
house-pool prospects that are Crystallux's own outbound list rather than a
pilot customer's inventory. That is a spend decision, so it is left to the
owner. The repaired scorer now refuses to invent a score in that situation, so
the condition cannot recur silently.

---

## Core platform

| Area | Product | Status | What exists | Tested | Not tested | Blocker | Owner? | Next action | Launch blocker? |
|---|---|---|---|---|---|---|---|---|---|
| Auth | Core | `DONE` | 9 workflows, `validate_session`, 167 sessions | Login flows; fail-closed verified on 126 fetches | Reset under load | — | no | — | no |
| Tenant isolation | Core | `DONE` | `client_id` from session row; RLS 208/208 | Code-traced and probed; `client/*` filters on session tenant | Two live sessions cross-tenant | — | no | — | no |
| Billing | Core | `LIVE_UNPROVEN` | Live Stripe keys, webhook, events log | Signature path exists | **No payment ever ran through it** | No Sales Engine Price | **yes** | Create the Price | **YES** |
| Product entitlement | Core | `DONE` | 3 functions live; all 11 `client/*` endpoints wired to `validate_session_for_product` | **Live: 11/11 no-session → 401; 10/11 unentitled → 403 `product_not_entitled`; 11/11 entitled → 200 with real data.** 11th (copilot/transcribe) needs a binary upload so bails earlier — fails closed, guard present in code | Under concurrent sessions | — | no | — | no |
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
| Copilot | Agentic | `DONE` (client side) | 6 endpoints | **Answered a real question live: "You have 79 leads in your pipeline" — the test tenant's count, not the global 2,518, so tenant scoping holds through the Copilot too** | Admin copilot; conversation persistence | — | no | — | no |
| Agent personality | Agentic | `DONE` | 1 row: construction, `recommend_only`, MAXI, 8 gated | Verified live; vertical resolves | — | — | no | — | no |
| Decision engine | Agentic | `DONE` | 9 workflows, 16 tables | **3 decisions persisted live** for the test tenant — `escalate`, `escalate`, `wait`, each with reasoning, `confidence_score` 0.75 and a `correlation_id`. `assess_why_now` resolved through the canonical MCP gateway and the tool output is quoted in the reasoning | Under a second tenant or vertical | — | no | — | no |
| Action executor | Agentic | `DONE` | Fail-closed gate on the only path to a send | **35 tests** — sensitive classes blocked, approval validated not trusted, tenant mismatch refused | Never run on a real decision | — | no | — | no |
| Policy gate | Agentic | `DONE` | Risk keyed on capability, not product | 35 tests in CI, reading shipped `jsCode` | — | — | no | — | no |
| Product routing | Agentic | `DONE` (as a decision) | MCP's `Parse Request` already maps all 10 capabilities to a product and refuses any tool without one | Verified in the shipped `jsCode`: `PRODUCT` map, `RISK` map, and a hard refusal on an unmapped tool | Not exercised under a second product | — | no | **No separate router. Building one would duplicate a mapping that already exists and fails closed** | no |
| MCP | Agentic | `PARTIAL` | Two gateways; `agent-tools` canonical | **28 tests**; no node may call a sender directly; probe confirms fail-closed | Never carried an authorised call | `MCP_WEBHOOK_SECRET` absent from container | **yes** | Defer — 5 calls ever | no |
| Memory | Agentic | `LIVE_UNPROVEN` | Table + retrieve tool | — | 0 rows | Nothing has written one yet | no | — | no |
| Escalation | Agentic | `LIVE_UNPROVEN` | Endpoint live, left direct as the safety valve | — | 0 rows | — | no | — | no |
| `agent_channels_enabled` | Agentic | `DONE` | 1 row: `internal`, `enabled: true`, `outbound: false`, `authorized_by: owner`, enabled `2026-08-31T06:36Z` | The read-only proof ran through it | No outbound channel enabled — deliberately | — | no | — | no |
| `behavioral_triggers` | Agentic | `LIVE_UNPROVEN` | Table exists | — | 0 rows | Nothing upstream runs | no | — | no |
| `agent_schedules` | Agentic | `LIVE_UNPROVEN` | Table exists | — | 0 rows | — | no | — | no |
| **Read-only proof** | Agentic | `DONE` — READ_ONLY_PROVEN | Real tenant decision, capability selection, `assess_why_now` through canonical MCP, persisted decision with correlation | **Tool output materially influenced the reasoning** — the `wait` decision cites signal staleness the capability returned | Repeat run under a second vertical | — | no | — | no |
| **Controlled-action proof** | Agentic | `DONE` — CONTROLLED_ACTION_PROVEN | Live Action Executor result: `executed=false`, `result=approval_required`, `risk_class=CONTACT_HUMAN`, `autonomy_level=recommend_only`, `allowed=false`, `approval_required=true` | The refusal is the proof: the gate stopped a contact action and left an `agent_actions` row at `status: pending` rather than sending | An approved action actually executing | Deliberate — outbound stays off | no | — | no |
| Sentinel sees agents | Agentic | `DEFERRED` | — | — | Not built | Workflow-health first | no | After that | no |

## Sales Engine — commercial status: **NOT PILOT READY**

An earlier revision of this file said PILOT READY (technical). That was
premature and is retracted here.

What is proven is the **middle** of the pipeline: research, scoring,
`score_components`, Why Now and Next Best Action have all run in
production against real tenant leads. That is genuine and it is not
nothing.

What is not proven is the **revenue loop**, and pilot readiness is the
loop, not the middle of it:

- **Promotion** is built and tested (28 tests, `agent/promotion-draft-safety`)
  but not deployed, and it correctly refuses all 59 scored leads because
  `campaigns` holds no authorised play. Nothing in the codebase writes
  that table.
- **Reply intelligence does not exist** — a binary interest detector is
  not a classifier.
- **Follow-up cannot stop** — the re-arm writes a column the fetch does
  not read, and the stop signal is coalesced away.
- **Attribution is missing seven hops** and has no journey-ordering key.
- **Three of the four send paths have no guard on them at all.**

Fresh discovery (Google Places) and purchase (Stripe Price) remain
owner-gated and are separate from all of the above.

| Area | Status | What exists | Tested | Not tested | Blocker | Owner? | Next action | Launch blocker? |
|---|---|---|---|---|---|---|---|---|
| Signup | `LIVE_UNPROVEN` | Signup workflow; webhook creates client + user | Endpoints answer | No real signup | — | no | — | no |
| Tenant creation | `LIVE_UNPROVEN` | Webhook creates `clients` | 4 clients exist | Not via a real purchase | — | no | — | no |
| Entitlement | `DONE` (enforcement) / `BLOCKED_OWNER` (purchase) | Enforced on all 11 endpoints; `grant_product` idempotent | **Granted to test tenant as TEST DATA; revoked and re-granted live to prove the 403 path.** Other 3 clients remain unentitled | No real purchase has granted it | Stripe Price for a real grant | **yes** | Create the Price | **YES** (purchase only) |
| Onboarding | `DONE` | `upsert_client_icp_from_onboarding()`; onboarding-3 applied | **Full happy path proven live**: `ok:true`, ICP row created for the test tenant on construction, 8 buyer titles inherited from the overlay, `offer_override` a JSON string, `channels_enabled` preserved as `["email"]`, `calendly_link` and `niche_name` correct, `niche_overlays` modified_recently = 0. Both refusals still hold | A second vertical for the same tenant | — | no | — | no |
| `client_icp_profiles` | `DONE` | Table + connector | **1 row live** — `cd80cca0-…`, test tenant, created `2026-08-31T06:05:35Z`. The earlier "0 rows" line was stale and contradicted the onboarding row above it | A second tenant | — | no | — | no |
| Vertical context | `DONE` | 8 verticals, `get_vertical_context()` | 11/11 checks; 4 verticals proven differentiated in titles, tone, signals, terminology, channel, cadence, compliance | — | — | no | — | no |
| Discovery (house) | `PARTIAL` | `clx-b2c-discovery-v2.1` schedule path | 2,378 house leads historically | **No lead since 2026-05-28** | Schedules not running | **yes** | Restart or retire | no |
| Discovery (tenant) | `BLOCKED_OWNER` / FRESH_DISCOVERY only | `discovery/tenant-scan` deployed, registered, and reached production | Ran `2026-08-31 06:07Z`: authenticated, tenant-scoped entry worked, died at the Google Places call | 115 `403 PERMISSION_DENIED` in `scan_errors` | Credential must send `X-Goog-Api-Key` | **yes** | Fix the credential | no — the middle pipeline runs on the 79 existing tenant leads |
| Person resolution | `PARTIAL` | Per-vertical title keywords | Config verified | **Apollo: 0 leads ever** | — | no | Email scraper found 881 emails without it | no |
| Signals | `PARTIAL` — **live drift** | Types + weights on all 8 verticals | 19 tenant leads carry a real `detected_signal` + `signal_confidence` | **60 of 79 leads at status `Signal Detected` have NO signal.** The repo writes `Scored` in that case; live does not. `signal_confidence` is NULL live although the code cannot produce null and the RPC allowlists it | Live definition differs from repo; needs the n8n key to read | **yes** | Confirm the running build, redeploy | no |
| Intent | `LIVE_UNPROVEN` | hot/warm/cold rules per vertical | Config verified | Never computed | — | no | — | no |
| Scoring | `DONE` | Scoring v2, **active and on schedule**, tenant-scoped | **37 of 37 researched tenant leads scored `21:46Z`** with full `score_components`; 831 of 2,518 platform-wide score ≥50 | Volume on a second tenant | — | no | — | no |
| Research | `DONE` | Research v2, **active and on schedule**, `lead_pool=eq.tenant` | **37 tenant leads researched live `20:45`–`21:31Z` 2026-08-31**, grounded summaries and angles on all 37; 483 house leads untouched | Volume beyond 37 | — | no | — | no |
| Outreach generation | `PARTIAL` | Generation v2, reads `niche_overlays` | **24 tenant leads hold a subject + body**, newest `2026-08-31T11:32Z` | **Drafts were generated for leads with `researched_at` NULL** — the fetch filters on `lead_status` alone, no `lead_pool`, no `research_summary IS NOT NULL` | Same ordering defect class as the 1,373 | no | Add the two filters | no |
| Email send | `PARTIAL` | Postmark + Gmail bound; eligibility guard added | **One real send: Haven Salon, `2026-08-31 08:02:21Z`** — a house lead with no owner and no research, which is the incident the guard exists for | The guard has never been observed refusing live | `Get Outreach Ready Leads` never selects `lead_score` / `lead_pool` / `research_summary`, so the guard refuses on missing data, not policy | no | Repair the select list before expecting any send | no |
| Replies | `LIVE_UNPROVEN` | Reply ingestion v1 (protected) | — | `outreach_log` 0 | Nothing to reply to | no | — | no |
| Follow-up | `LIVE_UNPROVEN` | Follow-up v2, per-vertical cadence | Config verified | 0 rows | — | no | — | no |
| Booking | `LIVE_UNPROVEN` | Booking v2 (protected), Calendly | — | `bookings` 0 | — | no | — | no |
| Attribution | `PARTIAL` | Lead provenance columns | Source attribution works — every lead traceable | **`campaigns` 0, `deals` 0 — chain cannot be reconstructed** | No campaign has run | no | One campaign row per send | **YES** (for selling) |
| Reporting | `LIVE_UNPROVEN` | Dashboards, per-vertical labels | Pages render | No data | — | no | — | no |

## Stripe — commercial status: **BLOCKED_OWNER / COMMERCIAL**

This gates the commercial proof — money in, entitlement out. It does **not**
gate technical pilot readiness: entitlement enforcement is already proven
live on 11 of 11 `client/*` endpoints, granted and revoked as test data.

| Area | Status | What exists | Tested | Not tested | Blocker | Owner? | Next action | Launch blocker? |
|---|---|---|---|---|---|---|---|---|
| Checkout | `LIVE_UNPROVEN` | Live keys, payment links | — | No checkout completed | No Sales Engine Price | **yes** | Create it | **YES** |
| Price mapping | `BLOCKED_OWNER` | `STRIPE_PRICE_SALES_ENGINE` + 4 siblings declared empty | Unmapped price grants nothing and records why | Never matched a real price | **Price ID does not exist** | **yes** | Create it | **YES** |
| Webhook verification | `LIVE_UNPROVEN` | Signature check, unverified logged | Chain traced node by node | No real event | — | no | — | no |
| Tenant resolution | `LIVE_UNPROVEN` | Resolved from `stripe_customer_id`, never from event-claimed identity | Chain verified | No real customer | — | no | — | no |
| Grant | `LIVE_UNPROVEN` | 4 nodes → `grant_product` | Allow-list refuses typos; fail-closed on unmapped price | No purchase | No Price | **yes** | Create it | **YES** |
| Revoke | `LIVE_UNPROVEN` | Suspend users, clear products, revoke sessions | Chain asserted unchanged by the grant patch | No real cancellation | — | no | — | no |
| Idempotency | `LIVE_UNPROVEN` | `grant_product` no-ops on re-grant; events logged | Logic verified in SQL | No replayed event | — | no | — | no |

**The only Stripe blocker is the Price.** Every other link in the chain exists
and was traced node by node: webhook → verify → log → patch client → resolve
grant → decide → resolve tenant → grant → cancellation branch unchanged.

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

# AGENTIC — PROVEN IN PRODUCTION (2026-08-31)

`READ_ONLY_PROVEN`. Three genuine decisions persisted; the third is the one
that matters.

| Evidence | Value |
|---|---|
| Decision | `b2998b02-dac3-493a-8688-86b64c5b28ad` |
| Correlation | `proof-1788199236653` |
| Capability selected | `assess_why_now` |
| MCP call | `mcp_tool_calls` 18:00:40.358 — first row since 8 April |
| Decision persisted | 18:00:43.388, three seconds later |
| Outcome | `wait`, confidence 0.75 |

The reasoning is the proof: *"Signal is 131 days stale with low urgency and
medium confidence."* Those three values are `assess_why_now`'s own output
fields — `recency_days: 131`, `urgency: low`, `confidence: Medium`. None was
in the trigger context, so the model could only know them by calling the
tool. And the recommendation changed because of it: runs one and two
escalated, run three decided to wait. The capability materially altered the
outcome, which is the difference between an agent that reasons and one that
merely runs.

Zero external communication throughout. `agent_channels_enabled` holds one
row, `internal`.

## Why nothing had been researched — two bugs stacked

**The status writer discarded the status decider.** `Parse Claude Response`
computes `lead_status` from whether research actually produced a summary --
the pipeline-ordering fix from earlier in this sprint. `Prep Update Lead`
then hardcoded `lead_status: 'Researched'` and threw it away. The fix was
real and had no effect.

**Underneath it, the Anthropic call was never authenticating.** The node
carried `anthropic-version` and `Content-Type` but no `x-api-key`, relying
on an n8n header credential named `Claude Anthropic` that returned nothing
for 50 consecutive leads. Both now use `$env.ANTHROPIC_API_KEY`, the
mechanism the decision engine uses and the only Anthropic call here with
production evidence behind it. The exact model, payload and prompt were
verified against the live API before shipping.

Live evidence that exposed it: 50 leads marked `Researched`, 0 with a
summary, 0 marked `Research Failed`. **The scoring guard held** —
`research_summary=not.is.null` excluded all 50, so nothing was scored
wrongly. Fail-closed did its job while two bugs sat behind it.

# POST-PILOT — RECORDED, NOT BLOCKING LAUNCH

The advanced competitive layer is deliberately not built. First revenue
outranks it, and each item below needs the pilot loop running before it has
anything to learn from.

| Area | Post-pilot work | Foundation that already exists |
|---|---|---|
| Unified GTM context | Compose tenant + ICP + account + signals + history at decision time | `Fetch Proof Lead` + capability selection already assemble a slice |
| Account/person resolution | Company and person as distinct entities; cross-source dedupe | `leads_company_unique`; no person entity yet |
| Multi-signal intelligence | type/source/timestamp/confidence/recency per signal | single `detected_signal` + `signal_confidence` today |
| Playbook engine | Per-vertical selling behaviour as configuration | `niche_overlays` (8 verticals) is the right home |
| NBA v2 | Reason across history, memory, reply state, campaign | `next_best_action` capability shipped, deterministic |
| Provider routing | One shared router; availability, cost, freshness, fallback | providers currently hard-wired per workflow |
| Cost-aware research | Staged enrichment, cost per lead/account | `apollo_credits_log`, `agent_actions.cost_cents` unused |
| Play selection | Choose acquisition / expansion / re-engagement per account | `campaigns.status` is the authorization state |
| Agent observability | Capabilities considered, latency, cost, policy outcome | `context_used` carries correlation + capability today |
| Experimentation | Variant tracking without invented significance | none |
| Outcome learning | Analytics first, calibration later, governed changes only | `agent_memory` (0 rows), `agent_decisions.outcome` |
| Natural-language operator | Plan, invoke capabilities, request approval | MCP capability plane is the substrate |
| Autonomy tiers | L3 auto-execute internal, L4 policy-authorized external | L1/L2 enforced today by the policy gate |
| Sentinel oversight | Cost spikes, unexpected sends, credential health | workflow-health collector still 0 rows |

The rule this sprint keeps proving: a check that cannot fail closed is not a
check. Every one of the above must land behind the policy gate, not beside
it.
