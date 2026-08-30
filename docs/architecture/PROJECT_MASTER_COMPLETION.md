# Crystallux — master completion register

**The single source of truth for what is finished.** A row is only `READY` or
`DONE` if the Evidence column says how that was established. "The code exists" is
not evidence.

Measured 2026-08-30 against the repo at `0a17874` plus this session's changes.
Production figures are carried from the 2026-08-28 audits
([infrastructure](../audit/2026-08-28-master-architecture-audit.md),
[products](PRODUCT_REGISTRY.md)), which measured the live Supabase schema, row
counts, and a probe of all 285 webhook paths. Where this session re-measured
something and got a different answer, the new figure is used and the correction
is called out.

Owner queue: [`OWNER_ACTIONS_REQUIRED.md`](OWNER_ACTIONS_REQUIRED.md).

---

## 0. The one-paragraph summary

Crystallux is a **fully built platform that was never switched on**. Ten products
are deployed and carry no data at all. The Sales Engine — the thing that makes
money — last sent an email on 2026-06-08 and last acquired a lead on 2026-05-28.
The only subsystem executing continuously is Sentinel, the monitoring layer, and
it has been blind to workflow state since before the Sales Engine stopped,
because the n8n API key it depends on returns 401.

The binding constraint is not code and never was. **One expired credential**
(§1.1) gates observability, deployment, and the ability to answer the question
"what is actually running?" Everything downstream of that is guesswork until it
is replaced.

---

## 1. Platform readiness

The finish-line conditions, each with the evidence that settles it.

