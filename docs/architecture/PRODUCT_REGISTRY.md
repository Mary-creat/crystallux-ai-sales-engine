# Crystallux product & command registry

**Verified 2026-08-28** against the repo at `ce5caa6`, the live Supabase schema and row
counts, and a read-only probe of all 285 webhook paths in production. Companion to
[`docs/audit/2026-08-28-master-architecture-audit.md`](../audit/2026-08-28-master-architecture-audit.md),
which covers infrastructure. This document covers **products, commands, MCP and agents**.

Rules observed: nothing was built, migrated, renamed, deleted or cleaned up. Production
state overrides repo flags; implementation overrides documentation.

---

## 1. Crystallux is not a Sales Engine with extras

All 326 workflows classify into **22 domains**. The Sales Engine is 14 of them — 4% of the
workflow estate. The largest domain by a wide margin is Insurance/MGA, and the only domain
executing continuously is Sentinel.

| Domain | Workflows | Endpoints | Live | Scheduled | Stubs |
|---|---:|---:|---:|---:|---:|
| Insurance / MGA | 90 | 85 | 85 | 8 | 3 |
| Sentinel | 33 | 27 | 27 | 22 | 0 |
| Productivity / Ops | 29 | 29 | 21 | 12 | 2 |
| Admin console | 22 | 21 | 21 | 1 | 0 |
| LUXI / Commerce | 21 | 18 | 17 | 3 | 0 |
| Creative / Content | 19 | 19 | 19 | 5 | 10 |
| Sales Engine | 14 | 2 | 2 | 13 | 2 |
| Intelligence | 14 | 7 | 6 | 7 | 2 |
| Video | 9 | 8 | 7 | 2 | 3 |
| Agentic (agent + supervisor) | 9 | 7 | 7 | 2 | 1 |
| Auth / Identity | 9 | 9 | 9 | 0 | 0 |
| Client portal | 9 | 9 | 9 | 0 | 1 |
| Booking / Field ops | 8 | 6 | 3 | 4 | 3 |
| Copilot | 6 | 6 | 6 | 0 | 4 |
| Voice | 6 | 6 | 2 | 1 | 2 |
| Avatars | 6 | 6 | 6 | 0 | 0 |
| Public / Marketing | 6 | 6 | 6 | 0 | 0 |
| Messaging channels | 4 | 4 | 4 | 2 | 2 |
| MCP / Tool gateway | 3 | 4 | 4 | 0 | 0 |
| Billing / Stripe | 3 | 3 | 3 | 0 | 2 |
| Core platform | 3 | 2 | 0 | 1 | 1 |
| Unclassified | 3 | 1 | 1 | 2 | 0 |
| **Total** | **326** | **285** | **265** | **85** | **38** |

Live tables split the same way: Insurance/MGA 38, Sales Engine 36, LUXI/Commerce 28,
Productivity 25, Content 23, Sentinel 19, Agentic 16, Auth 8, Voice 5, shared 16.

---

## 2. Product registry

Status vocabulary: **LIVE** (deployed and carrying real data) · **PARTIAL** (deployed,
little or no adoption) · **DORMANT** (deployed, never used) · **STUB** (code present,
does nothing) · **BROKEN** (was working, stopped).

