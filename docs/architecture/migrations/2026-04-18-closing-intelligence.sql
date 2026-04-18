-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX CLOSING INTELLIGENCE MIGRATION
-- File: docs/architecture/migrations/2026-04-18-closing-intelligence.sql
--
-- Adds the tables and seed data that make the agent "smart and
-- always ready" when engaging a prospect. This is what turns
-- Crystallux from a lead-gen tool into a sales closer.
--
-- Includes:
--   1. Discovery call frameworks (per niche)
--   2. Objection handlers (per niche)
--   3. Closing scripts (per niche)
--   4. Proposal templates (per niche)
--   5. Follow-up sequences (per niche)
--   6. Competitor comparison intelligence
--   7. Seed data for insurance brokers (first vertical)
--
-- Idempotent — safe to re-run.
-- Run AFTER 2026-04-18-full-platform-foundation.sql
-- Run AFTER 2026-04-18-niche-overlays.sql
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────
-- 1. DISCOVERY CALL FRAMEWORKS
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS discovery_frameworks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  niche_name TEXT NOT NULL,
  opening_script TEXT,
  key_questions JSONB,              -- ordered list of questions to ask
  pain_detection_prompts JSONB,     -- what to listen for
  qualification_criteria JSONB,     -- what makes a good fit
  red_flags JSONB,                  -- signs to disqualify
  transition_to_pitch TEXT,         -- how to move from discovery to offer
  duration_minutes INT DEFAULT 30,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);


-- ─────────────────────────────────────────────────────
-- 2. OBJECTION HANDLERS
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS objection_handlers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  niche_name TEXT NOT NULL,
  objection_category TEXT NOT NULL,  -- 'price', 'timing', 'trust', 'authority', 'need', 'competitor'
  objection_text TEXT NOT NULL,
  response_script TEXT NOT NULL,
  supporting_data TEXT,              -- stats, facts, proof points to back response
  escalation TEXT,                   -- what to say if they push back
  priority INT DEFAULT 5,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);


-- ─────────────────────────────────────────────────────
-- 3. CLOSING SCRIPTS
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS closing_scripts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  niche_name TEXT NOT NULL,
  close_type TEXT NOT NULL,          -- 'assumptive', 'urgency', 'choice', 'summary', 'risk_reversal', 'testimonial'
  trigger_condition TEXT,            -- when to use this close
  script_text TEXT NOT NULL,
  expected_response TEXT,            -- what they typically say
  follow_up_action TEXT,             -- next step if they say yes
  fallback_action TEXT,              -- next step if they hesitate
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);


-- ─────────────────────────────────────────────────────
-- 4. PROPOSAL TEMPLATES
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS proposal_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  niche_name TEXT NOT NULL,
  module_type TEXT,                  -- 'pipeline', 'content', 'coach', 'manager', 'operator'
  pricing_tier TEXT,                 -- 'starter', 'growth', 'scale', 'enterprise'
  proposal_structure JSONB,          -- sections: problem, solution, investment, guarantee, next_steps
  roi_calculation_method TEXT,       -- how to quantify ROI for this niche
  typical_objections TEXT[],         -- expected pushback
  closing_language TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);


-- ─────────────────────────────────────────────────────
-- 5. POST-CALL FOLLOW-UP SEQUENCES
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS post_call_sequences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  niche_name TEXT NOT NULL,
  call_outcome TEXT NOT NULL,        -- 'interested', 'needs_think', 'price_objection', 'not_now', 'no_fit'
  step_order INT NOT NULL,
  delay_days INT,
  channel TEXT,                      -- 'email', 'sms', 'linkedin', 'call'
  message_template TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);


-- ─────────────────────────────────────────────────────
-- 6. COMPETITOR INTELLIGENCE
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS competitor_intelligence (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  niche_name TEXT NOT NULL,
  competitor_name TEXT,
  competitor_positioning TEXT,
  our_advantages TEXT[],
  their_weaknesses TEXT[],
  common_comparison_questions JSONB,
  differentiation_script TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);


