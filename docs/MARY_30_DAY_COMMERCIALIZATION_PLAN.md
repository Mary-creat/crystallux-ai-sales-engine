# Mary's 30-Day Commercialization Plan

**Purpose:** week-by-week roadmap from sprint-end through $10K MRR.
**Starting point:** end of 14-day sprint — 2 paying clients, $3,494 MRR, email + LinkedIn live.
**Target by day 30:** 5 paying clients, $8K-12K MRR, first case study published, first non-founding-team hire (VA).

---

## Week 1 (Days 1-7): foundation + first live revenue

*(Covered in detail by `MARY_14_DAY_EXECUTION_SPRINT.md` days 1-7.)*

**Milestones:**
- Legal foundation complete (contract / ToS / Privacy with lawyer review)
- Stripe live + products created
- Crystallux landing page v1 live
- All migrations applied, workflows imported, email channel live
- First 10 live outbound emails sent
- Business bank account open

**Revenue target:** $0 (pipeline building only)
**Clients target:** 0 signed, 10+ conversations started

**Infrastructure completion markers:**
- [x] Business bank account
- [x] Stripe account verified
- [x] Contract template finalised
- [x] Landing page live
- [x] Pricing page live

---

## Week 2 (Days 8-14): first clients + live LinkedIn

*(Covered in detail by `MARY_14_DAY_EXECUTION_SPRINT.md` days 8-14.)*

**Milestones:**
- First discovery calls executed
- First client signs (consulting)
- Second client signs (consulting or real_estate)
- LinkedIn channel live
- First case study v1 published
- 14-day retrospective complete

**Revenue target:** $3,494 MRR (2 clients at founding pricing)
**Clients target:** 2 signed, both onboarded

**Infrastructure completion markers:**
- [x] LinkedIn channel live via Unipile
- [x] First case study template populated
- [x] Client #1 dashboard URL shared + feedback captured

---

## Week 3 (Days 15-21): sales engine for Crystallux itself + vertical expansion

**Focus shift:** Crystallux starts eating its own cooking. We run Crystallux's own outbound through the Crystallux platform, targeting consultants and real estate agents in Canadian markets.

### Day 15-17: Set up Crystallux as a client of itself

| Task | Time | Owner |
|---|---:|---|
| Create `clients` row for Crystallux itself: niche='consulting', focus_segments=['commercial'], channels_enabled=['email','linkedin','voice'] | 30 min | Mary |
| Load 100 consulting prospects (GTA + Calgary + Vancouver boutique firms) | 2h | Mary + VA (if hired) |
| Load 100 real_estate prospects in the same markets | 1h | Mary + VA |
| Run research + scoring + signal detection + campaign router on all 200 | 3h automated | Automation |
| Review first-batch copy, manually approve top 50 per vertical for live send | 2h | Mary |

### Day 18-19: Hire VA (critical move)

| Task | Time | Owner |
|---|---:|---|
| Post VA job description on OnlineJobs.ph / Upwork. Profile: Canadian English fluent, $8-15/hr, 20h/week to start | 90 min | Mary |
| Interview 5-10 candidates over 2 days | 4h | Mary |
| Hire 1 VA with 2-week trial period | 30 min | Mary |
| VA onboarding: Supabase dashboard access, Apollo, Calendly coordination, reply triage | 3h | Mary |

**Why now:** manual prospect loading + reply triage + onboarding coordination at 4 concurrent clients hits the wall fast. A VA at $10/hr buys 20 hours of Mary's time back for $800/month — trivial at $8K MRR.

### Day 20-21: Third + fourth client close

| Task | Time | Owner |
|---|---:|---|
| Execute any discovery calls booked from week-3 outbound | As needed | Mary |
| Close clients #3 and #4 | Per close | Mary |
| Onboard immediately via clx-stripe-provision-v1 | 30 min/each | Mary |
| Start case study v2 + v3 data collection | 60 min total | Mary |

**Revenue target by end of week 3:** $6-8K MRR (4 clients)
**Clients target:** 4 signed
**Infrastructure completion markers:**
- [x] VA hired and onboarded
- [x] Crystallux-as-client runbook validated
- [x] 4 clients in dashboard, 4 active campaigns

---

## Week 4 (Days 22-28): scale-readiness + dental vertical activation

**Focus shift:** start dental vertical activation with per-province regulatory copy review. Hire begins sales VA or SDR contractor for outreach follow-up.

### Day 22-23: Dental compliance review + first dental prospect batch

| Task | Time | Owner |
|---|---:|---|
| Hire Canadian marketing-compliance consultant for dental copy review (1-time gig, $500-1000) | 60 min | Mary |
| Submit dental outreach templates for RCDSO Ontario review | 30 min | Mary |
| Build Alberta Dental Association variant | 90 min | Mary |
| Pull 50 dental prospects in GTA | 60 min | VA |
| Load + run pipeline on 50 dental prospects | 2h | Mary / automation |

### Day 24-25: Outbound follow-up automation maturity

