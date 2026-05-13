# Sentinel — Operations Guide

> **For:** Mary. Day-to-day operation of Crystallux Sentinel (cost monitoring + future health/security modules).
>
> **What Sentinel does today:** tracks cloud spend per service, alerts before budgets blow, auto-pauses non-essential workflows when emergency thresholds hit, generates a monthly cost report. All defaults are sensible; you tune over time.

## Initial activation (one-time, ~30 min)

After Mary applies `db/migrations/sentinel-foundation-schema.sql` and imports the 13 workflows in `workflows/api/sentinel/`:

### Step 1 — Confirm seeds + register workflow breakers

In Supabase SQL Editor:

```sql
-- Confirm modules + budgets seeded
SELECT module_name, status FROM sentinel_modules;
-- Expect 4 rows: cost_monitoring=active, health/security/auto_remediation=planned

SELECT service_name, monthly_limit_cents, warning_pct, critical_pct, auto_pause_pct
FROM sentinel_cost_budgets ORDER BY service_name;
-- Expect 8 rows (7 services + total_platform)

-- Optional: mark essential workflows so they're NEVER auto-paused. Get workflow IDs from n8n UI.
-- Examples: auth/login workflow, session validation, Stripe billing webhook.
INSERT INTO sentinel_workflow_breakers (workflow_id, workflow_name, is_essential)
VALUES
  ('<auth-login-workflow-id>',           'CLX - Auth Login v1',          true),
  ('<validate-session-workflow-id>',     'CLX - Validate Session v1',    true),
  ('<stripe-webhook-workflow-id>',       'CLX - Stripe Webhook v1',      true)
ON CONFLICT (workflow_id) DO UPDATE SET is_essential = true;
```

### Step 2 — Activate workflows (in this order)

In n8n UI, flip `active: true` on these in this exact sequence:

1. **`clx-sentinel-alert-router-v1`** — must be first; everything else depends on it.
2. **`clx-sentinel-alert-acknowledge-v1`** — webhook for the UI.
3. **`clx-sentinel-cost-collector-anthropic-v1`** — the real working collector.
4. **The 5 scaffold collectors** (`openai`, `twilio`, `vapi`, `heygen`, `supabase`) — they record $0 daily until you wire each vendor's compute. Activating them now means tomorrow you'll see all 6 services in the dashboard with anthropic showing real spend + others showing 0.
5. **`clx-sentinel-cost-threshold-check-v1`** — runs every 4h, raises alerts.
6. **`clx-sentinel-cost-anomaly-detect-v1`** — needs ≥7 days of history before it does anything; safe to activate early.
7. **`clx-sentinel-workflow-auto-pause-v1`** — internal webhook for emergency response.
8. **`clx-sentinel-workflow-auto-resume-v1`** — cron 1st-of-month.
9. **`clx-sentinel-cost-monthly-report-v1`** — cron 1st-of-month 00:30.

### Step 3 — Smoke test

In Supabase SQL editor, force the anthropic collector to run by calling its webhook (you can test with curl):

```bash
curl -X POST https://automation.crystallux.org/webhook/api/sentinel/cost/collect-anthropic
```

Then verify:

```sql
SELECT tracking_date, service_name, spend_cents, usage_metrics
FROM sentinel_cost_tracking
ORDER BY tracking_date DESC LIMIT 5;
```

Should show today's row for `anthropic`. The amount may be 0 if you haven't run any Claude workflows yet — that's fine. The framework works.

## How to interpret alerts

Sentinel uses 4 severity levels:

| Severity | What it means | Where it goes | What you do |
|---|---|---|---|
| `info` | FYI signal. Daily collectors completing, budget changes, etc. | `sentinel_alerts` (no email) | Review weekly. |
| `warning` | Approaching a threshold (50% of monthly cap by default). | Email + dashboard | Investigate within 24h. Adjust budget if it's normal usage; investigate workflow if it's a spike. |
| `critical` | Past a threshold (75% by default). | Email + dashboard | Investigate within 4h. If trend continues you'll hit `emergency` mid-month. |
| `emergency` | At auto-pause threshold (90% by default for most services). **All non-essential workflows are paused automatically.** | Email + dashboard | Investigate immediately. Mary's call: raise budget, fix the runaway workflow, or wait for 1st-of-month reset. |

**Alert dedup:** the same service-at-same-severity-this-month produces ONE alert, not six per day. Aggregation key is `cost:<service>:<severity>:<YYYY-MM>`. Sentinel deliberately doesn't spam.

## How to adjust budgets

When you have a week of real spend data, the seed defaults will be wrong. Edit budgets directly in Supabase Studio:

```sql
-- Example: raise Anthropic cap to $500/mo after Claude usage stabilizes
UPDATE sentinel_cost_budgets
   SET monthly_limit_cents = 50000,
       daily_limit_cents   = 2000,
       updated_at          = now()
 WHERE service_name = 'anthropic';
```

**Pattern:** set the warning at the spend level you're comfortable with sustained, critical at where it gets uncomfortable, auto-pause where it'd actually hurt the business. Default is 50/75/90 which is sensible. You can shift to e.g. 70/85/95 for services where you have higher tolerance.

**The `total_platform` cap is the safety net.** Set it ~10% above the sum of the individual caps. If individual services don't blow but the total does (multiple services climbing in concert), this triggers.

## How to acknowledge alerts

Three paths:

**A. Via the dashboard (recommended).** Open `admin.crystallux.org/pages/sentinel.html` → **Alerts** tab → click an alert → Acknowledge or Resolve. The workflow `clx-sentinel-alert-acknowledge-v1` handles it.

**B. Via curl** (admin token in Authorization header):