-- ─────────────────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_discovery_frameworks_niche ON discovery_frameworks(niche_name) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_objection_handlers_niche ON objection_handlers(niche_name, objection_category) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_closing_scripts_niche ON closing_scripts(niche_name, close_type) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_proposal_templates_niche_module ON proposal_templates(niche_name, module_type) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_post_call_sequences_niche_outcome ON post_call_sequences(niche_name, call_outcome, step_order) WHERE is_active = TRUE;


-- ═══════════════════════════════════════════════════════════════════
-- SEED DATA — INSURANCE BROKERS (Ontario)
-- Pre-loaded intelligence so the agent is smart from day one
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────
-- DISCOVERY FRAMEWORK — Insurance Broker
-- ─────────────────────────────────────────────────────

INSERT INTO discovery_frameworks (niche_name, opening_script, key_questions, pain_detection_prompts, qualification_criteria, red_flags, transition_to_pitch)
VALUES (
  'insurance_broker',
  'Hey [NAME], appreciate you jumping on. Before I pitch anything, I want to understand your practice first so I can be useful to you. Sound good? I''ll keep this tight — 20 minutes max.',

  '[
    {"order": 1, "question": "How long have you been licensed, and what''s your current book size?", "purpose": "establish experience + scale"},
    {"order": 2, "question": "What products do you primarily sell? Life, disability, critical illness, group benefits, P&C?", "purpose": "understand specialization"},
    {"order": 3, "question": "Roughly how many policies do you write in an average month right now?", "purpose": "baseline for measuring success"},
    {"order": 4, "question": "Where do most of your new clients come from today? Referrals, networking, cold outreach, online?", "purpose": "identify lead source gaps"},
    {"order": 5, "question": "What percentage of your week would you say goes to prospecting vs closing vs admin?", "purpose": "identify time drain"},
    {"order": 6, "question": "If you could double your policy count without working more hours, what would have to change?", "purpose": "reveal their bottleneck in their own words"},
    {"order": 7, "question": "Have you tried any sales tools or outbound services before? What worked, what didn''t?", "purpose": "understand prior expectations/burns"},
    {"order": 8, "question": "What does a win look like for you 90 days from now?", "purpose": "lock in success criteria"}
  ]'::jsonb,

  '[
    "Listen for: burnout language (tired, exhausted, grinding) → pain is real",
    "Listen for: revenue plateau (stuck, capped, not growing) → scaling pain",
    "Listen for: admin complaints (paperwork, follow-up, CRM hell) → automation win",
    "Listen for: referral dependency (all my clients come from referrals) → vulnerable pipeline",
    "Listen for: competitor envy (so-and-so is writing 30 policies/month) → achievement motivation",
    "Listen for: time-with-family language → lifestyle motivator, use this in close"
  ]'::jsonb,

  '{
    "must_have": [
      "Licensed in Ontario (or target geography)",
      "Writing 3+ policies per month currently",
      "Commission $60K+ annually",
      "Has authority to decide (not captive agent needing carrier approval)"
    ],
    "nice_to_have": [
      "5+ years licensed",
      "Book size 100+ clients",
      "Multi-product licensing",
      "Already using a CRM"
    ],
    "deal_breakers": [
      "Recently let go from previous agency",
      "No book of business at all (send to Coach program instead)",
      "Expects us to close for them"
    ]
  }'::jsonb,

  '[
    "Unlicensed / license expired",
    "Less than 6 months experience",
    "No email (only phone-based advisor)",
    "Refuses to provide any business context",
    "Already has 50+ meetings/month but says they need more — unrealistic expectations"
  ]'::jsonb,

  'Based on what you''ve shared, I see three things that are almost certainly costing you real revenue. Can I walk you through what I think is happening and what we''d do about it? Then I''ll share exactly what this looks like and pricing — you tell me if it makes sense for your practice.'
);


