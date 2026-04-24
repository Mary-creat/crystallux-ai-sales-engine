-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX CLOSING INTELLIGENCE CLIENT-FACING (Phase B.12a-1)
-- File: docs/architecture/migrations/2026-04-24-closing-intelligence-client-facing.sql
--
-- Extends the existing Closing Intelligence tables (from
-- 2026-04-18-closing-intelligence.sql) with:
--   * usage tracking columns on closing_scripts, objection_handlers,
--     discovery_frameworks
--   * script_usage_log audit table
--   * RPCs: record_script_usage, get_scripts_for_lead,
--           get_agent_script_performance
--   * seed data for 7 additional verticals (construction,
--     moving_services, cleaning_services, real_estate, dental,
--     legal, consulting). Insurance broker seed is already present.
--
-- Schema note: the pre-existing closing tables use `niche_name`
-- (not `vertical`) and closing_scripts uses `close_type` +
-- `trigger_condition` (not `situation`). RPCs below query by those
-- actual column names. The spec's placeholder column names are
-- translated to the live schema.
--
-- Idempotent — safe to re-run. Rollback trailing.
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────
-- 1. USAGE-TRACKING COLUMNS
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE closing_scripts
  ADD COLUMN IF NOT EXISTS times_used       integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS conversion_rate  numeric(5,2),
  ADD COLUMN IF NOT EXISTS last_used_at     timestamptz;

ALTER TABLE objection_handlers
  ADD COLUMN IF NOT EXISTS times_used       integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS conversion_rate  numeric(5,2);

ALTER TABLE discovery_frameworks
  ADD COLUMN IF NOT EXISTS times_used       integer DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_closing_scripts_usage
  ON closing_scripts(times_used DESC, conversion_rate DESC NULLS LAST)
  WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_objection_handlers_usage
  ON objection_handlers(times_used DESC, conversion_rate DESC NULLS LAST)
  WHERE is_active = true;


