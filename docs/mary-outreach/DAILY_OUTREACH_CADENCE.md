# Daily Outreach Cadence — Mary's 30-Minute Routine

**Purpose:** the minimum-viable daily rhythm for Crystallux's own outbound. 30 minutes per day, compounding, sustainable, non-negotiable.

**Principle:** 30 minutes every business day beats 3 hours once a week. Compounding activity wins over heroic bursts.

**Outcome target:** 20-30 new discovery calls per month from Mary's own outbound. That's ~$10-25K of new-client MRR potential per month at founding-tier mix.

---

## The 30-minute routine

Every business day. No exceptions except true emergencies. Same time every day — pick a time that fits Mary's energy best (recommended: 8:30-9:00am before client work begins).

### Minutes 0-15 · Morning outreach (activation)

**Goal:** seed new outreach against fresh prospects.

Activities:

1. **LinkedIn connection requests (8 minutes):**
   - Send 15 personalised LinkedIn connection requests using the template from `docs/commercial/COLD_OUTREACH_TEMPLATES.md`
   - Use Sales Navigator to find 15 new prospects from the day's target list
   - Each request: 200-character max, references something specific from the prospect's profile, no pitch in the request itself

2. **Email outreach (7 minutes):**
   - Send 5 personalised first-touch emails (Sequence A, Email 1) from `COLD_OUTREACH_TEMPLATES.md`
   - Use Apollo-sourced email addresses, verify deliverability before sending
   - Customise each email with one specific observation per prospect (90 seconds per email is the target)

### Minutes 15-25 · Follow-ups + replies (retention)

**Goal:** keep warm leads moving through the pipeline.

Activities:

1. **Send follow-ups (6 minutes):**
   - Send any scheduled Sequence A Email 2 or Email 3 that lands today
   - Send LinkedIn messages 2 and 3 on prospects who accepted connection requests 3+ days ago

2. **Reply handling (4 minutes):**
   - Respond to any warm replies that came in overnight
   - Book discovery calls for anyone who asked for more info
   - Update HubSpot deal stage for every movement

### Minutes 25-30 · HubSpot tracking + list maintenance

**Goal:** keep the data clean so next week's prospecting is sharp.

Activities:

- Log every touch made today in HubSpot
- Mark bounced emails for removal
- Note any competitor mentions or pricing pushback captured from replies
- Note any new prospects encountered during reply handling (sometimes a prospect suggests a peer who'd also benefit — add to list)
- Review tomorrow's scheduled follow-ups so they're ready when you sit down

---

## Weekly breakdown

Sustained daily effort produces the following weekly totals:

| Activity | Daily | Weekly |
|---|---:|---:|
| LinkedIn connection requests | 15 | 75 |
| New Email 1 sends | 5 | 25 |
| Email 2 / Email 3 follow-ups | variable | ~10-20 |
| LinkedIn messages 2/3 | variable | ~15-25 |
| Reply handling + bookings | variable | ~8-15 |
| **Total new touches per week** | — | **~100** |

Monthly total: **~400 personalised touches**.

---

## Expected response rates

Based on realistic cold B2B SaaS benchmarks (peer-advisor tone, personalised, Canadian SMB audience):

| Metric | Expected rate | Weekly volume | Monthly volume |
|---|---:|---:|---:|
| Touches sent | — | 100 | 400 |
| Reply rate | 10-15% | 10-15 replies | 40-60 replies |
| Meeting-booked rate (of replies) | 30-50% | 3-7 demos | 12-30 demos |
| Meeting held (show rate) | 70-85% | 2-6 held | 8-25 held |
| Demo → contract conversion | 40-60% | 1-3 signed | 4-15 signed |

### Monthly target

**Baseline realistic:** 20-30 discovery calls booked per month, 4-12 signed clients.

**Optimistic (if copy and targeting are sharp):** 35-50 demos, 10-18 signed clients.

**Below-baseline flag:** if we're getting < 8 replies from 100 touches, the list, copy, or deliverability needs review.

---

## Daily routine guardrails

### Non-negotiables

- **Do the 30 minutes before checking email or Slack.** Starting with reactive work kills the proactive habit.
- **Set a 30-minute timer.** When it rings, stop. Over-running creates resentment toward the routine.
- **Same time every day.** Inconsistency breaks the habit loop.
- **No skipping.** Skipping one day requires two days' recovery. Skipping 3+ days breaks momentum — rebuild takes a week.

### Exceptions (real emergencies only)

- P0 incident requiring immediate technical work
- Family emergency
- Travel day where wifi is not feasible (batch the prior day)

A cancelled client meeting is NOT an emergency. Do the outreach first, then move the meeting.

---

## Batching option (for travel weeks)

If Mary has a travel day or client-heavy day, batch the outreach the day before:

- **Previous evening (45 min):** queue up 2 days' worth of outreach in a scheduler (Boomerang, Mixmax, or n8n's scheduled email feature)
- **Travel day:** only handle replies (5-10 min)
- **Next business day:** resume normal rhythm