| Product | Purpose | WF | Endpoints (live) | Tables | Frontend | Status | Evidence |
|---|---|---:|---:|---:|---|---|---|
| **Sentinel** | Platform monitoring, vendor health, cost, security, auto-remediation | 33 | 27 (27) | 19 | `admin/sentinel.html` | **LIVE** | 46,479 vendor rows, 480/day, last write minutes ago |
| **Auth / Identity** | Login, sessions, magic links, resets, provisioning | 9 | 9 (9) | 8 | login pages | **LIVE** | 165 sessions, most recent 2026-08-20 |
| **Admin console** | Operating surface for every product | 22 | 21 (21) | shared | `admin-dashboard` (26 pages) | **LIVE** | in daily use |
| **Billing / Stripe** | Checkout, provisioning, webhooks, renewals | 3 | 3 (3) | shared | `billing.html` | **LIVE** | live keys; paid provisioning wired |
| **LUXI / Commerce** | Live auctions, Buy Now, inventory, orders, fulfilment | 21 | 18 (17) | 28 | `commerce.html`, `luxi/`, public bid page | **PARTIAL** | 8 auctions, 2 products, **0 orders ever** |
| **Insurance / MGA** | Full insurance operating system — see §3 | 90 | 85 (85) | 38 | `insurance-mga-dashboard`, `insurer-dashboard`, `carriers/` | **PARTIAL** | 85 endpoints live; `carrier_quotes` 0, `policy_applications` 0 |
| **Smart Quote** | Multi-vertical quoting and comparison | (in MGA) | 6 (6) | 6 | `admin/smart-quote/` | **PARTIAL** | **50 marketplace quotes**, last 2026-07-24 — the most recent real human usage outside Sentinel |
| **Client portal** | Tenant-facing dashboard | 9 | 9 (9) | shared | `client-dashboard` (12 pages) | **PARTIAL** | endpoints live; campaigns/bookings/deals all 0 rows |
| **Sales Engine** | Discovery → research → scoring → outreach → booking | 14 | 2 (2) | 36 | `sales-engine.html`, `leads.html` | **BROKEN** | 13 schedule-driven workflows; no lead since 2026-05-28, no send since 2026-06-08 |
| **Productivity / Ops** | Goals, teams, training, briefings, reports, completeness | 29 | 29 (21) | 25 | client training pages | **PARTIAL** | 8 endpoints unregistered; `client_goals`, `team_members`, `training_sessions` all 0 |
| **Creative / Content** | Content pieces, publishing to 6 platforms, engagement, attribution | 19 | 19 (19) | 23 | `content-library.html`, client content pages | **STUB** | **10 of 19 are stubs**; `content_pieces` 0, `content_publications` 0 |
| **Avatars** | AVA, LUXI, MAXI, LUMI, LUMA, LETY, EAZA persona layer | 6 | 6 (6) | (in content) | `avatars/*` (8 pages) | **PARTIAL** | 7 registered, **only LUXI active**; only LUXI has HeyGen + voice IDs |
| **Video** | Script → render → deliver → engagement | 9 | 8 (7) | (in content) | — | **DORMANT** | `video_renders` 0, `video_generation_log` 0 |
| **Voice** | Vapi inbound/outbound, transcript classification, post-call analysis | 6 | 6 (2) | 5 | `ciro/communications.html` | **DORMANT** | 4 of 6 endpoints unregistered; `voice_call_log` 0 |
| **Booking / Field ops** | Booking, no-show, geocoding, routing, reshuffle | 8 | 6 (3) | shared | `bookings.html` | **DORMANT** | `bookings` 0; half the endpoints unregistered |
| **Messaging channels** | WhatsApp, LinkedIn, SMS/Twilio | 4 | 4 (4) | 5 | — | **PARTIAL** | endpoints live; WhatsApp gated on Meta review |
| **Intelligence** | Market signals, archetypes, behavioural triggers, upsell | 14 | 7 (6) | (in sales) | `market-intelligence.html` | **DORMANT** | `market_signals` 0, `signal_archetypes` 0 |
| **Copilot** | Admin + client natural-language assistant over the platform | 6 | 6 (6) | 2 | copilot widget in both dashboards | **DORMANT** | `admin_chat_sessions` 0, `admin_chat_messages` 0 |
| **MCP / Tool gateway** | Machine-callable tool surface | 3 | 4 (4) | 1 | — | **LIVE (insecure)** | `mcp_tool_calls` = 5 calls, ever. See §4 |
| **Agentic layer** | Decision engine, action executor, memory, escalation, conversation | 9 | 7 (7) | 16 | — | **DORMANT** | every `agent_*` table has **0 rows**, `agent_personalities` included |
| **Public / Marketing** | Signup, checkout, public pages | 6 | 6 (6) | shared | `site`, 4 marketing sites | **LIVE** | 5 hosts serving 200 |
| **Eazer / Delivery** | Provider-agnostic fulfilment | (in commerce) | — | 5 | `delivery_board` | **PARTIAL** | layer built, adapter not; `deliveries` 0 |

**The pattern.** Ten products are deployed and carrying no data at all. This is not a
half-built platform — it is a **fully built platform that was never switched on**, with a
monitoring system that cannot see that fact (see the infrastructure audit, §4).

---

## 3. The command layer, from the top down

There are **four command surfaces**, not one. Every one of the 285 webhook paths belongs
to exactly one of them.

### 3.1 Admin command surface — `admin/*` (33 paths, 32 live)

Session-gated on an admin `auth_sessions` token. Command families:

`luxi` (7) · `commerce` (3) · `smart-quote` (2) · `market-intelligence` (2) · `chat` (2) ·
and one each for `workflow-status`, `workflow-drift`, `system-health`, `sentinel`,
`sales-engine`, `provision-client`, `onboarding-pipeline`, `list-leads`, `list-clients`,
`comms-log`, `client-detail`, `ciro`, `bulk-import-leads`, `billing-summary`,
`avatar-schedule`, `avatar-content`, `audit-log`.

