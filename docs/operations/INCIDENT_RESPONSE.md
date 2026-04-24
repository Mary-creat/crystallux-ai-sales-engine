# Incident Response

**Purpose:** clear severity definitions, response SLAs, communication templates, and post-mortem structure for when Crystallux breaks at scale.

**Principle:** fast, specific communication beats slow, polished communication. Tell clients what happened, what you're doing, when it'll be fixed. No corporate-speak.

---

## Severity levels

### P0 — Platform down for all clients

**Definition:** Supabase down, Gmail OAuth failure across all clients, dashboard unreachable, workflow engine offline.

**Response SLA:** 1 hour initial response, 4 hours resolution target.

**Communication:** broadcast email to all active clients + status page update + LinkedIn announcement if downtime exceeds 2 hours.

**On-call:** Mary personally, until there's a hired on-call. Mobile always reachable.

### P1 — Feature broken for multiple clients

**Definition:** specific channel down (e.g., LinkedIn sends failing for all clients), billing workflow broken, specific migration issue affecting data integrity.

**Response SLA:** 4 hours initial response, same-day resolution.

**Communication:** email to affected clients only + internal incident log.

**On-call:** Mary, contractor backup via paid on-call contract (future hire).

### P2 — Single client issue

**Definition:** one client's outreach blocked, one client's dashboard login failing, one client's billing charge issue.

**Response SLA:** 1 business day initial response, 2 business day resolution.

**Communication:** individual email to the affected client. No broadcast.

**On-call:** Mary during business hours; VA during off-hours if escalation protocol allows.

### P3 — Cosmetic or minor issue

**Definition:** display bug, non-blocking dashboard glitch, typo, minor UX issue, feature request disguised as a bug.

**Response SLA:** acknowledge within 1 business day, fix in next release cycle (1-2 weeks).

**Communication:** individual email only if reported by a client.

---

## Communication templates per severity

### P0 — broadcast email (all active clients)

```
Subject: Crystallux service incident — in progress

Hi [First Name],

I'm writing to let you know Crystallux is currently experiencing
a platform-wide service incident.

**What's happening:** [specific description — e.g., "our Supabase
database provider is experiencing a regional outage affecting
all clients in the us-east-1 region, which is where Crystallux
is hosted"]

**What's affected:** [list — e.g., "dashboard access, new
outreach sends, reply ingestion"]

**What's NOT affected:** [list — e.g., "historical data is safe,
no loss of campaigns or leads, Stripe billing is unaffected"]

**Current status:** [e.g., "Supabase has acknowledged the issue.
Estimated time to resolution: 2 hours. I'm monitoring and will
update you in 45 minutes regardless of status"]

**What you should do:** nothing. I'll send an all-clear when
service resumes. If you need to reach a prospect urgently, use
your own email directly — Crystallux data is safe, it just
isn't accessible right now.

Apologies for the disruption. I'll follow up within 45 minutes
with a status update.

— Mary
info@crystallux.org · crystallux.org/status
```

### P0 — all-clear email

```
Subject: Crystallux is back — brief summary

Hi [First Name],

Crystallux service is fully restored as of [time].

**Total downtime:** [duration]
**Root cause:** [one-sentence explanation, no jargon]
**Fix applied:** [one-sentence description]
**Prevention:** [one-sentence commitment on what we're doing
to reduce recurrence]

Outreach that was queued during the incident has resumed and
should fully catch up within [timeframe].

A formal post-mortem will land in your inbox within 5 business
days, and I'll credit your account [credit amount] for the
disruption.

Thanks for your patience.

— Mary
```

### P1 — affected-clients email

```
Subject: Crystallux update — [specific feature] issue

Hi [First Name],

A heads up: we're seeing an issue with [specific feature — e.g.,
"LinkedIn outreach sends via Unipile"] that affects your account.

**What's happening:** [brief description]
**Impact on your campaigns:** [specific — e.g., "LinkedIn sends
for this week are paused. Email and voice channels are
unaffected"]
**ETA:** [e.g., "resolved within 4 hours"]

I'll update you when we're clear. If you have urgent sends that
can't wait, reply and we'll find a workaround.

— Mary
```

### P2 — individual client email