| Capability | Product | Status | Evidence | Test | Production State | Blocker | Needs Owner? | Next Action |
|---|---|---|---|---|---|---|---|---|
| **1.1 Workflow status is reliable** | Platform | `PARTIAL` | The **GitHub Actions** key now works — the deploy job enumerated and updated 131 workflows across two runs on 2026-08-30, so the management API answers. `sentinel_workflow_health` is **still 0 rows** (checked live after both deploys), so the *collector* is still not producing. `admin/workflow-status` still derives from `scan_log` (0 rows), not from n8n, so the admin Workflows page still reports fiction | CI deploy job probes the key on every run | API reachable from CI; **in-platform monitoring still blind** | Collector-side, not key-side — see 1.2 | **YES** | 1.2 |
| **1.2 Sentinel workflow monitoring** | Sentinel | `BLOCKED_OWNER` | Vendor health **47,214 rows** (up from 46,479 on 08-28 — still writing). Workflow health **0**. The collector `clx-sentinel-health-workflow-collector-v1` authenticates with `{{ $env.N8N_API_KEY }}` in a request header. `$env` **does** resolve in expressions — the daily briefing uses `$env.MARY_EMAIL` and runs 7×/day — so the likely causes are narrower: either `N8N_API_KEY` is absent from the **n8n container's** environment (`docker-compose.yml` does not pass it), or the collector workflow is not active. Setting the key in a shell profile or `/root/.env` does **not** put it in the container | live Supabase row count | Blind | Needs the live container env to tell which | **YES** | `docker inspect` — [owner action #1b](OWNER_ACTIONS_REQUIRED.md) |
| **1.3 CI validates the whole estate** | Platform | `DONE` | Was 50 of 326 files, `workflows/*.json` only, and ran neither validator. Now walks all 326 recursively and runs both. Verified locally: **326 workflows, 0 problems, 0 warnings**; **113 SQL files, 0 failed** | `.github/workflows/crystallux-ci.yml`, jobs `validate` | Runs on every push and PR | — | no | — |
| **1.4 Deployment is reproducible** | Platform | `DONE` — exercised twice against production | CI used to `POST /api/v1/workflows` for every file on every push — **POST creates**, so each push minted duplicates with fresh ids. Now updates by top-level id, deploys only files changed in the push, refuses to create, and never activates. 324/326 files carry a unique id (0 collisions), so update-by-id is well defined | `deploy` job; `scripts/n8n/n8n-put-body.py` | **Working.** Run 1 (`59bf216`) updated 56, run 2 (`6470371`) updated 75 — 131 workflow updates, 0 failures, no protected workflow touched, no activation changed | — | no | — |
| **1.5 Security endpoints fail closed** | Platform | `DONE` — verified in production | **126 of 126** `validate_session` fetches now carry `alwaysOutputData`. The first pass guarded only 51 because it treated `neverError: true` as equivalent protection — **it is not**, and a live probe proved it: after that deploy, `client/overview` returned `401 {"ok":false,"error":"Invalid or expired session"}` while `admin/avatar-schedule`, which carried `neverError`, still returned **HTTP 200, 0 bytes**. `neverError` suppresses a non-2xx; it does nothing about a 200 whose body is `[]`, which n8n splits into zero items. All 126 downstream Code nodes verified to reject a missing row first, so every guard is strictly fail-closed. 7 Switch nodes had no `fallbackOutput`; all 7 now route to their error responder | `validate-workflows.py` + live HTTP probe against production | **All 126 live and verified.** Post-deploy probe: `admin/avatar-schedule`, `admin/system-health`, `admin/luxi/auctions/manage`, `admin/list-leads`, `admin/billing-summary`, `mga/insurance/quote-engine` and `client/overview` all answer a bad token with **401 and a body**. Every one of the first six returned an empty 200 an hour earlier | — | no | — |
| **1.6 Auth works correctly** | Auth / Identity | `READY` | 9 workflows, 9 endpoints live, 165 sessions, most recent 2026-08-20. `validate_session` is the single gate and is now uniformly fail-closed (§1.5) | exercised by every admin/client login | Live | — | no | — |
| **1.7 Tenant isolation** | Platform | `PARTIAL` | RLS enabled on **208 of 208** public tables. `client/*` endpoints are tenant-scoped. **But neither MCP gateway takes a `client_id`** — every machine-callable tool is implicitly platform-wide | none | Live for humans, absent for agents | — | no | Add tenant context at the gateway before any agent runs (§4.3) |
| **1.8 Core migrations in source** | Platform | `PARTIAL` | 113 SQL files, all parse against the real Postgres grammar. **18 live tables have no `CREATE` anywhere in the repo — `leads` among them.** Production cannot be rebuilt from source | `validate-migrations.py`, now in CI | 194 of 198 declared tables live | — | no | Capture the 18, starting with `leads` |
| **1.9 Migration ledger** | Platform | `BROKEN` | Nothing records which of the 113 files have been applied. The three `schema_migrations`/`migrations` tables belong to Supabase's own `auth`/`realtime`/`storage` schemas | none | Applied state is unknowable without diffing live schema | — | no | Add an applied-migrations table + record backfill |
| **1.9a Code-node environment access** | Platform | `DONE` — verified in production | n8n's Code sandbox never exposes the Node.js `process` global, so `process.env` threw `process is not defined` regardless of what the container held — Mary confirmed the variables were present and it still failed. **`$env` is the supported accessor and was already proven here**: 33 Code nodes used it, including `clx-luxi-bid-parser-v1` (LUXI works) and the protected `clx-booking-v2`. Converted 57 Code nodes across 53 workflows; `$env[envKey]` covers the one dynamic lookup in Stripe provisioning. **No container change, no restart, no config edit** — [§31 of the brief and ADR rationale](ARCHITECTURE_DOCTRINE.md) | live HTTP probe, invalid credentials only | **49 of 53 live and verified.** `email/send`, `mga/insurance/needs-analysis`, `agent/action-execute`, `messaging/sms-send`, `video/script-generate` all answer `401 {"ok":false,"error":"internal secret required"}` — every one returned an empty 200 beforehand. MCP now answers `401 "MCP_WEBHOOK_SECRET is unset"`, the correct fail-closed message | 4 held back — see 1.9c | no | — |
| **1.9c Four workflows blocked on one n8n credential** | Video, MGA | `BLOCKED_OWNER` | CI refused to publish 4 of 53: `Cannot publish workflow: Credential not configured: aws`. **This is not AWS.** All 5 R2 nodes in the estate are `n8n-nodes-base.awsS3` referencing a credential named **`Cloudflare R2`** — n8n's *type* is `aws` because R2 speaks the S3 API. No AWS account is involved. The credential simply does not exist in n8n under that name; nothing else in the estate uses another R2/S3 name (only one `aws` credential name exists across all 326 workflows). Affected: `clx-heygen-webhook-v1`, `clx-mga-insurance-disclosure-generator-v1`, `clx-mga-insurance-review-documentation-v1`, `clx-mga-insurance-zoho-sign-callback-v1`; `clx-video-storage-cleanup-v1` shares the dependency but was not in the changed set | credential inventory across 326 workflows | These 4 are still on old `process.env` code | Credential must exist in n8n named exactly `Cloudflare R2` | **YES** | [Owner action #1c](OWNER_ACTIONS_REQUIRED.md) |
| **1.9b What 1.9a explains** | Platform | — | The agentic runtime has 0 rows in all 16 tables, Copilot has 0 chat rows, `video_renders` is 0, messaging is unused. These were read as "built but never switched on". At least in part they are **"switched on and unable to authenticate"** — the workflows are live and registered, they just cannot reach their secrets. **LUXI, Commerce, Sentinel and the Sales Engine do not use `process.env` and are unaffected** — verified by grep across all 326 | — | — | — | no | Re-test each after 1.9a is fixed before concluding anything about adoption |
| **1.10 Logs and errors are visible** | Platform | `BROKEN` | `admin_action_log` has 98 rows, every one `action_type='vertical_generated'` from an automated job, `action` NULL in all 98. Two overlapping schemas in one table (`admin_user`/`actor_email`, `created_at`/`occurred_at`). **No human admin action is audited**, though `audit-log.html` renders the table | none | Page exists over an empty concept | — | no | Reconcile the two schemas, then write on privileged actions |
| **1.11 Queue tier actually queues** | Platform | `PARTIAL` | `docker-compose.yml` ran main at `EXECUTIONS_MODE=regular` while `n8n-worker` ran `queue`. n8n only enqueues to Redis when the **main** instance is in queue mode, so the worker never received a job — a scaling tier declared, paid for in RAM, never reached. Main is now `queue` in the repo | none | **Repo only, and must stay that way for now** | **The VPS is not running this file** — see 1.11a | **YES** | Get the live env first, then rewrite the compose file to match |
| **1.11a The repo's compose file is not production** | Platform | `BROKEN` | The earlier audit marked this UNVERIFIED. Now settled: `blockers.md` §0ag records `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` as already set live with LUXI and the copilot depending on it, and that variable appears **nowhere** in `docker-compose.yml`. Nor does `MCP_WEBHOOK_SECRET`. The live container is configured from an edited copy, an `env_file`, or an override that is not in source | none | Infrastructure is not reproducible from the repo, and `docker compose up -d` from it would hand n8n a smaller environment than it has | — | **YES** | `docker inspect n8n --format '{{json .Config.Env}}'`, names only — [owner action #5](OWNER_ACTIONS_REQUIRED.md) |
| **1.12 Automated test coverage** | Platform | `PARTIAL` | Two static validators (now CI-gated) plus three Playwright audit harnesses under `tests/audit/`. **No unit tests, no endpoint contract tests, no integration tests.** Static analysis is the whole safety net | — | — | — | no | Endpoint contract test once #1 lands and live state is knowable |
| **1.13 Secrets hygiene** | Platform | `PARTIAL` | No secrets reach any frontend — checked. But `MARY_MASTER_TOKEN` is a static, long-lived shared secret in `localStorage`, no rotation, no expiry, no per-actor identity — and it is the only thing gating `copilot/query`, which asks Claude to write SQL | none | Live | — | **YES** | Scope and rotate; decide an expiry model |

