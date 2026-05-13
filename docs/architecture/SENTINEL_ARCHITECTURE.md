# Crystallux Sentinel — Architecture

> **What it is:** unified AI-powered platform guardian. Phase 1 (cost monitoring) is the foundation. Phases 2–5 extend the same architecture without rebuilding it.
>
> **Build status (2026-05-13):** Phase 1 shipped. All workflows dormant — Mary activates per `docs/handbook/SENTINEL_OPERATIONS_GUIDE.md`.

## Strategic role

Sentinel is **internal infrastructure first**, then a **standalone product**. Per `docs/strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md` Phase 7+8: prove it works for Crystallux for 3-6 months → package as standalone Sentinel Operations product (Watch $97 / Defend $297 / Active $697 / Enterprise $2,497 per month) → add Sentinel Security tier in Year 2. The 5 internal phases map directly to the eventual product tiers.

## The 5 phases

| # | Phase | Status today | When |
|---|---|---|---|
| 1 | **Cost monitoring** — daily spend per service, budget thresholds, anomaly detection, workflow circuit breakers, monthly report | **Shipped (dormant)** | Now |
| 2 | **Health monitoring** — workflow error rates, latency, auto-restart playbooks | Roadmapped | Month 2-3 |
| 3 | **Security detection** — brute-force, API abuse, vulnerability scanning, SOC 2/PIPEDA dashboards | Roadmapped | Month 9-12 |
| 4 | **Auto-remediation** — autonomous fixes, not just alerts | Roadmapped | Year 2 |
| 5 | **Standalone product** — Sentinel Operations + Sentinel Security as commercial SaaS | Roadmapped | Year 2-3 |

## Modular schema

Every phase adds its own `sentinel_<module>_*` tables. The **foundation** tables (used by every phase) are:

| Table | Purpose |
|---|---|
| `sentinel_modules` | Registry of every Sentinel capability + its status. New phases insert new rows. |
| `sentinel_alerts` | Unified alert feed. Every module writes here. Fields: `module_name`, `alert_type`, `severity`, `aggregation_key` (for dedup). |
| `sentinel_actions` | Append-only log of every action Sentinel takes or proposes. Fields: `module_name`, `action_type`, `target_resource`, `triggered_by`, `human_approved`. |

Phase 1 adds:

| Table | Purpose |
|---|---|
| `sentinel_cost_tracking` | Daily spend per service. Unique (date, service). `data_source` ∈ {internal_log, vendor_api, manual}. |
| `sentinel_cost_budgets` | Per-service thresholds. `monthly_limit_cents` + `warning_pct` + `critical_pct` + `auto_pause_pct`. Includes a special `total_platform` aggregate row. |
| `sentinel_workflow_breakers` | Per-workflow circuit breaker state. `is_essential=true` workflows are never auto-paused. |

Plus one RPC: `trip_workflow_breaker(p_workflow_id, p_reason, p_triggered_by)` — atomic pause + sentinel_actions log + sentinel_alerts entry.

Future phases add: `sentinel_health_checks`, `sentinel_security_events`, `sentinel_remediation_playbooks` — same naming convention, no foundation rebuild.

## The 13 Phase 1 workflows

### Foundation (universal — every Sentinel phase calls these)

| Workflow | Trigger | What |
|---|---|---|
| `clx-sentinel-alert-router-v1` | Webhook `POST /webhook/api/sentinel/alert` | Validates + dedupes by aggregation_key (1h window) + inserts into `sentinel_alerts` + emails via Postmark. Auth: MARY_MASTER_TOKEN or admin session. |
| `clx-sentinel-alert-acknowledge-v1` | Webhook `POST /webhook/api/sentinel/alert-acknowledge` | Admin marks alert as acknowledged or resolved. |

### Cost-specific (Phase 1)

| Workflow | Trigger | What |
|---|---|---|
| `clx-sentinel-cost-collector-anthropic-v1` | Cron 06:00 daily + webhook | **Working.** Sums yesterday's Claude calls from `agent_decisions.tokens_input/tokens_output`, applies published per-1M-token rates per model (Sonnet/Opus/Haiku), upserts `sentinel_cost_tracking`. |
| `clx-sentinel-cost-collector-{openai,twilio,vapi,heygen,supabase}-v1` | Cron 06:00 daily + webhook | **Scaffolds.** Each writes a $0 row daily so the framework runs end-to-end. Each has a TODO note specifying the vendor-specific compute path (OpenAI usage API / Twilio Usage Records / Vapi billing / HeyGen video_renders / Supabase Management API). Replace the `Compute Spend (stub)` node's body with real logic when each vendor is wired. |
| `clx-sentinel-cost-threshold-check-v1` | Cron every 4h + webhook | Fetches budgets + MTD spend, computes per-service % used, raises warning/critical/emergency alerts via alert-router. Emergency alerts also trigger `auto-pause`. Handles `total_platform` specially (sums all services). |
| `clx-sentinel-cost-anomaly-detect-v1` | Cron 07:00 daily + webhook | 14-day baseline vs yesterday per service. Raises warning if yesterday > 2× baseline AND baseline > 10¢/day. |
| `clx-sentinel-workflow-auto-pause-v1` | Webhook (internal — called by threshold-check) | Pauses ALL non-essential workflows (`is_essential=false`) via the `trip_workflow_breaker` RPC. Essential workflows are never auto-paused. |
| `clx-sentinel-workflow-auto-resume-v1` | Cron 00:00 1st of month + webhook | Resets all paused/tripped breakers to active. New month = fresh budget. |
| `clx-sentinel-cost-monthly-report-v1` | Cron 00:30 1st of month + webhook | Aggregates last month's spend + emails report to Mary. |