```
Subject: Investigating the issue you flagged

Hi [First Name],

Thanks for flagging this. I'm looking at it now.

**What I'm investigating:** [rephrase their issue so they see
you understood it]

**ETA:** by [specific time — e.g., "end of business tomorrow"]

If I need any additional info from you (screenshots, exact time
the issue happened, etc.), I'll ask within the next 2 hours.
Otherwise expect a resolution email by the ETA above.

— Mary
```

---

## Post-mortem template

Published within 5 business days of any P0 or P1 incident. Sent to all affected clients + internal log + status page.

```
# Post-Mortem: [Incident Name]

**Date:** [date of incident]
**Severity:** [P0 / P1]
**Duration:** [total downtime / degradation window]
**Affected clients:** [count or list]

## What happened

[2-3 paragraphs, in plain language. No jargon. What the user
experienced, not just what failed internally.]

## Timeline

- [time] — incident begins (from the dashboard / alert)
- [time] — Mary notified / alert triggered
- [time] — investigation begins
- [time] — root cause identified
- [time] — fix deployed
- [time] — validation that fix worked
- [time] — all-clear communicated

## Root cause

[One paragraph. What underlying issue caused the incident. Not "a
bug" — specific. E.g., "the rate limiter on the Apollo enrichment
workflow had a typo in the cap calculation, which meant the cap
was applied only to the first lead in a batch instead of the whole
batch."]

## Impact

- [Client count affected]
- [Hours of service loss per client]
- [Missed outreach volume, if relevant]
- [Financial impact: credits issued, refunds if any]

## Fix applied

[Specific: what code / config / data was changed.]

## Prevention measures

1. [Specific engineering change to prevent recurrence]
2. [Monitoring improvement — alert added, threshold tuned]
3. [Runbook update — documented the fix for future reference]

## What we learned

[1 short paragraph — the meta-lesson, not just the fix.]

## Credits

Clients affected by this incident will see a [credit amount]
adjustment on their next invoice. No action required on your end.

— Mary
Crystallux · info@crystallux.org
```

---

## Status page setup

### Option 1 — Statuspage.io free tier (recommended)

- Sign up: statuspage.io
- Free for up to 5 clients reading; enough for first 6 months
- Components: Dashboard, Outreach Engine, Reply Ingestion, Billing, Channel Integrations (one per channel), Database
- Update status within 15 minutes of incident detection
- Auto-posts to Twitter and embeds on status.crystallux.org (configurable subdomain)

### Option 2 — Simple HTML status page

If statuspage.io is deferred, build a minimum-viable status.crystallux.org page:

- Single HTML file hosted on GitHub Pages or Netlify free tier
- Four sections: Platform, Channels, Billing, Data
- Each with current status (green / yellow / red) and 24-hour timeline
- Mary updates manually via git commit

**Decision:** deploy Option 1 within 30 days of first client onboarded. Option 2 as temporary measure.

### Status page link in every client comms

Add `crystallux.org/status` to every email signature and the support auto-responder.

---

## On-call rotation

### Current state (Mary solo)

- Mary is 24/7 primary for the first 10 clients
- P0/P1 alerts page Mary via:
  - Slack webhook → Mary's phone push notification
  - Email alert (backup)
  - SMS via Twilio webhook (backup)
- Mary's phone on the nightstand; 1-hour response SLA holds 24/7
- Weekends covered; no "I'm off duty" without explicit communication to clients

### Mid-scale (10-25 clients, likely month 2-3)

- Technical contractor hired for 10-15 hours/week
- Weekend rotation: Mary + contractor alternate weekends
- Weekday business hours: Mary primary
- Weekday after-hours: contractor primary for technical incidents; Mary for client comms

### Late (25+ clients)

- Full-time engineer (in-house or dedicated contractor)
- Two-person rotation: Mary + engineer
- 24/7 coverage with hard SLA

### Alerting setup

- `clx-error-monitor-v1` sends Slack alerts on scan_errors threshold breaches
- Supabase status page integration (future) auto-flags provider incidents
- Stripe incident mailing list subscription
- Gmail API status alerts via Google Cloud status page

---

## Incident drill cadence

Quarterly, Mary runs a simulated incident drill:

1. Pick a P0 scenario (e.g., "pretend Supabase is down")
2. Time the response: how fast did I detect? How fast did I communicate?
3. Critique the post-mortem draft
4. Identify gaps in monitoring / runbooks
5. Implement fixes within 2 weeks

This stays on the quarterly calendar even when there's been no real incident. The muscle memory matters more than the specific drill.
