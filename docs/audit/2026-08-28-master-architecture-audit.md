# Master architecture audit — 2026-08-28

**Method.** Every claim below was verified against one of: the repo at `8f58afb`, the
live Supabase schema and data (PostgREST + `admin_execute_select`), a read-only GET probe
of all 285 webhook paths against `automation.crystallux.org`, or a live HTTP check.
Where documentation disagreed with implementation, implementation won. Where
implementation disagreed with production, production won. Claims that could not be
verified are marked **UNVERIFIED** rather than asserted.

---

## 1. The headline finding

**The monitoring subsystem is the only part of the platform that is running.**

| Subsystem | Last activity in production | Volume |
|---|---|---|
| Sentinel vendor health | **10 minutes ago** | 480 rows/day, 46,479 total |
| Sentinel alerts / briefings | **today, 15:01** | 854 alerts; **7 briefings every day** |
| Sentinel cost tracking | **today, 10:00** | daily |
| Commerce / LUXI | 2026-08-08 (test auction) | **0 orders, ever** |
| Outreach sender | **2026-06-08** | 13 emails ever, all to the test inbox |
| Lead discovery | **2026-05-28** (newest lead) | 0 leads in 92 days |
| Lead research | **2026-04-10** | — |
| Pipeline stats | 2026-04-27 | — |

The engine that makes money has been dark for 81 days. The engine that watches it has
written 46,479 rows in that time.

## 2. The stated blocker is false

Every document since June names *"top up Anthropic credits"* as the gate on go-live.

**Verified 2026-08-28: the Anthropic API key returns HTTP 200.** Independently, the
DevOps briefing workflow calls Claude seven times a day and produces output. Credits are
not the blocker and have not been for some time. The Sales Engine is dark because its
**schedule-triggered workflows are not running**, not because the writer cannot pay for
tokens.

## 3. What is actually deployed

- **326 workflow JSONs in the repo. 325 carry `active: false`.** The repo is *not* a
  record of production state and cannot be used as one.
- **Read-only probe of all 285 unique webhook paths:** **265 are registered in
  production** (their workflows are active), **20 are not**. The 20:
  `activity/classifier/run`, `activity/record`, `admin/luxi/restream/channels`,
  `call/finalized`, `clx-appointment-geocoder`, `clx-daily-plan`, `clx-no-show-detector`,
  `clx-reshuffle`, `clx-script-matcher`, `clx-task-classifier`, `clx-video-ready-v1`,
  `clx-voice-result-v1`, `form-intake`, `intelligence/seed-insurance`,
  `productivity/summary/run`, `script/learning/run`, `script/suggest`,
  `transcript/classify`, `vapi/transcript-stream`, `verify-access`.
- Webhook coverage says nothing about the **schedule-triggered** pipeline workflows —
  Lead Import, Discovery, Research, Scoring, Outreach, Sender. Production *data* says
  those are not producing.
- All five public hosts return 200. RLS is enabled on **208 of 208** public tables.

## 4. The n8n API key is dead, and it costs more than it looks

`GET /api/v1/workflows` → **401 unauthorized**. Three things depend on it:

1. **Sentinel's workflow-health collector** — `sentinel_workflow_health` has **0 rows,
   ever**. Sentinel monitors endpoints but is completely blind to workflow state.
2. **The daily briefing** — today's says *"The paused workflow entry is incomplete (no
   name or ID returned by the API)."* That is the 401, surfacing as a hallucinated-looking
   report.
3. **The GitHub Actions deploy job** (`.github/workflows/crystallux-ci.yml`) pushes each
   workflow via that API. (Whether the GitHub *secret* holds the same dead key is
   **UNVERIFIED** — no CI access from here.)

This is why nobody noticed the Sales Engine stopped on June 8: the system that would have
reported it has been blind since before that.

## 5. Duplication in production

- **7 identical DevOps briefings run every single day** — verified across 14 consecutive
  days, 7 per day, no exceptions. The repo contains **one** briefing workflow. Six are
  duplicate copies living in n8n (blockers §0n, still present). Each one calls Claude.
- **Two Google Places discovery implementations.** `clx-city-scan-discovery` (raw REST
  dup-check, direct insert) and `clx-b2c-discovery-v2.1` (uses `scan_query_tracker`,
  `insert_lead_if_not_exists`, `scan_log`, error logging). v2.1 is strictly better.
