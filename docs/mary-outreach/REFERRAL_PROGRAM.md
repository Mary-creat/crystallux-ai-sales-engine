# Referral Program — Client-Driven Growth

**Purpose:** formal structure for clients referring new business. Referrals close at 3-5× the rate of cold outreach and carry a 2-3× higher LTV. This is the cheapest channel Crystallux has.

**Target:** 30% of new clients from referrals by month 6.

---

## The offer

### Primary offer — "Refer a client, get a month free"

**For referring clients:**
- Refer a business that becomes a Crystallux founding client (signs a contract + makes first payment)
- Get **one month of your current subscription free** — applied as a Stripe credit against your next invoice
- No cap on total referrals; each qualified referral = one free month

**For the referred business:**
- Mention the referring client during their discovery call or in their sign-up email
- Get **a $200 CAD credit** on their first invoice (small symbolic gesture; it's not a discount big enough to incentivise bad-fit referrals)
- Standard founding rate applies (no discount on the base subscription)

### Compound incentive — "Refer 3+ successful closes"

If a client refers 3 or more businesses that become paying Crystallux clients within a 12-month window:

- All three months free as outlined above
- **Plus: 20% lifetime discount** on the referring client's current plan, starting with their next billing cycle

This is the advocate-level incentive. Designed to reward the 2-3 clients who become genuine word-of-mouth engines.

---

## How clients introduce

Three friction levels, picked by the client based on their comfort:

### Option 1 — Client makes the warm intro directly

Client forwards an email Crystallux has provided them. We give them a template they can customise or send as-is.

**Template for clients to forward:**

```
Subject: A quick intro — Crystallux for [their vertical]

Hi [Their contact],

Jumping on two threads briefly.

[Their contact], meet Mary Akintunde, founder of Crystallux.
Mary's been running my lead-generation pipeline for the last
[N] months and I owe her most of the growth I've hit this year.

Mary, meet [Their contact]. [1-2 sentences on who this person is
and why Mary should care — their vertical, their pain, why the
intro makes sense.]

Sharing because I genuinely think Crystallux could help —
zero obligation on either side. If it's a fit, Mary will take
it from there.

— [Their name]
```

This is the highest-quality referral path. Converts at 50-70%.

### Option 2 — Client drops a name, Crystallux does cold outreach

Client sends an email to info@crystallux.org with:
- The name and LinkedIn URL (or email) of the potential referral
- One sentence on why they came to mind
- Whether the client wants their name mentioned in the cold outreach or not

Crystallux does a cold-outreach touch but references the client's recommendation:

```
Subject: [Referring client] thought we should talk

Hi [Prospect First Name],

[Referring client] at [their business] mentioned you might be
running into the same outreach-pipeline problem they were.
They've been using Crystallux for the last [N] months and
thought a quick intro made sense.

Short version: Crystallux runs outbound pipeline for Canadian
operators. 20 qualified meetings a month, founding rate locked
for 12 months, CASL compliant.

If you'd like 20 minutes to see if the fit is there, here's my
calendar: [Calendly URL]

If not, totally respected. [Referring client] suggested you
because they think highly of what you're doing — not the other
way around.

— Mary
Founder, Crystallux
info@crystallux.org

PS: [Referring client] is getting a free month if we end up
working together. Total transparency.
```

Converts at 20-30% (still much higher than cold).

### Option 3 — Client posts a referral ask on LinkedIn

Client writes a LinkedIn post thanking Crystallux and tagging Mary's personal profile (`@Mary Akintunde`). The post itself becomes a referral signal to their connections.

Crystallux provides:
- Template copy clients can use (optional — most write their own if they're genuinely happy)
- Permission to share the post from Crystallux's company page (amplifies reach)

Converts at 10-15% of audience-click-throughs, which is actually strong for LinkedIn.

---

## Tracking — Stripe billing migration addendum

### Required database column (add to `clients` table)

The Stripe billing migration `2026-04-23-stripe-billing.sql` currently doesn't include a referral field. When this program goes live, add:

```sql
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS referred_by uuid REFERENCES clients(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_clients_referred_by
  ON clients(referred_by) WHERE referred_by IS NOT NULL;
```

Bundle into a small follow-up migration (`2026-04-24-referrals.sql`) — keep it its own file so it can be applied atomically when the referral program is ready.

### Tracking fields on new client onboarding

When Mary onboards a new client:

1. Ask during the onboarding call: "Did someone refer you?" If yes, capture the referring client's name.
2. Find the referring client's `clients.id` in Supabase.
3. Set `new_client.referred_by = referring_client_id` in the Supabase INSERT.
4. Flag the referring client for free-month credit (see below).

### Applying the free-month credit

When a referred client's first Stripe payment clears (`invoice.paid` event received):

1. `clx-stripe-webhook-v1` detects the paid invoice for the referred client
2. Human step (Mary): check if the paying client has `referred_by` populated
3. If yes: manually apply a Stripe coupon for 100% off one month to the referring client's subscription

Automate this step in `clx-stripe-webhook-v1` once the referral program volume justifies it (3+ active referrals per month). Until then, the manual step is fine.

### Monthly referral log

Track in Notion or Google Sheet:

| Referring client | Referred client | Date referral made | Date referred client signed | Free month applied? |
|---|---|---|---|---|

Review monthly to:
- Identify top referrers (candidates for compound incentive)
- Spot stalled referrals (made but not signed within 60 days — maybe needs a follow-up from Mary)
- Calculate referral-sourced MRR vs total MRR

---

## How to introduce the program to clients

**When:** during the month 2 weekly check-in (after the first-30-day guarantee has been met). Not before — don't ask for referrals until the client has experienced the product's value.

**Script:**

```
"Before we wrap, one ask: if you've been happy with what we've
built so far, would you be open to introducing me to one other
[broker/contractor/consultant] you think would benefit?

No pressure — genuinely. But I want to name the program explicitly:
every successful referral = one month of your subscription free.
Three successful referrals in a year = 20% off your plan for the
lifetime of your subscription.

Easiest way: you think of a name, I send you a template email
you can forward or customise. Or you just drop the name and I do
the outreach cold. Either way works."
```

Listen for the answer. Don't push.

### Do NOT ask for referrals when:

- Client is at a monthly target miss
- Client recently escalated a support ticket or incident
- Client is in a billing dispute
- Client is in the first 30 days (too early; no proof yet)

Ask when the client is happy. Don't ask when they're neutral or unhappy.

---

## Compound incentive activation (for top referrers)

When a client refers 3 successful closes within a 12-month window:

1. Mary personally emails the client:

```
Subject: You just hit the compound incentive

Hi [First Name],

Quick note of gratitude — you've now referred 3 businesses to
Crystallux that have signed as paying clients. That's a serious
advocacy vote and I want to honour it.

Activating the compound incentive:

— All three free months already credited to your Stripe account
— 20% off your current plan, permanently, starting your next
  billing cycle
— New effective rate: $[X]/mo instead of $[Y]/mo, for as long
  as your subscription stays active

No catch. No renewal requirement. It's yours.

If you're open to it, I'd love to do a 30-minute founder-to-founder
call — partly to thank you properly, partly to hear how Crystallux
could be even more useful for you.

— Mary
```

2. Update Stripe subscription with a 20% coupon.
3. Log in the referral tracker.
4. Flag the client as "advocate" in HubSpot — these are candidates for case studies, advisory board, beta-testing programs.

---

## Anti-abuse safeguards

Referral programs can be gamed. Simple rules prevent the common abuse cases:

- **One free month per referral.** Not per month; not per year. Hard cap.
- **Referred client must stay 60 days** before the free month is applied (prevents churn-game where someone signs a fake client and immediately cancels).
- **Referred client cannot be the same person/business under a different LLC** — Mary manually checks before awarding credits.
- **Referred client must be a new prospect**, not a reactivation of a past Crystallux client.
- **Client referring the client must have an active paying subscription** for the free-month credit to activate.
- **Self-referral is disqualifying.** Can't refer yourself to another subscription.

Document any edge-case adjudication in the referral tracker for future consistency.

---

## Program review cadence

### Monthly

- Count of new referral intros made
- Count of referrals converting to signed clients
- Referral-sourced MRR as % of total new MRR
- Free-month credits applied

### Quarterly

- Referral-sourced clients' retention vs cold-sourced — are referrals stickier?
- Referral-sourced clients' LTV vs cold-sourced
- Top 3 referrers and their impact

Adjust the program based on data:

- If referral conversion rate > 60%, program is working — pour on more promotion
- If compound incentive activation is rare, the program threshold may be too high — consider lowering to 2 referrals instead of 3
- If abuse cases are emerging, tighten safeguards

---

## What NOT to build (right now)

- **Formal referral landing page with automated tracking.** Premature. The warmth of the direct-email flow is the magic; a landing page kills it. Build only after manual volume > 10 referrals/month.
- **Public "Refer a friend" widget on crystallux.org.** Too consumer-y. Crystallux is B2B; referrals here are relationship-driven.
- **Multi-tier affiliate program (commissioned partners, agencies, etc.).** Defer until year 2. Current program is founder-to-founder, which matches the peer-advisor product voice.
- **Automated reminder emails asking existing clients to refer.** Annoying. Let Mary ask in person at the right moment.