| Task | Time | Owner |
|---|---:|---|
| Review Crystallux's own reply rate; tune `clx-outreach-generation-v2` prompts if below 8% | 2h | Mary |
| Add second follow-up step to `clx-follow-up-v2` (day 7 bump-email) | 90 min | Mary (prompt update only) |
| Verify `clx-error-monitor-v1` has no false alerts; tune thresholds if needed | 60 min | Mary |

### Day 26-28: Fifth client + operational rhythm

| Task | Time | Owner |
|---|---:|---|
| Close client #5 (any active vertical) | Per close | Mary |
| Establish weekly rhythm: Monday = client check-ins, Tuesday = outbound batch, Wednesday = VA 1:1, Thursday = deep work, Friday = reporting | 30 min to formalise | Mary |
| Publish first case study on crystallux.org/case-studies | 2h | Mary + contractor |
| Review week-4 metrics: MRR, CAC, first-month retention, dashboard engagement | 60 min | Mary |

**Revenue target by end of week 4:** $8-12K MRR (5 clients)
**Clients target:** 5 signed

---

## Day 29-30: retrospective + month-2 planning

| Task | Time | Owner |
|---|---:|---|
| 30-day retrospective: what scaled, what broke, what's the bottleneck | 2h | Mary |
| Plan month 2 sprint: target $15-20K MRR, 8-10 clients, dental live | 2h | Mary |
| Publish first LinkedIn / founder-note post on hitting month-1 milestone (optional but compounds pipeline) | 90 min | Mary |
| Run DO-NOT-BREAK full-stack verification (disk, TESTING MODE, credential hygiene) | 30 min | Mary |

**End-of-month state:**
- 5 paying clients
- $8-12K MRR
- 1 VA on staff
- Dental vertical copy review in-flight
- First case study published
- Crystallux sold through its own outbound platform (self-sell validated)

---

## Revenue milestones

| Day | MRR target | Clients | Trigger |
|---:|---:|---:|---|
| 7 | $0 | 0 | Foundation only |
| 14 | $3,494 | 2 | Sprint complete |
| 21 | $6-8K | 4 | VA hired |
| 28 | $8-12K | 5 | Weekly operational rhythm established |
| 30 | $10-12K | 5+ | Month retrospective + case study live |

## Client onboarding targets (per week)

- Week 1: 0 (foundation)
- Week 2: 2 (founding clients)
- Week 3: +2 (self-sell validated)
- Week 4: +1 (operational pace stabilised)

## Vertical expansion schedule

- Weeks 1-2: **consulting** + **real_estate** (top-2 active)
- Week 3: **+ construction** (ready but not urgent)
- Week 4: **+ dental** activation begins (per-province copy review)
- Month 2: dental live + legal founder-client search begins + moving/cleaning deferred

## Hiring triggers

| Trigger | Hire | When |
|---|---|---|
| 3+ concurrent clients, Mary doing repetitive ops | VA (20h/week Philippines or LATAM) | Day 18 |
| 5+ clients, inbound leads >10/day | VA hours bumped to 40h/week OR part-time sales associate | Day 30+ |
| 8+ clients, technical issues slowing sends | Part-time n8n / Supabase contractor (5-10h/week) | Month 2 |
| $15K+ MRR, multiple verticals live | First full-time hire (choose: sales lead OR ops lead based on bottleneck) | Month 3 |

## Business infrastructure completion markers

Tier-1 (before client 1, all done by day 10):
- [x] Business bank account
- [x] Stripe setup
- [x] Client contract template (lawyer reviewed)
- [x] Terms of Service + Privacy Policy (lawyer reviewed)
- [x] Landing page live with pricing
- [x] crystallux.org B2B positioning (not MGA) — positioning locked in copy

Tier-2 (before client 3, done by day 21):
- [x] VA hired + onboarded
- [x] Onboarding call script standardised
- [x] Support email auto-responder
- [x] First case study v1 published

Tier-3 (before client 10, done by month 2):
- [ ] Demo video recorded (2-min product walkthrough)
- [ ] Sales one-pager (PDF for email follow-ups)
- [ ] Testimonials from 3+ clients
- [ ] Weekly client check-in cadence documented
- [ ] Business insurance / E&O policy
- [ ] CRM for Crystallux's own sales pipeline (Attio / HubSpot Free / bespoke)

Tier-4 (month 2-3):
- [ ] Formal SLA document with uptime commitments
- [ ] SOP set (onboarding, client check-in, outbound-batch triage, escalation)
- [ ] Second full-time hire (if revenue supports)
- [ ] First non-Canadian client or first paid-ads CAC test

---

## Failure modes + contingency

| If... | Then... |
|---|---|
| Week 2 ends with 0 clients | Re-evaluate copy, widen ICP, consider 30-day-free trial for 2 founding clients |
| Week 3 ends with 2 clients (not 4) | Continue outbound, delay VA hire until 3+ clients, focus Mary on closing |
| Week 4 ends with 4 clients (not 5) | On track — close 5th in week 5; defer dental activation to week 5 |
| Client churns at end of month 1 | Conduct exit interview same-day; fix root cause before next onboarding |
| Stripe hold on payouts | Keep 2-month operating float in business account to bridge |