-- ─────────────────────────────────────────────────────
-- OBJECTION HANDLERS — Insurance Broker
-- ─────────────────────────────────────────────────────

INSERT INTO objection_handlers (niche_name, objection_category, objection_text, response_script, supporting_data, escalation, priority)
VALUES

('insurance_broker', 'price',
  'That''s too expensive / I can''t afford $2,000/month',
  'I hear you. Let me reframe it. You''re writing what, $5K-$15K in commission per closed policy? If this system books you 15 meetings in month one and you close even 2 of them, it''s paid for itself 3-5 times over. Most of our clients break even in the first 2-3 closed policies. What''s the real concern — is it the monthly out-of-pocket, or is it the risk that it won''t work?',
  'Average Ontario life insurance commission: $2,500-$8,000 per policy. Platform ROI breakeven: 1-2 policies closed from 15-25 meetings booked.',
  'If budget is genuinely the constraint, we offer a founding-client rate of $1,997/month locked for 12 months — saves you $12K over the year. That''s what I''d recommend given the gap.',
  10),

('insurance_broker', 'timing',
  'I need to think about it / Let me discuss with my partner / Now''s not a good time',
  'Totally fair. Before you go, let me ask: what specifically would need to be true for this to be a yes? Is it the price, the fit, the timing, or something else? I ask because if there''s a real concern, I''d rather address it now than have you think about it and lose momentum. We''ve all done the "I''ll get back to you" dance — it rarely ends in action. What''s the real blocker?',
  'Decision fatigue research: 70% of "let me think about it" responses never result in purchase. Direct confrontation of the real objection converts 35% of stalls.',
  'Tell you what: rather than an indefinite "I''ll think about it", let''s book a 15-minute follow-up for [specific day/time]. If you''re still a no then, you''re a no. But let''s put a hard stop on this so it doesn''t drift. Works?',
  9),

('insurance_broker', 'trust',
  'How do I know this actually works? / I''ve tried other lead gen services and got burned',
  'Valid concern. I''ve been burned by those services too — I''ve tried ZoomInfo, Apollo on its own, LinkedIn Sales Nav, a couple of "done-for-you" agencies. Most of them either delivered junk leads or ghosted after setup. Here''s what''s different: (1) I''m a licensed advisor in Ontario, same as you — this isn''t a tech company pretending to understand your world. (2) We run this on my own book — I''ll show you my pipeline from last month right now if you want. (3) Guarantee: 10 booked meetings in month one or month two is free. You can''t lose. What other concerns can I address?',
  'Founder is licensed Ontario insurance advisor. Platform actively used on founder''s own book. Guarantee: 10 meetings month one or month two free.',
  'Would it help if I connected you with one of our founding clients who''s been on the platform for 60 days? You can hear it from them, not me. I''ll set it up if you want.',
  9),

('insurance_broker', 'authority',
  'I need to check with my MGA / I''m under a captive contract',
  'Got it. Does your current agreement restrict you from using outside lead sources or prospecting tools? Most MGA contracts don''t — they only restrict placement of carrier contracts, not how you generate your own prospects. But let''s get clarity. Can you check your agreement in the next 48 hours and come back to me? If it''s fine, we move forward. If there''s a conflict, we identify exactly what clause is the issue.',
  'FSRA regulations permit licensed advisors to use outside lead generation tools as long as CASL compliance is maintained and the advisor retains authority over client placement.',
  'If your MGA is the issue and you want to explore moving under Crystallux MGA, that''s a separate conversation I''d be happy to have. We offer carrier contracts + platform bundled for advisors who want full independence.',
  7),

