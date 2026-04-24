# Support Flow — info@crystallux.org

**Purpose:** reliable process for handling client support email. SLA 4 business hours for initial reply. Use Gmail labels until client count hits 5, then graduate to Help Scout or equivalent.

**Principle:** every support touch is a retention signal. Fast, human, specific beats slow, templated, generic.

---

## Auto-responder (first message reply)

Set as Gmail vacation-auto-reply OR a filtered template that fires only on messages tagged "support". First-message-only so we don't spam regular correspondents.

```
Subject: Got your message — Mary

Hi,

Thanks for reaching out to Crystallux. I've received your message and
will respond within 4 business hours (Monday-Friday, 9am-5pm Eastern).

If this is urgent:
- Dashboard issue affecting live sends → reply with "URGENT" in the
  subject and I'll escalate immediately.
- Billing question → [Stripe Customer Portal URL] for account self-serve.
- New client enquiry → book a 20-minute demo: calendly.com/crystallux/discovery

— Mary Akintunde
Founder, Crystallux
info@crystallux.org · crystallux.org
Toronto, Canada · CASL-compliant · PIPEDA-aligned
```

---

## SLA commitments

| Severity | Initial reply | Resolution target |
|---|---|---|
| URGENT (live-send broken) | 1 hour | 4 hours |
| Normal (billing, config) | 4 business hours | 1 business day |
| Feature request | 4 business hours | next release cycle |
| General enquiry | 1 business day | n/a |

Business hours: Monday-Friday, 9:00 AM - 5:00 PM Eastern (Toronto). Messages after 5pm Friday get first-response Monday 9am.

---

## Triage decision tree

Every incoming email gets categorised within the first 60 seconds of reading:

1. **Billing or payment?** → Label `billing` → see §Billing templates below
2. **Technical issue (dashboard broken, outreach not sending)?** → Label `technical` → see §Technical templates
3. **Feature request?** → Label `feature-request` → see §Feature request templates
4. **Account change (add user, change plan)?** → Label `account` → see §Account templates
5. **New client enquiry?** → Label `sales` → reply with Calendly + one-pager
6. **Out of scope (non-Crystallux questions, spam)?** → Label `defer` → see §Out-of-scope

If label is ambiguous, apply the one best-fit and move on. Don't over-classify.

---

## Escalation rules

- **URGENT label** → Mary handles personally, within 1 hour regardless of time
- **Technical** + affects 2+ clients → Mary handles personally, pages contractor if needed
- **Billing dispute > $500** → Mary handles personally
- **Feature request from a founding client** → Mary reviews (product signal)
- Everything else → Mary or VA handles within SLA

---

## Response templates — 10 common issues

### 1. "How do I add a new sender address?"

```
Hi [First Name],

Good question. Email sender addresses are set at the client level
in Crystallux. Two steps:

1. In your dashboard, the Channels Active panel shows which
   addresses are configured. Click the email chip to review.
2. To add a new sender, reply to this email with the address and
   the admin of that inbox should confirm they've granted Gmail
   OAuth delegation to info@crystallux.org. I'll verify and
   activate within one business day.

Heads up: the new address needs to be warmed for 7-14 days before
heavy outbound (deliverability hygiene). I'll run a low-volume
warmup sequence on it before full send.

— Mary
```

### 2. "Why isn't outreach going out?"

```
Hi [First Name],

Let me check on this right now.

Quick questions so I can narrow it down fastest:

1. Approximate date/time you expected sends to go out?
2. Which channel (email / LinkedIn / SMS / voice)?
3. Any error banner visible in the dashboard?

In parallel, I'll check:
- scan_errors for recent failures tagged to your client_id
- channels_enabled for your client row
- Schedule Trigger status for the relevant workflow
- Daily cap counters (we cap to protect sender reputation)

I'll have a specific answer within 2 hours. If it turns out to be
a daily cap or scheduled-window issue, I'll adjust on the spot.

— Mary
```

### 3. "Can you pause my campaigns for [dates]?"

```
Hi [First Name],

No problem — summer/holiday/travel pauses are easy.

Confirming:
- Pause start: [date]
- Pause end: [date]
- Channels affected: all / email only / [specific list]

While paused, we freeze:
- Outbound sends on paused channels
- Your Founding-rate monthly target (so the pause doesn't count
  against your guarantee)

Your data, dashboard access, and reply monitoring stay on. Any
replies that trickle in during the pause land in your dashboard
normally.

I'll confirm activation of the pause by [same-day / next business
day], and automatic resume on [end date] 9am Eastern.

One housekeeping note: your Founding contract includes one free
pause per 12-month cycle (30 or 60 days max). If this is your first
pause, we're good. If it's a second pause in the same year,
standard rate applies during the pause. I'll confirm which applies
in my next reply.

— Mary
```

### 4. "I have a billing question"

```
Hi [First Name],

Happy to help. For fastest resolution:

- **Change card or update business address:** use the Stripe
  Customer Portal link in your welcome email (subject: "Welcome
  to Crystallux — your account is ready"). Self-serve, takes
  under 2 minutes.

- **Invoice question (wrong amount, unexpected tax, etc.):** reply
  with the invoice number and I'll review same-day.

- **Request refund or credit:** reply with details. Our policy is
  no pro-rata refunds for mid-month cancellations, but we issue
  credits case-by-case for service incidents or billing errors.

- **Change plan or tier:** let me know your target plan. Upgrades
  apply from next billing cycle; downgrades require 30-day written
  notice (standard contract terms).

— Mary
```