Risk profile: mostly read. The write/high-risk members are `provision-client`,
`bulk-import-leads`, `commerce/*`, `luxi/*` (creates lots, places bids, takes money) and
`avatar-schedule`.

### 3.2 Client command surface — `client/*` (11 paths, 11 live)

Session-gated and **tenant-scoped**: `overview`, `leads`, `campaigns`, `bookings`,
`activity`, `billing`, `settings`, `replies`, `performance`, `copilot/ask`,
`copilot/transcribe`. Read-only except `settings` and `copilot/ask`.

### 3.3 Insurance/MGA command surface — `mga/insurance/*` (80 paths, 80 live)

The largest command family in the platform, and a complete insurance back office:

- **Quoting** — `quote-engine`, `quote-comparison`, `quote-manual`, `quote-api`,
  `product-compare`, `calculator` (7 endpoints), `needs-analysis`
- **Advice & compliance** — `policy-recommend`, `policy-recommend-v2`,
  `suitability-start`, `suitability-reply`, `review-conduct`, `review-documentation`,
  `review-triggered-event`
- **Identity & contracting** — `kyc-start`, `stripe-identity-callback`, `license-verify`,
  `esign-send`, `zoho-sign-callback`
- **Advisor lifecycle** — `advisor` (5), `principal` (3), `onboarding-advance`,
  `onboarding-complete`, `onboarding-status`, `onboarding-curriculum-seed`
- **Insurer white-label** — `insurer-account-create`, `insurer-user-invite`,
  `insurer-session-validate`, `insurer-access-audit`, `whitelabel-create`,
  `whitelabel-deploy`, `whitelabel-update`
- **Reporting & content** — `report` (6), `report-template-seed`, `review-video-generate`,
  `review-video-deliver`, `review-video-engagement`, `seed-video-templates`
- **Intake** — `lead-capture`, `training-topics-seed`

This is a product in its own right with its own tenancy model (`insurer_accounts`,
`insurer_users`, `insurer_whitelabel_configs`). It should never have been modelled as a
Sales Engine vertical.

### 3.4 Machine command surface — MCP (4 paths, 4 live)

Two **separate and divergent** tool gateways, built at different times, with different
conventions and different security:

| | `crystallux-mcp` + `crystallux-tools` | `mcp/agent-tools` |
|---|---|---|
| Workflow | `clx-mcp-tool-gateway` (35 nodes) | `clx-mcp-agent-tools-v1` |
| Dispatch | linear chain of 10 `IF` nodes | one `Switch` (no fallback → empty 200) |
| Tools | `research_lead`, `score_lead`, `get_pipeline_stats`, `scan_city`, `get_lead`, `list_leads`, `update_lead_status`, `check_system_health`, `check_pipeline_health`, `get_execution_stats` | `place_outbound_call`, `send_whatsapp`, `send_sms`, `send_email`, `generate_video`, `book_meeting`, `update_lead_status`, `log_decision`, `retrieve_lead_memory`, `escalate_to_human` |
| Auth | **presence check only — see §4** | `internal_secret` compared to `INTERNAL_EMAIL_SECRET` ✔ |
| Tenant context | **none** | none |
| Discovery endpoint | `GET /crystallux-tools` returns a real tool list | none |
| Usage | 5 calls, ever | 0 |

`update_lead_status` exists in **both**, with different auth on each path.

### 3.5 Copilot (6 paths, 6 live)

`copilot/query` (Claude writes SQL → validator → read-only execute), `copilot/platform`
(Q&A over gathered context), `copilot/troubleshoot`, `copilot/whisper` (voice transcribe),
plus `client/copilot/ask` and `client/copilot/transcribe`. Admin copilot is gated on
`MARY_MASTER_TOKEN`; the client copilot uses a session token. Never used in production —
zero chat rows.

---

## 4. Security finding — the MCP Tool Gateway does not verify its key

`clx-mcp-tool-gateway.json`, node **Parse Request**, in full:

```js
const apiKey = headers['x-mcp-api-key'] || headers['X-MCP-API-Key'] || '';
if (!apiKey) { return { json: { valid: false, error: 'Missing X-MCP-API-Key header' … } }; }
```

The key is checked for **presence** and never compared to anything. There is no reference
to `MCP_WEBHOOK_SECRET`, `MARY_MASTER_TOKEN` or any other secret anywhere in the workflow —
verified by grep across the whole file. Any caller supplying a non-empty header value can
execute all ten tools, including `update_lead_status` (writes to `leads`) and `scan_city`
(spends Google Places quota). The endpoint is registered and live in production, and
`GET /webhook/crystallux-tools` returns the tool catalogue to anyone, unauthenticated —
confirmed live, HTTP 200.

