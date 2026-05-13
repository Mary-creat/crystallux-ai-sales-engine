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

### Phase 2 (Health monitoring) — BUILT 2026-05-13

**Schema (`db/migrations/sentinel-health-schema.sql`):**
- `sentinel_workflow_health` — one row per workflow per 5-min window. Columns: execution_count, success_count, error_count, waiting_count, generated `error_rate_pct`, avg/p95 duration, last_execution_at, status (healthy/degraded/critical/silent/unknown). UNIQUE (workflow_id, window_start) so the collector upserts cleanly.
- `sentinel_endpoint_health` — per-ping history with carry-forward `consecutive_failures` (via the `record_endpoint_check` RPC).
- `sentinel_endpoints` — registry of what to ping (supabase_rest, n8n_health, admin/client/marketing dashboards seeded).
- `sentinel_health_thresholds` — per-workflow / per-endpoint / default SLOs (error-rate warning/critical, max silence minutes, max p95, max consecutive down). Seeded with stricter SLOs for the 7 protected production workflows + auth pathway.

**Workflows in `workflows/api/sentinel/`:**
- `clx-sentinel-health-workflow-collector-v1` (cron */5 min) — pulls n8n's `/api/v1/executions` API for the window, joins with `/api/v1/workflows?active=true` so silent workflows still get a row. Aggregates per workflow into sentinel_workflow_health upserts. Requires `N8N_API_KEY` env var.
- `clx-sentinel-health-endpoint-collector-v1` (cron */5 min) — pings each active sentinel_endpoints row, classifies up/down/degraded, writes via RPC.
- `clx-sentinel-health-analyzer-v1` (cron */15 min) — joins latest workflow + endpoint windows against thresholds, raises alerts via the alert-router (`module_name='health_monitoring'`). Alert types: `health_workflow_silent`, `health_error_spike`, `health_latency_spike`, `health_endpoint_down`, `health_endpoint_degraded`. Aggregation_key prevents spam.
- `clx-sentinel-health-summary-v1` — admin-gated POST webhook powering the dashboard Health tab.

**Frontend:** Health tab in `sentinel.html` shows: overall health score ring (penalty-based 0–100), workflow/endpoint count tiles, sortable workflow health table (critical → silent → degraded → healthy), endpoint health table with consecutive-failures counter, open health alerts list.

**Deliberately deferred to Phase 4:** auto-restart, auto-recovery of tripped breakers when upstream healthy, automated SLO tuning. Phase 2 detects + alerts; it never modifies workflow state autonomously.

### Phase 3 (Security) — BUILT 2026-05-13

**Schema (`db/migrations/sentinel-security-schema.sql`):**
- `sentinel_security_events` — universal append-only event log. Workflows POST here (via the event-log webhook) when they observe a security-relevant signal: failed login, session rejection, webhook auth failure, privilege denial, rate-limit breach. Indexed on (event_type, created_at) + (user_email, created_at) + (source_ip, created_at) for cheap rule-window queries. `log_security_event()` RPC is the convenience writer.
- `sentinel_credential_inventory` — 15 seeded credentials (Supabase service-role, Supabase anon, MARY_MASTER_TOKEN, INTERNAL_EMAIL_SECRET, Anthropic, OpenAI, Twilio, Vapi, HeyGen, Postmark, Stripe secret + webhook signing, n8n API key, Cloudflare, admin password). Each row carries `rotation_interval_days` + `warning_threshold_days`. `next_rotation_due` is a generated column.
- `sentinel_security_rules` — 7 seeded detection rules. Each defines `event_type_filter`, `group_by` (user_email / source_ip / endpoint / user_id), `window_minutes`, `threshold_count`, `severity`. The detector reads this table — no code changes to add new rule types.
- Foundation `sentinel_modules.status` flipped to `'active'` for `security_monitoring`.

**Workflows in `workflows/api/sentinel/`:**
- `clx-sentinel-security-event-log-v1` — POST `/webhook/api/sentinel/security/event`. Universal sink. Auth: `MARY_MASTER_TOKEN`. Any workflow that detects a security signal posts here (no callsite knows the schema; the workflow does).
- `clx-sentinel-security-detector-v1` — cron */10 min. Loads active rules + last 90 min of events, groups events per `rule.group_by`, raises alerts when group count ≥ `threshold_count`. `aggregation_key=security:<rule>:<group_value>:<YYYY-MM-DDTHH>` collapses repeated spikes into one alert per group per rule per hour.
- `clx-sentinel-credential-age-check-v1` — cron 06:00 daily. Warns when within `warning_threshold_days` of `next_rotation_due`; raises critical when past due. `aggregation_key` by month.
- `clx-sentinel-security-summary-v1` — admin-gated POST webhook powering the Security tab. Returns posture score (0–100, penalty-based), 24h event-type buckets, severity counts, top-5 offending IPs + emails by failed-auth events, enriched credentials with `days_to_due` + `rotation_status`, all rules, open security alerts.
- `clx-sentinel-credential-rotate-record-v1` — admin POST that sets `last_rotated_at = now()` after Mary rotates a key. Also writes a `sentinel_actions` row with `human_approved=true` for the audit trail.

