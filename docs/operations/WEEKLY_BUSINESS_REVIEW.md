# Weekly Business Review — Mary's Self-Review

**Purpose:** structured weekly rhythm for Mary to plan the week, review the week, and keep the metrics honest. 30 minutes Monday morning, 30 minutes Friday afternoon. Non-negotiable.

**Rationale:** solo founders without a weekly review drift. Metrics stop being consulted. Priorities blur. The WBR keeps Crystallux operator-level disciplined.

---

## Monday planning template (30 min, first thing)

Done in Notion, Apple Notes, or a paper journal — whatever Mary sticks with. Consistency matters more than tool.

### 1. Last week's carryover (5 min)

Answer in one sentence each:

- What was on the priority list but didn't get done?
- Why? (time, blocked, deprioritised, forgot)
- Carrying forward this week or killing?

### 2. This week's top 3 priorities (15 min)

Pick exactly three. No more. No "and also". Each priority:

- One-sentence description
- Definition of done ("I'll know this is done when…")
- Estimated hours
- Blocker if any

**Priority selection rule:** each priority must move Crystallux closer to one of the three north-star metrics:

1. **MRR growth** — new clients signed, expansions
2. **Retention** — reducing churn risk, hitting guarantees, strengthening proof
3. **Leverage** — systems that let Mary (and later team) handle more clients per hour

If a priority doesn't map to one of these, it's probably not a priority — it's an activity.

### 3. Weekly calendar commitments (5 min)

- Client weekly check-ins (pre-scheduled)
- Discovery calls booked (calendar)
- Internal focus blocks (deep work, blocked in calendar)
- Non-negotiables (family, health, etc.)

Block time for the top-3 priorities before anything else. If they don't fit, cut scope.

### 4. Energy check (5 min)

Solo-founder burnout is real and compounds. One-sentence answers:

- How did last week feel — energised, drained, neutral?
- What's draining me right now?
- What gave me energy last week?
- Anything to remove from the plan if energy is low?

---

## Friday review template (30 min, end of day)

### 1. What got done (10 min)

- Top 3 priorities — done / partial / not started (be honest)
- Surprise wins (unplanned but valuable)
- Clients onboarded this week (count + names)
- Meetings booked for Crystallux itself (count + quality)

### 2. What's behind (5 min)

- Priorities that slipped
- Why they slipped (blocker, underestimated, new urgent thing)
- Consequence if still not done next week
- Re-queue or kill

### 3. Metrics dashboard (10 min)

Update the metrics spreadsheet (Notion or Google Sheet) with current week's numbers:

#### Core (every week)