### Cron schedule overview

```
06:00 — All 6 cost collectors (parallel, no dependencies between them)
07:00 — Anomaly detect (reads what collectors wrote)
00:00 1st — Auto-resume (resets breakers)
00:30 1st — Monthly report (after auto-resume)
Every 4h — Threshold check
Webhook-only — Alert router, alert acknowledge, auto-pause
```

## Frontend

`admin-dashboard/pages/sentinel.html` — 5-tab interface:

- **Overview:** module registry + summary stats
- **Costs (Phase 1 active):** today's spend, MTD budgets, 14-day trend, workflow breakers
- **Health (Phase 2 placeholder):** "Coming in Phase 2"
- **Security (Phase 3 placeholder):** "Coming in Phase 3"
- **Alerts:** unified open-alerts list

Phase 2/3/4 add tab content without restructuring the page.

## Design decisions

### Why "internal logs" rather than vendor billing APIs for cost computation

Each vendor's billing API has different auth (Anthropic admin keys, Twilio Account Auth + signed request, OpenAI admin endpoint, etc.) and some don't expose programmatic billing at all. Crystallux already logs every Claude call, every SMS, every video render, every voice call. **Computing from internal logs against published per-unit rates is more pragmatic + lets us attribute cost per-workflow** (something vendor billing doesn't tell us).

Tradeoff: spend reported by Sentinel is an **estimate** — the vendor's actual invoice may differ by a few % due to volume discounts, free-tier credits, billing currency rounding. For "are we about to blow past budget?" decisions, this is more than accurate enough. Reconciliation against the actual invoice happens monthly in the `data_source = 'manual'` path.

### Why circuit breakers, not just alerts

Alerts assume a human reads them within minutes. Mary doesn't read alerts in her sleep. A runaway Claude loop at 3am can burn $500 before sunrise. Circuit breakers cap the blast radius:

- Every workflow gets a `sentinel_workflow_breakers` row registered (on first execution).
- `max_iterations` per day + `max_daily_cost_cents` are configurable per workflow.
- When threshold-check hits emergency, **all non-essential workflows pause atomically** via the RPC.
- Essential workflows (`is_essential=true`) — auth, session validation, billing webhooks — are **never** auto-paused. That's by design.
- 1st of month auto-resume restores everything.

### Why the `total_platform` aggregate row

Per-service caps protect against one runaway service. The `total_platform` cap protects against multiple services climbing together — each at 70% of cap individually but 90% combined. The threshold-check workflow detects `service_name = 'total_platform'` and sums all per-service spend instead of looking up a single service.

### Why dedup via `aggregation_key`

Without dedup, a threshold-check that runs every 4h would raise 6 identical alerts per day for the same service-at-75%. The aggregation_key pattern (`cost:<service>:<severity>:<YYYY-MM>`) collapses these into one alert per service per month per severity tier. New alerts replace the count rather than spam Mary's inbox.

## Phases 2–5 — architectural extension points

### Phase 2 (Health monitoring)

Adds:
- `sentinel_health_checks` table — workflow_id, last_run, success_rate, p95_latency_ms, status.
- New workflows: `clx-sentinel-health-pulse-v1` (every 5 min), `clx-sentinel-health-error-rate-detect-v1`, `clx-sentinel-workflow-auto-restart-v1`.
- New alert types in the existing `sentinel_alerts` table (no schema change to foundation).
- Health tab in `sentinel.html` becomes functional.

### Phase 3 (Security)

Adds:
- `sentinel_security_events` table.
- `sentinel_credential_rotations` table.
- New workflows for brute-force detection, API abuse, vulnerability scans, SOC 2 dashboards.

### Phase 4 (Auto-remediation)

Adds:
- `sentinel_remediation_playbooks` table — declarative playbook definitions.
- Existing `sentinel_actions` table already supports auto-remediation (the `human_approved` field is the safety gate).
- New workflows for playbook execution.

### Phase 5 (Standalone product)

Same architecture, packaged. Each subscriber gets its own Supabase schema or row-level tenant separation. The `sentinel_*` tables become per-tenant.

## Cross-references

- [`db/migrations/sentinel-foundation-schema.sql`](../../db/migrations/sentinel-foundation-schema.sql) — the schema.
- [`docs/handbook/SENTINEL_OPERATIONS_GUIDE.md`](../handbook/SENTINEL_OPERATIONS_GUIDE.md) — how Mary operates Sentinel day-to-day.
- [`docs/strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md`](../strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md) §7 + §8 — commercial roadmap.
- [`workflows/api/sentinel/`](../../workflows/api/sentinel/) — the 13 workflows.
- [`admin-dashboard/pages/sentinel.html`](../../admin-dashboard/pages/sentinel.html) — the dashboard.
