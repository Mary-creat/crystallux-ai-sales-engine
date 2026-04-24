# Client Success Playbook — Retention by Milestone

**Purpose:** proactive intervention schedule to keep clients on-pace and catch churn signals before they escalate. Every active Crystallux client has a milestone-based lifecycle; this file is the reference.

**Principle:** churn is preventable. The signal window is 14-21 days before cancellation in most cases. Intervene early, specifically, in person when possible.

---

## Milestones by lifecycle stage

### Week 1 milestones

| Milestone | Target | Action if missed |
|---|---|---|
| First outreach sent | Day 5 | Investigate: channel not activated? Dashboard blocker? |
| First reply received | Day 7 | If no reply by day 10, review copy, widen ICP, send second batch |
| First draft-review session with client | Day 4 | Book 10-minute call to walk through drafts |

### Week 2 milestones

| Milestone | Target | Action if missed |
|---|---|---|
| First meeting booked | Day 10 | Review reply quality — are prospects interested but not converting? Adjust copy asking for meeting. |
| First bilateral conversation (reply → meeting held) | Day 14 | Investigate no-show rate; tune Calendly reminders |
| Client has logged into dashboard 3+ times | Week 2 | If dashboard dormant, email a snapshot + prompt a login |

### Month 1 milestones

| Milestone | Target | Action if missed |
|---|---|---|
| 10 qualified meetings booked (or vertical-specific target) | Day 30 | Triggers guarantee clause — next month free, communicate proactively |
| First discovery call taken by client | Week 3 | Ensure Calendly working, time slots aren't clustered, client actually shows up |
| First "I'd recommend this" signal | Week 4 | Ask for testimonial (see `docs/commercial/TESTIMONIAL_COLLECTION.md`) |

### Month 3 milestones

| Milestone | Target | Action if missed |
|---|---|---|
| Full pipeline running | Month 2-3 | Triggers renewal discussion; pipeline metrics stable, upsell eligible |
| First deal closed from Crystallux pipeline | Month 2 | If no deal by month 3, review ICP + conversion — is the problem our leads or client's close rate? |
| Channel expansion consideration | Month 3 | Mary proposes LinkedIn or video add-on based on reply patterns |
| Quarterly Business Review (QBR) | Month 3 | Formal 45-minute review; deeper than weekly |

### Month 6 milestone

- Renewal conversation kicked off (see `docs/operations/RENEWAL_CHURN_PREVENTION.md`)
- Testimonial/case study refreshed if client has been showcased before
- Channel mix review — drop low-performers, add high-performers

### Month 12 milestone

- Founding rate transition conversation (moving to standard rate or renewing under new founding lock)
- Intelligence tier upsell discussion (if available)
- Second case study with 12-month results published

---

## Early warning signs of churn

Catch these signals in weekly check-ins and dashboard reviews:

### 1. Decrease in reply rate vs baseline

**Signal:** Reply rate drops 30%+ from the client's trailing 4-week average.

**Likely causes:** deliverability issue (domain reputation), ICP drift, copy stale, saturating the target pool.

**Intervention:**
- Within 24 hours: investigate via scan_errors + Google Postmaster Tools
- Within 48 hours: report findings to client, propose fix
- Within 7 days: implement fix, show result in next weekly check-in

### 2. Missed weekly calls 2+ times

**Signal:** Client cancels or skips 2 weekly check-ins in a rolling 3-week period.

**Likely causes:** disengagement, over-committed, results not compelling enough to prioritise the call.

**Intervention:**
- After 2nd skip: Mary sends personal email, not VA. "Want to make sure everything's working — got 10 minutes this week?"
- After 3rd skip: Mary calls the client by phone. No email.
- If client unreachable for 10+ days: flag as high-risk, review before day 14

### 3. Client silence on follow-ups

**Signal:** No response to weekly recap emails for 2+ weeks.

**Likely causes:** email-fatigue, inbox chaos, disengaged.

**Intervention:**
- Week 3 of silence: send a single-sentence email: "Any blockers I should know about?"
- If no response in 5 business days: escalate per Missed weekly calls above

### 4. Billing delays

**Signal:** Stripe payment fails, client takes 5+ days to update card, or repeated `STRIPE_PAYMENT_FAILED` within a quarter.

**Likely causes:** cash flow issues, subscription de-prioritisation, pre-churn stall.

**Intervention:** see `docs/operations/PAYMENT_FOLLOW_UP.md` — specific day-0/day-3/day-7/day-14 sequence.

### 5. Feature request escalations

**Signal:** Client asks for 3+ features in one week, or a single very specific request with emotional language ("we really need this").

**Likely causes:** feature requests often mask underlying dissatisfaction with current results — "if only we had X, then it would work."

**Intervention:**
- Take the request seriously; log it
- But also: use the weekly check-in to dig into the underlying metric. Usually the feature is a symptom; the problem is elsewhere
- Propose a workaround if possible; commit to a timeline on the feature

### 6. Slow dashboard engagement

**Signal:** Client hasn't logged into dashboard for 14+ days (check via Supabase auth logs).

**Likely causes:** dashboard not solving a problem for them, results dashboard-less, forgot it exists.