Mitigating facts, all verified: the path is unguessable rather than linked; usage is 5
calls in the table's lifetime; the sibling gateway `mcp/agent-tools` **does** verify its
secret correctly, so this is one workflow's omission and not a platform-wide pattern; and
`docs/architecture/mcp-tool-registry.md` never specified an auth model, so this reads as
unfinished rather than regressed.

Not exploited — established from source, then confirmed only that the endpoint is
registered.

**Fixed in the repo 2026-08-28** (after this audit was filed and on Mary's
instruction): `Parse Request` now compares the header against
`MCP_WEBHOOK_SECRET` — the variable `.env.example` had declared all along — and
fails closed when it is unset. The catalogue endpoint is gated on the same key.
Rejections answer `401` using the `_unauthorized ? 401 : 400` expression already
used by 18 other workflows. **Not yet live** — see `docs/audit/blockers.md` §0ag.

Two smaller items found in the same pass:

- **The admin audit log records nothing.** `admin_action_log` has 98 rows, every one
  `action_type = 'vertical_generated'` from an automated job; the `action` column is NULL
  in all 98. The table also carries two overlapping schemas (`admin_user`/`actor_email`,
  `created_at`/`occurred_at`). There is an `audit-log.html` page over it. **No human admin
  action is currently audited.**
- **`MARY_MASTER_TOKEN` is a static, long-lived, shared secret** held in `localStorage`,
  with no rotation, expiry, or per-actor identity. It is the only thing standing between a
  browser and `copilot/query`, which asks Claude to write SQL.

---

## 5. How MCP and agents should be layered — without rebuilding anything

**The command layer already exists.** It is 285 authenticated webhooks with tenant
scoping, session validation and per-domain ownership. The mistake to avoid is building an
MCP server *beside* it that reaches into Supabase directly — that produces a second
permission model, and the two will diverge exactly as the two existing gateways already
have.

**Recommended shape — one gateway, three planes:**

1. **Keep the existing webhooks as the capability plane.** They are the tools. No MCP tool
   should ever touch Supabase directly; every one calls an existing `admin/*`,
   `client/*` or `mga/*` endpoint, inheriting its auth, tenancy and validation for free.

2. **Consolidate to one gateway** by adopting, on both, what each already does best: the
   secret comparison from `mcp/agent-tools`, and the tool-registry endpoint from
   `crystallux-tools`. Retire the linear IF-chain in favour of the Switch — **with a
   `fallbackOutput`**, which the current Switch lacks. Do not delete either workflow until
   the merged one is proven; deprecate by routing, not deletion.

3. **Add the two things both gateways are missing**, which is what actually blocks agents
   from being safe:
   - **Tenant context.** Neither gateway takes a `client_id`. Every tool today is
     implicitly platform-wide. An agent acting for one tenant cannot currently be confined
     to it — that is the single largest safety gap in the agentic design.
   - **A risk classification per tool**, declared in the registry: read / write /
     spends-money / contacts-a-human. `place_outbound_call`, `send_whatsapp`, `send_sms`,
     `send_email` reach real people; `scan_city` and `generate_video` spend money;
     `update_lead_status` writes. Human-in-the-loop belongs at that boundary, not inside
     each workflow.

4. **The agent runtime is already built — 9 workflows, 16 tables, 10 action tools —
   and has never executed once.** `agent_personalities` is empty, so nothing can run even
   if triggered. Before writing any new agent code, seed one personality and drive one
   decision end to end through `agent-decision-engine → agent-action-executor →
   mcp/agent-tools`, then read `agent_decisions` and `agent_actions` to confirm the loop
   closes. That test costs nothing and will tell you more than any new design.

5. **`avatars` is the agent identity table you already have** — 7 personas, ICP-style
   config, HeyGen and ElevenLabs bindings, compliance rules, outbound channel. Only LUXI
   is active and only LUXI has media IDs. Agent identity should hang off `avatars`, not a
   new registry; `agent_personalities` (empty) and `personas` (2 rows) are a third and
   fourth overlapping concept that should be reconciled before anything is layered on top.

**Sequencing.** None of this should start before the n8n API key is replaced and the
Sales Engine's scheduled workflows are accounted for (infrastructure audit §10). An
agentic layer over a platform that cannot report its own workflow state is an agent
operating blind.

---

*Every count, status and code excerpt in this document was measured or read on
2026-08-28. Nothing was modified.*
