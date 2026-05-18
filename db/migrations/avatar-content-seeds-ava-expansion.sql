-- ══════════════════════════════════════════════════════════════════
-- AVA content seeds — expansion (T1.6 / 80 topics, 5 streams)
-- ══════════════════════════════════════════════════════════════════
-- Companion to avatar-content-seeds-ava.sql (commit 4560d9b → 667bc88,
-- which seeded the first 24 topics under the a0a0-0000-… → 0008-…
-- stream-code blocks).
--
-- This migration adds 80 more topics, raising AVA's total content
-- inventory to 104. Stream layout:
--
--   Stream 1   Insurance education          25 topics  (0010-0016)
--   Stream 2   Advisor recruitment          20 topics  (0020-0028)
--   Stream 3   Carrier partnership          15 topics  (0030-0036)   <- new theme
--   Stream 4   AdvisorAssist promotion      10 topics  (0040-0047)
--   Stream 5   RIBO Study Coach             10 topics  (0050-0056)
--
-- UUIDs follow `00000000-a0a0-NNNN-MMMM-000000000ZZZ` — same vanity
-- prefix as the first batch, with NNNN bumped to 0010+ to avoid
-- collision with the existing 24 (which used 0000-0008). All hex-valid
-- (lesson from [[uuid-vanity-prefix-trap]]).
--
-- Weights bias the topic rotation in the script writer:
--   90 — flagship (priority_score ≥ 85)
--   70 — strong evergreen (≥ 75)
--   50 — default (≥ 65)
--   30 — niche / supplementary
--
-- Idempotent (ON CONFLICT (id) DO NOTHING on both inserts).
-- No rollback required — orphaned content_topics rows are harmless.
-- ══════════════════════════════════════════════════════════════════

-- Resolve AVA id once to fail fast if the previous migrations weren't applied.
DO $$
DECLARE ava_id uuid;
BEGIN
  SELECT id INTO ava_id FROM avatars WHERE avatar_name = 'AVA';
  IF ava_id IS NULL THEN
    RAISE EXCEPTION 'AVA avatar not found — run avatars-platform-schema.sql first.';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────
-- Content topics — 80 rows
-- ─────────────────────────────────────────────────────────────────