('insurance_broker', 'need',
  'I get enough referrals / I don''t need more leads',
  'That''s actually a great position to be in. Quick question though: what happens when referrals slow down? Last recession, every advisor I know who relied only on referrals got hammered because people stopped referring. Pipeline isn''t about MORE leads right now — it''s about having a predictable stream you control so you''re never vulnerable. Does the idea of a diversified lead source appeal to you, or are you genuinely okay with referral-only?',
  '73% of advisors who rely solely on referrals report significant income drops during economic downturns. Advisors with 3+ diversified lead sources report 40% less revenue volatility.',
  'Different angle: even if you don''t need new clients, we could put the platform to work upselling your existing book. 60% of your current clients probably have only one product with you. Would more revenue from existing clients be interesting without adding new names?',
  8),

('insurance_broker', 'competitor',
  'Isn''t this just HubSpot / Mailchimp / Apollo with extra steps?',
  'Fair question. Here''s the difference: HubSpot is a toolbox — you have to configure it, write your own content, build your own sequences. Same with Apollo. You''re paying for software you then have to operate. We''re the opposite — you give us your ICP, we run everything, meetings appear in your calendar. Plus we''re built specifically for insurance — the language, the objections, the compliance (CASL), the offer types. Generic tools can''t do that without you being the expert. Make sense?',
  'HubSpot Growth: $890-$3,600/mo for software only. Apollo: $49-$499/mo for data only. Both require full-time operator. Crystallux: $1,997-$5,997/mo fully managed including all software, data, copy, and execution.',
  'I can pull up a side-by-side comparison right now if useful. But the simple test: if you had to run HubSpot/Apollo yourself, how many hours per week would that take? And what''s your hour worth? That''s usually the full ROI answer.',
  6);


-- ─────────────────────────────────────────────────────
-- CLOSING SCRIPTS — Insurance Broker
-- ─────────────────────────────────────────────────────

INSERT INTO closing_scripts (niche_name, close_type, trigger_condition, script_text, expected_response, follow_up_action, fallback_action)
VALUES

('insurance_broker', 'assumptive',
  'Prospect is engaged, no major objections raised, discovery went well',
  'Great. So the way this works: you and I jump on a 60-minute onboarding call to map your ICP, we launch your first campaign within 5 business days, first meetings book within 10-14 days. Want to grab a Tuesday or Thursday for the onboarding? I''ve got a 2pm slot this coming Tuesday or 10am Thursday.',
  'Tuesday 2pm works OR I need to check my calendar',
  'Send Calendly confirmation + welcome email + onboarding form link',
  'Send link to book onboarding call + proposal document'),

('insurance_broker', 'urgency',
  'Prospect is warm but hesitant to decide today',
  'I''m only opening 3 founding-client slots and 2 are already spoken for. The founding rate locks you at $1,997/mo for 12 months — after these slots, it''s $2,997/mo for everyone. If you''re leaning yes, let''s lock it in today. If you''re a no, no hard feelings — just want to give you first right of refusal before I open it up to the next broker on my list.',
  'Okay let''s do it OR I need a day to think',
  'Collect payment method and send onboarding materials',
  'Offer 48-hour hold on founding rate with verbal commitment'),

('insurance_broker', 'risk_reversal',
  'Price objection or "what if it doesn''t work" concern',
  'Here''s what I''ll do. Sign up today. If we don''t book 10 qualified prospect meetings in month one, your month two is free. That means you''re paying $1,997 for potentially up to 30 booked calls over 60 days. Even at your conversion rate, that should produce 3-5 closed policies worth $10K-25K in commission. You literally cannot lose here unless you refuse to show up for the meetings we book for you.',
  'Okay that''s fair, let''s go OR I still need to think',
  'Send contract with guarantee clause highlighted',
  'Propose 30-day trial at $1,500 (reduced) with same guarantee'),

('insurance_broker', 'summary',
  'End of discovery call, ready to wrap',
  'So quick recap: you''re writing [X] policies/month, spending [Y] hours on prospecting you hate, and you want to get to [Z] policies while working less. What we do: book 15-25 qualified meetings into your calendar per month, handle all the outreach, research, follow-up. Price: $1,997/mo founding rate, month-to-month, 10 meetings month-one guarantee. Fair summary? Questions before we make it official?',
  'Yeah that''s right, let''s do it OR One more question',
  'Transition to assumptive close',
  'Answer question then transition to assumptive close'),

