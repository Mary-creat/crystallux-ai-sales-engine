# Weekly Check-In — 15-Minute Client Meeting

**Purpose:** recurring 15-minute touchpoint with every active client every Friday (or the client's preferred weekday). Catches friction before it becomes churn; surfaces upsell signals early.

**Frequency:** weekly for the first 90 days of every client's lifecycle. Drops to bi-weekly after 90 days if metrics are healthy. Monthly from month 6 onward, except for Growth Pro tier (always weekly).

**Tool:** Google Meet or Zoom, Calendly booking, Loom recording if client consents.

---

## Agenda (5 items, time-boxed)

### 1. Wins this week (1 minute)

> "Before anything else — what's going well? Something book, a
> reply land, a meeting happen?"

Listen. Celebrate the specific thing. This sets a collaborative tone and builds retention momentum.

If client has no win to report: pivot directly to metrics review — don't dwell on the absence.

### 2. Metrics review (4 minutes)

Share the client's dashboard. Point at each of these on-screen:

- **Leads surfaced this week** — volume trend vs prior week
- **Outreach sent** — channel mix
- **Replies received** — reply rate %
- **Qualified meetings booked** — vs their target
- **Conversion on meetings** (if month 2+) — meetings → real opportunities

**One-line framing rule:** state each number, then the comparison.

> "25 leads this week, down from 31 last week. Reply rate held at
> 12%. 6 meetings booked, which puts us at 18 for the month —
> target is 20."

Don't over-explain. Client interrupts if they want detail.

### 3. Blockers or issues (3 minutes)

> "Anything that's bugged you this week? Outreach that felt off,
> a reply that wasn't handled right, a feature you wish existed?"

Capture verbatim in your notes. Do not argue, do not defend — listen.

Common blockers:

- "I didn't like the copy on [specific email]" → capture example, adjust prompt the same day
- "A reply took 24 hours to land in my inbox" → investigate reply-ingestion delay
- "I want to target [new segment]" → update ICP filter; takes 1 business day
- "The dashboard didn't load Tuesday morning" → P1/P2 investigation per `INCIDENT_RESPONSE.md`

### 4. Optimisations for next week (4 minutes)

> "One thing to adjust next week. Either from what you just flagged
> or from what I'm seeing in the metrics. Pick the one with the
> biggest lift."

Examples of good optimisations:

- Narrow ICP to exclude a segment that's replying but not booking
- Switch sending time from Monday 9am to Tuesday 11am (better open rates in their vertical)
- Add a second follow-up email 7 days after the initial
- Activate LinkedIn channel now that Unipile is set up
- Increase daily send cap by 20% now that deliverability is stable

Commit to one change. Document it in your notes. Implement within 2 business days.

### 5. Client questions (3 minutes)

> "Anything on your mind I haven't covered?"

Leave space. Client questions surface what they're really worried about, which often differs from what's showing up in the metrics.

Take notes. If a question requires research, commit to a reply within 1 business day — not during the call.

---

## "Results aren't what I expected" framework

When a client pushes back during the check-in, follow this 4-step pattern:

### Step 1 — Acknowledge specifically (no hedging)

> "You're right — we hit 6 meetings this week against a weekly
> target of 8. That's below pace. Let me tell you what I'm seeing
> and what we're going to change."

Do NOT:
- Hedge ("well, cold outreach is hard")
- Defend ("but we did send 150 emails")
- Compare to other clients ("other brokers are hitting target")

### Step 2 — Share what the data shows

> "The reply rate is healthy at 11%, which is above industry
> baseline. The issue is conversion from reply to booked meeting
> — we're at 55%, typically that's 75%+. The gap is that replies
> are asking questions the outreach should have answered upfront."

Specificity wins trust. Generic reassurance loses it.

### Step 3 — Propose a specific fix with a timeline

> "I'm going to rewrite the opening of the outreach copy tonight
> so it pre-answers the two most common reply questions. By
> Monday, the next batch uses the new copy. By next Friday, we'll
> see if the reply-to-meeting conversion lifts."

Time-bound. Measurable. Owned by Mary.

### Step 4 — Confirm the check-in mechanic

> "Next Friday's call, the first 4 minutes are reviewing whether
> that change moved the number. If it didn't, we go deeper — maybe
> the ICP is off, maybe the channel mix needs to shift. Sound
> good?"

Don't promise you'll "fix it". Promise you'll review it and adjust again if needed.

---

## Upsell opportunity flags

Capture these signals during check-ins and revisit monthly:

| Signal | Upsell |
|---|---|
| Client hit weekly target 4 weeks running | Offer Growth Pro tier upgrade |
| Client asks "can we add another channel" | Channel add-on ($150/mo per channel) |
| Client asks "can we do this for [other business I own]" | Second client, full founding rate |
| Client says "my [partner/employee] should see this" | Additional user access seat |
| Client mentions competitor using paid tools ($$$) | Intelligence tier Q2 2026 teaser |
| Client had a big win (big deal closed) | Ask for case study + testimonial |

Don't upsell during a bad-results conversation. Never twice in the same call.

---

## Follow-up email template (after every check-in)

Send within 2 hours of the call:

```
Subject: Quick recap — [client name] weekly check-in

Hi [First Name],

Quick recap from our call:

**What's working:**
- [win 1]
- [win 2]

**Numbers this week:**
- Leads surfaced: [N]
- Outreach sent: [N]
- Replies: [N] ([rate]%)
- Meetings booked: [N] (target: [T])

**Blockers flagged:**
- [blocker 1]

**Change for next week:**
- [specific optimisation, with a date]

**Next check-in:** [date/time] — Calendar invite already sent.

Any follow-ups between now and then go to info@crystallux.org.

— Mary
```

Client gets this every Friday by 5pm. Builds the pattern: check-in Friday, recap Friday evening, Monday priorities are clear.

---

## Escalation — when to bring Mary personally vs email reply

Early in the business (0-10 clients): Mary runs every check-in herself.

Mid-business (10-25 clients): Mary runs check-ins for Growth Pro clients and any at-risk accounts; VA handles standard weekly check-ins with email recaps and escalation if the client flags a blocker.

Later (25+ clients): dedicated Customer Success Manager (new hire) runs standard check-ins; Mary joins for month 3, month 6, month 12 milestones + any at-risk account.

### Always escalate to Mary personally when:

- Client mentions cancellation or "we might not renew"
- Metric miss for 2 consecutive weeks
- Client brings up a billing concern or dispute
- Client asks for features that don't exist
- Client mentions a competitor they're considering
- Client introduces a partner/decision-maker who wasn't on the original contract

Non-escalation-worthy (VA handles with email):

- Standard weekly checkbox meetings where client says "all good, keep going"
- Minor configuration changes (change sender address, adjust schedule)
- Administrative follow-up (invoice question, add user access)

---

## Call skip handling

If a client skips a weekly check-in:

**First skip:** No action. Life happens.

**Second skip (non-consecutive):** Email the Friday recap using the most recent dashboard data. Offer to reschedule to any time next week.

**Second skip (consecutive):** Flag as early churn risk — see `docs/operations/CLIENT_SUCCESS_PLAYBOOK.md` → Early warning signs. Mary emails personally: "Hey, noticed we haven't connected in two weeks. Want to make sure everything's working — got a minute for a quick call?"

**Third consecutive skip:** Phone call from Mary. No more email-only follow-ups. If no phone answer, send text. This is the intervention window — either we re-engage or we lose the account.
