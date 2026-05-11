# Lead Distribution Architecture (F7 — Layer 1)

> Universal core engine feature. No vertical assumptions. Reused by
> every vertical's frontend (insurance MGA today; mortgage / dental /
> any future vertical without changes).

## Why

The lead generation engine routes leads to **campaigns** (via
`clx-campaign-router-v2`). But routing to a campaign is not the same
as routing to a **person** — the campaign-router sets
`lead_status='Campaign Assigned'` and `preferred_channel`, then stops.
Without F7, leads pile up unassigned in production. F7 closes that
gap with a rules engine, capacity tracking, and explicit assignment
audit trail.

## Tables (db/migrations/lead-distribution-schema.sql)

| Table | Purpose |
|---|---|
| `lead_distribution_rules` | Per-client routing rules. `rule_type` ∈ {round_robin, geographic, capacity_aware, skill_match, priority_queue}. Priority field — lowest evaluates first. |
| `team_member_preferences` | Per-user opt-in capacity + zone + skill preferences. `is_accepting_leads`, `daily_capacity`, `weekly_capacity`, `preferred_zones`, `skills`, `out_of_office_until`. |
| `lead_assignments` | Append-only history of every assignment. `assigned_at`, `unassigned_at`, `assignment_method` ∈ {auto, manual, self_claim, reshuffle}. |
| `team_capacity_log` | Daily rollup: `leads_assigned_today` vs `leads_capacity_today`, with `utilization_pct` as a GENERATED column. |
| `leads` (extended) | `assigned_advisor_id`, `assigned_at`, `assignment_method` columns added idempotently. |

## RPCs

| Name | Purpose |
|---|---|
| `assign_lead_to_user(p_lead_id, p_user_id, p_rule_id, p_method)` | Atomic claim. Locks the lead row (`SELECT FOR UPDATE`), checks capacity, inserts `lead_assignments` row, updates `leads`, bumps `team_capacity_log` + `team_member_preferences.last_assigned_at`. Returns assignment_id or NULL. |
| `unassign_lead(p_lead_id, p_reason)` | Closes the open `lead_assignments` row and clears `leads.assigned_advisor_id`. |
| `distribute_pending_leads(p_client_id, p_lead_id?, p_max_leads?)` | Bulk round-robin over pending leads (`lead_status='Campaign Assigned' AND assigned_advisor_id IS NULL`). v1 implements round_robin only; other rule_types fall through (see Roadmap). |

## Workflows (workflows/api/distribution/)

| Workflow | Webhook | Trigger | Role |
|---|---|---|---|
| `clx-lead-distribute-v1` | POST `/webhook/api/leads/distribute` | Manual / cron-triggered by ops | Session-token (any) |
| `clx-lead-reassign-v1` | POST `/webhook/api/leads/reassign` | Principal/admin override | admin / mga_principal / supervisor |
| `clx-lead-self-claim-v1` | POST `/webhook/api/leads/self-claim` | Advisor grabs an unassigned lead | Session-token (any) |
| `clx-team-member-preferences-update-v1` | POST `/webhook/api/team-member/preferences` | User updates own preferences | Session-token (own row) |
| `clx-team-capacity-monitor-v1` | Cron 00:15 daily + POST `/webhook/api/team-capacity/recalc` | Seeds today's capacity row per user | Schedule / ops |

All workflows are `active: false` by default. Mary activates per client + tier.

## Hand-off contract with `clx-campaign-router-v2` (PROTECTED)

Campaign-router-v2 (`workflows/clx-campaign-router-v2.json`) writes:

- `lead_status = 'Campaign Assigned'`
- `preferred_channel = <channel>`

`clx-lead-distribute-v1` polls leads with exactly that signature and
assigns them. **No modifications to campaign-router-v2 are required.**
A simple cron on the distribute workflow (e.g. every 15 minutes) keeps
the pipeline flowing.

## Roadmap (deferred from v1)

- **`geographic` rule_type:** match `lead.postal_code` prefix against
  `team_member_preferences.preferred_zones`. Falls through to round-robin
  in v1.
- **`capacity_aware` rule_type:** weighted assignment favouring users
  with the lowest `utilization_pct`. Falls through to round-robin in v1.
- **`skill_match` rule_type:** intersect `lead.required_skills` (when
  set) with `team_member_preferences.skills`. Falls through to round-robin
  in v1.
- **`priority_queue` rule_type:** assign by `lead_score` band to users
  flagged for high-value queues. Falls through to round-robin in v1.

To enable in a future commit: add CASE branches to
`distribute_pending_leads` matching `v_rule.rule_type`.

## Frontend wiring

The insurance-mga-dashboard `principal/lead-distribution-config.html`
(Commit B) CRUDs `lead_distribution_rules` + `team_member_preferences`
via the universal Layer 1 webhooks above. Other verticals plug in the
same way — terminology shifts in the UI, the API stays universal.
