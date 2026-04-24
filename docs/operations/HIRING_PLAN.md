# Hiring Plan — Scaling Crystallux

**Purpose:** trigger-based hiring sequence. Hire only when the metric triggers the hire, never pre-emptively. Solo-founder stage stays solo longer than most founders expect.

**Principle:** hire the bottleneck. The bottleneck changes as the business scales. Don't hire the second full-time engineer when the real bottleneck is customer success.

---

## Hire 1 — Virtual Assistant (Client Operations Associate)

### Trigger

- **Metric:** 5 concurrent active clients AND Mary spending 10+ hours/week on support + onboarding + check-ins
- **Timing estimate:** month 2 (if sprint execution on plan)
- **Runway requirement:** $1,500-2,500 monthly committed for 90 days minimum

### Role

Full details in `docs/operations/VA_ONBOARDING_RUNBOOK.md`.

Summary:
- Tier-1 support, weekly check-ins for standard accounts, onboarding coordination, admin
- 20-40 hours per week (start part-time, scale up)
- Canadian remote or Philippines/LATAM depending on budget

### Budget

- **Entry (Philippines/LATAM):** $10-15 CAD/hour × 20-30 hrs/week = $800-1,800/month
- **Mid (Canadian remote):** $18-25 CAD/hour × 20 hrs/week = $1,500-2,000/month
- **Fully loaded (payroll taxes, tools, one-time setup):** add 15-20%

### Interview template

4-step process — keep it tight:

1. **Written application review** — writing sample + relevant experience
2. **Async writing test** — two scenario responses; review for tone + CASL awareness
3. **30-min video interview with Mary** — English fluency, cultural fit, availability
4. **Paid trial project** — 3-5 hours paid for real tasks; evaluate output

Budget 2 weeks from job post to hire.

---

## Hire 2 — Sales Rep (Senior Business Development)

### Trigger

- **Metric:** 10 concurrent active clients AND inbound leads exceeding Mary's capacity (Mary taking > 3 discovery calls per week and starting to drop prospects)
- **Timing estimate:** month 3-4
- **Runway requirement:** $3,000-5,000 monthly base + commission committed for 90 days

### Role

- Own full sales cycle: first response to qualified inbound → discovery call → contract close
- Target: 5-8 new signed clients per month
- Sales deck + demo delivery (Mary records new demos as product evolves; sales rep uses them)
- Handoff to Mary or VA for onboarding; sales rep doesn't run onboarding

### Compensation

- **Base:** $3,500-5,000/month CAD (Canadian remote, aligned with Toronto tech SMB salaries for early-stage BD role)
- **Commission:** 30% of first-month fee on every client they close (e.g., $1,497 client = $450 commission)
- **Vesting on retention:** commission only paid if client stays 60 days
- **OTE at target performance:** $80-120K CAD annualised

Why 30% first-month only: pays handsomely for strong closers; caps cost on churn-risk closes.

### Interview

1. **Application review:** prior SaaS sales experience, Canadian market knowledge
2. **Role-play:** candidate runs a mock discovery call with Mary playing a broker
3. **Written follow-up:** after role-play, candidate writes a follow-up email
4. **Reference check:** two references from prior sales managers

Hire decision based primarily on role-play performance. Resumes lie; role-play doesn't.

---

## Hire 3 — Technical Contractor

### Trigger

- **Metric:** 15 active clients AND Mary spending 5+ hours/week on workflow debugging / schema changes / technical support
- **Timing estimate:** month 5-6
- **Runway requirement:** $2,000-3,500 monthly for 10-15 hours/week part-time contractor

### Role

- Maintain n8n workflow integrity, fix deploy issues, handle P1 technical incidents
- Schema migrations for new features
- API integration updates (Apollo, Stripe, etc. when providers release breaking changes)
- Not a product-builder; a maintenance + incident contractor

### Profile

- Node.js / TypeScript comfortable
- Prior n8n or Zapier workflow experience
- Supabase / PostgreSQL comfortable
- Part-time, hourly contractor (not full-time hire yet)
- Canadian or time-zone-aligned

### Compensation

- **Hourly:** $80-120 CAD/hour for 10-15 hrs/week
- **Retainer alternative:** $2,500/month for 15 hrs/week + SLA on 4h incident response

### Sourcing

- Post in relevant Slacks (n8n community, Supabase community, Canadian dev Slacks)
- Upwork for initial short-term contracts; convert to retainer if fit
- Referrals from Mary's technical network

---

## Hire 4 — Customer Success Manager (CSM)

