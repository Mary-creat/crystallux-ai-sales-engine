# VA Onboarding Runbook

**Purpose:** first-VA hiring + onboarding sequence. Triggered when Mary hits 5 concurrent clients. VA buys Mary 20 hours/week back at $10-25/hour; the math works at 3+ clients.

**Role summary:** tier-1 support, onboarding coordinator, weekly check-in execution, administrative tasks. Not a salesperson, not an engineer, not a decision-maker.

---

## Role definition

### Title

**Client Operations Associate** (internal). Public title when communicating with clients: "Crystallux Customer Success Team" (Mary remains the face of the brand).

### Core responsibilities

1. **Support tier 1** — handle first-touch response on every support@crystallux.org email within SLA. Resolve standard issues (see `docs/operations/SUPPORT_FLOW.md` templates 1-4, 6, 8-9). Escalate anything requiring Mary per escalation rules.

2. **Weekly check-in execution** — run standard weekly check-ins for non-at-risk clients. Use the agenda from `docs/operations/WEEKLY_CHECK_IN.md` verbatim. Send the recap email within 2 hours of the call. Escalate at-risk accounts to Mary.

3. **Onboarding coordination** — post-contract, execute the VA half of the onboarding checklist from `docs/operations/ONBOARDING_CALL_SCRIPT.md`: load prospects, configure dashboard access, test TESTING MODE outreach, send welcome email with dashboard URL. Mary runs the kickoff call; VA handles the operational setup.

4. **Administrative tasks** — Calendly coordination, scheduling the weekly 15-min check-ins, tracking client-facing metrics in Notion/HubSpot, maintaining the testimonial + case study spreadsheet, gentle reply-handling during off-hours.

### What VA does NOT handle

- Contract negotiation or pricing changes
- Closing new prospects (Mary runs discovery calls)
- Technical incidents requiring workflow edits
- At-risk client intervention
- Feature requests from founding clients
- Payment disputes above $500
- Anything marked URGENT

---

## Hiring profile

### Compensation (Canadian remote market, 2026)

- **Entry ($10-15/hour CAD):** Philippines / LATAM VA via OnlineJobs.ph, Paired, or Upwork. Part-time 20-30h/week. Strong English, async-friendly.
- **Mid ($15-25/hour CAD):** Canadian-based VA or North America contractor. 20-40h/week. Time-zone-aligned. Preferred for voice work, client-facing calls.

Start at entry tier. Graduate to mid once VA demonstrates first-quarter reliability.

### Candidate profile

**Must-have:**
- Fluent written and spoken English (conversational + professional written)
- Availability for 20+ hours/week during Eastern Time business hours (at least 50% overlap)
- Gmail, Google Workspace, Slack, Zoom, Calendly experience
- Prior client-facing or customer-success experience
- Demonstrable written communication (sample email writing during interview)

**Nice-to-have:**
- Experience with Supabase / simple SQL queries
- HubSpot or similar CRM familiarity
- Canadian context awareness (PIPEDA, CASL vocabulary)
- Prior B2B SaaS experience

**Disqualifying:**
- Any prior SMS/voice/LinkedIn spam or grey-hat outreach experience
- Inability to write in Crystallux peer-advisor tone after 2 examples
- Time zone requiring >4h response delay on Eastern-business-hours requests

### Sourcing

- **First pick:** OnlineJobs.ph (Philippines) for entry tier
- **Second pick:** Upwork or Paired for targeted search
- **Third pick:** LinkedIn Jobs for Canadian-based candidates at mid-tier
- **Avoid:** Fiverr (too transactional), Craigslist (too unfiltered)

### Interview process

1. **Application review** (~5 min/candidate): writing sample, prior roles, availability
2. **Written skills test** (20 min, candidate asynchronous): two provided scenarios, candidate writes email responses; Mary reviews for tone + CASL awareness
3. **30-min video interview with Mary:** cultural fit, English fluency in real-time, understanding of confidentiality, availability windows
4. **Trial project** (3-5 hours paid): handle three synthetic support scenarios + execute one mock onboarding coordination task
5. **Decision:** 2-week paid trial period before permanent contract

---

## First-week training plan (40 hours)

### Day 1 (8 hours) — Context + culture

- **Hour 1-2:** review the Crystallux landing page, pricing page, and demo video (from `docs/commercial/`). Understand what we sell.
- **Hour 3-4:** read `docs/operations/SUPPORT_FLOW.md` and `docs/operations/WEEKLY_CHECK_IN.md` cover to cover.
- **Hour 5-6:** read all seven `docs/verticals/{vertical}/README.md` files. Understand our target clients by vertical.
- **Hour 7-8:** 1-hour video call with Mary. Walk through two real (past) client histories. Answer VA's questions.

### Day 2 (8 hours) — Tools + access

