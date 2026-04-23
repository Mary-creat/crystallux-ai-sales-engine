# Vertical Expansion Ranking

**Scope:** 7 verticals seeded in `2026-04-24-verticals-batch-full.sql`. insurance_broker is the existing baseline (validated in production) and sits outside this ranking.

**Ranking dimensions** (equal weight, 1-10 scale):

- **Speed to revenue** — first-client contract signed, first invoice paid
- **Ease of outreach** — buyer accessibility, sales cycle compression
- **Likely LTV** — 12-month revenue per client, retention profile
- **Pain intensity** — how acutely the target feels the problem today
- **Platform fit** — how well the existing stack (Apollo + multi-channel + video + dashboard) maps to this audience

Sum / 50. Top 4 are active in this migration; bottom 3 are inactive.

| Rank | Vertical | Speed | Ease | LTV | Pain | Fit | **Total** | Status |
|---:|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 1 | **consulting** | 9 | 9 | 9 | 8 | 10 | **45/50** | 🟢 active |
| 2 | **real_estate** | 9 | 8 | 8 | 9 | 9 | **43/50** | 🟢 active |
| 3 | **construction** | 7 | 7 | 10 | 9 | 9 | **42/50** | 🟢 active |
| 4 | **dental** | 7 | 7 | 9 | 7 | 9 | **39/50** | 🟢 active |
| 5 | legal | 5 | 5 | 9 | 7 | 8 | 34/50 | 🔴 inactive |
| 6 | moving_services | 8 | 7 | 5 | 8 | 8 | 36/50 | 🔴 inactive |
| 7 | cleaning_services | 7 | 7 | 5 | 7 | 8 | 34/50 | 🔴 inactive |

Note: moving_services scores 36 > legal's 34, but is still inactive because the $997 AOV doesn't cover operating leverage until the top-4 clients hit scale. Ranking intentionally weights sustainable margin over raw fit.

---

## 1. Consulting — rank #1 (active)

**Why this rank:** consultants buy fastest. They recognise the math on a discovery call immediately (one $25K engagement pays the platform 12 months over), they have budget authority, and their pain (feast-or-famine, bizdev eating weekends) maps 1:1 to what Crystallux does. Platform fit is a perfect 10 — LinkedIn + email + voice is the exact stack this audience lives on.

**First-client timeline:** 5-10 business days from first outreach to signed contract + first payment.

**Blockers to execute:**
- Need two named case studies before going upmarket to $5M+ consulting shops.
- LinkedIn channel must be credentialed live (scaffolded, activation pending — see OPERATIONS_HANDBOOK §14.1).

---

## 2. Real Estate — rank #2 (active)

**Why this rank:** volume + urgency. Canadian market has ~160,000 active agents, and every month without a listing is zero commission. Platform delivers what agents hunt daily (pre-MLS seller signals), and the ROI math on one listing (12-18K commission) covers 10 months of fees. Slightly behind consulting on fit because the residential buyer depends on SMS, which requires Twilio WhatsApp approval.

**First-client timeline:** 3-7 business days. Agents decide fast.

**Blockers to execute:**
- Twilio WhatsApp sender approval (1-3 day Meta review) — critical for the primary residential channel.
- Per-province real estate council rules (RECO Ontario strictest) require copy review before first send.

---

## 3. Construction — rank #3 (active)

**Why this rank:** highest deal size in the active set. Average reno is $40-120K; one booked project pays platform fee 30+ months. Contractors are skeptical of tech vendors but respond to peer-advisor framing. Fit is strong — email + voice + WhatsApp + video all map to how contractors communicate. Slower than consulting/real_estate because operators are on jobsites during business hours.

**First-client timeline:** 7-14 business days (scheduling friction on operator side).

**Blockers to execute:**
- Operator availability — jobsite owners hard to reach 9-5. Need evening/weekend voice outreach carve-outs in DNCL config.
- Commercial construction segment has 60-90 day cycles; start clients in residential-focused mode.

---

## 4. Dental — rank #4 (active)

**Why this rank:** strongest retention economics of any vertical (patient LTV $1,500-3,500), and owner-operators understand chair-hour math. Ranks below top 3 due to regulatory overhead: RCDSO / BC College / Alberta Dental Association advertising rules require per-province copy review before first send, adding 3-5 days to activation.

**First-client timeline:** 10-21 business days. Compliance review + front-desk change management extend the window.

**Blockers to execute:**
- Per-province regulatory copy review (mandatory before any outreach).
- Front-desk workflow integration — staff must route inbound consult calls to the new booking flow.
- Avoid outcome language, diagnostic claims, comparative claims in every template.

---

## 5. Legal — rank #5 (INACTIVE)

**Why this rank:** not a fit problem — a compliance gate. Law Society advertising rules in every province require every outreach template to be reviewed against jurisdiction-specific restrictions. Cannot activate without a law-society-practising advising lawyer.

**First-client timeline (when activated):** 21-45 business days. Longest cycle in the catalog.

**Blockers to execute:**
1. **Need an advising lawyer** willing to sign off on per-province template bank. Not optional.
2. Per-province variants required (Ontario / BC / Alberta / Quebec minimum).
3. Slow sales cycle doubles CAC until 2 reference clients are in place.

**When to activate:** only after a founder legal client signs and commits to helping establish compliant templates.

---

## 6. Moving Services — rank #6 (INACTIVE)

**Why this rank:** solid fit + high pain intensity, but $997 AOV with high-churn client-side customers makes platform unit economics difficult until Crystallux has operating leverage. Strong playbook — just needs scale.

**First-client timeline (when activated):** 5-10 business days.

**Blockers to execute:**
1. Platform operating leverage — at $997 AOV, Crystallux needs shared ops and template-driven onboarding to break even.
2. SMS channel (primary conversion for residential movers) requires Twilio WhatsApp live.
3. Retention playbook for winter-season churn not yet built.

**When to activate:** after top-4 actives hit ≥3 paying clients each and operating leverage is proven.

---

## 7. Cleaning Services — rank #7 (INACTIVE)

**Why this rank:** same structural issue as moving. $997 AOV, high client-side customer churn, operator-side cleaner turnover creates inconsistent delivery. Crystallux delivers leads well; the operator has to hold up their end.

**First-client timeline (when activated):** 5-10 business days residential; 30-60 days commercial.

**Blockers to execute:**
1. Platform operating leverage same as moving_services.
2. Needs at least one cleaning-vertical founding client as reference.
3. Client-side quality-delivery variance risks reputation damage if lead volume exceeds operator capacity — pace controls required.

**When to activate:** after top-4 actives mature and at least one cleaning-vertical reference lead signs.

---

## Summary table — by strategic purpose

| Purpose | Best vertical |
|---|---|
| **Fastest cash-in** | consulting (5-10 day close) |
| **Highest unit LTV** | dental (recurring patient LTV) or construction (high-value project AOV) |
| **Highest volume potential** | real_estate (~160K agents in Canada) |
| **Biggest moat once established** | dental (regulatory moat) or legal (compliance moat) |
| **Easiest first-100 clients** | consulting + real_estate in parallel |
| **Backup verticals when top 4 saturate** | moving_services + cleaning_services |
| **Hold for founder-client catalyst** | legal |

## Activation sequence recommendation

1. **Weeks 1-4:** consulting + real_estate in parallel. Target 3 signed clients total.
2. **Weeks 5-8:** add construction. Target 5 total signed across the three.
3. **Weeks 9-12:** add dental after per-province compliance templates are drafted.
4. **Month 4+:** re-evaluate moving + cleaning based on operating leverage state.
5. **Month 4+:** legal activation gated on founder-client catalyst.
