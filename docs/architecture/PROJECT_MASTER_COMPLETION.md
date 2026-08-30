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
| **1.1 Workflow status is reliable** | Platform | `BLOCKED_OWNER` | `GET /api/v1/workflows` → **401**. `sentinel_workflow_health` has 0 rows, ever. `admin/workflow-status` returns `{"active_count":1,"workflows":[{"name":"unknown"}]}` — it derives from `scan_log` (0 rows), not from n8n | none possible while the key is dead | Nothing can report what is running | n8n API key expired | **YES** | Mint a new key — [owner action #1](OWNER_ACTIONS_REQUIRED.md) |
| **1.2 Production state is observable** | Sentinel | `PARTIAL` | Vendor health 46,479 rows, 480/day, writing continuously; alerts + cost tracking daily. But workflow health 0 rows (§1.1) | Sentinel self-checks run on schedule | Endpoint + vendor monitoring live; **workflow monitoring blind** | §1.1 | **YES** | Unblocks with #1 |
| **1.3 CI validates the whole estate** | Platform | `DONE` | Was 50 of 326 files, `workflows/*.json` only, and ran neither validator. Now walks all 326 recursively and runs both. Verified locally: **326 workflows, 0 problems, 0 warnings**; **113 SQL files, 0 failed** | `.github/workflows/crystallux-ci.yml`, jobs `validate` | Runs on every push and PR | — | no | — |
| **1.4 Deployment is reproducible** | Platform | `PARTIAL` | CI used to `POST /api/v1/workflows` for every file on every push — **POST creates**, so each push minted duplicates with fresh ids. Now updates by top-level id, deploys only files changed in the push, refuses to create, and never activates. 324/326 files carry a unique id (0 collisions), so update-by-id is well defined | `deploy` job; `scripts/n8n/n8n-put-body.py` | Cannot run until the key is replaced — and now **fails loudly** instead of reporting success | §1.1 | **YES** | Unblocks with #1 |
| **1.5 Security endpoints fail closed** | Platform | `DONE` | 47 of 126 `validate_session` fetches had neither `alwaysOutputData` nor `neverError` — an empty RPC result yields zero items, the auth check never runs, caller gets a bodyless 200. All 47 now guarded; **0 unguarded remain**. All 47 downstream Code nodes were confirmed to reject a missing row first, so the change is strictly fail-closed. 7 Switch nodes had no `fallbackOutput`; all 7 now route to their error responder | `validate-workflows.py`, now failing on dead-end branches too | **Repo only — not yet live** | needs re-import | **YES** | Ship the 54 workflows — [owner action #3](OWNER_ACTIONS_REQUIRED.md) |
| **1.6 Auth works correctly** | Auth / Identity | `READY` | 9 workflows, 9 endpoints live, 165 sessions, most recent 2026-08-20. `validate_session` is the single gate and is now uniformly fail-closed (§1.5) | exercised by every admin/client login | Live | — | no | — |
| **1.7 Tenant isolation** | Platform | `PARTIAL` | RLS enabled on **208 of 208** public tables. `client/*` endpoints are tenant-scoped. **But neither MCP gateway takes a `client_id`** — every machine-callable tool is implicitly platform-wide | none | Live for humans, absent for agents | — | no | Add tenant context at the gateway before any agent runs (§4.3) |
| **1.8 Core migrations in source** | Platform | `PARTIAL` | 113 SQL files, all parse against the real Postgres grammar. **18 live tables have no `CREATE` anywhere in the repo — `leads` among them.** Production cannot be rebuilt from source | `validate-migrations.py`, now in CI | 194 of 198 declared tables live | — | no | Capture the 18, starting with `leads` |
| **1.9 Migration ledger** | Platform | `BROKEN` | Nothing records which of the 113 files have been applied. The three `schema_migrations`/`migrations` tables belong to Supabase's own `auth`/`realtime`/`storage` schemas | none | Applied state is unknowable without diffing live schema | — | no | Add an applied-migrations table + record backfill |
| **1.10 Logs and errors are visible** | Platform | `BROKEN` | `admin_action_log` has 98 rows, every one `action_type='vertical_generated'` from an automated job, `action` NULL in all 98. Two overlapping schemas in one table (`admin_user`/`actor_email`, `created_at`/`occurred_at`). **No human admin action is audited**, though `audit-log.html` renders the table | none | Page exists over an empty concept | — | no | Reconcile the two schemas, then write on privileged actions |
| **1.11 Queue tier actually queues** | Platform | `PARTIAL` | `docker-compose.yml` ran main at `EXECUTIONS_MODE=regular` while `n8n-worker` ran `queue`. n8n only enqueues to Redis when the **main** instance is in queue mode, so the worker never received a job — a scaling tier declared, paid for in RAM, never reached. Main is now `queue` in the repo | none | **Repo only, and must stay that way for now** | **The VPS is not running this file** — see 1.11a | **YES** | Get the live env first, then rewrite the compose file to match |
| **1.11a The repo's compose file is not production** | Platform | `BROKEN` | The earlier audit marked this UNVERIFIED. Now settled: `blockers.md` §0ag records `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` as already set live with LUXI and the copilot depending on it, and that variable appears **nowhere** in `docker-compose.yml`. Nor does `MCP_WEBHOOK_SECRET`. The live container is configured from an edited copy, an `env_file`, or an override that is not in source | none | Infrastructure is not reproducible from the repo, and `docker compose up -d` from it would hand n8n a smaller environment than it has | — | **YES** | `docker inspect n8n --format '{{json .Config.Env}}'`, names only — [owner action #5](OWNER_ACTIONS_REQUIRED.md) |
| **1.12 Automated test coverage** | Platform | `PARTIAL` | Two static validators (now CI-gated) plus three Playwright audit harnesses under `tests/audit/`. **No unit tests, no endpoint contract tests, no integration tests.** Static analysis is the whole safety net | — | — | — | no | Endpoint contract test once #1 lands and live state is knowable |
| **1.13 Secrets hygiene** | Platform | `PARTIAL` | No secrets reach any frontend — checked. But `MARY_MASTER_TOKEN` is a static, long-lived shared secret in `localStorage`, no rotation, no expiry, no per-actor identity — and it is the only thing gating `copilot/query`, which asks Claude to write SQL | none | Live | — | **YES** | Scope and rotate; decide an expiry model |

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
| Multi-vertical quoting and comparison | **Smart Quote** | `PARTIAL` | 6/6 live, **50 marketplace quotes**, last 2026-07-24 | none | **The most recent real human usage outside Sentinel** | — | no | The warmest surface here — worth pointing demand at |
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

- **Not 122 workflows exposed to the empty-200 trap — 47.** The earlier count
  matched every `validate_session` call without `alwaysOutputData`, but 79 of
  those carry `neverError: true`, which also keeps the node emitting. The real
  exposure was 47, and is now 0.
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