- **Two Apollo integrations.** `clx-lead-import` (crude search→insert, the one active
  workflow) and `clx-apollo-enrichment-v1` (quota gate, `niche_overlays` title keywords,
  RPC update). The second is the pattern; the first is the one that runs.
- **Eight frontend surfaces**, ~200 HTML files: `site`, `admin-dashboard`,
  `client-dashboard`, `dashboard` (legacy), `insurance-mga-dashboard`,
  `insurer-dashboard`, `insurance-marketing`, `insurer-marketing`.
- **85 of 326 workflows (26%) live in `api/insurance-mga/`** — insurance is built as its
  own subsystem, which is the opposite of the overlay model the platform already has.

## 6. Stubs — 11 workflows that do nothing

Six social publishers (Facebook, Instagram, LinkedIn, TikTok, X, YouTube) plus
`content-engagement-poller`, `content-comment-monitor`, `content-attribution-loop`,
`mga-insurance-quote-api`, `file-completeness-bulk-refresh`. Nine of the fourteen content
workflows are stubs: **the entire content distribution loop is a shell.**

## 7. Technical debt, ranked by consequence

1. **18 live tables have no `CREATE` statement anywhere in the repo — including `leads`
   itself.** Production cannot be rebuilt from source. Also: `personas`, `content_pieces`,
   `distribution_platforms`, `scan_errors`, `scan_query_tracker`, `follow_up_sequences`.
2. **No migration ledger.** The three `schema_migrations`/`migrations` tables belong to
   Supabase's own `auth`/`realtime`/`storage` schemas. Nothing tracks which of the repo's
   113 SQL files have been applied. (194 of 198 declared tables *are* live; only
   `post_call_sequences` is genuinely missing.)
3. **122 workflows call `validate_session` without `alwaysOutputData`** (verified count) —
   a bad token yields an empty 200 instead of a 401. **8 Switch nodes have no
   `fallbackOutput`** — an unmatched input yields an empty 200. Both live.
4. **CI validates 50 of 326 workflows** (`workflows/*.json` only, not subdirectories) and
   runs neither `validate-workflows.py` nor `validate-migrations.py`.
5. **`leads` is a 130-column table** carrying discovery, enrichment, scoring, campaign
   copy, video, voice, marketplace and assignment concerns in one row.
6. **The admin Workflows page reports fiction.** `admin/workflow-status` returns
   `{"active_count":1,"workflows":[{"name":"unknown"}]}` — it derives from `scan_log`
   (0 rows), not from n8n.
7. **`docker-compose.yml`: main n8n runs `EXECUTIONS_MODE=regular` while `n8n-worker`
   runs `EXECUTIONS_MODE=queue`.** In a queue deployment the main instance must also be
   `queue`, or the worker never receives jobs. Redis has no password (commented out).
   Whether the VPS runs this exact file is **UNVERIFIED**.
8. `MARY_MASTER_TOKEN` is a long-lived static shared secret held in `localStorage` with no
   rotation or expiry. No secrets are leaked to any frontend — checked.
9. `docs/audit/production-readiness.md` is dated 2026-05-05 and still says the branch is
   `scale-sprint-v1`. Most of its "gated" rows are resolved.

## 8. Production data, as it actually is

- **2,518 leads.** 881 with an email (35%), 2,156 with a website, 52 `do_not_contact`,
  5 unsubscribed.
- **Every lead came from Google Maps.** `google_maps_discovery` 1,770, `google_maps` 739,
  everything else 9. **Apollo has produced zero leads, ever** — that answers the open
  question in the project log with data.
- **Scoring works.** Average 25.7, max 82, **831 leads score ≥ 50**. The documented claim
  that scoring is broken at an average of 4 is stale by months.
- **Funnel to date:** 16 Contacted → 1 Replied → 1 Booking Sent → 1 Closed Lost.
- **Commerce:** 8 auctions, 2 products, 2 inventory items, **0 orders, 0 reservations,
  0 commerce events**.
- **Built but never used:** `discovery_jobs` (0 rows), `client_icp_profiles` (0),
  `signal_archetypes` (0), `campaigns` (0), `market_signals` (0), `bookings` (0),
  `outreach_log` (0), `messages_sent` (0), `deals` (0).

