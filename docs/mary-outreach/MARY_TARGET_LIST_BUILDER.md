# Mary's Target List Builder — Prospecting Crystallux Clients

**Purpose:** systematic process for building Mary's outbound target list. 100 brokers in month 1; 300 by month 3.

**Principle:** quality over volume. 100 well-targeted contacts produce more booked meetings than 500 broad-match ones. Target criteria are strict.

---

## Target criteria (initial month-1 ICP)

### Firmographics

- **Size:** 3-20 employees (sweet spot is 5-12 — large enough for pipeline pain, small enough for owner to be the buyer)
- **Geography:** Ontario, with a Toronto-GTA bias for first 50
- **Vertical focus (month 1):** insurance brokers. Expand to construction + real estate in month 2-3
- **Revenue band:** $500K-$5M annual gross (proxy: LinkedIn employee count, Apollo firmographic data)

### Decision-maker criteria

- **Role titles:** Owner, Founder, President, Managing Partner, Principal, General Manager (NOT Marketing Manager, Sales Manager, or Inside Sales)
- **Tenure:** 2+ years at current business (new hires are less likely to buy)
- **LinkedIn activity:** active in last 90 days (posts, comments, profile updates); absent prospects are likely at firms that don't use LinkedIn for business development

### Exclusion rules (hard filter)

- **Crystallux competitors:** other AI sales engines (Reflect, Apollo itself as a competitor, Clay, Smartlead, Instantly, Lemlist) — do not target their customers or employees
- **Adversely affected in 2026 economic climate:** flag but don't exclude. Capture for Q3 re-engagement.
- **Existing Crystallux clients or prospects in active discussion:** exclude — don't double-touch
- **Mary's personal network within 1st-degree LinkedIn:** handle via warm-intro referral sequence instead (see `docs/mary-outreach/REFERRAL_PROGRAM.md`), not cold
- **Businesses on our do-not-contact list:** Mitch Insurance (from early testing days) permanently on do_not_contact; add others as we learn

---

## Target sources (ranked by quality)

### Tier 1 — Highest quality