INSERT INTO content_topics (id, vertical, avatar_id, topic_title, topic_description, generated_by, status, priority_score)
SELECT * FROM (VALUES
  -- ════════ STREAM 1 — Insurance education (25) ════════

  -- Life insurance deepening (5)
  ('00000000-a0a0-0010-0001-000000000001'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Indexed universal life: the promise vs the small print$av$,
   $av$IUL marketing oversells the cap and the participation rate. Walk through what those numbers actually do to a 20-year projection.$av$,
   'admin', 'approved', 80),
  ('00000000-a0a0-0010-0002-000000000002'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Level term vs decreasing term: pick the one your mortgage actually wants$av$,
   $av$When decreasing term saves $30/mo against your amortization; when it costs you at renewal once the principal is paid down.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0010-0003-000000000003'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Joint last-to-die: the estate-tax product nobody understood until it was too late$av$,
   $av$How second-to-die pays the CRA bill at the second death and protects the kids' inheritance. Who actually needs it.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0010-0004-000000000004'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Convertible term: the option you bought without realizing it$av$,
   $av$Inside your conversion window you can flip to permanent with no medical. The deadlines + the cliff after they pass.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0010-0005-000000000005'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Life insurance and the CRA: when proceeds are taxable, and when they're not$av$,
   $av$Beneficiary designations, corporate-owned policies, the CDA bump, and the three structures that trip people up.$av$,
   'admin', 'approved', 80),

  -- Auto insurance deepening (5)
  ('00000000-a0a0-0011-0001-000000000006'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Total loss: how the insurer values your car the day it gets written off$av$,
   $av$ACV vs replacement-cost vs OPCF 43 explained against a real claim. What each clause pays out on a 4-year-old vehicle.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0011-0002-000000000007'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Auto deductibles: the $1,000 swing that doesn't always pay for itself$av$,
   $av$Break-even math on raising your deductible from $500 to $1000 vs $2000. The driver profile where each makes sense.$av$,
   'admin', 'approved', 65),
  ('00000000-a0a0-0011-0003-000000000008'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Reporting a claim vs paying out of pocket: the 3-year decision$av$,
   $av$How a single claim affects your renewal rate over the surcharge period. The threshold below which paying yourself wins.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0011-0004-000000000009'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Ridesharing endorsement: why your personal policy probably excludes Uber$av$,
   $av$OPCF 6A in plain English; ridesharing fleet alternatives; the gap in coverage when the app is on but you haven't accepted a ride.$av$,
   'admin', 'approved', 65),
  ('00000000-a0a0-0011-0005-000000000010'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Classic + collector car: when your daily-driver policy is silently wrong$av$,
   $av$Agreed-value coverage, restoration limits, mileage caps. The three things that make a collector policy a different product entirely.$av$,
   'admin', 'approved', 55),

  -- Home insurance deepening (4)
  ('00000000-a0a0-0012-0001-000000000011'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Water damage: the four categories your policy treats completely differently$av$,
   $av$Plumbing burst vs overland flood vs sewer backup vs ice dam. Two are usually excluded. The riders to add for full coverage.$av$,
   'admin', 'approved', 85),
  ('00000000-a0a0-0012-0002-000000000012'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Airbnb / short-term rental: how to keep coverage when you rent out a room$av$,
   $av$The home-business exclusions to watch, the endorsement options, and the carriers that won't insure it at all.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0012-0003-000000000013'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Vacant home: the 30-60-90-day rule that voids policies silently$av$,
   $av$Long trips, listing for sale, snowbird seasons. When you need a vacancy permit and what happens to coverage during the gap.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0012-0004-000000000014'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Personal liability outside your home: the umbrella every parent should have$av$,
   $av$House parties, your kid's hockey practice, your dog on a walk. Standard $1M is often too little — when $5M umbrella is cheap insurance.$av$,
   'admin', 'approved', 70),

  -- Travel insurance deepening (3)
  ('00000000-a0a0-0013-0001-000000000015'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Family travel policies: when one annual policy beats per-trip$av$,
   $av$Frequent-traveller math; the trip-count threshold where annual wins; covering kids who travel separately.$av$,
   'admin', 'approved', 60),
  ('00000000-a0a0-0013-0002-000000000016'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$COVID and travel insurance: what's actually still covered in 2026$av$,
   $av$Post-pandemic coverage reality; the new pre-existing-condition language; cancellation-for-quarantine clauses.$av$,
   'admin', 'approved', 65),
  ('00000000-a0a0-0013-0003-000000000017'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Adventure-sports rider: skiing, scuba, anything off-pavement$av$,
   $av$Sports excluded by default + how to add them. The altitude / depth / speed thresholds in the fine print.$av$,
   'admin', 'approved', 55),

  -- Critical illness deepening (2)
  ('00000000-a0a0-0014-0001-000000000018'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Childhood CI: the policy you take out before there's a problem$av$,
   $av$Locks in low rates + covers childhood-specific conditions. Conversion options at age 21. The argument for $50k coverage on a 6-year-old.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0014-0002-000000000019'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$CI return-of-premium variants: 15-year vs 75-year ROP$av$,
   $av$Two completely different products with similar names. The premium delta vs the recovery probability. Who each fits.$av$,
   'admin', 'approved', 65),

  -- Disability deepening (2)
  ('00000000-a0a0-0015-0001-000000000020'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Disability insurance for self-employed: closing the EI gap$av$,
   $av$Self-employed don't get EI sickness benefits. Private DI is the only floor. Costs vs benefit math for the typical small-business owner.$av$,
   'admin', 'approved', 80),
  ('00000000-a0a0-0015-0002-000000000021'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Disability + workers comp: when WSIB isn't enough$av$,
   $av$Provincial WSIB caps + the income gap above them. Private DI top-up math for trades + healthcare workers.$av$,
   'admin', 'approved', 70),

  -- Newer product lines (4)
  ('00000000-a0a0-0016-0001-000000000022'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Business overhead expense (BOE): the insurance for keeping the lights on$av$,
   $av$DI variant that pays rent + payroll + utilities while the owner is disabled. The product solo proprietors forget exists.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0016-0002-000000000023'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Group benefits for the 5-person shop: cheaper than you think$av$,
   $av$Plan design + the carriers that quote small-group + the LIVE issue threshold where premiums actually start to compress.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0016-0003-000000000024'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Insurance trusts: when your spouse shouldn't be the direct beneficiary$av$,
   $av$Minor children, blended families, creditor protection. The three reasons to name a trust + the cost of getting it set up.$av$,
   'admin', 'approved', 65),
  ('00000000-a0a0-0016-0004-000000000025'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Segregated funds vs mutual funds: insurance-wrapper investing explained$av$,
   $av$75/100 guarantees, named-beneficiary bypass of probate, lock-in periods. Who wins when each is the right tool.$av$,
   'admin', 'approved', 70),

  -- ════════ STREAM 2 — Advisor recruitment (20) ════════

  -- Why join Crystallux (3)
  ('00000000-a0a0-0020-0001-000000000026'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Why I left a captive carrier for Crystallux MGA — Mary's story$av$,
   $av$First-person. Concrete commission delta + lead pipeline + lifestyle change after the move. Honest about what was harder.$av$,
   'admin', 'approved', 80),
  ('00000000-a0a0-0020-0002-000000000027'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Crystallux MGA: what we are not (we are not a lead-mill)$av$,
   $av$Honest positioning vs the LinkedIn-ad MGAs. What we won't promise; what we will. Sets the tone for the advisor we want.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0020-0003-000000000028'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$The 90-day promise we make to new Crystallux advisors$av$,
   $av$Concrete deliverables in the first three months: carriers, leads, training, first sales. What you owe us back.$av$,
   'admin', 'approved', 80),

  -- Get leads without buying (2)
  ('00000000-a0a0-0021-0001-000000000029'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Lead generation 2026: stop buying $40 shared internet leads$av$,
   $av$Why purchased leads convert 4x worse than warm referrals; how Crystallux turns content into qualified pipeline.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0021-0002-000000000030'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Our content engine: how one video becomes 30 leads over 90 days$av$,
   $av$Behind-the-scenes of the AVA content pipeline + the attribution we track per advisor per topic.$av$,
   'admin', 'approved', 70),

  -- Higher commission splits (2)
  ('00000000-a0a0-0022-0001-000000000031'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$What MGA splits really mean: gross vs net commission math$av$,
   $av$Read the contract. The "85% split" is often 85% OF NET, not of gross. Worked example with real numbers.$av$,
   'admin', 'approved', 80),
  ('00000000-a0a0-0022-0002-000000000032'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Renewal commissions: the income you don't think about until year 3$av$,
   $av$Why Crystallux's renewal structure matters more than first-year split. 10-year income projection comparison.$av$,
   'admin', 'approved', 75),

  -- Multi-carrier access (2)
  ('00000000-a0a0-0023-0001-000000000033'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Why being tied to one carrier costs your clients money$av$,
   $av$A real example where three carriers quoted the same case at $X / $Y / $Z. The conversation that earned the referral.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0023-0002-000000000034'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Carriers we represent + the ones we don't (and why)$av$,
   $av$Honest about our gaps. We're not for every advisor — and the gaps tell you whether we fit your book.$av$,
   'admin', 'approved', 70),

  -- AI-powered compliance (2)
  ('00000000-a0a0-0024-0001-000000000035'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$FSRA + RIBO compliance: how AVA helps you not screw up$av$,
   $av$The compliance agent + the audit trail + the escalation paths. The three patterns it catches before they become problems.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0024-0002-000000000036'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$The advisor-side audit log: why your future-self will thank you$av$,
   $av$Every interaction logged. Protects you in a complaint. The one screen that resolves 80% of regulator inquiries.$av$,
   'admin', 'approved', 70),

  -- AdvisorAssist for productivity (2)
  ('00000000-a0a0-0025-0001-000000000037'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$AdvisorAssist: $49/mo saves 6 hours of admin a week$av$,
   $av$Concrete use cases for the Starter tier — needs analyses + client renewal alerts + FSRA-aware scripts.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0025-0002-000000000038'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$From 12 to 40 active clients, same hours: the AdvisorAssist math$av$,
   $av$Operational leverage explained. Where the time goes today + which features eliminate which task.$av$,
   'admin', 'approved', 70),

  -- Success stories (2)
  ('00000000-a0a0-0026-0001-000000000039'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$From rookie to $X in 12 months: an advisor's first year at Crystallux$av$,
   $av$Concrete numbers + what they actually did month-by-month. The first three sales + how they got there.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0026-0002-000000000040'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Second-career advisors: making 35-year-olds and 55-year-olds both succeed$av$,
   $av$Profiles of two non-traditional advisors. What they brought from prior careers; what made the difference in year one.$av$,
   'admin', 'approved', 70),

  -- How to apply / onboarding (3)
  ('00000000-a0a0-0027-0001-000000000041'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$How to apply to Crystallux MGA: the 4-step process$av$,
   $av$Application → screen → license check → offer. Timeline + paperwork + the three questions our principal asks every applicant.$av$,
   'admin', 'approved', 80),
  ('00000000-a0a0-0027-0002-000000000042'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Your first 30 days as a Crystallux advisor: the onboarding playbook$av$,
   $av$The curriculum + the daily check-ins + the carrier appointments. Day-by-day for the first six weeks.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0027-0003-000000000043'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$New advisor compliance bootcamp: the FSRA + RIBO modules in week one$av$,
   $av$The seven modules every new advisor finishes before their first client call. Why the order matters.$av$,
   'admin', 'approved', 65),

  -- What we expect (2)
  ('00000000-a0a0-0028-0001-000000000044'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$What Crystallux expects: the 3 things we won't compromise on$av$,
   $av$Ethics, response time, recurring training. Concrete examples of where we've parted ways with advisors who didn't deliver.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0028-0002-000000000045'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$We measure response time, not raw activity$av$,
   $av$Our SLA for first-touch on a lead + why it matters more than dialer-count. The dashboards advisors actually see.$av$,
   'admin', 'approved', 70),

  -- ════════ STREAM 3 — Carrier partnership (15) ════════

  -- Why carriers partner (3)
  ('00000000-a0a0-0030-0001-000000000046'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Why life carriers partner with Crystallux: our advisor screen$av$,
   $av$Our application process filters. Carriers see a cleaner book. The vetting we do before any contract is signed.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0030-0002-000000000047'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Carrier loss ratio at Crystallux: better than channel average$av$,
   $av$The number that earns carriers' attention. How our compliance-first approach affects the book's 24-month performance.$av$,
   'admin', 'approved', 80),
  ('00000000-a0a0-0030-0003-000000000048'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Multi-carrier shelf: how we serve clients without favouritism$av$,
   $av$Best-fit recommendation engine + audit trail. How carriers see their share-of-fit, not just share-of-sales.$av$,
   'admin', 'approved', 70),

  -- Our advisor quality (2)
  ('00000000-a0a0-0031-0001-000000000049'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$FSRA-licensed advisors: our continuing-education compliance$av$,
   $av$100% CE on-track. The dashboards we share with partner carriers. The advisors who don't stay current don't stay.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0031-0002-000000000050'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Background + book quality: our two-stage pre-onboarding screen$av$,
   $av$What gets through and what doesn't. The five red flags we catch before granting MGA contracting.$av$,
   'admin', 'approved', 65),

  -- Compliance reduces risk (2)
  ('00000000-a0a0-0032-0001-000000000051'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Compliance-by-design: how our AI agent reduces E&O claims$av$,
   $av$Specific examples of issues flagged pre-sale. The compliance-cost-vs-claims math that justifies the system.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0032-0002-000000000052'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Carrier-side audit access: full transparency on every sale$av$,
   $av$How carriers can pull their book's compliance scorecard on demand. The drill-down by advisor + product.$av$,
   'admin', 'approved', 65),

  -- Multi-vertical exposure (2)
  ('00000000-a0a0-0033-0001-000000000053'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Insurance + adjacent verticals: cross-sell without confusion$av$,
   $av$How AVA handles a multi-product conversation without straying outside FSRA / RIBO scope. Soft hand-offs to specialist advisors.$av$,
   'admin', 'approved', 60),
  ('00000000-a0a0-0033-0002-000000000054'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Our client base: demographics + buying patterns$av$,
   $av$Carriers see the segments before signing. Age + income + product-mix breakdown of our active book.$av$,
   'admin', 'approved', 65),

  -- Modern technology (2)
  ('00000000-a0a0-0034-0001-000000000055'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Real-time submissions: digital intake + e-signature + carrier API$av$,
   $av$How submissions hit your underwriter same-day. The 6 fields we always pre-fill and the 3 that always need clarification.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0034-0002-000000000056'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Performance dashboards: per-advisor + per-carrier$av$,
   $av$Carriers see their book's velocity vs our other carriers (anonymized). The data feed every quarterly review now uses.$av$,
   'admin', 'approved', 60),

  -- How to onboard (2)
  ('00000000-a0a0-0035-0001-000000000057'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Carrier partnership: the 4-step onboarding process$av$,
   $av$Initial pitch → terms → contracting → pilot. Timeline (~3 weeks end-to-end) + what each step actually requires.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0035-0002-000000000058'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Carrier-side mutual-due-diligence checklist$av$,
   $av$Documentation we need from carriers + what we provide. Sets expectations so the contracting call isn't a surprise.$av$,
   'admin', 'approved', 55),

  -- Approval process (2)
  ('00000000-a0a0-0036-0001-000000000059'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Crystallux carrier approval: 3 weeks end-to-end$av$,
   $av$Why we can do it fast (and what we need from you). The two delays that cost the most time, and how to avoid them.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0036-0002-000000000060'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Pilot phase: 90-day partnership trial before full rollout$av$,
   $av$Sandbox period structure + KPIs both sides agree on. The exit ramp if either side decides not to proceed.$av$,
   'admin', 'approved', 60),

  -- ════════ STREAM 4 — AdvisorAssist promotion (10) ════════

  ('00000000-a0a0-0040-0001-000000000061'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$AdvisorAssist: needs-analysis in 5 minutes, not 45$av$,
   $av$Live demo of the needs-analysis flow. The five inputs that get you to a credible coverage recommendation.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0040-0002-000000000062'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Compliance script generator: every client conversation, FSRA-compliant$av$,
   $av$Demo + before/after time stamps. Generates the conversation outline an advisor can read on the call.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0041-0001-000000000063'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$AdvisorAssist ROI: $49/mo to recover 24 hours/mo$av$,
   $av$Time-to-value math. At $50/hr opportunity cost, the tool returns its monthly fee on day 1 of week 1.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0042-0001-000000000064'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$How Sarah went from 8 to 22 active clients in Q1 using AdvisorAssist$av$,
   $av$Real before/after numbers from one advisor's funnel. The two features that moved the needle most.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0042-0002-000000000065'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$An advisor's typical week: with vs without AdvisorAssist$av$,
   $av$Concrete time blocks. Monday-to-Friday calendar of an active advisor in both states. Where the saved time goes.$av$,
   'admin', 'approved', 65),
  ('00000000-a0a0-0043-0001-000000000066'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$AdvisorAssist 14-day free trial: what to try first$av$,
   $av$The 4 features that prove value fastest. Order matters — the first thing to set up is the renewal-alert config.$av$,
   'admin', 'approved', 65),
  ('00000000-a0a0-0044-0001-000000000067'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$AdvisorAssist vs SalesLogix vs Wealthbox: honest comparison$av$,
   $av$Where AA wins + where it doesn't. The advisor profile each tool actually fits.$av$,
   'admin', 'approved', 65),
  ('00000000-a0a0-0045-0001-000000000068'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$The 7 admin tasks AdvisorAssist eliminates$av$,
   $av$Specific tasks + minutes saved each. Renewal reminders, NIGO follow-ups, compliance one-pagers, post-call notes…$av$,
   'admin', 'approved', 60),
  ('00000000-a0a0-0046-0001-000000000069'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$AdvisorAssist for solo advisors vs 5-person teams$av$,
   $av$Different feature sets for different shop sizes. Where Starter is enough + where Pro starts to pay back fastest.$av$,
   'admin', 'approved', 60),
  ('00000000-a0a0-0047-0001-000000000070'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$AdvisorAssist pricing: every tier + what's included$av$,
   $av$Starter $49 / Pro $99 / Premium $149. Feature-by-feature. The tier most solo advisors land on after their trial.$av$,
   'admin', 'approved', 75),

  -- ════════ STREAM 5 — RIBO Study Coach (10) ════════

  ('00000000-a0a0-0050-0001-000000000071'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$RIBO study tip: the morning 20 minutes that gets you 60% of the way$av$,
   $av$Daily anchoring strategy. Why the first 20 minutes after waking outperform any other study block in retention.$av$,
   'admin', 'approved', 65),
  ('00000000-a0a0-0050-0002-000000000072'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$Spaced repetition for RIBO: the science-backed schedule$av$,
   $av$Day 1, 3, 7, 14, 30 review pattern. Why cramming the week before fails for a regulatory exam.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0051-0001-000000000073'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$RIBO practice exam: 50 questions that mirror the real one$av$,
   $av$Free sample + how to use it. Score thresholds that correlate with first-try pass.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0052-0001-000000000074'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$RIBO exam day: the 6-hour breakdown that beats fatigue$av$,
   $av$Section-by-section pacing strategy. When to skip + come back. The 3 minutes per question rule + when to break it.$av$,
   'admin', 'approved', 70),
  ('00000000-a0a0-0052-0002-000000000075'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$RIBO trick-question patterns: the 5 wording tells$av$,
   $av$Identifying which questions are deliberately misleading. "All of the above" + the double-negative trap explained.$av$,
   'admin', 'approved', 65),
  ('00000000-a0a0-0053-0001-000000000076'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$RIBO Study Coach pass-rate testimonials$av$,
   $av$Quotes from 12 students who used the program. Before/after study habits + score deltas.$av$,
   'admin', 'approved', 60),
  ('00000000-a0a0-0054-0001-000000000077'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$RIBO Study Coach pricing tiers: $29 vs $49 vs $79 compared$av$,
   $av$What's in each tier. Who needs what — full-time students vs part-timers vs second-try retakers.$av$,
   'admin', 'approved', 75),
  ('00000000-a0a0-0055-0001-000000000078'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$RIBO in 30 days: an aggressive but doable study plan$av$,
   $av$Daily breakdown for full-time students. The two weeks that matter most — and what to skip if you fall behind.$av$,
   'admin', 'approved', 65),
  ('00000000-a0a0-0056-0001-000000000079'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$RIBO topic deep-dive: tort vs contract law for insurance$av$,
   $av$One of the trickiest sections, explained without the lawyer-speak. Three worked examples that map to exam scenarios.$av$,
   'admin', 'approved', 60),
  ('00000000-a0a0-0056-0002-000000000080'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
   $av$RIBO topic: claims handling timelines and the 30-day rule$av$,
   $av$A high-frequency exam topic. The four statutory deadlines, what triggers each, and where exams test the edges.$av$,
   'admin', 'approved', 65)
) AS t(id, vertical, avatar_id, topic_title, topic_description, generated_by, status, priority_score)
ON CONFLICT (id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- Weighted join — avatar_knowledge_topics
-- ─────────────────────────────────────────────────────────────────
-- Same weighting bands as the first 24:
--   priority_score >= 85 → weight 90 (flagship)
--   priority_score >= 75 → weight 70 (strong evergreen)
--   priority_score >= 65 → weight 50 (default)
--   else                 → weight 30 (niche)

INSERT INTO avatar_knowledge_topics (avatar_id, content_topic_id, weight)
SELECT
  (SELECT id FROM avatars WHERE avatar_name = 'AVA'),
  ct.id,
  CASE
    WHEN ct.priority_score >= 85 THEN 90
    WHEN ct.priority_score >= 75 THEN 70
    WHEN ct.priority_score >= 65 THEN 50
    ELSE 30
  END
FROM content_topics ct
WHERE ct.id::text LIKE '00000000-a0a0-001%'
   OR ct.id::text LIKE '00000000-a0a0-002%'
   OR ct.id::text LIKE '00000000-a0a0-003%'
   OR ct.id::text LIKE '00000000-a0a0-004%'
   OR ct.id::text LIKE '00000000-a0a0-005%'
ON CONFLICT (avatar_id, content_topic_id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- Verify
-- ─────────────────────────────────────────────────────────────────
-- After running, this should return 80:
--
--   SELECT count(*) FROM content_topics WHERE id::text LIKE '00000000-a0a0-001%'
--                                          OR id::text LIKE '00000000-a0a0-002%'
--                                          OR id::text LIKE '00000000-a0a0-003%'
--                                          OR id::text LIKE '00000000-a0a0-004%'
--                                          OR id::text LIKE '00000000-a0a0-005%';
--
-- And total AVA topics (counting the first 24 from 4560d9b):
--
--   SELECT count(*) FROM avatar_knowledge_topics
--   WHERE avatar_id = (SELECT id FROM avatars WHERE avatar_name = 'AVA');
--   -- expect 104
-- ═══════════════════════════════════════════════════════════════════