('insurance_broker', 'choice',
  'Prospect is ready but hasn''t committed',
  'Two ways we can do this. Option A: we onboard you this week, first campaign launches Monday, you''re producing new policies by end of month. Option B: you think about it, we talk next week, same process just starts 7 days later. Which sounds right?',
  'This week OR next week works',
  'Book onboarding immediately',
  'Lock in next week discovery call + send follow-up'),

('insurance_broker', 'testimonial',
  'Prospect wants more proof before committing',
  'Let me give you something concrete. My own practice — I was writing 4-6 policies a month before building this system. Last month: 14 policies closed from 47 booked discovery calls the platform generated. That''s the system running on my own book. I built this for myself first, then opened it up because it worked. You''re not a guinea pig — you''re the 4th or 5th broker using a system I already proved on my own business.',
  'That''s impressive, okay',
  'Transition to assumptive close or urgency close',
  'Offer to share screen showing dashboard of founder''s own pipeline');


-- ─────────────────────────────────────────────────────
-- POST-CALL FOLLOW-UP SEQUENCES — Insurance Broker
-- ─────────────────────────────────────────────────────

INSERT INTO post_call_sequences (niche_name, call_outcome, step_order, delay_days, channel, message_template)
VALUES

-- INTERESTED but didn't close on the call
('insurance_broker', 'interested', 1, 0, 'email',
  'Hey [NAME], great conversation today. Recap of what we talked about: [summary]. As discussed, here''s the proposal and next-step link: [PROPOSAL_URL]. Founding rate ($1,997/mo locked 12 months) holds through [DATE+3]. Ready when you are.'),

('insurance_broker', 'interested', 2, 2, 'email',
  'Hey [NAME], just bumping the proposal from Monday. Any questions holding you back? Happy to jump on another quick 10-min call if it helps. Otherwise you can lock in here: [PROPOSAL_URL]'),

('insurance_broker', 'interested', 3, 5, 'email',
  'Hey [NAME], checking in. The founding slot with locked pricing expires [DATE]. After that it''s $2,997/mo. Want me to hold it for you through [DATE+3] or move on to the next broker on the list?'),

-- NEEDS TO THINK
('insurance_broker', 'needs_think', 1, 1, 'email',
  'Hey [NAME], appreciated the call yesterday. Know you wanted to think — totally reasonable. In case it helps, I put together a 1-page summary of what we discussed: [PROPOSAL_URL]. When''s a good time for a quick follow-up? Tomorrow same time?'),

('insurance_broker', 'needs_think', 2, 3, 'sms',
  'Hey [NAME], Ade from Crystallux. Circling back on our conversation. Where''s your head at? Quick text back either way is cool.'),

('insurance_broker', 'needs_think', 3, 7, 'email',
  'Hey [NAME], last ping from me. If the timing isn''t right, no worries at all — I''ll take you off the list. If it''s still a maybe, here''s a simpler option: 30-day pilot at $1,500 with the same 10-meeting guarantee. Yes/no/maybe?'),

-- PRICE OBJECTION
('insurance_broker', 'price_objection', 1, 1, 'email',
  'Hey [NAME], thinking about our conversation and the budget concern. Two options that might work better: (1) Starter tier at $1,497/mo for 10-15 meetings. (2) 60-day pilot at $1,500/mo with results guarantee. Both get you started without the full commitment. Want to talk through either?'),

('insurance_broker', 'price_objection', 2, 4, 'email',
  'Hey [NAME], one more idea. If cash flow is the issue, we can do quarterly billing (3 months paid upfront at $5,491 instead of monthly). Saves you 8%. Or, if you refer another broker who signs up, you get your first month free. Any of these work?'),

-- NOT NOW / NO FIT
('insurance_broker', 'not_now', 1, 30, 'email',
  'Hey [NAME], just a 30-day check-in. No pitch — genuinely curious how things are going with your prospecting. Any changes in your business that might make this worth revisiting?'),