**Intervention:**
- Send a week-in-review email with key numbers + dashboard URL
- If still no login within 7 days: schedule a 15-minute "dashboard refresher" call

### 7. Calendly no-shows from Crystallux-booked meetings

**Signal:** Client has 30%+ no-show rate on meetings that Crystallux outreach booked.

**Likely causes:** either the outreach is setting unclear expectations, or the client's Calendly auto-reminders aren't working.

**Intervention:**
- Review outreach copy for the meeting-asks
- Check client's Calendly reminder settings
- Propose a pre-meeting follow-up email 24h before each meeting

### 8. Competitor mention

**Signal:** Client mentions a competitor's tool or agency during a check-in ("I saw X is doing this…").

**Likely causes:** they're evaluating alternatives — not yet cancelled, but on the fence.

**Intervention:**
- Don't dismiss or mock the competitor
- Ask: "What specifically caught your eye about them?"
- Address the specific angle (feature, pricing, brand) head-on
- Offer a shared future-roadmap conversation with Mary directly

---

## Intervention playbook per warning sign

| Warning sign | Days to intervention | Who acts | Mechanism |
|---|---:|---|---|
| Reply rate drop | 2 | Mary | Dashboard snapshot email + fix proposal |
| Missed calls 2x | 0 | Mary | Personal email within 24h |
| Missed calls 3x | 0 | Mary | Phone call within 24h |
| Silence 2 weeks | 0 | Mary | Single-question email |
| Billing delay | Per payment-followup file | Automated + Mary | Stripe retries + email + SMS + call |
| Feature escalation | 1 | Mary | Research underlying metric, schedule call |
| Dashboard dormant | 7 | VA or Mary | Week-in-review email + prompt |
| Calendly no-shows | 3 | Mary | Outreach copy review + Calendly config audit |
| Competitor mention | 0 | Mary | Same-call acknowledgement + follow-up email |

---

## Quarterly Business Review (QBR) — for month 3+ clients

Formal 45-minute meeting, quarterly, in addition to the weekly check-in.

### QBR agenda

1. **Quarter in review** (10 min) — 3-month metrics trend, major wins, major blockers
2. **ROI analysis** (10 min) — closed deals attributable to Crystallux × gross margin vs Crystallux fees
3. **Channel mix review** (10 min) — which channels are producing, which to drop or add
4. **Vertical context** (5 min) — what we're seeing across their vertical in aggregate (anonymised)
5. **Roadmap preview** (5 min) — what Mary is building next, what's coming
6. **Renewal discussion** (5 min) — plan for the next quarter, any tier/term adjustments

### QBR deliverable

Mary sends a written QBR report 48 hours after the call:

```
Subject: Crystallux QBR — [Client Name] — [Quarter]

Hi [First Name],

Thanks for the QBR yesterday. Here's the written recap for your records.

## Quarter in numbers
- Meetings booked: [N] (target: [T])
- Opportunities created: [N]
- Deals closed: [N] ($[X] value)
- ROI on Crystallux spend: [X]×

## What's working
- [top 3 wins]

## What we're adjusting next quarter
- [commitment 1]
- [commitment 2]
- [commitment 3]

## Roadmap preview
- [what Mary is building + timeline]

## Renewal plan
- [commitment on tier, term, pricing]

I'll attach the dashboard PDF snapshot to this email for your records.

— Mary
```

---

## Advocate pathway

Once a client hits month 6+ with clean metrics, they become a Crystallux advocate. Handle carefully — advocates produce the best referrals.

### Advocate privileges

- Early access to new features and channels
- Lower-friction referral program (see `docs/mary-outreach/REFERRAL_PROGRAM.md`)
- Public case-study feature with fee waiver for one month of service
- Quarterly 1:1 call with Mary (not VA)
- Beta-tester status on Intelligence tier when launched

### Advocate asks (Mary's direct channel)

- **Month 6:** Ask for introduction to 3 peers in their network. Template: "Know anyone in [adjacent vertical] who'd benefit? Happy to take a warm intro."
- **Month 9:** Ask to participate in a customer advisory board (quarterly, 1-hour, 5-10 advocates)
- **Month 12:** Ask for a founder-to-founder case study interview + a published quote + a logo placement

Never ask for all three at once. Space the asks.

---

## Churn triage — when intervention fails

If a client formally gives 30-day notice:

1. **Respond within 4 hours** with acknowledgement + exit interview request
2. **Exit interview:** 30 minutes, same structure as the onboarding call but backwards. Why now, what would have retained, what's next, would they ever come back
3. **Post-exit:**
   - Export their data to CSV + JSON
   - Cancel Stripe subscription at end of current period
   - Send final invoice if any balance owed
   - Add to the 6-month reactivation sequence (see `RENEWAL_CHURN_PREVENTION.md`)
   - Capture exit-interview findings in internal doc; review quarterly for product signal

### Do NOT

- Offer a discount to retain (sets a bad precedent; other clients will demand same)
- Argue with the client's reason for leaving
- Promise features you aren't sure you'll ship
- Bad-mouth the client internally (small business, word travels)