---

## 1z. Four levels of "working" — read this before believing any green row

The `process.env` fix removed the *first* error in a chain. That is not the same
as a product working, and conflating the two is how a platform ends up with ten
products marked done and zero orders. Every claim in this document sits at one
of four levels:

| Level | Means | How it is established |
|---|---|---|
| **1. Environment access fixed** | The Code node can read its secret. `process is not defined` is gone | Static: the workflow no longer references `process.env` |
| **2. Endpoint responds correctly** | A bad request is rejected with a real status and body; a well-formed one is accepted | Live HTTP probe |
| **3. Functionally tested** | The workflow does its actual job end to end — the email sends, the video renders, the tool executes and writes a row | A real transaction, checked in the database |
| **4. Commercially ready** | Level 3, plus monitoring, cost/rate limits understood, failure path exercised, no test-only behaviour in the live path, and documented operation | The 16-point definition in the brief |

**As of 2026-08-30 the 53 repaired workflows are at level 1, and a handful are at
level 2.** None is at level 3. Nothing in this pass should be read as "Copilot
works" or "the agent runtime works" — only as "they are no longer failing for
this particular reason." Reaching level 3 for the agent runtime means seeding one
personality and driving one decision through to `agent_decisions`; for Copilot it
means one real question answered; for Video one real render. Those are cheap and
none has been done.

---

## 1a. Credential state

Where each credential lives, and how confidently that is known. **"Verified"
means observed, not reported.** Values are never recorded here or anywhere in
the repo.