- **Hour 1:** access provisioning with Mary over screen-share. VA gets:
  - Gmail delegate access to info@crystallux.org
  - Supabase read-only role (custom role `va_readonly` granting SELECT on clients, leads, outreach_log, scan_errors but nothing else)
  - Notion/Google Drive folder access (client-tracking spreadsheet, testimonial log, incident log, onboarding checklist Notion template)
  - Slack workspace invitation (channels: #clients, #support, #incidents, #random)
  - HubSpot CRM seat (if available; Mary's separate setup)
  - Loom account (for demo-recording backup)
  - Zoom personal meeting ID for 1:1s with clients
- **Hour 2:** password manager setup (1Password or Bitwarden). No shared passwords in email or Slack.
- **Hour 3-5:** VA creates first three "Loom video walkthroughs" of how to do common tasks (this becomes onboarding material for VA 2 later). Mary reviews.
- **Hour 6-8:** VA shadows Mary on one live client check-in and one live support-email response.

### Day 3 (8 hours) — First solo work under Mary review

- VA handles 5 support emails solo. Every reply reviewed by Mary before sending on day 3. Day 4+: VA can reply first and Mary reviews post-send.
- VA books and attends (observes) one client weekly check-in.
- VA shadows an onboarding coordination task (loading a new prospect batch into a test client account).

### Day 4 (8 hours) — Ramping solo responsibilities

- VA handles all incoming support emails solo (Mary spot-checks 2-3 per day).
- VA executes the VA half of one onboarding flow.
- VA runs one standard weekly check-in solo (Mary joins for first 2 minutes then drops off — effectively validates VA is solo-ready).
- Mary holds 30-minute end-of-day retro with VA: what felt hard, what surprised, what to adjust.

### Day 5 (8 hours) — Review + calibration

- Full day solo.
- Mary reviews the entire week's support email history, check-in recaps, onboarding steps.
- 1-hour end-of-week retro with VA: what's working, what needs adjustment.
- Decision: confirm 2-week paid trial continuation.

### Week 2 — Validation

- VA runs all tier-1 responsibilities solo.
- Mary shadows 2-3 interactions per week (with client consent).
- End of week 2: decision on permanent contract.

---

## Ongoing management

### Weekly 1:1 with Mary

- 30 minutes, Mondays
- VA brings: prior week's metrics, any clients at risk, any support tickets stuck
- Mary brings: feedback on specific tickets/recaps, product updates, client escalations
- Shared: improvement to runbook

### Performance metrics

Track weekly and review quarterly:

- **Support response time** — median and p95 (target: under 4 business hours p95)
- **Support resolution time** — median and p95 (target: under 24 business hours p95)
- **Client satisfaction (1-5 post-interaction)** — average (target: 4.3+)
- **Onboarding-coordination completion** — % of clients onboarded fully within Mary's 72-hour deadline (target: 95%+)
- **Escalation rate** — % of tickets escalated to Mary (target: 15-25%; lower = VA over-extending, higher = VA under-empowered)

### Review cadence

- **Week 2:** hired / not-hired decision
- **Month 1:** contract confirmation + any pay adjustment
- **Month 3:** performance review, raise if metrics and client feedback are strong
- **Month 6:** evaluate for Mid-tier move (if started at Entry)

---

## Access management + security

Access for VAs is revocable. Maintain these access entries in a password manager or Notion page:

| Access | Granted on hire | Revoked on separation |
|---|---|---|
| Gmail info@crystallux.org (delegate) | Yes (read + send on behalf) | Immediately |
| Supabase va_readonly role | Yes | Immediately |
| Notion client tracker | Yes (edit) | Immediately |
| HubSpot CRM | If applicable | Immediately |
| Slack | Yes | Immediately |
| Google Drive /clients/ folder | Yes (read; edit only during specific tasks) | Immediately |
| Dashboard URLs + tokens | No | N/A |
| Stripe | No | N/A |
| Production database write | No | N/A |
| Credentials on workflow nodes | No | N/A |

Rule: VA never has write access to Supabase (beyond dashboard-driven updates), never has Stripe access, never has workflow-edit rights. These require Mary or a contracted engineer.

### On separation

Within 24 hours of VA leaving:

- Revoke Gmail delegate
- Revoke Supabase role
- Revoke Notion, Slack, Drive, HubSpot
- Change any shared credentials (there shouldn't be any, but verify)
- Rotate info@crystallux.org password
- Remove from any ongoing client email threads via "BCC removed" note

---

## When VA hits capacity (usually 8-10 clients under management)

Signals that you need VA 2 or a second hire:

- **Response time drift** — SLA misses 2+ weeks in a row
- **Escalation rate jump** — VA escalating > 40% of tickets because they're saturated
- **Fatigue** — VA reports consistent overtime or weekend work
- **Missed weekly check-ins** — VA skipping to catch up

When signals trigger: hire second VA using the same runbook. Two VAs can split:

- **Americas/Eastern VA:** North American business hours, client-facing
- **Offshore VA:** Asian or European hours, async support + admin backlog

Cross-training: both VAs maintain the same skill set; either can cover the other's shift.
