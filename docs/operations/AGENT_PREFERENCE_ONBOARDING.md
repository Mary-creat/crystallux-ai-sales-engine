# Agent Preference Onboarding

A 5-minute guided setup for every agent (Mary + future reps + each
client's closing team) before they start using the Morning Priority
dashboard. Captures the handful of per-agent knobs that make the
`daily_task_plan` actually fit how that person works.

## What the agent sets

Stored in `agent_calendar_prefs` (one row per agent). Every field has
a safe default, so skipping setup is fine — output will still be
coherent, just less personalised.

| Field | Meaning | Default |
|---|---|---|
| `timezone` | IANA name — used for all scheduling math | `America/Toronto` |
| `work_start_local` / `work_end_local` | Working window in local time | `09:00` / `17:00` |
| `buffer_minutes` | Between-meeting buffer the reshuffle suggester leaves | `15` |
| `max_per_day` | Hard cap on appointments scheduled by the reshuffle | `8` |
| `morning_focus_block` | `replies_then_hot` \| `hot_then_replies` \| `calls_first` \| `custom` | `replies_then_hot` |
| `daily_task_cap` | Max number of tasks surfaced in "Today's Plan" | `25` |
| `prefer_batch_similar` | Group same-category tasks together | `true` |
| `reply_sla_hours` | Escalates an inbound reply to top of plan after this | `4` |
| `hot_lead_threshold` | Lead score ≥ this is a "hot_lead" in the plan | `80` |
| `custom_order` | jsonb `[{ task_category, weight }]` when `morning_focus_block='custom'` | `[]` |
| `no_show_sms_enabled` | Calendar B.12a-2 — auto-SMS after a no-show | `true` |
| `no_show_sms_template` | Override the default recovery SMS copy | `NULL` |
| `notification_email` | Where the morning plan + summary digest lands | `NULL` |

## Canonical 5-question Q&A

Run through these with each agent once. Everything else derives from
answers here.

1. **"What time zone are you in, and what are your working hours?"**
   → `timezone`, `work_start_local`, `work_end_local`.
2. **"First thing in the morning, do you answer replies or call hot
   leads?"**
   → `morning_focus_block` (`replies_then_hot` vs `hot_then_replies`).
   If they say "depends on the day" → `custom` + ask them to rank
   `reply / hot_lead / no_show_rebook / upcoming_call / follow_up`
   and store weights 5/4/3/2/1 by their order.
3. **"How many prospects can you realistically call or email in a
   day before you stop being useful?"**
   → `daily_task_cap`. Mary's honest answer is 25; many reps say 40
   but produce better output capped at 20.
4. **"If a prospect replies to an email, how fast should we flag it
   as overdue?"**
   → `reply_sla_hours`. Four is aggressive; eight is realistic for
   part-timers.
5. **"When a prospect no-shows, do you want the platform to text them
   a rebook link automatically?"**
   → `no_show_sms_enabled`. If yes, also capture
   `no_show_sms_template` (or leave default).

Everything else (`buffer_minutes`, `max_per_day`, `hot_lead_threshold`,
`prefer_batch_similar`) keeps its default unless the agent volunteers
a preference.

## Creating a new agent row

SQL pattern — safe to run by hand from Supabase SQL editor:

```sql
INSERT INTO agent_calendar_prefs (
  agent_id, client_id, agent_name, agent_email,
  timezone, work_start_local, work_end_local,
  morning_focus_block, daily_task_cap, reply_sla_hours,
  hot_lead_threshold, no_show_sms_enabled, notification_email
)
VALUES (
  gen_random_uuid(),        -- agent_id
  '<client-uuid>',          -- leave NULL for platform-wide admin agents (Mary)
  'Alex Rep',
  'alex@client.example',
  'America/Toronto',
  '09:00', '17:00',
  'replies_then_hot',
  25, 4, 80, true,
  'alex@client.example'
)
ON CONFLICT (agent_id) DO NOTHING
RETURNING agent_id;
```

Hand the returned `agent_id` to the agent — they paste it into the
Today's Plan panel's "Agent id" field. The morning plan generator
reads their row automatically on next run.

## When to update preferences

- After a week of live use — revisit Q3 (`daily_task_cap`) and Q4
  (`reply_sla_hours`); most agents discover they over-estimated
  capacity.
- If an agent moves time zones or changes working hours — update
  `timezone` + both `work_*_local` fields.
- When a client promotes the SMS recovery path to go-live — flip
  `no_show_sms_enabled=true` (default) or supply a custom template.

## Privacy

`agent_calendar_prefs` is service_role-only. The dashboard never reads
it via anon key; the daily-plan generator workflow loads it through
the service_role key on the n8n backend. Don't expose `agent_email`
or `notification_email` in any public surface.

## Related

- Migration: `docs/architecture/migrations/2026-04-24-morning-priority-ordering.sql`
- Workflow: `workflows/clx-daily-plan-generator-v1.json`
- Handbook: `docs/architecture/OPERATIONS_HANDBOOK.md` §30
