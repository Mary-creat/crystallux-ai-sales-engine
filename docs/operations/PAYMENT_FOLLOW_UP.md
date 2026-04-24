# Payment Follow-Up — Failed Payment Recovery

**Purpose:** deterministic sequence for handling failed Stripe payments. Most failures are cosmetic (expired card, wrong CVV); a few are early churn signals. Sequence distinguishes them.

**Trigger:** `STRIPE_PAYMENT_FAILED` event posted to `clx-stripe-webhook-v1`. Event writes to `stripe_events_log` + emits a monitoring alert to `scan_errors` per `2026-04-23-stripe-billing.sql` seed.

---

## Sequence at a glance

| Day | Action | Owner | Stripe status |
|---:|---|---|---|
| **0** | Automatic Stripe retry + first email | Automated | past_due |
| **3** | SMS + second email | Automated + Mary | past_due |
| **7** | Mary personal call + email | Mary | past_due |
| **14** | Service pause notification + final retry | Mary | past_due |
| **30** | Cancellation + save attempt | Mary | canceled |

---

## Day 0 — failed payment

### Stripe auto-retry settings

Configure Stripe → Settings → Subscriptions → **Smart Retries**:

- Enabled
- Retry 3 times over 7 days (Stripe picks optimal days based on ML)
- Cancel subscription after 1 week of failure
- Send customer email from Stripe (off — we send our own branded emails)

### Day-0 email template (automated — triggered by webhook)

Fires when `invoice.payment_failed` lands. Sent via `clx-stripe-webhook-v1` or dashboard alert.

```
Subject: Payment issue on your Crystallux account

Hi [First Name],

Heads up — your monthly Crystallux payment didn't go through today.

Most of the time this is a card issue (expired, wrong CVV,
insufficient funds). Usually takes 2 minutes to fix:

**Update your card:** [Stripe Customer Portal URL]

Stripe will automatically retry the payment once you update. If
everything clears, your service continues uninterrupted.

If there's something else going on — cash-flow issue, billing
question, you want to pause for a month — just reply to this
email. No judgement.

— Mary
Crystallux · info@crystallux.org

---
This is an automated alert. Your subscription is currently in
"past_due" status in Stripe. Please take action within 7 days to
avoid service interruption.
```

---

## Day 3 — second failed retry

If the first retry failed and no customer action:

### SMS (if mobile on file)

```
Hi [First Name] — quick nudge. Your Crystallux payment
hasn't cleared yet. Update card: [short Stripe URL].
Reply if there's an issue. — Mary
```

Character count: 140.

### Email template

```
Subject: Second try on Crystallux payment

Hi [First Name],

Following up — Stripe tried your card again and it still didn't
go through.

Update your card in 2 minutes: [Stripe Customer Portal URL]

If your business is having a cash-flow moment, reply and let's
figure out a workable option. One free pause per year is part of
your founding contract — we can freeze your account for 30 or
60 days if that helps.

If this is a timing thing (card in transit, bank issue), totally
fine — just reply to let me know when to expect payment to clear.

— Mary
```

---

## Day 7 — Mary personal outreach

If two retries failed and no customer response:

### Call

Call the client's primary phone number (if known). 30-second voicemail if no pickup:

```
"Hi [First Name], Mary from Crystallux. Your monthly payment
hasn't cleared yet — just checking in to make sure everything's
okay. If it's a card issue we can fix in 2 minutes through
the portal link I've emailed. If there's something else going on
I'd rather talk it through than have the account go into
suspension next week.

Call me back at 416-***-**** or reply to my email. Thanks
[First Name]."
```

### Email (same day, whether call connects or not)

```
Subject: Quick call on your Crystallux account

Hi [First Name],

Left you a voicemail — wanted to follow up in writing too.

Your payment hasn't cleared in the last two retries. Before the
account goes into suspension next week, I'd rather just talk —
make sure I understand what's going on.

Three paths forward:

1. **It's a card issue.** Fixed in 2 minutes: [Stripe Portal URL]
2. **Cash flow crunch.** Founding pause option available (30 or
   60 days, free, one per year). Reply and I'll process.
3. **You're rethinking the service.** Totally fair — let's talk.
   No hard sell, just want to understand.

Reply or call: [Mary's phone]

— Mary
```