- **MRR** — sum of all `clients` with `subscription_status='active'` × their monthly rate
- **Active clients** — count
- **Trialing clients** — count
- **New trials started this week** — count
- **Trial → paid conversion rate (trailing 30 days)** — %
- **Churned this week** — count + named
- **New discovery calls booked** (from Mary's own outreach engine)
- **Discovery call → contract conversion (trailing 30 days)** — %

#### Every week

- **Client satisfaction proxy** — avg rating from support-interaction follow-ups, or count of complaints
- **Pipeline value** — $ value of signed contracts not yet paid + $ of prospects in late-stage
- **Stripe MRR** (for reconciliation with our calculated MRR — should match)

### 4. Client health check (5 min)

Open the master client tracker. For each active client, rate:

- 🟢 Green: metrics on track, engaged
- 🟡 Yellow: one or two warning signs per `CLIENT_SUCCESS_PLAYBOOK.md`
- 🔴 Red: active churn risk, intervention already in progress

Any yellow or red in the tracker moves to Monday's priority list.

---

## Monthly metrics (add to the Friday review on last Friday of the month)

Expand the Friday review by 30 minutes on month-end.

### Financials

- **Total revenue** this month (from Stripe)
- **Total expenses** (VA cost, API fees, tooling — API costs tracked via each vendor dashboard)
- **Gross margin** — revenue minus variable costs (Apollo, Claude tokens, Tavus renders, Twilio sends, VA)
- **Net margin** — gross minus fixed costs (office, insurance, retained legal)
- **Cash runway** — current cash / monthly burn rate

### Growth

- **MRR month-over-month growth** — %
- **New clients this month** — count + revenue
- **Churned clients this month** — count + revenue lost
- **Net MRR change** — new - churned
- **Average revenue per client (ARPC)** — MRR / active clients

### Product

- **Active verticals** — count (currently 5 active out of 8 seeded)
- **Active channels per average client** — average of channels_enabled length
- **Meetings booked per client per month** — average
- **Reply rate, trailing 30 days** — %

### Team

- **VA hours used this month** — for cost reconciliation
- **Mary hours worked** — honest number, not inflated
- **Mary hours spent on low-leverage work** — time spent on support, coordination, admin (target: reducing month over month as VA absorbs)

### Month-end snapshot

Write a 2-3 paragraph retrospective at the end of each month:

- **Biggest win:** one sentence, specific
- **Biggest miss:** one sentence, specific
- **Biggest learning:** one sentence, specific
- **Outlook for next month:** one sentence, specific

Save in a running file (`docs/private/monthly-retrospectives.md` — gitignored).

---

## Quarterly metrics (add to month-end review on last Friday of the quarter)

Expand another 30 minutes.

### Product + market fit signals

- **NPS from active clients** — quarterly survey (email link to simple Typeform or Google Form)
- **Net Revenue Retention (NRR)** — MRR at end of quarter / MRR at start of quarter (from same set of clients)
- **Logo retention** — % of clients from start of quarter still active at end
- **Organic referrals this quarter** — count of inbound leads who mentioned a referral source
- **Case studies published this quarter** — count

### Vertical performance

Per-vertical breakdown:

- Active clients per vertical
- MRR per vertical
- Avg meetings-booked-per-month per vertical (vs target)
- Churn rate per vertical
- NPS per vertical

This identifies which verticals to double down on and which to deprioritise.

### Competitive intelligence

- **Pricing moves by competitors** — what did peer tools change?
- **Product moves by competitors** — new features launched
- **Client mentions of alternatives** — logged from check-ins
- **Lost deals** — where did we lose? To who? Why?

### Strategic questions (quarterly)

Reserve 60 minutes at quarter-end for these:

1. Are we growing the way we expected?
2. Is the vertical mix working?
3. Is the team composition right for the next quarter?
4. Is pricing still optimal?
5. What should we build? What should we kill?
6. Where are we over-investing? Where are we under-investing?

Answers become the next quarter's OKRs.

---

## Red flags (when to pause and reassess)

Stop-and-reassess triggers (halt business-as-usual, think deeply):

| Red flag | Reassess what |
|---|---|
| 2+ consecutive months of MRR decline | Pricing, product, GTM motion |
| Churn rate > 10% in a month | Onboarding, product-market fit, client communication |
| Trial → paid conversion < 40% | Trial design, onboarding, demo quality |
| Gross margin < 60% | API cost creep, plan mismatch, over-servicing |
| Mary working > 60 hours/week for 4+ weeks | Delegation, hiring, scope creep |
| 2+ consecutive incidents in one month | Technical debt, provider reliability |
| First paying client cancels in first 30 days | ICP fit, expectation-setting, urgent product review |
| Net Promoter Score < 7 (when measured) | Client experience, product, communication |
| More than 2 clients mention same competitor | Competitive positioning, feature gap |

---

## Anti-patterns to avoid in WBRs

- **Over-celebrating vanity metrics** — "we got 500 landing-page visitors this week!" means nothing if MRR is flat. Celebrate the real numbers only.
- **Skipping when busy** — the weeks Mary most wants to skip are the weeks she most needs to do a WBR. Discipline wins.
- **Writing for future-Mary instead of action-Mary** — the goal is to drive this week's action, not create a permanent journal. Keep it punchy.
- **Turning it into a planning session** — Monday is 30 minutes, not 2 hours. Cap it hard.
- **Metrics as decoration** — a metric that doesn't drive a decision isn't worth tracking. If a metric has never changed what Mary does, drop it.
- **Solo-founder isolation** — share a condensed version of the monthly retro with one peer founder or advisor. External accountability reduces drift.

---

## Time investment

| Cadence | Duration | When |
|---|---:|---|
| Monday planning | 30 min | First thing, Monday |
| Friday review | 30 min | End of day, Friday |
| Monthly add-on | +30 min | Last Friday of month |
| Quarterly add-on | +60 min | Last Friday of quarter |

**Total weekly:** 1 hour standard; 1.5 hours month-end; 2.5 hours quarter-end.

Non-negotiable. If any WBR is skipped, catch up on the next business day at minimum.