### Trigger

- **Metric:** 20 active clients AND (a) VA at capacity, (b) retention risk increasing, (c) weekly check-in quality dropping
- **Timing estimate:** month 7-10
- **Runway requirement:** $5,000-7,500 monthly for full-time CSM

### Role

- Own all weekly check-ins, QBRs, renewal conversations
- Manage the retention playbook per `CLIENT_SUCCESS_PLAYBOOK.md`
- Handle churn triage, reactivation sequences
- Supervise VA on support escalations
- Report directly to Mary

### Compensation

- **Base:** $55,000-75,000 CAD/year (Canadian CSM market for B2B SaaS early-stage)
- **Performance bonus:** quarterly based on logo retention + NRR

### Profile

- Prior B2B SaaS CSM experience (not exclusively sales)
- Canadian market awareness
- Strong written communication
- Not a seller; a retention + expansion operator

---

## Hire 5 — Content / Marketing

### Trigger

- **Metric:** 30 active clients AND inbound pipeline flattening (signals the brand needs investment)
- **Timing estimate:** month 12-18
- **Runway requirement:** $4,000-6,500 monthly for part-time content lead

### Role

- Own the Crystallux content engine: blog, LinkedIn, case studies, podcast appearances
- Publish 2-3 pieces per week
- Repurpose client wins into shareable content
- Own the monthly newsletter to prospects + past clients
- Work closely with Mary on the founder-voice layer (Mary's LinkedIn stays Mary's)

### Compensation

- **Part-time contractor (20 hrs/week):** $4,000-5,500/month CAD
- **Full-time (40 hrs/week):** $60,000-85,000 CAD/year

### Profile

- Strong writing, proven B2B SaaS content
- Canadian context fluency
- Comfortable with peer-advisor tone (not corporate marketing fluff)
- Can work with minimal direction given existing content library (`docs/commercial/`)

---

## Hire sequence summary

| # | Role | Trigger (clients) | Monthly cost | Mary time back |
|---:|---|---:|---|---|
| 1 | VA | 5 | $1,500-2,500 | 15-20 hrs/week |
| 2 | Sales Rep | 10 | $3,500-5,000 + commission | 8-15 hrs/week |
| 3 | Technical Contractor | 15 | $2,000-3,500 | 5-10 hrs/week |
| 4 | Customer Success Manager | 20 | $5,000-7,500 | 10-15 hrs/week |
| 5 | Content / Marketing | 30 | $4,000-6,500 | Strategic time |

**Total hiring cost at 30 clients:** ~$16,000-25,000/month.
**Revenue at 30 clients, average ARPU $1,600/month:** $48,000/month MRR.
**Gross margin at that scale:** comfortably positive even after hiring + variable costs.

---

## Budget constraints + gates

### Before every hire, verify:

1. **Cash on hand covers 6 months** of the new hire's cost at current run rate (not projected growth)
2. **The bottleneck metric has sustained for 4+ weeks** (hiring on a 1-week anomaly burns cash)
3. **Mary can articulate the first 90 days** of what the new hire will own (if she can't, the role isn't fully defined)
4. **The interview process budget is blocked** (2-3 weeks, including role-play or trial project)

If any of the above fails: delay the hire.

### Runway rule

Crystallux maintains a **6-month runway floor** on operating expenses at all times. If cash dips below that threshold, pause hiring regardless of growth metrics.

---

## Anti-patterns to avoid

- **Hiring before delegation works.** If Mary can't delegate existing work cleanly, hiring adds management overhead, not leverage.
- **Hiring peers ahead of tier-1 ops.** First full-time hires should offload support + admin, not be strategy collaborators.
- **Hiring without a 30-60-90 plan for the role.** Unclear first-90-day expectations → unclear performance expectations → bad hire.
- **Hiring equity in first 10 hires unless the role justifies it.** Cash > equity for VAs, sales reps, CSMs at this stage.
- **Ignoring the trigger and hiring because "I should".** The metric triggers the hire. Gut triggers the reassessment.
- **Hiring out of Canada before it's necessary.** Canadian talent is deep and time-zone-aligned; save overseas hiring until it materially saves money.

---

## When to pause hiring

Regardless of triggers, halt hiring if:

- 2+ consecutive months of MRR decline
- 2+ consecutive months of churn > 10%
- Unexpected large expense (lawsuit, platform incident requiring engineering, regulatory fine)
- Personal bandwidth — Mary running at < 60% health / energy

Hiring during a stressed period locks in cost at exactly the wrong time.