---

## Day 14 — service pause notification

If all previous outreach has been ignored:

### Email (service paused)

```
Subject: Your Crystallux account is being paused

Hi [First Name],

Following up on my previous emails and voicemail — your payment
hasn't cleared and I haven't heard back. As of today, your
Crystallux campaigns are paused.

**What this means:**
- No new outreach sends from your account
- Dashboard is still accessible (read-only)
- Leads and outreach history preserved
- Your Calendly bookings (if any) continue landing in your inbox

**What you can do:**

1. **Resolve the payment.** Update your card in the portal:
   [Stripe Customer Portal URL]. Campaigns resume within 2 hours.

2. **Cancel.** Reply with "cancel my account" and I'll process
   per our 30-day notice terms.

3. **Talk.** Reply with any question or context. I'd rather
   understand than assume.

If I don't hear from you by [day 30], the account auto-cancels
and I'll export your data per our standard offboarding.

— Mary
```

At this point: manually pause the client via `UPDATE clients SET subscription_status='past_due' WHERE id = '<uuid>';` and set `channels_enabled=[]` temporarily to prevent any further sends.

---

## Day 30 — cancellation + save attempt

If 30 days have passed with no response:

### Cancellation email

```
Subject: Crystallux account closed — save offer inside

Hi [First Name],

It's been 30 days with no payment and no response, so your
Crystallux account has been closed per our contract terms.

A few housekeeping items:

- Final invoice is zero (no unpaid balance)
- Your data export (leads, outreach, campaigns) is attached as
  CSV + JSON
- Dashboard access is revoked
- All active campaigns are stopped

**Reactivation offer, good for 60 days:**

If you come back within the next 60 days, I'll honour your founding
rate and apply 20% off your first month. The offer covers any
resurrection of the same client account — we pick up where we
left off, same data, same campaigns.

After 60 days, standard rate applies for any reactivation.

Genuinely best of luck with the business, [First Name].

— Mary

---
Account closure details:
- Close date: [date]
- Stripe subscription: canceled
- Data retention window: 90 days, then deletion
- Reactivation offer expires: [close date + 60 days]
```

---

## Data logging for every failed payment

Keep a simple log (Google Sheet, or `stripe_events_log` query) of every failed payment event. Columns:

- Client name
- Client UUID
- Stripe invoice ID
- Failure date
- Failure reason (from Stripe: `card_declined`, `expired_card`, `insufficient_funds`, etc.)
- Resolution date (if recovered)
- Resolution action (card updated, pause applied, cancelled)
- Recovery window (days from failure to resolution)

Review quarterly:

- **Median recovery window** — target ≤3 days
- **% recovered in 7 days** — target ≥80%
- **% cancelled due to non-payment** — target ≤5% of all cancellations
- **Most common failure reason** — if "expired card" dominates, update the pre-expiry reminder cadence

---

## Pre-expiry proactive reminder

Separate from failure recovery: Stripe marks cards expiring within 30 days. Run a weekly job:

```sql
SELECT id, client_name, stripe_customer_id, notification_email
FROM clients
WHERE subscription_status = 'active'
  AND stripe_customer_id IN (
    -- Stripe API call: customers with cards expiring in next 30 days
    SELECT stripe_customer_id FROM stripe_card_expiry_upcoming
  );
```

Send:

```
Subject: Your card on file expires soon

Hi [First Name],

Admin note: the card on file for your Crystallux account expires
[month]. If you've already updated your bank's records, just
update the card in the portal so your service continues
uninterrupted:

[Stripe Customer Portal URL]

Takes 1 minute. No action needed if your new card uses the
same 16-digit number (rare but happens).

— Mary
```

Prevents ~60% of preventable payment failures.

---

## Reactivation after payment failure

If a churned-for-non-payment client returns within 60 days:

- Apply the 20% first-month-back discount via Stripe coupon
- Restore their client_id, vertical, channels_enabled from the archived row
- Resume their dashboard URL with a fresh token
- Pick up where campaigns left off (same ICP, same copy, same pipeline state)
- Send a brief welcome-back email: "Campaigns resuming this week. First outreach send is back on schedule."

After 60 days: treat as a new client onboarding (new founding window if available, new onboarding call, fresh ICP).