### 5. "Want to change my plan / upgrade"

```
Hi [First Name],

Great — always good news. Two quick questions:

1. Which tier are you looking at? (Growth Pro / Intelligence /
   add-on channel)
2. When should the change take effect? (next billing cycle is
   fastest; immediate activation is possible with a pro-rated
   adjustment)

For reference, your current plan is [X], and your next billing
date is [Y].

The upgrade takes effect from the next billing cycle unless you
specifically request immediate. In that case Stripe issues a
prorated upgrade invoice for the balance of the current cycle.

No penalty for upgrading; your founding rate lock carries forward
on the tier delta.

— Mary
```

### 6. "Cancel my subscription"

```
Hi [First Name],

Sorry to hear. Before we process, I have to ask one question —
what's the main reason? I won't push back, I just want to know
whether there's something to fix in the product or whether this
is a timing/budget call.

Either way, here's how cancellation works:

- Our contract requires 30 days' written notice. This email
  counts as notice.
- Your cancellation date is [today + 30 days] — service continues
  through that date.
- No refund for the current month, consistent with our
  cancellation policy.
- Your data (leads, outreach history, campaigns) is exported to
  CSV + JSON and delivered within 14 days of your final service
  date. After 90 days post-cancellation, data is deleted per our
  Privacy Policy.
- If you change your mind, your founding rate remains available
  to you for one reactivation attempt within 6 months of cancel
  date.

If you'd like a 15-minute exit-interview call, I'd genuinely
appreciate the feedback. No sales pressure — just trying to learn.

— Mary
```

### 7. "Technical error in dashboard — [error code]"

```
Hi [First Name],

Thanks for the error code. Looking at this right now.

Common errors I've seen and their fix:

- "Could not load data — check your API keys in Settings":
  Supabase session expired, log out and back in. If it repeats,
  your dashboard_token may have rotated — reply and I'll send
  a fresh URL.

- "No data — check your Supabase key in Settings":
  Open Settings in the dashboard and paste your Supabase anon key
  (in your welcome email). I'll re-send the key if needed.

- Specific error code I haven't seen: I'll investigate via
  scan_errors and reply with a fix within 2 hours.

If the dashboard is completely unreachable, that's a P0 — I'll
escalate and update you within 1 hour.

— Mary
```

### 8. "Adding a team member to our account"

```
Hi [First Name],

Yes, we support multiple users per account. Two access levels:

- **Viewer** — can see dashboard, read leads and outreach, no
  editing.
- **Admin** — everything viewers can do, plus edit campaigns,
  approve outreach, change channel settings.

Reply with:
- New user's name
- New user's email address
- Access level (Viewer / Admin)

I'll add them to your client_access_list and email them a
dashboard URL + token within 1 business day.

Note: if this person is at a different business (partner,
referral, etc.), they need their own Crystallux account, not
user access to yours. Their own data is separate.

— Mary
```

### 9. "Change notification settings"

```
Hi [First Name],

Three notification types you can control:

1. **Weekly pipeline summary email** (Mondays 9am). Default on.
2. **New reply alert** (immediately when a qualified reply
   lands). Default on.
3. **Monthly review reminder** (end of month, billing + targets).
   Default on.

To change: reply with which ones to toggle off (or on).

If you want granular per-channel alerts (e.g., "only voice-call
results, not email replies"), let me know — that's a Growth Pro
feature but I can enable case-by-case for founding clients.

— Mary
```

### 10. "Feature request"

```
Hi [First Name],

Thanks — genuinely. Feature requests from founding clients are
how I figure out what to build next.

Captured your request: [summarise the request in one sentence].

Here's how I handle this:

1. I log every request in my product roadmap.
2. Requests from 3+ clients move to the top of the priority stack.
3. If your request matches something already on the roadmap, I'll
   tell you the timeline.
4. If it's novel, I'll reply within 5 business days with either
   "building it in the next 30 days", "building it in Q[N]", or
   "not right for Crystallux — here's why".

Is there a workaround I can offer you in the meantime? Let me
know what specific problem the feature would solve and I'll see
if there's a manual fix available today.

— Mary
```

---

## Resolution + follow-up template

When a ticket closes, send one follow-up 24 hours later:

```
Subject: Re: [original subject] — quick check

Hi [First Name],

Just following up on our thread yesterday about [issue].

Is everything working as expected now? If yes, I'll close this
ticket and you won't hear from me again on it. If there's any
residual issue, reply and we'll reopen.

One quick question if you have 30 seconds: on a 1-5 scale, how
did that support interaction feel?

— Mary
```

Capture 1-5 response, track in a simple log (Notion or Google Sheet) for quarterly review.

---

## Support tools progression

**0-4 clients:** Gmail with labels (`billing`, `technical`, `feature-request`, `account`, `sales`, `urgent`, `defer`). Manual SLA tracking via Google Sheet.

**5-10 clients:** Upgrade to Help Scout (free for 3 users, $20/month per additional). Benefits: shared inbox, SLA tracking automated, saved replies = faster responses, satisfaction ratings built in.

**10-20 clients:** Add Gorgias or Intercom for in-dashboard chat. Budget $50-150/month. Only if email volume exceeds 30/week.

**20+ clients:** First VA handles tier-1 support per `docs/operations/VA_ONBOARDING_RUNBOOK.md`. Escalation to Mary for billing disputes, technical issues affecting 2+ clients, feature requests from founding clients.

Stay in Gmail as long as humanly possible. Tool proliferation is a time sink.