- **LinkedIn Sales Navigator (paid, $99/mo Essentials tier)** — the single best source. Advanced filters: geography + size + tenure + industry + job title. Decision-maker filters cut noise by 80%.

  Filter template for insurance brokers:
  - Industry: Insurance
  - Company size: 11-50 (LinkedIn's bucket spans our sweet spot)
  - Geography: Ontario, Canada
  - Job title: Owner, President, Founder, Managing Partner, Principal, Broker of Record
  - Posted on LinkedIn in last 30 days: yes
  - Mutual connections: prioritise 1st + 2nd degree

- **Apollo.io B2B search ($49/mo Basic tier)** — strong secondary for firmographic data and business email addresses. Use to enrich LinkedIn finds with direct emails.

  Filter template for insurance brokers:
  - Industry: Insurance (sub-industry: General, Commercial)
  - Company size: 3-50
  - Location: Ontario
  - Revenue range: $500K-$5M
  - Seniority: Owner, CEO, President, Founder

### Tier 2 — Vertical-specific directories

Insurance brokers:

- **RIBO Directory** (ribo.com) — every licensed insurance broker in Ontario is here, sorted by licence class. Scrape ethically (manual browse, not automated). Verify licence status on the site before outreach.
- **Canadian Broker Network member list**
- **IBC (Insurance Bureau of Canada) member directory**

Construction / contractors:

- **Ontario College of Trades licensed contractor database**
- **HomeStars Pro listings** (the premium operators who paid for badges)
- **WSIB registered contractors** (small firm filter)

Real estate:

- **TREB member directory** (Toronto Regional Real Estate Board)
- **RECO licensee registry** (Ontario)
- **Realtor.ca** agent profiles (for individual agents)

Dental:

- **RCDSO licensee search** (Ontario dental registry, public)
- **Ontario Dental Association member directory**
- **BC CDSBC registry** (British Columbia)

Consulting:

- **Canadian Association of Management Consultants (CMC) member search**
- Canadian small-consulting-firm LinkedIn lists maintained by various newsletters (find via Google search)

### Tier 3 — Volume sources (lower quality, for scale)

- **Google Maps** — filter by city + business type. Useful for local-focus verticals (moving, cleaning, construction). Lower quality because it mixes owner-operator shops with big chains and chains aren't in our ICP.
- **Chamber of Commerce member lists (Toronto, Mississauga, etc.)**
- **Canadian Trade Commissioner directories**

---

## List hygiene process

Before adding any contact to the outreach queue, verify:

### Per-contact verification

- [ ] **Active status:** last LinkedIn activity or business website still live. Abandoned firms = wasted outreach.
- [ ] **Decision-maker confirmation:** the person on the LinkedIn profile holds the decision-maker title (not just listed as one).
- [ ] **Email verified:** Apollo-provided email OR manually verified via a tool like Hunter.io, Neverbounce, or Apollo's verification. Bounces tank deliverability.
- [ ] **CASL implied consent check:** public business email on business website or Apollo = implied consent for B2B. Gmail/Yahoo personal = requires express consent or skip.
- [ ] **Not a competitor or on do-not-contact:** cross-check against exclusion list.
- [ ] **LinkedIn URL captured:** for mirror LinkedIn outreach.
- [ ] **Phone captured where available:** for voice follow-up windows 7+ days out.

### Batch verification

Before launching an outreach campaign against a batch:

- [ ] Batch size > 20 and < 100 (deliverability sweet spot)
- [ ] Geographic dispersion sane (not 80% in one zip code — signals list-buying)
- [ ] Title diversity sane (not 100% "Owner" — signals automated generation)
- [ ] First batch warmup complete if using a new Gmail sending domain

---

## Starting target: 100 brokers in first month

### Month 1 target breakdown

- **Week 1:** 30 insurance brokers in GTA, Sales Navigator-filtered + Apollo-enriched
- **Week 2:** 30 additional insurance brokers in rest of Ontario (Ottawa, London, Windsor, Kitchener-Waterloo)
- **Week 3:** 20 insurance brokers + 10 consulting practices (starting vertical 2)
- **Week 4:** 20 insurance brokers + 10 real estate agents (starting vertical 3)

Total: 100 in month 1, transitioning from single-vertical focus to diversified testing.

### Expected pipeline from 100 targeted touches

Based on realistic cold-outreach baselines:

- **100 cold outreach attempts** (Sequence A, 3 emails)
- **12-15% reply rate** → 12-15 replies
- **40-60% of replies are "interested enough to book a demo"** → 5-9 demos
- **40-60% of demos convert to paid client** (or POC) → 2-5 new paying clients

Month 1 target: **2-5 new clients**. MRR contribution: **$3,000-10,000** depending on vertical mix.

### Month 2-3 scaling

- **Month 2:** 150 targeted touches → expect 3-9 new clients (scaling as copy learns)
- **Month 3:** 200 targeted touches → expect 4-12 new clients (referrals starting to compound)

### Month 3 total target

50-150 targeted prospects per week sustained, with 5-10 clients signing monthly.

---

## Tracking in HubSpot

Mary uses HubSpot (separately configured) for her Crystallux-sales-pipeline tracking. Required fields per contact:

### Contact-level fields

- Name, title, company
- Work email, LinkedIn URL, phone (if available)
- Source (Sales Navigator, Apollo, RIBO, etc.)
- Vertical assignment
- CASL consent status (implied, express, or unknown)
- First outreach date
- Last activity date
- Stage (listed below)

### Deal-level fields (when a lead progresses)

- Deal stage (Contacted, Replied, Demo Booked, Demo Held, Proposal Sent, POC Active, Closed Won, Closed Lost)
- Deal size (estimated MRR)
- Vertical of client
- Founding vs standard tier
- Expected close date
- Objection captured

### Pipeline stages

```
1. Contacted           – outreach sent (email or LinkedIn)
2. Replied             – prospect responded
3. Demo Booked         – Calendly slot confirmed
4. Demo Held           – actually attended
5. Proposal Sent       – contract or POC offer out
6. POC Active          – 14-day POC running
7. Closed Won          – contract signed, Stripe subscription active
8. Closed Lost         – formally declined or ghosted > 30 days
```

---

## List maintenance cadence

### Daily (5 min)

- Add new names from today's prospecting
- Update status of any overnight replies
- Note any bounces for removal

### Weekly (30 min, Friday)

- Review conversion rates by source (Sales Navigator vs Apollo vs RIBO etc.)
- Kill underperforming filters
- Expand top-performing filter criteria by 20% (widen slightly)
- Update competitor-exclusion list if any new competitor emerges

### Monthly (60 min, month-end)

- Full audit: list vs HubSpot reconciliation
- Deliverability review (via Google Postmaster + MXToolbox)
- Dead-contact purge (6+ months no activity with no reply)
- Strategy reflection: which source is producing the most booked demos?

### Quarterly (2 hours, quarter-end)

- Vertical prioritisation: which of the 5 active verticals is closing fastest? Allocate more prospecting here.
- Geographic expansion decision: stay Ontario-focused or expand to BC/Alberta?
- List-size decision: am I prospecting too little? Too much? What does the conversion ratio tell me?

---

## Tools investment (budget: ~$250/month)

| Tool | Monthly | Purpose |
|---|---:|---|
| LinkedIn Sales Navigator Essentials | $99 CAD | Primary prospecting |
| Apollo.io Basic | $49 USD (~$65 CAD) | Email enrichment |
| Hunter.io or Neverbounce (as-needed) | $20-50 CAD | Email verification |
| HubSpot CRM | Free (grow to Sales Hub Starter when volume justifies) | Pipeline tracking |
| Instantly.ai OR n8n (for sending from Mary's own outreach) | $37 CAD (Instantly) | Outbound delivery (when volume exceeds 40/day manual from Gmail) |

Total tooling: ~$230 CAD/month. Payback: one client close (smallest $997) × 4 months.

---

## Anti-patterns to avoid

- **Buying contact lists** — universally bad quality, CASL risk, damages deliverability
- **Scraping at scale** — LinkedIn and Google Maps restrict this; Unipile is the authorised LinkedIn automation path
- **Mass-emailing from personal Gmail** — deliverability tanks fast; use a dedicated domain + warmup
- **Skipping CASL consent check** — legal risk outweighs any short-term deliverability win
- **Targeting outside the ICP for volume** — wastes budget and introduces churn from the wrong buyers
- **Not logging activity in HubSpot** — untracked outreach is invisible; invisible activity can't be optimised