('insurance_broker', 'no_fit', 1, 0, 'email',
  'Hey [NAME], appreciate your time. Sounds like we''re not a fit right now and that''s all good. If things change or you know another broker who''d benefit, keep me in mind. Best of luck with your practice.');


-- ─────────────────────────────────────────────────────
-- PROPOSAL TEMPLATE — Insurance Broker / Pipeline
-- ─────────────────────────────────────────────────────

INSERT INTO proposal_templates (niche_name, module_type, pricing_tier, proposal_structure, roi_calculation_method, typical_objections, closing_language)
VALUES
('insurance_broker', 'pipeline', 'growth',
  '{
    "section_1_problem": "You have [X] hours/week going to prospecting that you hate. You''re writing [Y] policies/month but know you could do more if prospecting was solved.",
    "section_2_solution": "Crystallux Pipeline delivers 15-25 qualified prospect meetings to your calendar every month. We find them, research them, write personally-crafted outreach, handle replies, and book them. You show up to the meeting and close.",
    "section_3_what_you_get": [
      "Google Maps + Apollo.io prospect discovery tuned to insurance advisor ICP",
      "AI research on every prospect before outreach",
      "Personalized email sequences (not templates)",
      "Automated 3-touch follow-up over 14 days",
      "Calendly integration for direct booking",
      "CASL-compliant unsubscribe handling",
      "Monthly performance report"
    ],
    "section_4_investment": "$1,997/month founding-client rate (locked 12 months). $2,997/mo standard after founding slots close. Month-to-month, 90-day minimum.",
    "section_5_guarantee": "10 qualified prospect meetings in month one, or month two is free. No minimum beyond 90 days.",
    "section_6_next_steps": "(1) Sign agreement via DocuSign. (2) 60-min onboarding call within 48 hours. (3) First campaign launches within 5 business days. (4) First meetings booked within 10-14 days."
  }'::jsonb,
  'Number of meetings booked × close rate × average commission per policy = monthly ROI. Breakeven typically 1-2 closed policies per month.',
  ARRAY['price', 'timing', 'trust', 'competitor'],
  'If this matches what you''re looking for, let''s get you onboarded this week. I''ll send over the agreement and we''ll schedule your kickoff call. Ready to move?'
);


-- ─────────────────────────────────────────────────────
-- COMPETITOR INTELLIGENCE — Insurance Broker
-- ─────────────────────────────────────────────────────

INSERT INTO competitor_intelligence (niche_name, competitor_name, competitor_positioning, our_advantages, their_weaknesses, common_comparison_questions, differentiation_script)
VALUES

('insurance_broker', 'HubSpot + Apollo (DIY stack)',
  'Generic sales automation. Customer builds their own system.',
  ARRAY[
    'Fully managed — you don''t run software, we do',
    'Built specifically for insurance, not a general tool',
    'Founder is licensed advisor, not a generalist',
    'Cheaper when you factor in operator time (at $100/hr, running HubSpot costs more than our fee)',
    'Includes data + copy + execution, not just software'
  ],
  ARRAY[
    'Requires full-time person to operate',
    'No insurance expertise — generic templates',
    'Expensive at scale ($890-$3,600/mo HubSpot alone)',
    'Learning curve is weeks to months',
    'No guarantee, no managed service'
  ],
  '[
    {"q": "Why not just use HubSpot myself?", "a": "You can — but you''ll spend 15 hours/week operating it and you''ll write generic copy because you''re not a copywriter. Our fee includes all of that done-for-you."},
    {"q": "Isn''t Apollo cheaper?", "a": "Apollo is just data — $49-$499/mo. But data without outreach, copy, follow-up, and booking = zero meetings. We include Apollo access + all the other layers."}
  ]'::jsonb,
  'Generic tools are built for generic users. We''re built for licensed insurance advisors, specifically. That shows up in the copy, the ICP targeting, the objection handling, and the compliance awareness (CASL). If you''re comparing us to HubSpot, you''re really comparing "software you operate" to "service we deliver" — different categories entirely.'),