| Credential | Location | State | How that was established | What it gates |
|---|---|---|---|---|
| `N8N_API_KEY` | GitHub Actions secret | **Set by owner 2026-08-30**, verified by the deploy job's probe | The deploy job calls `GET /api/v1/workflows?limit=1` before touching anything and exits non-zero on any non-200 — see §5 for the result of the first run | CI deploy |
| `N8N_URL` | GitHub Actions secret | **Set by owner 2026-08-30** → `https://automation.crystallux.org` | same probe | CI deploy |
| `N8N_API_KEY` | VPS / server environment | **UNKNOWN — cannot be verified from here** | There is no SSH access to `srv1365369.hstgr.cloud` from the working machine: no key, `Permission denied (publickey,password)`. The owner reports setting it; that report is **not independently confirmed** | `ship.sh`, the four `activate-*.sh`, the drift detector, and 10 other scripts. Also Sentinel's workflow-health collector and the daily briefing, which is why all three failed together |
| `N8N_API_KEY` | repo-root `.env` (local dev only) | **INVALID** | Probed 2026-08-30: `GET /api/v1/workflows?limit=1` → **HTTP 401 `{"message":"unauthorized"}`**. This is the dead key the August audit found; it was never rotated locally | local script runs from this machine |
| `MCP_WEBHOOK_SECRET` | VPS / server environment | **UNVERIFIED — must be confirmed before MCP is expected to work** | Absent from `docker-compose.yml`; no way to read the live container env without server access | Both MCP endpoints. The gateway fix is **fail-closed**: until this is set they answer `401`. See [owner action #3b](OWNER_ACTIONS_REQUIRED.md) |
| `N8N_ENCRYPTION_KEY` | VPS / server environment | **Present and deliberately untouched** | Declared in `docker-compose.yml` and `.env.example`. **Not modified, not read, not rotated** | Decrypts every credential n8n has stored. Overwriting it would lock n8n out of all of them — it is not the API key and must never be treated as one |

**The asymmetry that matters:** the GitHub key gets tested automatically on every
push, because the deploy job probes it first. The **server** key has no such
check — nothing on the VPS verifies it until a script happens to use it and
fails. That is precisely how it stayed dead from June to August without anyone
noticing. A periodic probe of the server-side key belongs on Sentinel, and
cannot be built until §1.1 is genuinely closed.

---

## 1b. Multi-vertical, MAXI, and the agentic plane

| Capability | Product | Status | Evidence | Test | Production State | Blocker | Needs Owner? | Next Action |
|---|---|---|---|---|---|---|---|---|
| **Vertical intelligence source of truth** | Sales Engine | `DONE` | `niche_overlays` read by 8 workflows (campaign router, lead scoring, outreach generation, Apollo enrichment, signal intelligence, video outreach, voice outreach, copilot query). No second system exists or is being built — [ADR-001](ARCHITECTURE_DOCTRINE.md) | grep across 326 workflows | Live and in use | — | no | — |
| **MAXI taxonomy alignment** | MAXI | `BLOCKED_OWNER` | Two taxonomies with no FK: `maxi_industries` (22 marketing rows) vs `niche_overlays` (8 operable). Only 3 slugs matched; `cleaning`/`cleaning_services` and `lawyers`/`legal` had drifted. Migration adds a nullable `maxi_industries.niche_overlay_id` and maps the 5 confident pairs. **17 of 22 stay NULL on purpose** — marketed but not operable, now queryable instead of implied | `validate-migrations.py` ok | **Migration written, not applied** | Mary applies migrations | **YES** | Apply `db/migrations/vertical-context-schema.sql` |
| **Vertical configuration completeness** | Sales Engine | `BLOCKED_OWNER` | Before: 1 of 8 verticals (`insurance_broker`) had `icp_template`/`dashboard_labels`/`routing_preferences`; the other 7 were NULL. Seed populates all 7 with **industry-specific** values — construction gets permits and estimators, dental gets operatories and PHIPA sensitivity, movers get seasonality. Nothing copied from insurance. Working assumptions are tagged `"_assumed": true` so they can be found and corrected | `validate-migrations.py` ok | **Migration written, not applied** | Mary applies migrations | **YES** | Apply `db/migrations/vertical-context-seed.sql` |
| **Missing vertical behaviour fields** | Sales Engine | `BLOCKED_OWNER` | ~13 concepts (signal_weights, intent_rules, qualification_rules, sales_process, followup_cadence, conversion_event, channel_strategy, objection_handling, terminology) had no home. Added as **two** JSONB columns — `behavior_config`, `sales_process_config` — not 13 columns and not new tables, because they are always read whole and never filtered on | `validate-migrations.py` ok | **Migration written, not applied** | Mary applies migrations | **YES** | Same migration |
| **`get_vertical_context()` capability** | Platform | `BLOCKED_OWNER` | One RPC reading the canonical config, deliberately not named after MAXI ([ADR-003](ARCHITECTURE_DOCTRINE.md)). Returns ICP, buyer roles, terminology, tone, pain points, signals + weights, qualification, sales process, offers, channels, follow-up, compliance, conversion event. Tenant layer returned under its own `tenant` key, never merged ([ADR-004](ARCHITECTURE_DOCTRINE.md)) | `validate-migrations.py` ok, 1 plpgsql body parsed | **Written, not applied** | Mary applies migrations | **YES** | Same migration, then wire callers |
| **Sales Engine consumes it without regression** | Sales Engine | `DEFERRED` | Cannot be tested until the migration is applied. No workflow has been changed to call it yet — deliberately, so the schema lands and is verified first | — | Unchanged | depends on migration | no | After apply |
| **Agentic runtime first loop** | Agentic | `DEFERRED` | 9 workflows, 16 tables, 7/7 endpoints live, **0 rows in every `agent_*` table including `agent_personalities`** — nothing can run even if triggered. The `process.env` fix removed the first blocker (env access), which was previously masking this | — | Never executed | needs a seeded personality | no | Seed one personality, drive one read-only decision |
| **MCP consolidation to one plane** | MCP | `PARTIAL` | Two gateways. `crystallux-mcp` now verifies its secret and fails closed — **verified live**: answers `401 "MCP_WEBHOOK_SECRET is unset"`. `mcp/agent-tools` verifies correctly and has a wired fallback. Neither takes a `client_id`, so no tool is tenant-scoped — the largest remaining safety gap | live probe | Gateway fix live | tenant context not built | no | Add tenant + risk class at the boundary |
| **Sentinel independence** | Sentinel | `DONE` (as a decision) | [ADR-006](ARCHITECTURE_DOCTRINE.md): standalone product *and* independent guardrail; reuses auth/billing/messaging, never merged into Admin, Copilot, MCP or the agent runtime | — | Vendor health live, workflow health blind | §1.2 | **YES** | — |
| **Smart Quote multi-industry** | Smart Quote | `DEFERRED` | [ADR-007](ARCHITECTURE_DOCTRINE.md) records the core/adapter boundary. **50 marketplace quotes, last 2026-07-24 — the warmest human-used surface on the platform outside Sentinel.** No code written yet | — | Live, insurance-shaped | — | no | P1 after revenue path |
| **UGC / Studio / Theatre** | Future | `DEFERRED` | Explicitly P3. Each must consume shared Media capabilities; no separate video, voice, avatar or publishing stack | — | Not started | — | no | Not before revenue readiness |

---

## 1c. Smart Quote — traced end to end 2026-08-30

**Correction first, because I got this wrong twice.** I told you Smart Quote had
"50 real quotes, the warmest human-used surface on the platform." Traced to the
table, those 50 rows are in `marketplace_quotes`: **2 distinct leads, 25 carrier
comparison rows each, across 7 days**, all from `insurance.crystallux.org` with
`vertical='auto'`. That is the **MGA marketing site's auto-insurance comparison
widget** — a different product. It is not Smart Quote and never was.

**Smart Quote's own funnel: 1 draft, `in_progress`, created 2026-05-22. Zero
completed quotes, ever.** The "warmest surface" argument I built on that figure
does not stand, and the prioritisation case for Smart Quote has to rest on
something else — which, as it happens, it can: the machinery is unusually
complete for something never used.

| Step | Status | Evidence |
|---|---|---|
| Public/customer entry | `WORKING` | `public/quote/fetch` live, answers `400 {"ok":false,"error":"Invalid quote_id format"}` — validates rather than swallowing |
| Questionnaire / templates | `WORKING` | `quote_templates` = **7 active industries**: insurance_personal, construction, dental, cleaning, restaurants, moving, beauty |
| Industry detection | `WORKING` | `industry_slug` on every template; admin flow switches on it |
| Estimator + pricing rules | `WORKING` | `quote_pricing_rules` = 30, `quote_addons` = 30, **evenly distributed 4–5 per industry**. This is a genuine multi-industry estimator, not insurance with six empty shells |
| Quote creation | `PARTIAL` | `admin/smart-quote/flow` live and gated (401 with body). `quote_drafts` = 1, stuck `in_progress` since 2026-05-22 |
| Quote storage | `PARTIAL` | Tables exist and are correctly shaped; `quote_completed` = **0** |
| Email / document | `DEAD` | No completed quote has ever existed to send |
| Accept / decline | `WORKING (untested)` | `public/quote/respond` live and validating, but has never had a real quote to act on |
| Follow-up | `DORMANT` | `clx-quote-followup-cron-v1` exists on a 6-hour schedule; `quote_follow_ups` = 0 |
| Booking | `NOT WIRED` | No link from `quote_completed` to the booking chain |

**The honest read.** Smart Quote is the most complete unused product on the
platform: seven configured industry estimators, 60 pricing artefacts, four live
endpoints that validate their input properly, and a funnel that has never had a
single quote pass through it. It is not insurance-only and does not need
re-architecting to become multi-industry — it already is. What it has never had
is one completed quote.

**One draft stuck `in_progress` since May is the cheapest possible test:** push
that one quote to `quote_completed` and the email/document, accept/decline and
follow-up steps all become testable in a single pass.

---

## 1d. Vertical context — COMPLETE, verified in production 2026-08-30

All five migration steps applied and independently verified. 11 of 11 checks pass.

| Check | Evidence |
|---|---|
| Schema | `niche_overlays` at **24 columns**; `behavior_config` + `sales_process_config` present |
| MAXI edge | `maxi_industries.niche_overlay_id` uuid, FK `ON DELETE SET NULL`, partial index; **5 of 22 mapped**, 17 deliberately NULL |
| Capability | `get_vertical_context()` — 1 definition |
| Positive | `construction` → `ok=true`, 8 process stages, 6 signal types. `insurance_broker` → `ok=true`, conversion `appointment_booked` |
| Negative | `restaurant` → `ok=false`, `vertical_not_configured` — marketed by MAXI, not operable, and the capability says so rather than inventing a default |
| Configuration | **8 of 8** verticals carry icp, labels, routing, behavior, process, terminology, signal_weights, followup_cadence, conversion_event |
| Assumptions | all 8 carry `_assumed` flags, findable by query |
| Regression | All 8 consumers use explicit `select=` lists, so additive columns are invisible. Verified live: signal-intelligence returns 5 active verticals, Apollo returns 6 title keywords |

**What this changes commercially:** the Sales Engine can now be pointed at
construction, dental, real_estate or consulting with industry-correct ICP,
titles, signals, tone, terminology and cadence — where before only
`insurance_broker` was configured. It does **not** mean those campaigns have
been run; nothing has been sent.

### Correction to my own diagnosis, recorded because it cost a cycle

Step 5 first failed with `Character with value 0x0d must be escaped`. I
attributed it to CRLF inside multi-line JSON literals. **Tested against the live
database, that was wrong:** CR *between* JSON tokens is accepted; only CR
*inside a string* is rejected, and the actual failing literal — carriage returns
intact — was accepted. Zero literals across all 118 migrations have CR inside a
string. The JSON was valid; the cause lay between file and SQL editor, not in
the SQL. The single-line collapse was kept anyway (data verified byte-identical)
because it removes the transport risk regardless, and the requested guard was
made precise rather than coarse — a first cut flagged 20 migrations that had
already applied cleanly.

---

## 2. Product register

Status per the vocabulary above. Row counts and endpoint registration are the
2026-08-28 production measurement.

| Capability | Product | Status | Evidence | Test | Production State | Blocker | Needs Owner? | Next Action |
|---|---|---|---|---|---|---|---|---|
| Platform monitoring, vendor health, cost, security, auto-remediation | **Sentinel** | `PARTIAL` | 33 workflows, 27/27 endpoints live, 19 tables, 46,479 vendor rows | schedule-driven self-checks | **The only continuously executing subsystem** | workflow-health blind (§1.1) | **YES** | #1 |
| Login, sessions, magic links, resets, provisioning | **Auth / Identity** | `READY` | 9/9 live, 165 sessions | login flows | Live | — | no | — |
| Operating surface for every product | **Admin console** | `READY` | 22 workflows, 21/21 live, 26 pages | Playwright page audit | In daily use | Workflows page reports fiction (§1.1) | no | — |
| Checkout, provisioning, webhooks, renewals | **Billing / Stripe** | `PARTIAL` | 3/3 live, **live keys**, paid provisioning wired | none | Live keys, no exercised purchase recorded here | — | **YES** | One real end-to-end purchase — [#4](OWNER_ACTIONS_REQUIRED.md) |
| Signup, checkout, public pages | **Public / Marketing** | `READY` | 6/6 live; all 5 public hosts return 200 | live HTTP check | Live | — | no | — |
| Live auctions, Buy Now, inventory, orders, fulfilment | **LUXI / Commerce** | `PARTIAL` | 21 workflows, 17/18 live, 28 tables, 8 auctions, 2 products — **0 orders, 0 reservations, 0 commerce events, ever** | none | Deployed, never transacted | needs one real sale | **YES** | [#4](OWNER_ACTIONS_REQUIRED.md) — largest untested surface on a live-key stack |
| Full insurance operating system | **Insurance / MGA** | `PARTIAL` | 90 workflows (26% of the estate), 85/85 endpoints live, 38 tables. `carrier_quotes` 0, `policy_applications` 0 | none | Endpoints live, no business data | — | no | Decide whether this is a product or a vertical |
| Multi-industry estimator | **Smart Quote** | `PARTIAL` | 7 active industry templates, 30 pricing rules, 30 addons, 4 live endpoints. **`quote_completed` = 0** — no quote has ever been finished. The 50 `marketplace_quotes` belong to the MGA comparison widget, not here (§1c) | endpoint probe only | Live, never completed a quote | — | no | Finish the one stuck draft — it makes 4 dead steps testable at once |
| Tenant-facing dashboard | **Client portal** | `PARTIAL` | 9/9 live, 12 pages; `campaigns`, `bookings`, `deals` all 0 rows | Playwright page audit | Live, unpopulated | upstream Sales Engine | no | Follows the Sales Engine |
| Discovery → research → scoring → outreach → booking | **Sales Engine** | `BROKEN` | 14 workflows, 13 schedule-driven. **No lead since 2026-05-28, no send since 2026-06-08.** 2,518 leads, 881 with email, **831 score ≥ 50** — scoring works, contrary to stale docs. Funnel to date: 16 Contacted → 1 Replied → 1 Booking Sent → 1 Closed Lost | none | **Dark for 83 days** | schedules unknown until §1.1 | **YES** | #1, then decide restart or retire |
| Goals, teams, training, briefings, reports | **Productivity / Ops** | `PARTIAL` | 29 workflows, 21/29 endpoints live; `client_goals`, `team_members`, `training_sessions` all 0 | none | 8 endpoints unregistered | — | no | — |
| Content pieces, publishing to 6 platforms, engagement | **Creative / Content** | `STUB` | 19 workflows, **10 are stubs**; `content_pieces` 0, `content_publications` 0. All six social publishers do nothing | none | **The distribution loop is a shell** | platform API approvals | **YES** | Meta/LinkedIn/TikTok review — [#7](OWNER_ACTIONS_REQUIRED.md) |
| AVA, LUXI, MAXI, LUMI, LUMA, LETY, EAZA persona layer | **Avatars** | `PARTIAL` | 6/6 live, 7 personas registered; **only LUXI is active and only LUXI has HeyGen + voice IDs** | none | One of seven usable | media IDs for six | **YES** | Provision or formally defer six |
| Script → render → deliver → engagement | **Video** | `DORMANT` | 9 workflows, 7/8 live; `video_renders` 0, `video_generation_log` 0 | none | Never rendered | — | no | — |
| Vapi inbound/outbound, transcript classification | **Voice** | `DORMANT` | 6 workflows, **2 of 6 endpoints live**; `voice_call_log` 0 | none | 4 endpoints unregistered | — | no | — |
| Booking, no-show, geocoding, routing, reshuffle | **Booking / Field ops** | `DORMANT` | 8 workflows, 3/6 live; `bookings` 0 | none | Half unregistered | — | no | — |
| WhatsApp, LinkedIn, SMS/Twilio | **Messaging channels** | `BLOCKED_EXTERNAL` | 4/4 endpoints live, 5 tables | none | Live, unused | **WhatsApp gated on Meta review** | **YES** | [#7](OWNER_ACTIONS_REQUIRED.md) |
| Market signals, archetypes, behavioural triggers | **Intelligence** | `DORMANT` | 14 workflows, 6/7 live; `market_signals` 0, `signal_archetypes` 0 | none | Never run | — | no | — |
| Admin + client natural-language assistant | **Copilot** | `DORMANT` | 6/6 live; `admin_chat_sessions` 0, `admin_chat_messages` 0 | none | Never used | — | no | Gate `copilot/query` behind something better than a static token (§1.13) |
| Machine-callable tool surface | **MCP / Tool gateway** | `PARTIAL` | **Two divergent gateways.** `crystallux-mcp` checked the API key for *presence only* and never compared it — fixed in repo at `0a17874`, **not yet live**. `mcp/agent-tools` verifies its secret correctly and its Switch **does** have `fallbackOutput` wired to `Respond 4xx` — re-verified today, correcting PRODUCT_REGISTRY §3.4. `update_lead_status` exists in both with different auth. 5 tool calls, ever | none | Fix not deployed | needs re-import | **YES** | [#3](OWNER_ACTIONS_REQUIRED.md); then consolidate to one gateway |
| Decision engine, action executor, memory, escalation | **Agentic runtime** | `DORMANT` | 9 workflows, 7/7 live, 16 tables — **every `agent_*` table has 0 rows**, `agent_personalities` included, so nothing can run even if triggered | none | Never executed once | — | no | Seed one personality, drive one decision end to end. Costs nothing, settles more than any new design |
| Provider-agnostic fulfilment | **Eazer / Delivery** | `PARTIAL` | Layer built, 5 tables, `deliveries` 0; adapter not built | none | Awaiting a real order | no orders exist | no | Follows the first sale |

---

## 3. What this session changed

Every item below was verified before and after. Nothing was deployed — all of it
is repo state awaiting [owner action #3](OWNER_ACTIONS_REQUIRED.md).

| Change | Why it mattered | Verification |
|---|---|---|
| **CI deploy no longer creates duplicates** | `POST /api/v1/workflows` creates. Every push to main minted a fresh copy of all 50 top-level workflows with new ids, while the old copies kept running. This is the mechanism behind the seven identical DevOps briefings running daily (blockers §0n) — one file in the repo, six surplus copies in n8n, each calling Claude. The moment a valid API key is restored, the old CI would have resumed manufacturing them | 324/326 files carry a unique top-level id; 0 collisions; update-by-id is well defined |
| **CI no longer reports success when it deployed nothing** | Failures were swallowed with `\|\| true`, non-200s printed a warning and continued, and the summary said "✅ Deployed successfully" unconditionally. A 401-ing key looked exactly like a healthy deploy — which is why nobody noticed | Deploy now probes the key first and exits non-zero on any failed update |
| **CI validates 326 workflows instead of 50** | `workflows/*.json` skipped every dashboard webhook under `workflows/api/` — 276 files, including all 85 MGA endpoints | 326 checked, 0 problems, 0 warnings |
| **CI runs both validators** | Neither `validate-workflows.py` nor `validate-migrations.py` ran in CI, despite being written for exactly this | Both wired; 113 SQL files parse clean |
| **A migration that could never have run** | Wiring the migration validator to CI immediately found `docs/architecture/migrations/add_scoring_columns.sql` using `ADD CONSTRAINT IF NOT EXISTS` — **syntax Postgres does not have**. Pasted into the Supabase editor it adds the five columns, then dies on the constraint. So `leads_lead_score_range` does not exist in production and nobody knew. Rewritten to the `pg_constraint` guard used everywhere else in `db/migrations` | 113 files, 1 failed → 0 failed |
| **47 auth fetches now fail closed** | An empty `validate_session` result yields zero items in n8n; the auth check never runs and the caller gets a bodyless 200 that reads as a broken endpoint rather than a rejected request | 0 of 126 now unguarded. All 47 downstream Code nodes verified to reject a missing row before the change |
| **7 Switch nodes now route their misses** | An unmatched action answered with an empty 200 | Validator warnings 7 → 0 |
| **4 responders stopped calling a bad action "Unauthorized"** | `$json.status \|\| 401` reported 401 for an unknown action on a perfectly good session. Now `$json.status \|\| ($json._unauthorized ? 401 : 400)` — the auth path still sets `status` explicitly, so 401/403 are preserved exactly | Traced `Check Admin` on every affected path |
| **Validator gained a dead-end check** | The empty-200 trap has been found four separate times (CLAUDE.md). It is now a build failure, not a discovery | 255 responseNode workflows, 0 real dead-ends; the single hit is `disabled` and annotated `DELIBERATELY DISCONNECTED` |
| **Queue mode is coherent** | Main ran `regular` while the worker ran `queue`; the worker could never receive a job | `docker-compose.yml`; applying it restarts n8n, so it is owner action #5 |
| **One implementation of the n8n PUT body** | The settings whitelist from `68fad4a` existed only inside `ship.sh`. CI needed the same rule; copying it would have guaranteed drift | `scripts/n8n/n8n-put-body.py`; across the estate it strips `binaryMode` and `availableInMCP`, either of which earns HTTP 400 |

### Corrections to earlier audits

- **The empty-200 exposure was 126, not 122 and not 47 — and my own first
  correction was wrong.** The original audit counted every `validate_session`
  call lacking `alwaysOutputData` and said 122. I narrowed that to 47 on the
  reasoning that `neverError: true` provided equivalent protection for the other
  79. **A live probe after deploying disproved it.** `neverError` controls
  whether a non-2xx *throws*; it says nothing about a 200 carrying an empty
  array, which n8n splits into zero items — the actual failure. Evidence:
  post-deploy, `client/overview` (guarded) answered `401` with a body while
  `admin/avatar-schedule` (`neverError`, unguarded) answered **HTTP 200, 0
  bytes**. The correct figure is **126 of 126**, all now guarded.

  The lesson is the one this register is built on: the first fix passed every
  static check and was still wrong. Only the probe against production settled
  it.
- **`mcp/agent-tools` is not missing a Switch fallback.** PRODUCT_REGISTRY §3.4
  records "one Switch (no fallback → empty 200)". Re-read today: it declares
  `fallbackOutput: "extra"` and wires output 10 to `Respond 4xx`.
- **8 unguarded Switch nodes was 7.** The validator finds 7; all are fixed.

---

## 4. Sequence

Ordered by what unblocks the most, not by size.

1. **Mint the n8n API key** ([#1](OWNER_ACTIONS_REQUIRED.md)). One action restores
   Sentinel's workflow monitoring, the daily briefing, and CI deployment. Nothing
   about production can be trusted until the platform can see itself.
2. **Establish which scheduled workflows are actually active.** Impossible until
   (1). Then restart the Sales Engine or consciously retire it — but decide,
   rather than leaving it dark by accident for a fourth month.
3. **Delete the six duplicate briefings** ([#2](OWNER_ACTIONS_REQUIRED.md)), and
   note that the CI fix means they stop coming back.
4. **Ship the fail-closed fixes** ([#3](OWNER_ACTIONS_REQUIRED.md)) — 54 workflows,
   additive, no behaviour change on any successful path.
5. **Sell one thing** ([#4](OWNER_ACTIONS_REQUIRED.md)). Zero orders through a
   live-key commerce stack is the largest untested surface on the platform, and
   no amount of static analysis substitutes for one real transaction.
6. **Then** the consolidation work: capture the 18 undocumented tables starting
   with `leads`, add a migration ledger, retire the duplicate discovery and Apollo
   implementations, and merge the two MCP gateways — taking the secret comparison
   from one and the tool registry from the other, and adding the tenant context
   neither has.

Not before (5): the discovery layer, the agentic runtime, and the 100,000
records/day proposal. The system has 2,518 leads and has sent 13 emails.
**Discovery volume is not the constraint. Nothing is running.**
