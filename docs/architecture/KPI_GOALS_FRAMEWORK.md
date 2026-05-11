# KPI / Goals Framework (F3 — Layer 1)

> Universal targets + achievement tracking + periodic snapshots. No
> vertical assumptions. The `metric` column is freeform text so any
> vertical can plug in its own KPI vocabulary.

## Why

`clx-daily-summary-generator-v1` and `agent_daily_summary` (universal,
§30) capture *what happened*. F3 adds *what should happen*: per-user
targets, achievement %, weekly/monthly snapshots, automated "behind
track" notifications. Without F3, advisor coaching has no quantitative
spine.

## Tables (db/migrations/agent-goals-schema.sql)

| Table | Purpose |
|---|---|
| `goal_templates` | Per-client target definitions. `metric` (freeform), `period` ∈ {daily, weekly, monthly, quarterly, annual}, `target_value`. Defines "every advisor should book 8 meetings per week" once; instantiates for each user. |
| `user_goals` | Per-user instantiated targets. `period_start` / `period_end`, `current_value`, `achievement_percentage` (GENERATED column), `status` ∈ {in_progress, achieved, missed, abandoned}. |
| `performance_snapshots` | Weekly + monthly materialised rollups. `metrics` jsonb keyed by metric name. Used for trend lines, rank-within-team, retrospective queries. |

## RPCs

| Name | Purpose |
|---|---|
| `upsert_user_goal_progress(p_user_goal_id, p_current_value)` | Updates `current_value`, recomputes status (`achieved` when `current_value >= target_value`; `missed` when `period_end < today` and short). |
| `recompute_goal_progress(p_user_goal_id)` | Derives `current_value` from universal source tables based on metric: `meetings_booked` → `bookings`; `calls_made / emails_sent / sms_sent` → `messages_sent` by channel; `leads_assigned` → `lead_assignments`; `revenue_cents` → sum of `bookings.fee_per_booking_cents`. Returns `false` for unknown metrics (verticals must aggregate those themselves). |

## Workflows (workflows/api/goals/)

| Workflow | Webhook | Trigger | Role |
|---|---|---|---|
| `clx-goal-template-create-v1` | POST `/webhook/api/goals/template-create` | Manager defines a target | admin / mga_principal / supervisor |
| `clx-user-goals-assign-v1` | POST `/webhook/api/goals/assign` | Manager assigns target to user | admin / mga_principal / supervisor |
| `clx-user-goals-list-v1` | POST `/webhook/api/goals/my-progress` | Frontend: my goals | Session-token (own data) |
| `clx-team-goals-list-v1` | POST `/webhook/api/goals/team` | Frontend: team goals | admin / mga_principal / supervisor |
| `clx-performance-aggregator-v1` | Cron 00:30 daily + POST `/webhook/api/goals/aggregate` | Walks active `user_goals` → `recompute_goal_progress` per row | Schedule / ops |
| `clx-performance-snapshot-v1` | Cron Sun 01:00 + 1st-of-month 01:00 + POST `/webhook/api/goals/snapshot` | Materialises `performance_snapshots` | Schedule / ops |
| `clx-goal-progress-notification-v1` | Cron Mon 09:00 + POST `/webhook/api/goals/notify` | Emails users behind track or freshly achieved | Schedule / ops |

All workflows are `active: false`. Mary activates after applying
migrations and confirming the aggregator picks the right source
counts for her tier.

## Notification policy

`clx-goal-progress-notification-v1` runs Mondays at 09:00. For each
user with `status='in_progress'` goals:

- **Achieved (achievement_pct >= 100):** Send "you hit a target" email.
- **Behind track:** if `achievement_pct < (period_progress_pct - 20)`,
  send "needs attention" email. `period_progress_pct` is elapsed /
  total period as a percentage — so the SLA is "must keep within 20
  percentage points of the linear pace".

Uses Postmark (`POSTMARK_SERVER_TOKEN` env var). Subject lines are
universal — no insurance terminology.

## Frontend wiring (Commit B Layer 2)

- `advisor/goals.html` → `clxApi.postApi('goals/my-progress', {})`.
- `principal/team-goals.html` → `clxApi.postApi('goals/team', { client_id })`.

Other verticals: same call shape, terminology shifts in HTML labels.

## Roadmap

- Pluggable metric aggregators (vertical-specific): currently
  `recompute_goal_progress` is a hardcoded switch. Future commit can
  add a `metric_aggregators` table or a dispatch convention where
  a vertical workflow handles unknown metrics.
- Forecast: predict end-of-period achievement from velocity. Useful
  for coaching alerts mid-week rather than at retrospective.
- Streaks + leaderboards: materialise into `performance_snapshots`
  with a `rank_within_team` column already provisioned.