('insurance_broker', 'Traditional MGA recruiters / prospecting consultants',
  'Human-led prospecting, usually on commission-share or retainer.',
  ARRAY[
    'Scalable — human services cap at 5-10 clients, we scale infinitely',
    'Cheaper than full-time SDR ($60K-80K/yr Canadian)',
    'No dependency on one person''s schedule or vacation',
    'Better data — we use AI to research each prospect, humans can''t',
    'Consistent quality — no off days'
  ],
  ARRAY[
    'Expensive ($3K-10K/mo) for human-led',
    'Limited scale — one person can only do so much',
    'Variable quality — depends on the individual''s mood/energy',
    'Sick days and vacation pause your pipeline',
    'Usually can''t match AI''s depth of research per prospect'
  ],
  '[
    {"q": "Why not hire an SDR?", "a": "An SDR costs $60K-80K fully loaded and takes 3-6 months to get productive. Our system starts producing meetings in 10-14 days and costs 1/3 the price. You can always hire an SDR later to scale — but start here."}
  ]'::jsonb,
  'Humans don''t scale, AI does. A human SDR works 40 hours, takes sick days, has mood swings. Our system runs 24/7, researches every prospect with consistent depth, and never has a bad day. For 1/3 the cost.'),

('insurance_broker', 'LinkedIn Sales Navigator',
  'Self-service prospecting platform for LinkedIn.',
  ARRAY[
    'LinkedIn is ONE channel — we use email + LinkedIn + (soon) SMS/WhatsApp',
    'Sales Nav gives you data, we give you booked meetings',
    'LinkedIn deliverability is declining — email still wins',
    'We''re end-to-end, Sales Nav is just search'
  ],
  ARRAY[
    'Data only, no outreach automation',
    'LinkedIn restrictions on outreach volume',
    'Saturated channel for cold outreach',
    'No email alternative'
  ],
  '[
    {"q": "Why not just use LinkedIn Sales Navigator?", "a": "You can — but Sales Nav is search only. You still have to write the messages, send them manually, handle replies, and book meetings. We do all of that, plus email, plus coming soon SMS/WhatsApp. Multi-channel always beats single-channel."}
  ]'::jsonb,
  'LinkedIn alone is a dying channel for B2B outbound — message response rates dropped 40% in 2024. Email + LinkedIn + SMS multi-touch outperforms any single channel by 3-5x. Sales Navigator is a tool; we''re the full outbound system.');


-- ─────────────────────────────────────────────────────
-- VERIFICATION QUERIES
-- ─────────────────────────────────────────────────────

-- Confirm tables created (expect 6 rows)
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'discovery_frameworks', 'objection_handlers', 'closing_scripts',
    'proposal_templates', 'post_call_sequences', 'competitor_intelligence'
  )
ORDER BY table_name;

-- Confirm insurance broker seed data
SELECT
  (SELECT COUNT(*) FROM discovery_frameworks WHERE niche_name = 'insurance_broker') AS discovery_frameworks,
  (SELECT COUNT(*) FROM objection_handlers WHERE niche_name = 'insurance_broker') AS objection_handlers,
  (SELECT COUNT(*) FROM closing_scripts WHERE niche_name = 'insurance_broker') AS closing_scripts,
  (SELECT COUNT(*) FROM post_call_sequences WHERE niche_name = 'insurance_broker') AS post_call_sequences,
  (SELECT COUNT(*) FROM proposal_templates WHERE niche_name = 'insurance_broker') AS proposal_templates,
  (SELECT COUNT(*) FROM competitor_intelligence WHERE niche_name = 'insurance_broker') AS competitor_intelligence;

-- Expected: 1 discovery framework, 6 objection handlers, 6 closing scripts, 10 post-call sequences, 1 proposal template, 3 competitor intelligence