```bash
TOKEN='<your-admin-session-token>'
ALERT_ID='<uuid>'
curl -X POST https://automation.crystallux.org/webhook/api/sentinel/alert-acknowledge \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"alert_id\":\"$ALERT_ID\",\"action\":\"resolve\",\"notes\":\"Investigated — normal usage spike from new advisor onboarding.\"}"
```

**C. Directly in Supabase Studio:**

```sql
UPDATE sentinel_alerts
   SET status            = 'resolved',
       acknowledged_at   = now(),
       acknowledged_by   = (SELECT id FROM auth_users WHERE email = 'info@crystallux.org'),
       resolved_at       = now(),
       resolution_notes  = 'Investigated — normal usage spike.'
 WHERE id = '<alert-uuid>';
```

## What to do when an emergency alert fires

The auto-pause has already run by the time you read the email. Steps:

1. **Read the email.** It names the service + the % of cap + the auto-pause action taken.
2. **Open `sentinel.html` → Costs tab.** Confirm which workflows were paused (the `Workflow circuit breakers` table shows `current_status = paused`).
3. **Investigate root cause.** Open `agent_decisions` (for Anthropic), `messages_sent` (for Twilio), `video_renders` (for HeyGen) — find the volume spike. Common causes: runaway loop, attack/abuse, legitimate large customer onboarding.
4. **Decide:**
   - If legitimate spike → **raise the budget**, then manually resume workflows: `UPDATE sentinel_workflow_breakers SET current_status='active', paused_at=NULL, paused_reason=NULL WHERE current_status='paused';`
   - If runaway loop → fix the workflow, then resume.
   - If attack → rate-limit the offending source, escalate to security playbook (Phase 3 future; today: block IP at Cloudflare).
   - If you can wait until 1st of month → leave paused. Auto-resume will run at 00:00 on the 1st.
5. **Resolve the alert** so it doesn't keep showing as open.

## Monthly review procedure (1st of every month, 15 min)

Sentinel emails you the monthly report at 00:30 on the 1st. After reading:

1. **Cross-reference with actual vendor invoices** as they arrive. Note any deltas > 10% — usually means a collector needs tuning or a free-tier credit ran out.
2. **Update budgets if needed.** If you stayed under 50% all month, consider lowering the cap (saves auto-pause sensitivity). If you hit critical, raise it.
3. **Review paused workflows.** Auto-resume restored them at 00:00 — verify they're running by 02:00 (most cron workflows fire by then).
4. **Scan `sentinel_alerts` for the past month.**

```sql
SELECT severity, alert_type, count(*) AS occurrences
FROM sentinel_alerts
WHERE triggered_at >= date_trunc('month', now()) - interval '1 month'
  AND triggered_at <  date_trunc('month', now())
GROUP BY severity, alert_type
ORDER BY severity DESC, count(*) DESC;
```

Patterns of alerts in the same category each month = signal to act (raise budget, refactor workflow, restructure usage).

## Troubleshooting

### "No spend data is being recorded"

- Check if the cost collector workflow ran: n8n UI → Executions → filter by workflow.
- Check if the workflow is `active: true`.
- For Anthropic specifically: confirm `agent_decisions` table has rows in the date range. If empty, no Claude calls happened that day — $0 spend is correct.
- For the 5 scaffold collectors: they record $0 by design until you wire vendor compute. **Not a bug.**

### "Workflow auto-paused but I don't know why"

```sql
SELECT b.workflow_id, b.workflow_name, b.paused_at, b.paused_reason,
       a.title, a.message, a.triggered_at
FROM sentinel_workflow_breakers b
LEFT JOIN sentinel_alerts a ON a.aggregation_key = 'breaker:' || b.workflow_id
WHERE b.current_status = 'paused'
ORDER BY b.paused_at DESC;
```

### "Alert email never arrived"

- Confirm `POSTMARK_SERVER_TOKEN` is in `/root/crystallux/n8n/.env` and loaded in the container.
- Check Postmark dashboard for delivery status.
- Verify `sentinel@crystallux.org` is a verified sender in Postmark (or change the From address in `clx-sentinel-alert-router-v1`).
- Check that the alert isn't being dedup'd: `SELECT * FROM sentinel_alerts WHERE aggregation_key = '<key>' ORDER BY triggered_at DESC;` — if there's already an open alert with the same key within the hour, the router returns deduped:true and doesn't email.

### "I want to disable Sentinel temporarily"

Deactivate the 13 workflows in n8n UI. The dashboard still loads (shows last data + placeholders). When you reactivate, collectors resume from the next cron.

## What Sentinel does NOT do (yet)

Honest list of current limits:

- **No real-time cost.** Collectors are daily. The 4h threshold check catches climbs within ~4h of crossing a tier, not instantly.
- **No per-customer cost attribution.** Cost is per-service, not per-customer or per-workflow. Phase 4 adds this.
- **No proactive cost forecasting.** Sentinel reports yesterday + MTD. Projecting month-end requires anomaly-detect + an additional forecaster workflow (future work).
- **No Health monitoring.** Phase 2.
- **No security event detection.** Phase 3.
- **No SOC 2 / PIPEDA dashboard.** Phase 3.

## Cross-references

- [`docs/architecture/SENTINEL_ARCHITECTURE.md`](../architecture/SENTINEL_ARCHITECTURE.md) — full architecture + future-phase extension points.
- [`docs/strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md`](../strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md) §7 + §8 — commercial roadmap (standalone product Year 2+).
- [`docs/handbook/INDEPENDENT_OPERATIONS_GUIDE.md`](INDEPENDENT_OPERATIONS_GUIDE.md) — when to use Sentinel vs Copilot vs Claude Code.
- [`db/migrations/sentinel-foundation-schema.sql`](../../db/migrations/sentinel-foundation-schema.sql) — the schema.