## 9. The discovery layer — most of it already exists

The proposed Discovery Orchestrator is largely a **reorganization of parts already in the
database**, not new construction.

**Already built — reuse, do not recreate:**

| Proposed concept | What already exists | State |
|---|---|---|
| `discovery_jobs` | **`discovery_jobs`** — `client_id, vertical, geography, requested_count, platforms_used[], leads_found, status, signal_context, created_at, completed_at` | exists, 0 rows |
| Vertical configuration | **`niche_overlays`** (22 cols, incl. `icp_template`, `lead_discovery_sources` jsonb, `apollo_title_keywords`, `lead_target_type`) | **8 verticals, 5 active** |
| ICP matching | **`client_icp_profiles`** (size, titles, include/exclude keywords, signal types) | exists, 0 rows |
| Deduplication | **`insert_lead_if_not_exists`** RPC + `leads_company_unique` | in use |
| Query-level backoff | **`scan_query_tracker`** (`consecutive_zero_new`, `paused`) | **215 rows** |
| Raw record store | **`market_signals_raw`** (`source, external_id, raw_payload, processed, processing_error`) — the exact pattern, for signals | proven |
| Provenance on leads | `platform_source`, `platform_lead_id`, `enrichment_source`, `source_domain`, `email_source`, `place_id`, `data_quality_score` | columns exist |
| Cost metering per provider | `apollo_usage`, `apollo_credits_log`, `get_monthly_apollo_credits_used` + quota-gate node pattern | proven |
| Cheap enrichment | `clx-email-scraper-v3` (website → email, no API key) | 881 emails found |

**Genuinely missing — three things:**

1. `discovery_providers` — the registry (type, auth, enabled, priority, daily_limit,
   cost_per_record, **commercial_use_allowed**, config).
2. `discovery_raw_records` — the raw store. Copy `market_signals_raw` exactly; it already
   works.
3. A **normalizer boundary**. Today normalization is inline in per-provider Code nodes
   ("Parse Places Results", "Normalize Lead Data"), which is precisely why each new
   provider means a new workflow.

**Extend `discovery_jobs`, do not replace it:** add `provider_id`, `returned_count`,
`accepted_count`, `rejected_count`, `error`, `query`. Keep `platforms_used` and
`signal_context`.

**On the 100,000 records/day proposal.** The cost funnel the request describes is correct
and the deterministic stages for it already exist in pieces. Two conditions before that
provider is wired to anything: `commercial_use_allowed` must be a verified fact per
source, not a column that defaults to true; and the provider's daily budget must go
through the same quota-gate pattern Apollo already uses, *before* the first record is
fetched. At current volumes the funnel is theoretical — the system has 2,518 leads and
sent 13 emails. **Discovery volume is not the constraint. Nothing is running.**

## 10. Recommended sequence

**Before any new feature:**

1. **Mint a new n8n API key.** It unblocks Sentinel's workflow monitoring, the daily
   briefing, and CI deployment in one action. Nothing else can be trusted until the
   platform can see itself.
2. **Establish which schedule-triggered workflows are actually active** — impossible until
   (1). Then restart the Sales Engine or consciously decide not to.
3. **Delete the 6 duplicate briefing workflows.** Seven Claude calls a day for one report.
4. **Sell one thing.** 0 orders through a live-key commerce stack is the largest untested
   surface on the platform.

**Consolidation, in benefit order:**

5. Retire `clx-city-scan-discovery` in favour of the v2.1 pattern; retire
   `clx-lead-import`'s raw Apollo search in favour of the enrichment pattern — Apollo
   becomes a provider behind the router, which is what the request asks for anyway.
6. Capture the 18 undocumented tables (starting with `leads`) into
   `db/migrations/`, and add a real applied-migrations ledger.
7. Fix the 8 `fallbackOutput` gaps (contained). Decide separately on the 122
   `alwaysOutputData` gaps (requires re-shipping against live traffic).
8. Widen CI to all 326 workflows and run both validators.

**Then, and only then, the discovery layer:** three new tables, one normalizer, one
router — extending `discovery_jobs`, `niche_overlays`, `client_icp_profiles` and
`scan_query_tracker` rather than duplicating them.

---

*Every figure in this document was measured on 2026-08-28 against live production.*