Batching is the exception, not the rule. Don't batch more than 2 days at a time.

---

## Monthly review (30 min, last Friday of month)

Add to the WBR monthly retrospective. Specifically for outreach:

- **Total touches this month** vs target (400)
- **Reply rate** — trending up or down?
- **Demos booked** — trending up or down?
- **Signed clients** — trending up or down?
- **Best-performing subject line this month**
- **Worst-performing subject line** (retire it)
- **Best-performing day of week for replies** (adjust send schedule)
- **Best-performing vertical ICP** (expand share of next month's targets)

Use findings to adjust the next month's list + copy.

---

## Copy rotation (anti-template-fatigue)

Every 30 touches to a similar ICP segment, rotate the subject line and opener from the subject-line library in `docs/commercial/COLD_OUTREACH_TEMPLATES.md`. Template fatigue is real — the same subject repeatedly reduces deliverability and reply rate.

Keep a rotation log:

- Week 1-2: Subject A "Renewal season math"
- Week 3-4: Subject B "[City] broker question"
- Week 5-6: Subject C "A note from a fellow Toronto operator"
- Week 7-8: Subject D "The outreach that doesn't sound like outreach"

Track reply rates per subject. After 200 sends on each, keep the top 2, retire the bottom 2.

---

## When to step on the gas vs step off

### Step on the gas (increase volume) when:

- Reply rate holds > 12%
- Conversion rate holds > 40%
- Deliverability (Google Postmaster) is clean
- Crystallux's own team/tooling can handle more inbound demos

### Step off the gas (pause or throttle) when:

- Crystallux platform has a P1/P0 incident (can't credibly sell what's broken)
- Mary's personal bandwidth is saturated beyond 60h/week
- Reply rate drops to < 5% for 2+ weeks (signals deliverability or ICP drift)
- Domain reputation tanks (Gmail start routing to spam)

Gas-off is temporary — usually 5-10 days to recover. Don't quit the routine entirely.

---

## Automation graduation

### Stage 1 (now — 0-3 months): Mary sends manually from Gmail

- Every email sent from info@crystallux.org
- Personalisation is real (not mail-merge)
- Max 40 sends/day to protect Gmail sender reputation
- No sending from additional subdomains yet

### Stage 2 (month 3-6): switch to dedicated outreach tool

- Options: Instantly.ai, Lemlist, or Salesforge
- Requires a warmup period (2 weeks) on the sending domain
- Enables 100-150 sends/day with deliverability safeguards
- Still uses Mary's Claude-authored copy; tool handles delivery only

### Stage 3 (month 6+): full n8n automation

- Build a Crystallux-for-Crystallux workflow using the Crystallux platform itself (self-serve marketing)
- At that point, the outreach is running on Crystallux — the product pitching itself
- Mary's personal 30 minutes stays for LinkedIn + replies; send automation handles volume

---

## When the routine is working, it looks like this

Month 2 snapshot (after 2 months of daily discipline):

- Mary has sent ~800 targeted touches
- ~80-120 replies have come back
- ~25-40 demos have been booked
- ~10-24 clients have signed
- MRR from Mary's own outreach: $15-50K+ (depending on vertical mix)
- HubSpot pipeline has 100+ active deals across stages
- Referrals starting to compound (5+ inbound from existing clients)

When the routine isn't working, the problem is almost always one of: copy quality, target quality, or deliverability. Diagnose in that order.
