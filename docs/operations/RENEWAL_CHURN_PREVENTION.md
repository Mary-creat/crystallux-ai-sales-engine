# Renewal & Churn Prevention

**Purpose:** 90/60/30-day sequence leading up to every client's renewal window. Prevents "surprise cancellations" by making renewal conversations explicit and proactive. Also: downgrade, churn, and reactivation handling.

**Renewal anchor dates:**

- **Founding clients:** 12 months from first paid invoice date
- **Standard clients:** month-to-month auto-renew; renewal conversation at month 12 is informational (rate unchanged unless we raise it globally)
- **Annual-term clients** (future option): 12 months from contract signing

---

## 90-day pre-renewal sequence

All dates are "days before renewal anchor date".

### Day -90 · Schedule QBR

Mary emails the client (or VA on Mary's behalf for month 3+ clients on bi-weekly cadence):

```
Subject: Your Crystallux renewal is 90 days out — let's plan

Hi [First Name],

Quick admin note: your founding contract renews on [date] — 90 days
from today.

Before then, I'd like to do a formal QBR (Quarterly Business Review):
60 minutes, we go deep on the numbers across the full 12 months, talk
about what's working, and plan the next 12.

Calendly link for 30 days from now: [URL]

If any scheduling doesn't work, pick a different date and I'll
accommodate. The QBR is valuable regardless of your renewal decision.

— Mary
```

### Day -60 · Analyze results + prepare data

Mary (or VA) pulls the 12-month client data for the QBR. Specifically:

- **Outreach volume** — total emails / LinkedIn / SMS / voice / video per month
- **Reply rate trend** — monthly reply rate % with trend line
- **Meetings booked** — month by month, target vs actual
- **Meetings taken** — no-show rate
- **Pipeline conversion** — meetings → opportunities → closed-won (if client shares)
- **Revenue attribution** — client-reported $ from Crystallux-sourced deals
- **Support interactions** — number, categories
- **Churn risk scores** — weekly check-in attendance, dashboard logins, payment history

Goal: walk into the QBR with numbers, not opinions.

### Day -30 · QBR + formal renewal conversation

60-minute meeting. First 50 minutes are the standard QBR agenda (see `docs/operations/CLIENT_SUCCESS_PLAYBOOK.md` → Quarterly Business Review). Last 10 minutes are renewal-specific.

#### Renewal discussion section

> "Your founding contract auto-renews on [date] unless you give
> notice. Three conversations to have:
>
> **One: terms.** Your founding rate has been $[X] for the past
> 12 months. Standard rate for your vertical is now $[Y]. Going
> forward you have three options:
>
> (a) Renew at standard rate month-to-month — no lock, $[Y]/mo.
> (b) Renew into a new 12-month founding lock at $[X + minor
>     increase] — founding clients can upgrade their lock once.
> (c) Upgrade to Growth Pro (or Intelligence when launched) for
>     $[Z]/mo, locked 12 months.
>
> **Two: results.** The 12-month data we just reviewed — does
> it justify a renewal?
>
> **Three: what changes next year?** Any new channels, new ICP,
> new territory?"

Listen for signals. Don't push. Most clients land on (b) or (c) if results have been good.

### Day -14 · Confirm renewal intent

If client hasn't responded to the renewal conversation from day -30:

```
Subject: Renewal confirmation — 14 days

Hi [First Name],

Circling back on the renewal conversation from two weeks ago.
Your contract auto-renews on [date] under the terms we discussed
(standard rate month-to-month).

If you want to shift to option (b) or (c) — 12-month lock or
Growth Pro — just reply to this email by [date - 7] and I'll send
an updated agreement.

If you're pausing or ending, same deal — reply with 30 days'
notice per the contract and I'll process.

No reply means option (a) — standard rate month-to-month kicks
in automatically on [date].

— Mary
```

### Day 0 · Renewal activates

One of three outcomes:

- **Auto-renew at standard rate** — Stripe starts charging the new monthly on the renewal date. Send a confirmation email.
- **New founding lock or Growth Pro** — send updated DocuSign agreement, countersign, Stripe subscription-item updated to new Price ID.
- **Cancellation** — process per the Churn handling section below.

---

## Downgrade handling

Signal: client says "I want to stay but not at this price" or "I can't afford the current tier".

### Step 1 — Understand why

> "Totally fair. Before we move on terms, can you tell me what's
> driving it? Is it cash flow, ROI concerns, or did your business
> shift direction?"

The answer determines the right offer:

- **Cash flow short-term** → offer a 30-day pause (1x per 12-month cycle, free) to bridge; continue at current rate after
- **ROI concerns** → review metrics, fix the root cause, propose a 60-day extension at 50% rate if they commit to the fix
- **Business shift** → match them to a cheaper tier that matches new direction (e.g., their growth goals shrank, move from Growth Pro to Founding Standard)

### Step 2 — Match to a cheaper tier

If business shifted, walk through the tier options:

> "Given where you are now, here are two options that fit:
>
> - Drop from Growth Pro to Founding Standard: saves you $1,500/mo.
>   You lose the monthly strategy call and Google review automation.
>   Lead volume stays roughly the same.
>
> - Drop from Founding to Moving/Cleaning pricing (vertical shift):
>   saves $500/mo. Volume adjusts down too.
>
> Which fits?"

### Step 3 — Implement the downgrade

Update Stripe subscription to new Price ID effective next billing cycle. Send confirmation. Keep weekly check-in cadence — downgrade is a retention signal, not a demotion.

---

## Churn handling

Client gives 30-day notice.

### Step 1 — Acknowledge within 4 hours

```
Subject: Re: [client cancellation email]

Hi [First Name],

Got it — cancellation noted. Your service continues through
[last day of current billing period], and your card is not
charged again.

Two asks before you go:

1. **15-minute exit interview?** I'd value the candid feedback
   on what didn't work. Calendly: [URL]. Totally optional.

2. **Testimonial ask:** If any part of Crystallux did work — even
   if the overall fit wasn't right — I'd appreciate a 2-sentence
   note I could use anonymised. No pressure.

Either way, I'll export your data (leads, outreach history, campaigns)
to CSV + JSON and email the package within 14 days. After 90 days
post-cancellation, the data is deleted per our Privacy Policy.

Thanks for trying Crystallux. Best of luck with [whatever's next].

— Mary
```

### Step 2 — Exit interview (if client takes the call)

30 minutes, specific agenda:

1. **What was the primary reason to cancel?** *(open question; don't suggest answers)*
2. **When did you first think about cancelling?** *(identifies the inflection point — usually 21+ days before notice)*
3. **Was there a specific moment that tipped it?**
4. **What would have retained you?** *(Mary listens; doesn't counter-offer)*
5. **Where are you going next?** *(intelligence on competitors / alternatives)*
6. **Would you ever come back?** *(gauges reactivation potential)*

Take notes. Never argue, never defend. Thank them at the end.

### Step 3 — Data export + offboarding

Within 14 days of final service date:

- Export `leads`, `outreach_log`, `outreach_generation_log`, `video_generation_log`, `linkedin_outreach_log`, `whatsapp_outreach_log`, `voice_call_log` for that `client_id` to CSV
- Export campaign configuration as JSON
- Zip, password-protect, email to client's notification email
- Cancel Stripe subscription at end of current period
- Archive client row in Supabase (don't delete — set `archived=true` and `cancelled_at=now()` if we add these fields; otherwise use metadata jsonb)
- Revoke dashboard token

At day 90 post-cancellation: delete personal data per Privacy Policy (send one final confirmation email).

### Step 4 — Internal review

Add the exit-interview findings to a running internal doc (`~/.notes/client-churn-log.md`). Quarterly, review:

- Common churn reasons (tier match? expectation gap? delivery issue?)
- Which signals predicted the churn (often visible 21+ days in advance)
- What we'll change in onboarding, check-ins, or product to prevent similar

---

## Reactivation sequence

Churned clients sometimes come back — especially if the issue was timing (wrong season, wrong quarter, wrong cash position) rather than fit.

### Reactivation touch schedule

Light-touch, no-sell:

- **Month 3 post-churn** — a single email sharing a useful industry insight (no Crystallux pitch)
- **Month 6 post-churn** — "Where are you at?" email, genuinely curious, no sell. Offers a no-commitment 20-minute catch-up call.
- **Month 12 post-churn** — "Year since we wrapped. Things changed at Crystallux — here's a 2-minute update. Interested?" With a specific product update hook (e.g., new channel, new vertical active)

### Month-3 email template

```
Subject: Saw this and thought of you

Hi [First Name],

Not pitching — genuinely. Saw [specific industry insight or
article relevant to their business] and you came to mind.

No Crystallux angle in this email. Just a check-in. If there's
anything I can help you with (intro to someone in my network,
a question you're working through), let me know.

— Mary
```

### Month-6 email template

```
Subject: 6 months in — how's it going?

Hi [First Name],

Checking in since we wrapped in [month]. Not pitching, promise.

How's the business? What did you end up doing for pipeline
after Crystallux?

If you want a 20-minute catch-up call — not a sales pitch, just
a chat — here's my calendar: [URL]. Or just reply with what's
new.

— Mary
```

### Month-12 email template

```
Subject: A year later — some Crystallux updates you might find interesting

Hi [First Name],

A year since we wrapped. Thought I'd share what's changed at
Crystallux, in case any of it changes the math for you:

- [specific product update 1 — e.g., "we added video outreach
  via Tavus, which has been a big lift for [vertical]"]
- [specific product update 2 — e.g., "pricing stayed the same
  for founding clients returning"]
- [specific proof point — e.g., "our case studies page now has
  three real-number stories from [vertical] clients"]

Reactivation offer if you're ever curious: 20% off your first
month back if you return within 60 days of this email. Founding
rate still honoured.

Either way, hope the business is well.

— Mary
```

### Reactivation terms

If the client re-engages:

- **Within 60 days of first reactivation touch:** 20% off first month back; founding rate honoured
- **Within 12 months of churn:** founding rate honoured, no discount
- **12+ months after churn:** current standard rate; no founding rate available

Apply the discount via a Stripe coupon, not by adjusting the subscription price.

---

## Reactivation metrics to watch

Over a 12-month window post-churn:

- **Reactivation rate** — % of churned clients who return. Target: 15-25% over 12 months. Below 15% = exit-interview findings aren't being incorporated.
- **Reactivation LTV** — average revenue from returned clients. Often higher than first-time LTV because they know the product.
- **Lag to reactivation** — median days from churn to re-signing. Useful for timing the reactivation touches.

Review quarterly with churn-log review.