**Frontend:** Security tab in `sentinel.html` shows: posture-score conic-gradient ring, event-count + credential-count + open-alert tiles, rules table with 24h event-matching counts, top-5 IPs + top-5 emails by failed-auth, credential inventory with "Mark rotated" button per row, open security alerts list.

**Deliberately deferred to Phase 4:** auto-IP-block on brute-force critical, auto-lockout on confirmed compromise, vulnerability scanning (needs external tooling — Snyk/Trivy out of scope for now), SOC 2/PIPEDA dashboards (separate compliance feature, not core security detection).

### Phase 4 (Auto-remediation) — BUILT 2026-05-13

**Schema (`db/migrations/sentinel-remediation-schema.sql`):**
- `sentinel_remediation_playbooks` — declarative playbook registry. Each row binds a (module, alert_type, severity_min) trigger to an action_type (pause_workflow / resume_workflow / block_ip / propose_account_lockout / propose_credential_revocation / notify_only), with cooldown_minutes + requires_approval + action_config jsonb. Six playbooks seeded.
- `sentinel_ip_blocklist` — active blocked source IPs with optional `expires_at`. Unique-active partial index prevents duplicate live blocks per IP.
- `is_ip_blocked(p_ip)` STABLE SQL function — cheap boolean check for auth-path opt-in.
- Foundation `sentinel_modules.status` flipped to `'active'` for `auto_remediation`.

**Workflows in `workflows/api/sentinel/`:**
- `clx-sentinel-remediation-orchestrator-v1` (cron */5 min) — the brain. Sweeps expired blocklist rows first. Joins open alerts (last 30 min) against active playbooks, evaluates cooldown via recent `sentinel_actions` rows. Auto-actions execute in one tick: pause/resume PATCHes `sentinel_workflow_breakers` (with `&is_essential=eq.false` URL guard on pauses); block_ip INSERTs `sentinel_ip_blocklist`. Every execution writes a `sentinel_actions` row. Approval-required actions write a pending `sentinel_actions` row with `human_approved=false`. Also evaluates the time-driven `auto_resume_when_healthy` playbook by joining paused breakers against recent `sentinel_workflow_health` rows (3 consecutive healthy windows = resume).
- `clx-sentinel-action-approve-v1` — admin POST. Body: `{ action_id, decision: 'approve'|'reject', notes? }`. Re-reads the pending action, re-executes the side effect on approve, marks `rolled_back` on reject. Sets `human_approved + approved_by + approved_at` atomically.
- `clx-sentinel-remediation-summary-v1` — admin webhook for the Remediation tab. Returns playbooks, active blocklist, pending approvals, last-7-days action history, status counts, per-playbook action stats.

**Frontend:** New 6th tab "Remediation" in `sentinel.html`. Stat tiles for pending approvals (highlighted when >0), active blocklist count, active playbooks count, 7-day action total + success/rolled-back/failed breakdown. Pending approvals table with Approve / Reject buttons. Active blocklist table with expiry countdown. Playbook table showing trigger config + auto/human badge + 7-day action counts. Recent actions history (last 50).

**Safety rails:**
- Essential workflows (`is_essential=true`) NEVER auto-paused. Both the `trip_workflow_breaker` RPC and the orchestrator's PATCH URL filter enforce this.
- Destructive actions (account_lockout, credential_revocation) NEVER auto-execute. Orchestrator writes pending row; Mary approves via the dashboard.
- Cooldowns per (playbook, target) prevent flap loops.
- Every action — auto or human-approved — writes a `sentinel_actions` audit row with `triggered_by` (`auto:<playbook>` or `human:<user_id>`).

**Deferred (Phase 5+):** Cloudflare WAF integration (push blocklist to edge), `auth_users.locked_until` integration for actual account lockout, vendor-API credential revocation hooks.

### Phase 5 (Standalone product)

Same architecture, packaged. Each subscriber gets its own Supabase schema or row-level tenant separation. The `sentinel_*` tables become per-tenant.

## Cross-references

- [`db/migrations/sentinel-foundation-schema.sql`](../../db/migrations/sentinel-foundation-schema.sql) — the schema.
- [`docs/handbook/SENTINEL_OPERATIONS_GUIDE.md`](../handbook/SENTINEL_OPERATIONS_GUIDE.md) — how Mary operates Sentinel day-to-day.
- [`docs/strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md`](../strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md) §7 + §8 — commercial roadmap.
- [`workflows/api/sentinel/`](../../workflows/api/sentinel/) — 27 workflows (Phase 1 + Phase 2 + Phase 3 + Phase 4).
- [`db/migrations/sentinel-health-schema.sql`](../../db/migrations/sentinel-health-schema.sql) — Phase 2 schema.
- [`db/migrations/sentinel-security-schema.sql`](../../db/migrations/sentinel-security-schema.sql) — Phase 3 schema.
- [`db/migrations/sentinel-remediation-schema.sql`](../../db/migrations/sentinel-remediation-schema.sql) — Phase 4 schema.
- [`admin-dashboard/pages/sentinel.html`](../../admin-dashboard/pages/sentinel.html) — the dashboard.