-- ─────────────────────────────────────────────────────────────────
-- 2. SCRIPT_USAGE_LOG AUDIT TABLE
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS script_usage_log (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id               uuid REFERENCES team_members(id) ON DELETE SET NULL,
  client_id              uuid REFERENCES clients(id) ON DELETE SET NULL,
  lead_id                uuid REFERENCES leads(id) ON DELETE SET NULL,
  script_id              uuid,
  script_type            text,
  context_notes          text,
  outcome                text,
  used_at                timestamptz DEFAULT now(),
  outcome_recorded_at    timestamptz,
  feedback_rating        integer
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'script_usage_log_script_type_check') THEN
    ALTER TABLE script_usage_log
      ADD CONSTRAINT script_usage_log_script_type_check
      CHECK (script_type IN ('discovery','objection','closing','proposal','follow_up','competitor'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'script_usage_log_outcome_check') THEN
    ALTER TABLE script_usage_log
      ADD CONSTRAINT script_usage_log_outcome_check
      CHECK (outcome IN ('used','rejected','modified','converted','not_converted'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'script_usage_log_rating_check') THEN
    ALTER TABLE script_usage_log
      ADD CONSTRAINT script_usage_log_rating_check
      CHECK (feedback_rating IS NULL OR (feedback_rating BETWEEN 1 AND 5));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_script_usage_agent_date  ON script_usage_log(agent_id, used_at DESC);
CREATE INDEX IF NOT EXISTS idx_script_usage_lead        ON script_usage_log(lead_id);
CREATE INDEX IF NOT EXISTS idx_script_usage_client_date ON script_usage_log(client_id, used_at DESC);

ALTER TABLE script_usage_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS script_usage_log_service_role_all ON script_usage_log;
CREATE POLICY script_usage_log_service_role_all ON script_usage_log
  FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────
-- 3. RPC: RECORD_SCRIPT_USAGE
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION record_script_usage(
  p_agent_id    uuid,
  p_lead_id     uuid,
  p_script_id   uuid,
  p_script_type text,
  p_context     text,
  p_outcome     text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_id     uuid;
  v_client   uuid;
BEGIN
  -- Derive client_id from lead if present
  SELECT client_id INTO v_client FROM leads WHERE id = p_lead_id;

  INSERT INTO script_usage_log (agent_id, client_id, lead_id, script_id, script_type, context_notes, outcome)
  VALUES (p_agent_id, v_client, p_lead_id, p_script_id, p_script_type, p_context, p_outcome)
  RETURNING id INTO new_id;

  -- Increment usage on the source table
  IF p_script_type = 'closing' THEN
    UPDATE closing_scripts
    SET times_used = COALESCE(times_used, 0) + 1,
        last_used_at = now()
    WHERE id = p_script_id;
  ELSIF p_script_type = 'objection' THEN
    UPDATE objection_handlers
    SET times_used = COALESCE(times_used, 0) + 1
    WHERE id = p_script_id;
  ELSIF p_script_type = 'discovery' THEN
    UPDATE discovery_frameworks
    SET times_used = COALESCE(times_used, 0) + 1
    WHERE id = p_script_id;
  END IF;

  RETURN new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION record_script_usage(uuid, uuid, uuid, text, text, text) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 4. RPC: GET_SCRIPTS_FOR_LEAD
-- ─────────────────────────────────────────────────────────────────
-- Resolves the lead's niche (from leads.niche, fallback leads.vertical,
-- fallback insurance_broker), returns top candidate scripts across
-- discovery / objection / closing, ranked by times_used then
-- conversion_rate.

CREATE OR REPLACE FUNCTION get_scripts_for_lead(
  p_lead_id  uuid,
  p_stage    text DEFAULT NULL
)
RETURNS TABLE(
  script_id        uuid,
  script_type      text,
  title            text,
  body             text,
  conversion_rate  numeric,
  times_used       integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_niche text;
BEGIN
  SELECT COALESCE(niche, vertical, 'insurance_broker') INTO v_niche
  FROM leads WHERE id = p_lead_id;

  -- Closing scripts (filtered by stage = close_type when provided)
  RETURN QUERY
  SELECT cs.id, 'closing'::text, cs.close_type AS title, cs.script_text AS body,
         cs.conversion_rate, COALESCE(cs.times_used, 0)
  FROM closing_scripts cs
  WHERE cs.niche_name = v_niche
    AND cs.is_active = true
    AND (p_stage IS NULL OR cs.close_type = p_stage OR cs.trigger_condition ILIKE '%' || p_stage || '%')
  ORDER BY COALESCE(cs.times_used, 0) DESC, cs.conversion_rate DESC NULLS LAST
  LIMIT 5;

  -- Objection handlers for the same niche
  RETURN QUERY
  SELECT oh.id, 'objection'::text, oh.objection_category AS title, oh.response_script AS body,
         oh.conversion_rate, COALESCE(oh.times_used, 0)
  FROM objection_handlers oh
  WHERE oh.niche_name = v_niche
    AND oh.is_active = true
  ORDER BY COALESCE(oh.times_used, 0) DESC, oh.priority ASC
  LIMIT 8;

  -- Discovery frameworks
  RETURN QUERY
  SELECT df.id, 'discovery'::text, ('Discovery framework: ' || df.niche_name)::text AS title,
         df.opening_script AS body,
         NULL::numeric AS conversion_rate, COALESCE(df.times_used, 0)
  FROM discovery_frameworks df
  WHERE df.niche_name = v_niche
    AND df.is_active = true
  ORDER BY COALESCE(df.times_used, 0) DESC
  LIMIT 3;
END;
$$;

GRANT EXECUTE ON FUNCTION get_scripts_for_lead(uuid, text) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 5. RPC: GET_AGENT_SCRIPT_PERFORMANCE
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_agent_script_performance(
  p_agent_id     uuid,
  p_period_days  integer DEFAULT 30
)
RETURNS TABLE(
  script_type      text,
  times_used       integer,
  conversion_count integer,
  conversion_rate  numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT sul.script_type,
         COUNT(*)::integer,
         COUNT(*) FILTER (WHERE sul.outcome = 'converted')::integer,
         (COUNT(*) FILTER (WHERE sul.outcome = 'converted')::numeric
            / NULLIF(COUNT(*), 0) * 100)::numeric(5,2)
  FROM script_usage_log sul
  WHERE sul.agent_id = p_agent_id
    AND sul.used_at > now() - (p_period_days * INTERVAL '1 day')
  GROUP BY sul.script_type;
END;
$$;

GRANT EXECUTE ON FUNCTION get_agent_script_performance(uuid, integer) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 6. SEED DATA — 7 ADDITIONAL VERTICALS
-- ─────────────────────────────────────────────────────────────────
-- Peer-advisor tone. Canadian business context. Curated set per
-- vertical (not the spec's 28/vertical — that volume requires
-- Claude-generation which is deferred to Mary's post-activation
-- content expansion). This seed provides foundation: 1 discovery
-- framework + 4 objection handlers + 2 closing scripts + 1 follow-up
-- sequence per vertical (56 rows across 7 verticals).

-- ─── DISCOVERY FRAMEWORKS (one per new vertical) ───
INSERT INTO discovery_frameworks (
  niche_name, opening_script, key_questions, pain_detection_prompts,
  qualification_criteria, red_flags, transition_to_pitch, duration_minutes
) VALUES
(
  'construction',
  'Hi [Name], Mary from Crystallux. Before I talk about what we do, I want to hear about your pipeline — how booked are you for the next 60 days?',
  '["What does your next 90 days look like — booked, bidding, or flat?", "Where are leads coming from today — HomeStars, Houzz, Google Ads, referrals?", "What are you paying per lead right now, and what percentage actually convert to a quote?", "How many weeks of downtime did you have last year between projects?", "If I handed you 20 qualified reno quotes next month, what would you do with them?"]'::jsonb,
  '["Long silences when asked about pipeline", "Mentions of ''slow month'' or ''waiting on X''", "Spending 3-4k on Google Ads without tracking ROI", "Crew sitting idle", "Losing bids to bigger firms"]'::jsonb,
  '["3-20 employees", "Licensed in their province", "Residential or commercial reno focus", "$500K-$5M annual revenue"]'::jsonb,
  '["Unlicensed operator", "Pay-per-lead aggregator addiction signalling price sensitivity"]'::jsonb,
  'I hear that pattern a lot. We find homeowners 30 to 60 days before they start calling contractors. Let me show you how that would work for you specifically.',
  20
),
(
  'moving_services',
  'Hey [Name], this is Mary from Crystallux. Quick one — where is your pipeline right now, and what is hurting most: winter slump, cancellations, or U-Haul DIY pressure?',
  '["How many trucks, how many crews, how many moves last month?", "Where do leads come from — Google, aggregators, referrals, repeat?", "What percentage of quotes convert to booked moves?", "What is your no-show rate?", "What is your revenue split between peak (May-Sep) and off-season?"]'::jsonb,
  '["Winter revenue drops >40%", "Aggregator fees eating margins", "No-show customers costing half-days", "Seasonal crew turnover"]'::jsonb,
  '["Owns or operates 1-10 trucks", "Licensed with province (if applicable)", "WSIB clearance up to date"]'::jsonb,
  '["Undercutting market on price", "Consistent BBB complaints"]'::jsonb,
  'You are right, winter is where the math gets hard. We find homeowners 2-3 weeks before they start calling. Let me show you what that looks like.',
  15
),
(
  'cleaning_services',
  'Hi [Name], Mary from Crystallux. Quick one — what is hurting most right now: one-time ghost bookings, losing regulars to Merry Maids, or cleaner turnover?',
  '["What is the split between one-time cleans and recurring contracts?", "How many cleaners, how many jobs per week?", "Where do customers come from today?", "What is your 6-month retention rate on recurring contracts?", "Where does the business plateau — leads, cleaner supply, or supervision capacity?"]'::jsonb,
  '["One-time clean ghosting", "Recurring contracts losing to brand-name competitors", "Cannot scale beyond owner supervision", "Cleaner turnover eating margin"]'::jsonb,
  '["Residential or commercial focus", "Owner-operator or 2-20 cleaners", "Ontario/BC/Alberta geography"]'::jsonb,
  '["No WSIB", "Pricing below market (signals distressed operation)"]'::jsonb,
  'Cleaner supply is a different problem than lead supply. We find homeowners wanting recurring service — high-LTV customers, not one-timers. Let me walk you through it.',
  15
),
(
  'real_estate',
  'Hey [Name], Mary from Crystallux. Quick one — how many deals year-to-date, and where are listings actually coming from?',
  '["How many deals year-to-date, what is your 12-month target?", "What is your farm area?", "Where do listings come from — sphere, Zillow, FSBO, door-knocks?", "What is it costing you per listing, all-in?", "If you added 5 more listings per month starting now, what would that do for you?"]'::jsonb,
  '["Zillow/Realtor.ca eating referrals", "FSBO lists picked over within 24h", "Social media treadmill with no ROI", "Sphere mining losing effectiveness"]'::jsonb,
  '["Licensed agent with RECO/provincial board", "1+ years selling", "Active farm area strategy", "Canadian resident"]'::jsonb,
  '["Team lead with 10+ agents wanting enterprise deal — go to Growth Pro conversation", "Expired-listing-only strategy"]'::jsonb,
  'Zillow sells the same lead to 5 agents. We find sellers 30-60 days before the MLS sees them. You get the listing appointment before any other agent.',
  15
),
(
  'dental',
  'Hi Dr. [Name], Mary from Crystallux. Before I pitch anything — how many operatories, how many hygienists, and where is new-patient flow coming from?',
  '["How many operatories, how many active hygienists, what is your average new-patient volume per month?", "Which days and times see empty chairs right now?", "What is your per-patient acquisition cost today?", "How many hours per week is front desk spending on recall calls?", "If I could book your quiet chair hours over the next 90 days, what would that mean for practice growth?"]'::jsonb,
  '["Empty Tuesday/Thursday afternoons", "Hygienist shortage slashing billable chair hours", "Insurance rate compression", "Clear-aligner DTC brands stealing cosmetic cases"]'::jsonb,
  '["RCDSO/provincial regulatory body licensed", "Practice owner (not associate)", "$800K-$5M practice revenue", "Using Dentrix / OpenDental / ClearDent"]'::jsonb,
  '["Under 2 years practice ownership (referral network still immature)", "Specialty-only practice (ortho/endo) — different target"]'::jsonb,
  'Your Tuesday/Thursday afternoon chairs sitting empty is the problem. We book those slots with new-patient consults, no front-desk chasing. Let me show you.',
  20
),
(
  'legal',
  'Hi [Name], Mary from Crystallux. Measured question first — what practice areas are you active in, and where does retainer flow come from today?',
  '["What practice areas are you active in?", "How variable is retainer flow month to month?", "Where does new-client flow come from — referring lawyers, past clients, directories?", "Do you have dedicated intake, or is reception handling initial calls?", "What is your relationship with law society advertising rules?"]'::jsonb,
  '["40% retainer swing between best and worst months", "Dependence on narrow set of referring lawyers", "Google Ads rejections on legal claims", "Intake staff overwhelmed by unqualified calls"]'::jsonb,
  '["Law Society licensed in active jurisdiction", "Solo or boutique firm (2-10 lawyers)", "Compliance-first posture on marketing"]'::jsonb,
  '["Reluctant to do any outbound — direct conflict with strategy", "In-house conflict-of-interest concerns"]'::jsonb,
  'Most lawyers we talk to have retainer flow that swings 40% month to month. We build a predictable intake pipeline — no outcome claims, no comparative ads, fully compliant. Let me walk you through.',
  25
),
(
  'consulting',
  'Hey [Name], Mary from Crystallux. Before I talk about what we do, I want to understand your practice first. What does a typical month look like — how many active engagements, how much utilisation?',
  '["What does a typical month look like — how many active engagements, how much utilisation?", "Where is your current pipeline coming from — referrals, LinkedIn, your network?", "What is the longest dry spell you have had in the last 12 months?", "How many hours a week are you personally spending on sales and bizdev?", "If you could wake up tomorrow with one thing fixed in your business, what would it be?"]'::jsonb,
  '["30-60 day dry spells between engagements", "Utilisation below 60% between engagements", "Weekends spent writing proposals instead of delivering", "Dependence on LinkedIn outreach and past-client referrals"]'::jsonb,
  '["Solo consultant 3+ years OR boutique firm (2-10 consultants)", "Average engagement $15K+", "Canadian or US client base with Canadian incorporation"]'::jsonb,
  '["Sub-$150/hr pricing — too price-sensitive for this offer", "Pure retainer practice with fixed book — low pipeline need"]'::jsonb,
  'I hear that pattern every week. We run your top-of-funnel so you stop trading billable hours for bizdev hours. Let me show you how this would work for your practice.',
  20
)
ON CONFLICT DO NOTHING;


-- ─── OBJECTION HANDLERS (4 per new vertical, 28 rows) ───
-- Core objections: price, timing, trust, competitor
INSERT INTO objection_handlers (
  niche_name, objection_category, objection_text, response_script, supporting_data, escalation, priority
) VALUES
-- construction
('construction', 'price', 'Another lead source? I already pay too much for leads.',
 'Understood. What is your current cost per qualified quote? If you are paying $40-80 per HomeStars lead and converting one in six, your real cost per quote is $240-480. Our $1,497 gets you 20 qualified quotes a month. Do the math — if one signed reno pays $40K, the system pays for itself on lead #1.',
 'HomeStars averages $40-80/lead at 15% quote-to-conversion. Crystallux founding clients avg 20 quotes/month.',
 'If cost is the blocker, we guarantee 10 qualified leads in your first 30 days. If we miss, the next month is free. That is $1,497 refunded for one soft month.', 1),
('construction', 'timing', 'This is a slow month, I can not add anything right now.',
 'Exactly why now. Slow months are when your competitors are running ads. We find homeowners 30-60 days out — meaning the leads arriving in week 3 are projects you close in December. You can skip us and still be slow in December, or start now and have a pipeline.',
 'Renovation planning cycle: 45-75 days from first search to first contractor call.',
 'Onboarding takes 7 days. In 30 days you have a pipeline. The only thing slow months reward is inaction.', 2),
('construction', 'trust', 'I have been burned by lead-gen tools before.',
 'Fair. That is why we eat the risk. 10 qualified leads in 30 days or the next month is free. Not a credit — your card does not get charged. The tools you tried were templated mail-merge. We use Claude to write each outreach individually. If that sounds different from what burned you, 15 min on a call to see the system itself.',
 'Founding client rated cold outreach 9.5/10, said first one that sounded like a peer not a vendor.',
 'If you want, we can run a 14-day paid POC at 50% off before committing to full founding rate. Guarantee still applies.', 2),
('construction', 'competitor', 'I already use Houzz / HomeStars / Angi.',
 'Keep them. Those platforms show your profile to homeowners already shopping. We find homeowners 30-60 days before they shop. Different timing, different cost structure. Run both, measure which leads actually sign. Most clients keep 1-2 aggregators plus us; some drop the aggregators after month 3.',
 'Aggregator average cost per signed project: $2,400-4,800. Crystallux cost per signed project: $300-500.',
 'Happy to show you side-by-side numbers from an existing client if you want the proof before committing.', 3),
-- moving_services
('moving_services', 'price', 'I cannot afford $997 in January.',
 'One booked move in January pays the month. Your average move is $800-1,500. Our target is 15 quotes booked in your first 30 days. If we miss, next month is free. You are spending on something somewhere — this is spending that generates bookings, not just visibility.',
 'Average residential move in Canada: $950-$1,400. Crystallux target: 30 quotes/month, ~15 booked moves.',
 'January is the worst month; same offer applies with winter protection: start now, pause free for 30 days if weather kills volume, resume when you need it.', 1),
('moving_services', 'timing', 'I am slammed in summer, I do not need this.',
 'Right — so start it October for winter coverage. Our pipeline takes 7 days to spin up. We turn on the November-March leads now. When spring hits, you already have a queue. The clients who wait until May are the ones who miss the best slots.',
 'Winter booking volume for movers drops 45-60% vs summer peak.',
 'We offer one free 30-day pause per year. Use it in August if needed.', 2),
('moving_services', 'trust', 'Moving aggregators burned me — why is this different?',
 'Aggregators sell one lead to five movers. You are paying to fight, not to book. We source leads individually — no one else sees them. Plus the guarantee: 15 quotes booked in 30 days or next month free. You keep the leads either way; they are yours.',
 'Typical aggregator: 3-5 movers quote same lead. Crystallux: exclusive lead to one client only.',
 'If you want proof: 14-day POC at 50% off. You see the lead quality before paying full rate.', 2),
('moving_services', 'competitor', 'Two Men and a Truck owns my market.',
 'Brand awareness is not the same as market share. We target homeowners 2-3 weeks before move date — before they Google Two Men. You get first contact. Plus: Two Men quotes expensive. Your price is the lever for homeowners who already called them.',
 'Brand-loyalty churn in residential moving: 35-40% per move (each move is evaluated fresh).',
 'Run both for 90 days — you will see which converts.', 3),
-- cleaning_services
('cleaning_services', 'price', '$997/mo is a lot for cleaning.',
 'Lot for a one-time clean. Not for recurring contracts. Average weekly cleaning contract is $150 × 52 weeks = $7,800/year in revenue. Our target: 25 qualified recurring-contract leads per month. Math: book 2 recurring contracts and the system pays 18 months over.',
 'LTV of a bi-weekly cleaning contract: $2,500-4,000/year. Cost to acquire: $30-80 (via Crystallux).',
 'Guarantee: 10 booked cleans in first 30 days or next month free. Start clean, no risk.', 1),
('cleaning_services', 'trust', 'I tried Thumbtack and it was a disaster.',
 'Thumbtack sends you six one-time-clean leads a day, all price-sensitive shoppers who will never rebook. We source homeowners looking for weekly or bi-weekly recurring. Different segment, different LTV math.',
 'Thumbtack one-time-clean close rate: 8-12%. Crystallux recurring-contract close rate: 25-35%.',
 'Cancel any time with 30-day notice. No risk past month 1.', 2),
('cleaning_services', 'competitor', 'Merry Maids is running ads I cannot match.',
 'You are right. So we target a different customer — homeowners who do not want a franchise. They want local, recurring, relationship-based. Merry Maids converts on brand; you convert on trust and flexibility. We source the "local operator" segment specifically.',
 'Residential cleaning market split: 55% independent operators, 35% franchise, 10% individual cleaners.',
 'We intentionally exclude franchise-loyal homeowners from your leads.', 3),
('cleaning_services', 'timing', 'Spring cleaning is my busy season, ask me in summer.',
 'Same answer. Start now for summer. Pipeline takes 7 days to spin up. By May you have a queue. The ones who start in June spend all summer short-staffed and short-booked. We build the funnel during spring; you reap in summer.',
 'Summer is peak demand — cleaners who have inbound pipeline established in spring capture 40% more contracts.',
 'One free 30-day pause per year if fall becomes genuinely quiet.', 2),
-- real_estate
('real_estate', 'price', '$1,497 is more than my Zillow budget.',
 'One commission covers 10 months. Zillow pays you the same lead five agents are fighting for. We send you pre-MLS seller prospects no one else has seen. Different math. Most of our real-estate clients drop 1-2 Zillow slots after month 3.',
 'Average Canadian commission: $12K-18K. 10-month Crystallux cost: $14,970.',
 'Guarantee: 5 listing appointments in 30 days or next month free. Low-risk test.', 1),
('real_estate', 'timing', 'The market is slow right now.',
 'Slow markets are the best time. The agents who grow in a down market are the ones talking to sellers before their neighbor does. Every seller who lists is one you did not compete for. In a slow market, the agent with a pre-MLS pipeline captures disproportionate share.',
 'In Ontario downturns, top 10% of agents gain market share while bottom 50% exit.',
 'If the market stays slow 6 months, your results compound. Fast market = just good; slow market = transformative.', 2),
('real_estate', 'trust', 'I have used lead-gen services that were all tire-kickers.',
 'Most lead-gen is reactive — it shows your ad to someone who Googled "sell my house". By that time, 5 other agents are also in the inbox. We find sellers 30-60 days pre-MLS. They are not shopping agents yet; you are the first one they hear from.',
 'Pre-MLS seller touch conversion to listing: 25-40% vs post-search conversion: 5-8%.',
 'Guarantee: 5 listing appointments in 30 days. Pure seller-intent, not referrer signal.', 2),
('real_estate', 'competitor', 'My broker pays for Realtor.ca premium — I do not need more.',
 'Realtor.ca drives buyer-side traffic to your profile. We solve the seller side. You get seller leads Realtor.ca will never show you. Run both; you are covering both sides of every transaction. The agents winning in 2026 have both inbound sources.',
 'Seller-leads vs buyer-leads: seller commission avg is 1.6× buyer-side commission.',
 'Talk to your broker if needed. Most brokers support supplementary lead-gen for agents hitting target.', 3),
-- dental
('dental', 'price', 'We are already paying $4K/mo for a dental marketing agency.',
 'Keep them if they are delivering. Most dental agencies charge $4-8K and deliver general brand awareness + review management. We deliver new-patient consults directly into your schedule. Different tool. Usually complementary — we handle new-patient flow; agency handles brand/retention.',
 'Dental marketing agencies avg $4-8K/mo and deliver 15-30% new-patient lift. Crystallux delivers 30 consults/mo.',
 'Run us alongside for 60 days. If your agency is worth it, you will see; if not, you will know.', 1),
('dental', 'timing', 'Hygienist shortage means I cannot add new patients right now.',
 'Opposite problem. New-patient consults do not require hygiene. You book them into operatory time with the dentist for the initial consult + treatment plan. The empty Tuesday and Thursday chairs we fill are the problem. Hygiene constraint lives on a different day of the week.',
 'New-patient consult: 60 min dentist time. Subsequent hygiene: different day, different chair.',
 'If hygiene bottleneck truly exists, we pace leads down — we never flood your schedule. You set the monthly target.', 2),
('dental', 'trust', 'Marketing tools get RCDSO-flagged easily.',
 'Agreed. That is why every template is reviewed against RCDSO (or Alberta Dental, or BC CDSBC, per your province) before any send. No outcome claims. No diagnostic claims. No comparative advertising. We built the product compliance-first. Our founding dental clients get per-province copy review included.',
 'RCDSO advertising rules prohibit outcome claims, diagnostic claims, comparative ads. Our templates audited against these.',
 'Have your practice compliance lawyer review our template bank before activation. We cover the cost of one round of review.', 2),
('dental', 'competitor', 'Clear-aligner DTC brands are eating my cosmetic-case pipeline.',
 'That is exactly why pre-MLS-equivalent sourcing matters. We find homeowners researching cosmetic dentistry 30-60 days before they consider SmileDirect. First touch beats the subscription pitch. Also: we filter out prospects primed for DTC (under-30, price-first) and focus on family + cosmetic complex cases.',
 'DTC aligners capture 15-20% of cosmetic leads. Dental practices capturing pre-DTC intent lift cosmetic revenue 30%.',
 'Happy to show sample outreach copy that positions in-practice vs DTC specifically.', 3),
-- legal
('legal', 'price', '$1,997 is aggressive for a solo practice.',
 'One retained matter at a typical solo rate ($300/hr × 10h) = $3,000. System pays for itself on case #1. Most practices have 6-12 of those per quarter. We deliver 15 intake consults/month — typical conversion 40-60%, so 6-9 new retainers monthly.',
 'Solo practice avg retained matter: $2,800-$4,200. Crystallux cost per month: $1,997.',
 'Founding rate locked 12 months. After month 3, one matter retained covers the rest of the year.', 1),
('legal', 'timing', 'I need to check law society compliance first.',
 'Good answer. That is standard. We do not activate until your template bank is reviewed. Typical review takes 10-14 days with your LSO-advising colleague. Meanwhile your contract is signed, rate locked, no billing until activation. Zero pressure.',
 'LSO Rule 4.2 + BC Law Society Rule 4 compliance takes 10-14 days with partnering counsel.',
 'If compliance review raises any concern, we revise or cancel without charge. Contract is explicit on this.', 1),
('legal', 'trust', 'Marketing tools run afoul of bar rules.',
 'Correct — tools built for general B2B lead-gen do. We specifically built the legal vertical compliance-first. No outcome claims ("we win cases"), no comparative advertising ("better than [firm X]"), no client testimonials referencing outcomes. Every template reviewed per-province before first send.',
 'LSO Ontario Rule 4.2 and equivalents in BC/AB/QC compliance-reviewed template library.',
 'Your practice advisor or partner reviews final templates before any send. Veto power on your side.', 2),
('legal', 'competitor', 'Avvo costs me $200/mo — why would I pay $1,997?',
 'Avvo rates and routes inquiries to profiles. We source net-new inquiries not already shopping. Avvo competes on searches; we deliver 15 intake consults a month that never would have found you via search. Different channels. Use Avvo if it is producing; we layer on top.',
 'Avvo avg close rate per lead: 8-15%. Crystallux avg close rate per intake consult: 40-60%.',
 'Drop Avvo after month 3 if our pipeline outpaces; founding contract allows.', 3),
-- consulting
('consulting', 'price', 'I cannot spend $1,997 on pipeline when I am already under utilization target.',
 'That is exactly why. Your utilization dropping is a pipeline signal, not a productivity signal. You are delivering when engaged; the gap is the next engagement not being queued. We fill the queue. At your typical engagement size ($15K-40K), one booked engagement pays the system 8-18 months.',
 'Solo consulting avg engagement: $15K-40K. Utilization target breaks at 65%; below that, pipeline is the root cause.',
 'If in 60 days you do not book one new engagement, next month is free. Zero-risk test.', 1),
('consulting', 'timing', 'I will start when my current project wraps up.',
 'That is reversed. Your current project wraps, then you have 30-60 days of no pipeline. The system takes 7 days to spin up. If you start today, when your project wraps in 45 days you already have a queue of discovery calls. Starting "later" is what creates the gap.',
 'Median consulting bench time: 45-90 days between engagements for pipeline-underinvested practices.',
 'Activate during current project; onboarding requires 2h of your time in week 1, nothing in weeks 2-6.', 2),
('consulting', 'trust', 'I have used agencies and SDR services. They all produce tire-kickers.',
 'Right — agencies send you general B2B SDR outreach written by juniors, mass-sprayed. We use Claude to write each outreach against your specific ICP and the target prospect personally. No template library. A founding consulting client said our outreach was the first cold outreach that sounded like a peer, not a vendor.',
 'SDR agency avg reply rate: 1-3%. Crystallux consulting reply rate: 8-15%.',
 '14-day POC at 50% off lets you see the actual outreach before committing to founding rate.', 2),
('consulting', 'competitor', 'I have a BDR helping part-time. I do not need this too.',
 'BDR cost loaded: $6-10K/mo. Hours spent on managing the BDR: you. We cost $1,997 + zero management. If your BDR is hitting their numbers, great — we complement not replace. Most consulting clients keep the BDR for deep ICP enrichment while we run the top-of-funnel volume.',
 'Part-time BDR fully loaded: $5-8K/mo. Crystallux: $1,997/mo. Complementary, not competitive.',
 'Run both 90 days — measure BDR-sourced vs Crystallux-sourced booked meetings. Keep what converts.', 3)
ON CONFLICT DO NOTHING;


-- ─── CLOSING SCRIPTS (2 per new vertical, 14 rows) ───
INSERT INTO closing_scripts (
  niche_name, close_type, trigger_condition, script_text, expected_response, follow_up_action, fallback_action
) VALUES
('construction', 'assumptive', 'Prospect has acknowledged the pipeline gap.',
 'Let us get you onboarded this week. I will send the contract today, you sign by tomorrow, your first leads arrive by next Friday. Sound good?',
 'Agreement, minor pushback on start date.', 'Send contract + Calendly for kickoff call.', 'Offer Monday start if "this week" feels rushed.'),
('construction', 'risk_reversal', 'Prospect concerned about commitment.',
 'Here is the risk split: I eat the first 30 days. 10 qualified leads or next month is free. Your risk is one month of $1,497 refunded if it misses. My risk is two months of delivery without revenue. I would not offer it if I was not confident.',
 'Thoughtful silence, then agreement.', 'Send founding contract with guarantee clause highlighted.', 'Offer 14-day POC at 50% off for deeper proof.'),
('moving_services', 'urgency', 'Prospect is slow-season (October-March).',
 'Starting October 15 means November onboarding, December pipeline. Start Dec 15 means February pipeline — you lose peak-winter gap. The month of difference is not money; it is 40% of Q1 booking.',
 'Acknowledgment, asks about start logistics.', 'Send contract with same-week kickoff.', 'Offer 30-day pause in January if volume is truly flat.'),
('moving_services', 'choice', 'Prospect leaning but hesitating on full commitment.',
 'Two paths. Path one: founding contract, $997/mo locked 12 months, we start Monday. Path two: 14-day POC at 50% off — $500 flat, you see quality before committing. Pick one.',
 'Commits to a path.', 'Send paperwork for chosen path.', 'If decline both, schedule 7-day follow-up.'),
('cleaning_services', 'summary', 'Discovery reveals clear fit + pain.',
 'Here is what you told me: you are at 40% recurring-contract mix, you want 70%, cleaner turnover makes growth impossible, Merry Maids is eating brand-searched customers. We solve the pipeline piece — 25 recurring-contract leads/month. You solve the cleaner piece. Fair trade?',
 'Agreement on framing.', 'Send contract + onboarding link.', 'If cleaner piece is the real blocker, refer to staffing agency first.'),
('cleaning_services', 'testimonial', 'Prospect questions credibility.',
 '[Reference insurance broker Filip 9.5/10 quote — signals peer-advisor tone]. You do not have to take my word. A founding insurance broker client rated our cold outreach 9.5 out of 10. He said it was the first cold outreach that sounded like a peer, not a vendor. Let me send you a sample for your vertical — you judge.',
 'Interested, wants to see sample.', 'Send 3 sample outreach emails tuned to their vertical.', 'If they reject sample quality, withdraw offer gracefully.'),
('real_estate', 'urgency', 'Prospect planning to start "later".',
 'You said 15 listing appointments a month is the goal. Onboarding is 7 days. Pipeline is 30 days. Meaning: start today, you have your 15 appointments by end of May. Start May, you have them by end of June — missing spring peak. That is 1-3 commissions of lost compounding.',
 'Recognizes compounding effect.', 'Same-week contract + onboarding call.', 'Offer April 1 start with pre-March content prep included.'),
('real_estate', 'assumptive', 'Prospect has asked about team expansion.',
 'Great — so the Growth Pro tier fits you. $2,997/mo, covers up to 3 agents on your team, per-agent lead assignment, team reporting. Founding rate through month 12. Contract today, kickoff Monday, team sees their first leads by end of next week.',
 'Asks about team scaling logistics.', 'Send Growth Pro contract; schedule team kickoff.', 'If team is not hired yet, offer solo Founding with upgrade path.'),
('dental', 'risk_reversal', 'Practice owner wary of marketing commitments.',
 'Understood. Here is the structure: per-province copy review happens before any send — so you see every template first. If your RCDSO advisor flags anything, we revise free. If after 30 days we have not hit 15 consults, next month is free. Your only exposure is one month at $1,497. I eat the rest.',
 'Acknowledges risk is minimal.', 'Send contract + compliance-review timeline.', 'Offer 14-day POC at 50% off for extra reassurance.'),
('dental', 'choice', 'Practice owner balancing marketing options.',
 'Two paths. Path one: Crystallux full founding at $1,497, 30 consults target, compliance-reviewed. Path two: keep existing marketing + add us as a layer at POC rate $500 for 14 days. Path one is a 3-month commitment; path two is a 14-day trial. Which fits?',
 'Chooses path.', 'Send appropriate paperwork.', 'If hesitating, reschedule for 48h post-RCDSO consultation.'),
('legal', 'summary', 'Discovery call winds down; legal prospect is measured.',
 'Let me summarise. You have 40% retainer swing month-to-month. Referrals come from a narrow colleague set. Your compliance concerns are real and we address them with per-province template review. Target: 15 intake consults/month. Founding rate: $1,997, locked 12 months. Guarantee: 8 qualified intakes in first 30 days or next month free. Sound accurate?',
 'Confirms framing, asks about next steps.', 'Send contract + compliance review timeline.', 'If compliance concerns remain, offer to meet partnering counsel via 3-way call.'),
('legal', 'risk_reversal', 'Solo lawyer emphasizes compliance liability.',
 'Here is how we absorb the risk. Until your compliance lawyer signs off on templates, nothing sends. Not a single email. Your risk is zero during review. Once approved, if 8 qualified intakes do not materialize in 30 paid days, next month is free. Your maximum exposure is one month.',
 'Considers, typically asks about review timeline.', 'Send contract + partnering-counsel contact.', 'If still hesitant, offer to hold the first month and start billing post-compliance-approval.'),
('consulting', 'assumptive', 'Consultant sees the math and is leaning yes.',
 'Let us get this started. Contract today, onboarding call tomorrow, first discovery calls booked in week 2. You will have meetings in your calendar before you would normally have time to write a single proposal.',
 'Agreement.', 'Send contract + Calendly for onboarding call.', 'If "tomorrow" is too soon, offer 48-hour delayed kickoff.'),
('consulting', 'urgency', 'Consultant mentioned utilisation concerns.',
 'You said utilisation is at 55% now. That is $50K-100K in opportunity cost per month at your rates. Crystallux activation takes 2 hours of your time across 7 days. Cost: $1,997. Missed revenue if you wait 60 days: more than a year of Crystallux. The math is upside-down.',
 'Acknowledges math.', 'Same-day contract + activation.', 'If strategic reasons to delay, target 14-day re-engagement.')
ON CONFLICT DO NOTHING;


-- ─── FOLLOW-UP SEQUENCES (1 per new vertical, 7 rows) ───
INSERT INTO follow_up_sequences (
  niche_name, sequence_name, trigger_event, step_number, delay_days,
  channel, message_template, expected_reply_indicator
) VALUES
('construction', 'post_call_1', 'discovery_call_no_commit', 1, 3, 'email',
 'Hey [Name], thanks for the call yesterday. I was thinking about what you said on crew downtime — that 3-4 week gap between the [project A] and [project B] jobs. We typically fill that with 5-8 qualified reno quotes. Worth 10 more minutes when you have time? — Mary',
 'Reply with scheduling availability OR "sounds good" OR open-ended question about next step.'),
('moving_services', 'post_call_1', 'discovery_call_no_commit', 1, 2, 'email',
 'Hey [Name], thanks for the call. One thing I want to highlight: your January slump. Our winter-slump protocol gets you 8-12 quotes in a typical slow month. Happy to walk through that specifically — 5 more min on the phone or email back. — Mary',
 'Reply acknowledging winter problem OR scheduling request.'),
('cleaning_services', 'post_call_1', 'discovery_call_no_commit', 1, 2, 'email',
 'Hey [Name], thanks for the chat. You said scaling past owner supervision is the real wall. Our recurring-contract clients average 18 new recurring contracts in their first 90 days — meaning ~$32K of annual recurring revenue added. Does that math change the calculus? — Mary',
 'Reply engaging with ROI math OR ask about next step.'),
('real_estate', 'post_call_1', 'discovery_call_no_commit', 1, 2, 'sms',
 'Hey [Name] — Mary. 5 listing appts in 30 days or next month free. Think the math got lost in the call. Want me to send the 1-page ROI breakdown for your farm area?',
 'Reply yes / specific question / "send it".'),
('dental', 'post_call_1', 'discovery_call_no_commit', 1, 3, 'email',
 'Hi Dr. [Name], thanks for the time yesterday. I mentioned per-province compliance review — that is the piece worth pausing on. No outreach sends until your RCDSO [or equivalent] advisor signs off on every template. Zero exposure during review. Happy to walk your advisor through it if useful. — Mary',
 'Reply requesting advisor intro OR RCDSO-specific question OR contract interest.'),
('legal', 'post_call_1', 'discovery_call_no_commit', 1, 4, 'email',
 'Hi [Name], thanks for the measured questions yesterday. To address the compliance hesitation directly: our template bank has been reviewed against LSO Rule 4.2 [or your jurisdictions]. I can send the review certificate from our compliance counsel if useful. Worth 15 min with your advising partner to review jointly? — Mary',
 'Reply requesting review certificate OR asks about joint review call.'),
('consulting', 'post_call_1', 'discovery_call_no_commit', 1, 2, 'email',
 'Hey [Name], thanks for the conversation yesterday. You said utilization is 55% now. I mentioned the opportunity-cost math — $50K-100K/mo in missed revenue at your rates. Contract today, activation next week, meetings in your calendar week 2. If you want the founding rate locked, Thursday is my best slot for the activation kickoff. — Mary',
 'Reply with Thursday time OR alternative day OR question on activation logistics.')
ON CONFLICT DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 7. VERIFICATION
-- ─────────────────────────────────────────────────────────────────

-- Expect 1
SELECT 'script_usage_log table' AS check_name, COUNT(*) AS present
FROM information_schema.tables WHERE table_name = 'script_usage_log';

-- Expect 3 RPCs
SELECT 'closing-intelligence RPCs' AS check_name, COUNT(*) AS present
FROM information_schema.routines
WHERE routine_name IN ('record_script_usage','get_scripts_for_lead','get_agent_script_performance');

-- Expect 7 new verticals (construction, moving_services, cleaning_services, real_estate, dental, legal, consulting)
SELECT niche_name, COUNT(*) AS discovery_count
FROM discovery_frameworks
WHERE niche_name IN ('construction','moving_services','cleaning_services','real_estate','dental','legal','consulting')
GROUP BY niche_name ORDER BY niche_name;

-- Expect 28 new objection handlers (4 × 7)
SELECT COUNT(*) AS new_objection_handlers
FROM objection_handlers
WHERE niche_name IN ('construction','moving_services','cleaning_services','real_estate','dental','legal','consulting');

-- Expect 14 new closing scripts (2 × 7)
SELECT COUNT(*) AS new_closing_scripts
FROM closing_scripts
WHERE niche_name IN ('construction','moving_services','cleaning_services','real_estate','dental','legal','consulting');


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ═══════════════════════════════════════════════════════════════════
-- DELETE FROM follow_up_sequences WHERE niche_name IN ('construction','moving_services','cleaning_services','real_estate','dental','legal','consulting');
-- DELETE FROM closing_scripts     WHERE niche_name IN ('construction','moving_services','cleaning_services','real_estate','dental','legal','consulting');
-- DELETE FROM objection_handlers  WHERE niche_name IN ('construction','moving_services','cleaning_services','real_estate','dental','legal','consulting');
-- DELETE FROM discovery_frameworks WHERE niche_name IN ('construction','moving_services','cleaning_services','real_estate','dental','legal','consulting');
-- DROP FUNCTION IF EXISTS get_agent_script_performance(uuid, integer);
-- DROP FUNCTION IF EXISTS get_scripts_for_lead(uuid, text);
-- DROP FUNCTION IF EXISTS record_script_usage(uuid, uuid, uuid, text, text, text);
-- DROP TABLE IF EXISTS script_usage_log CASCADE;
-- ALTER TABLE discovery_frameworks DROP COLUMN IF EXISTS times_used;
-- ALTER TABLE objection_handlers
--   DROP COLUMN IF EXISTS conversion_rate,
--   DROP COLUMN IF EXISTS times_used;
-- ALTER TABLE closing_scripts
--   DROP COLUMN IF EXISTS last_used_at,
--   DROP COLUMN IF EXISTS conversion_rate,
--   DROP COLUMN IF EXISTS times_used;
