-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX VERTICAL EXPANSION — BATCH FULL (7 verticals)
-- File: docs/architecture/migrations/2026-04-24-verticals-batch-full.sql
--
-- Seeds 7 new niche_overlays rows in one pass:
--   Top 4 (is_active=true): consulting, real_estate, construction, dental
--   Bottom 3 (is_active=false):  legal, moving_services, cleaning_services
--
-- Every row carries the full required schema: claude_system_prompt,
-- outreach_tone, 12 pain_signals, offer_mapping with lead_segments
-- (residential + commercial), preferred_channels, voice_script_template
-- (90s target), apollo_title_keywords, compliance_notes (CASL/PIPEDA),
-- is_active, lead_target_type, lead_discovery_sources.
--
-- Idempotent — ON CONFLICT DO NOTHING. Rollback SQL trailing.
-- DOES NOT touch the insurance_broker seed — it remains unchanged.
--
-- Runs AFTER:
--   * 2026-04-22-scale-sprint-v1.sql
--   * 2026-04-23-apollo-schema.sql
--   * 2026-04-23-multi-channel.sql
--   * 2026-04-23-video-schema.sql
--   * 2026-04-23-b2b-b2c-segmentation.sql
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────
-- 0. SCHEMA PRE-CHECK (ADD MISSING COLUMNS IF NEEDED)
-- ─────────────────────────────────────────────────────────────────
-- The live schema uses niche_name as the key. This migration adds the
-- `vertical` column as a secondary identifier + adds every column the
-- seed expects. All IF NOT EXISTS so re-runs are safe.

ALTER TABLE niche_overlays
  ADD COLUMN IF NOT EXISTS vertical              text,
  ADD COLUMN IF NOT EXISTS niche_display_name    text,
  ADD COLUMN IF NOT EXISTS apollo_title_keywords jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS compliance_notes      text,
  ADD COLUMN IF NOT EXISTS is_active             boolean DEFAULT true;

-- Backfill vertical=niche_name so the unique index below doesn't trip
-- on existing rows with NULL vertical.
UPDATE niche_overlays SET vertical = niche_name WHERE vertical IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_niche_overlays_vertical_uq
  ON niche_overlays(vertical);


-- ─────────────────────────────────────────────────────────────────
-- 1. CONSULTING  (ACTIVE — rank #1)
-- ─────────────────────────────────────────────────────────────────

INSERT INTO niche_overlays (
  niche_name, vertical, niche_display_name,
  claude_system_prompt, outreach_tone,
  pain_signals, offer_mapping, preferred_channels,
  voice_script_template, apollo_title_keywords,
  compliance_notes, is_active,
  lead_target_type, lead_discovery_sources
) VALUES (
  'consulting', 'consulting',
  'Management & Business Consulting',
  'Peer-to-peer tone. Write as a fellow consultant who understands what it''s like to run a solo or boutique practice: feast-or-famine revenue, biz-dev eating weekends, fee compression from larger firms, utilisation anxiety. Reference specific pain signals like: dependence on LinkedIn + referrals, one-month pipeline gaps between engagements, proposal-writing time sinks, never having a predictable sales system. Offer framed as: "We run your top-of-funnel for you so you stop trading billable hours for bizdev hours. Book 20 discovery calls per month on autopilot." Never sound like a vendor. Write short, confident sentences. No jargon. No bullet points or dashes.',
  'Strategic peer, confident, respects consultant time and judgment.',
  '[
    "Feast-or-famine revenue with 30-60 day dry spells",
    "Spending evenings writing proposals instead of delivering",
    "Dependence on LinkedIn outreach and past-client referrals",
    "Losing RFPs to bigger firms with larger marketing budgets",
    "Utilisation dropping below 60 percent between engagements",
    "Discovery calls that don''t convert because pre-qualification is weak",
    "Can''t charge premium rates without case studies",
    "Bizdev eating weekends that should be rest or family time",
    "Website hasn''t been updated in 18 months, stale positioning",
    "Cold outreach feels beneath the brand but warm pipeline is empty",
    "Conference ROI unclear, business cards go nowhere",
    "Hiring a BDR is too expensive for the revenue stage"
  ]'::jsonb,
  '{
    "primary_offer": {
      "founding_price": 1997,
      "retail_price": 2997,
      "target_outcome": "20 qualified discovery calls per month with founder or C-suite decision-makers",
      "guarantee": "10 qualified meetings in first 30 days or month free"
    },
    "upsell_offer": {
      "name": "Consulting Growth Pro",
      "price": 3997,
      "includes": "Lead gen + automated follow-up + proposal-request template bank + pipeline dashboard + monthly strategy review"
    },
    "lead_segments": {
      "residential": {
        "target": "Personal coaches and solopreneurs — smaller deal sizes, higher volume",
        "pain_angles": ["solo practice overwhelm", "irregular income", "DIY marketing fatigue"],
        "channels": ["sms","email","voice"]
      },
      "commercial": {
        "target": "Boutique consulting firms, solo strategy consultants, fractional execs",
        "pain_angles": ["utilisation swings", "enterprise RFP losses", "biz-dev time sink", "premium-rate justification"],
        "channels": ["email","linkedin","voice"]
      }
    }
  }'::jsonb,
  '["email","linkedin","voice","video"]'::jsonb,
  'Hi, is this {name}? This is Mary from Crystallux. I work with boutique consultants and strategy practices in {city} like {company}. Most consultants I talk to burn their weekends on bizdev and still hit 30-60 day pipeline gaps between engagements. We run the top-of-funnel for you so you stop trading billable hours for sales hours. My founding consulting clients are booking 20 qualified discovery calls per month with decision-makers, not gatekeepers. I would love 20 minutes to show you how this works, tuned to {company}. Can I send you a Calendly link for this week?',
  '["Founder","Managing Partner","Principal","President","Partner","Director","Managing Director","Senior Consultant"]'::jsonb,
  'Canadian CASL compliance required. PIPEDA for data handling. No regulatory licensing concerns specific to consulting outreach beyond standard B2B.',
  true,
  'b2b',
  '["apollo_company","linkedin","city_scan","industry_directories"]'::jsonb
) ON CONFLICT (vertical) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 2. REAL_ESTATE  (ACTIVE — rank #2)
-- ─────────────────────────────────────────────────────────────────

INSERT INTO niche_overlays (
  niche_name, vertical, niche_display_name,
  claude_system_prompt, outreach_tone,
  pain_signals, offer_mapping, preferred_channels,
  voice_script_template, apollo_title_keywords,
  compliance_notes, is_active,
  lead_target_type, lead_discovery_sources
) VALUES (
  'real_estate', 'real_estate',
  'Real Estate Agents & Brokers',
  'Peer-to-peer tone. Real estate is an ultra-competitive, burnout-prone business. Write as someone who understands the daily grind: seller leads evaporating in spring markets, buyer leads ghosting after one showing, 10 agents fighting for every FSBO listing, Zillow/Realtor.ca eating the referral flow. Reference signals like: MLS alerts going cold, open-house traffic dropping, FSBO expiration lists getting picked over by the top 10 percent of agents, personal-brand burnout on social. Offer framed as: "We find ready-to-list sellers 30-60 days before they hit the MLS so you get the listing appointment before the listing goes to anyone else." Direct, confident, no fluff.',
  'Direct, hustle-aware, respects agent pace and commission math.',
  '[
    "Zillow and Realtor.ca eating referral flow",
    "FSBO lists picked over within 24 hours",
    "Open house traffic dropping year-over-year",
    "Seller leads going cold before the listing appointment",
    "Buyer leads ghosting after one showing",
    "Paying 40+ percent referral fees to lead aggregators",
    "Social media content treadmill with no pipeline ROI",
    "Competing with 10 agents for every expired listing",
    "New-agent competition undercutting commission rates",
    "Winter and spring market swings creating income gaps",
    "Tech stack bloat: CRM, IDX, drip, no single system",
    "Sphere-of-influence mining losing effectiveness year by year"
  ]'::jsonb,
  '{
    "primary_offer": {
      "founding_price": 1497,
      "retail_price": 2497,
      "target_outcome": "15 qualified seller listing appointments per month within your service area",
      "guarantee": "5 listing appointments in first 30 days or month free"
    },
    "upsell_offer": {
      "name": "Real Estate Growth Pro",
      "price": 2997,
      "includes": "Lead gen + automated listing-appointment booking + buyer-lead nurture sequence + monthly market heat map"
    },
    "lead_segments": {
      "residential": {
        "target": "Homeowners planning to list 30-60 days out (primary segment for real estate)",
        "pain_angles": ["selling in a shifting market", "timing the sale with a purchase", "downsizing decisions", "inherited property management"],
        "channels": ["sms","whatsapp","email","voice"]
      },
      "commercial": {
        "target": "Commercial real estate brokers, property investors, multi-door landlords",
        "pain_angles": ["cap rate compression", "vacancy risk on commercial portfolios", "1031-style Canadian reinvestment timing", "property manager churn"],
        "channels": ["email","linkedin","voice"]
      }
    }
  }'::jsonb,
  '["sms","whatsapp","email","voice","video"]'::jsonb,
  'Hi, is this {name}? This is Mary from Crystallux. I work with real estate agents in {city} like {company}. Most agents I talk to are fighting 10 other agents for every expired or FSBO listing and paying 40 percent referral fees to Zillow and Realtor.ca. We find ready-to-list sellers 30 to 60 days before they hit the MLS, so you get the listing appointment before anyone else knows about it. My founding agent clients are booking 15 listing appointments a month. I would love 15 minutes to show you how this works in your farm area. Can I grab time this week or next?',
  '["Realtor","Sales Representative","Broker","Broker of Record","Real Estate Agent","Team Lead","Managing Broker"]'::jsonb,
  'Canadian CASL compliance. PIPEDA for homeowner data. Provincial real estate council (RECO in Ontario, etc.) advertising rules apply to any co-branded messaging. DNCL compliance for voice outreach to homeowners.',
  true,
  'mixed',
  '["google_maps","facebook_local","apollo_company","linkedin","public_listings_feeds","mls_adjacent_signals"]'::jsonb
) ON CONFLICT (vertical) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 3. CONSTRUCTION  (ACTIVE — rank #3)
-- ─────────────────────────────────────────────────────────────────

INSERT INTO niche_overlays (
  niche_name, vertical, niche_display_name,
  claude_system_prompt, outreach_tone,
  pain_signals, offer_mapping, preferred_channels,
  voice_script_template, apollo_title_keywords,
  compliance_notes, is_active,
  lead_target_type, lead_discovery_sources
) VALUES (
  'construction', 'construction',
  'Construction & General Contracting',
  'Peer-to-peer tone. Write as a fellow small business operator who understands job-site pressures, cash flow between projects, and the stress of inconsistent lead flow. Reference specific pain signals like: weeks between project handoffs, dependence on HomeStars/referrals, losing bids to larger firms, crews sitting idle between jobs, insurance premium creep. Offer framed as: "We find the homeowners planning renovations 30-60 days before they start calling contractors. You close 10 quality projects this quarter." Never sound like a tech vendor. Write in short direct sentences. No jargon. No bullet points or dashes.',
  'Confident peer, direct language, acknowledges job-site realities, respects operator busyness.',
  '[
    "Weeks of downtime between projects",
    "Paying Google Ads $40-80 per lead that never convert",
    "Losing bids to bigger firms with marketing budgets",
    "Relying on word-of-mouth and referrals with no system",
    "Crew sitting idle while waiting for next project",
    "HomeStars and Houzz fees eating into profit margins",
    "Bidding against unlicensed contractors",
    "Seasonal gaps, winter slowdowns, spring scramble",
    "Spending evenings quoting instead of running the business",
    "Missed callbacks because no one is in the office",
    "Clients ghosting after the quote",
    "Cannot compete with large firms on SEO"
  ]'::jsonb,
  '{
    "primary_offer": {
      "founding_price": 1497,
      "retail_price": 2497,
      "target_outcome": "20 qualified homeowner leads per month actively planning renovations",
      "guarantee": "10 qualified leads in first 30 days or month free"
    },
    "upsell_offer": {
      "name": "Construction Growth",
      "price": 3497,
      "includes": "Lead gen + automated follow-up + SMS reminders + booking pipeline + monthly pipeline report"
    },
    "lead_segments": {
      "residential": {
        "target": "Homeowners planning renovations 30-60 days out",
        "pain_angles": ["kitchen outdated","basement finishing","addition for growing family","aging home repairs"],
        "channels": ["sms","whatsapp","email","voice"]
      },
      "commercial": {
        "target": "Property managers, developers, commercial building owners",
        "pain_angles": ["tenant buildouts","office renovations","warehouse expansions","building code upgrades"],
        "channels": ["email","linkedin","voice"]
      }
    }
  }'::jsonb,
  '["email","voice","whatsapp","linkedin"]'::jsonb,
  'Hi, is this {name}? This is Mary from Crystallux. I work with construction and renovation contractors in {city} like {company}. Most contractors I talk to are spending 3-4k a month on Google Ads and lead aggregators and getting homeowners who aren''t ready to pull the trigger. We find homeowners planning renovations 30 to 60 days before they start calling contractors, so you get in front of them first. My founding contractor clients are booking 20 quality quotes per month. I would love 15 minutes to show you how this works at {company}. Can I send you a Calendly link for this week or next?',
  '["Owner","Founder","President","Managing Partner","General Manager","Principal","Operations Manager","Estimator"]'::jsonb,
  'Canadian CASL compliance required. CRTC Do Not Call List check before voice outreach. Provincial contractor licensing — target licensed contractors only.',
  true,
  'mixed',
  '["google_maps","apollo_company","facebook_local","linkedin","commercial_property_databases","renovation_intent_signals"]'::jsonb
) ON CONFLICT (vertical) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 4. DENTAL  (ACTIVE — rank #4)
-- ─────────────────────────────────────────────────────────────────

INSERT INTO niche_overlays (
  niche_name, vertical, niche_display_name,
  claude_system_prompt, outreach_tone,
  pain_signals, offer_mapping, preferred_channels,
  voice_script_template, apollo_title_keywords,
  compliance_notes, is_active,
  lead_target_type, lead_discovery_sources
) VALUES (
  'dental', 'dental',
  'Dental Practices & Clinic Owners',
  'Peer-advisor tone. Dental practice owners are dentists first, business operators second. Write as someone who understands: hygienist shortage, insurance-rate compression, the cost of every empty chair hour, the grind of patient-recall campaigns. Reference signals like: new-patient acquisition cost creeping up, cosmetic-dentistry competition from clear-aligner DTC brands, insurance reimbursement squeeze, front-desk turnover. Offer framed as: "We book your chairs with new-patient consults — families and cosmetic-case candidates — without you or your front desk chasing anyone." Professional, calm, respects the clinical day.',
  'Professional, calm, patient-focused, acknowledges the clinical workload.',
  '[
    "Hygienist shortage slashing billable chair hours",
    "Insurance-rate compression squeezing margins",
    "New-patient acquisition cost climbing $200-400 per head",
    "Clear-aligner DTC brands stealing cosmetic-case pipeline",
    "Google Ads rejecting dental ads randomly for policy issues",
    "Front desk spending hours on recall calls",
    "Empty chairs on Tuesday and Thursday afternoons",
    "Patient no-show rate above 15 percent",
    "Treatment plan close rate below 50 percent",
    "Review generation sporadic, 3-star reviews undermining trust",
    "Associate dentists leaving to start their own practices",
    "Insurance audit risk making ad claims hard to write"
  ]'::jsonb,
  '{
    "primary_offer": {
      "founding_price": 1497,
      "retail_price": 2497,
      "target_outcome": "30 qualified new-patient consults per month in your service area",
      "guarantee": "15 booked consults in first 30 days or month free"
    },
    "upsell_offer": {
      "name": "Dental Growth Pro",
      "price": 2997,
      "includes": "Lead gen + automated recall sequence + treatment-plan follow-up + Google review automation + monthly practice growth report"
    },
    "lead_segments": {
      "residential": {
        "target": "Families and individuals needing new dentist — primary for this vertical",
        "pain_angles": ["moved recently, need new dentist","avoiding appointments due to past bad experience","cosmetic insecurity","kids'' first dental visits"],
        "channels": ["sms","whatsapp","email","voice"]
      },
      "commercial": {
        "target": "Corporate benefit administrators, employer group dental plans",
        "pain_angles": ["employee benefit cost","dental plan provider changes","onsite dental day programs"],
        "channels": ["email","linkedin","voice"]
      }
    }
  }'::jsonb,
  '["sms","email","voice","whatsapp"]'::jsonb,
  'Hi, is this Dr. {name}? This is Mary from Crystallux. I work with dental practices in {city} like {company}. Most practice owners I talk to have Tuesday and Thursday afternoon chairs sitting empty and their front desk spending hours on recall calls. We book your chairs with new-patient consults — families and cosmetic cases — without you or your front desk chasing anyone. My founding dental clients are booking 30 qualified new-patient consults a month. I would love 15 minutes to show you how this works at {company}. Can I send you a Calendly link for next week?',
  '["Owner","Doctor","Dentist","Practice Owner","Managing Partner","Chief Dental Officer","DDS","DMD"]'::jsonb,
  'Canadian CASL compliance. PIPEDA for patient-lead data. Provincial dental-regulatory body advertising rules apply (RCDSO in Ontario) — avoid outcome claims, diagnostic claims, comparison to other practices.',
  true,
  'mixed',
  '["google_maps","apollo_company","linkedin","dental_association_directories"]'::jsonb
) ON CONFLICT (vertical) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 5. LEGAL  (INACTIVE — rank #5)
-- ─────────────────────────────────────────────────────────────────

INSERT INTO niche_overlays (
  niche_name, vertical, niche_display_name,
  claude_system_prompt, outreach_tone,
  pain_signals, offer_mapping, preferred_channels,
  voice_script_template, apollo_title_keywords,
  compliance_notes, is_active,
  lead_target_type, lead_discovery_sources
) VALUES (
  'legal', 'legal',
  'Solo Lawyers & Boutique Law Firms',
  'Peer-to-peer, measured tone. Lawyers are deeply regulated — write as someone who understands law-society advertising rules, retainer cash flow, file-churn pressure, the compliance risk of claim-style marketing. Reference signals like: Google Ads policy rejections for legal claims, bar advertising rules, unpredictable retainer flow for solo practices, dependence on referring colleagues. Offer framed as: "We build a predictable intake pipeline for practice-area-matched clients — no outcome claims, no comparative advertising, compliant with your law society." Measured, respectful, compliance-aware.',
  'Measured, respectful, compliance-aware, peer of a fellow professional.',
  '[
    "Google Ads policy rejecting legal claims randomly",
    "Law society advertising rules limiting marketing copy",
    "Retainer flow unpredictable month to month",
    "Dependence on referrals from a narrow set of colleagues",
    "Legal aid caps on billable hours for certain practice areas",
    "Associate lawyer turnover in boutique firms",
    "File churn eating profitability on fixed-fee work",
    "Intake staff spending time on unqualified calls",
    "Bar compliance risk from comparative advertising",
    "Avvo and legal directory fees for mediocre leads",
    "Contingency-fee case qualification extremely time-consuming",
    "Solo practitioners cannot afford full-time marketing staff"
  ]'::jsonb,
  '{
    "primary_offer": {
      "founding_price": 1997,
      "retail_price": 2997,
      "target_outcome": "15 qualified intake consults per month in your practice areas",
      "guarantee": "8 qualified intakes in first 30 days or month free"
    },
    "upsell_offer": {
      "name": "Legal Practice Growth",
      "price": 3997,
      "includes": "Lead gen + automated intake qualification + conflict-check prep + matter-type routing + monthly compliance review"
    },
    "lead_segments": {
      "residential": {
        "target": "Individuals needing family, immigration, real estate, estate, or personal injury counsel",
        "pain_angles": ["emotional urgency of the matter","unclear fee structures","fear of legal costs","language accessibility"],
        "channels": ["sms","email","voice"]
      },
      "commercial": {
        "target": "Small business owners needing corporate, employment, commercial litigation, or IP counsel",
        "pain_angles": ["retainer commitment","in-house vs outside counsel trade-off","litigation cost control","regulatory compliance deadlines"],
        "channels": ["email","linkedin","voice"]
      }
    }
  }'::jsonb,
  '["email","voice","linkedin"]'::jsonb,
  'Hi, is this {name}? This is Mary from Crystallux. I work with solo lawyers and boutique firms in {city} like {company}. Most solo practitioners I talk to have retainer flow that swings 40 percent month to month and rely on a narrow set of colleague referrals. We build a predictable intake pipeline for your practice areas — no outcome claims, no comparative advertising, fully compliant with your law society. My founding legal clients are booking 15 qualified intake consults per month. I would love 20 minutes to show you how this works at {company}. Can I send you a Calendly link?',
  '["Lawyer","Barrister","Solicitor","Partner","Principal","Managing Partner","Founder","Senior Counsel"]'::jsonb,
  'Canadian CASL compliance mandatory. PIPEDA for prospective-client intake data. LAW SOCIETY ADVERTISING RULES are the binding constraint — in Ontario, LSO Rule 4.2; in BC, Law Society Rules section 4; Quebec Barreau strict. No outcome claims, no comparative advertising, no client testimonials without written consent. REQUIRES pre-activation review of all outreach copy with a law-society-practising advising lawyer.',
  false,
  'mixed',
  '["apollo_company","linkedin","law_society_directories","city_scan"]'::jsonb
) ON CONFLICT (vertical) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 6. MOVING_SERVICES  (INACTIVE — rank #6)
-- ─────────────────────────────────────────────────────────────────

INSERT INTO niche_overlays (
  niche_name, vertical, niche_display_name,
  claude_system_prompt, outreach_tone,
  pain_signals, offer_mapping, preferred_channels,
  voice_script_template, apollo_title_keywords,
  compliance_notes, is_active,
  lead_target_type, lead_discovery_sources
) VALUES (
  'moving_services', 'moving_services',
  'Moving & Relocation Services',
  'Peer-operator tone. Moving is a brutal business — seasonal, price-sensitive, high-competition. Write as someone who understands the daily grind: no-show customers, last-minute cancellations, fuel costs, insurance premiums, crew turnover. Reference signals like: Two Men and a Truck competitors, U-Haul DIY pressure, slow winter months, rate pressure from aggregators. Offer framed as: "We find homeowners planning moves 2-3 weeks before they start calling quotes, so you lock them in before your competitors do." Direct, confident, no fluff.',
  'Direct, fast-paced, respects operator time, acknowledges competitive pressure.',
  '[
    "Losing jobs to last-minute cancellations",
    "Competing with Two Men and a Truck on brand",
    "U-Haul and PODS stealing DIY-price-sensitive customers",
    "Moving aggregators capping rates",
    "Seasonal income swings, summer boom, winter famine",
    "Crew turnover during peak moving season",
    "Customer ghosting after quote",
    "No-show customers costing a truck plus crew half-day",
    "Fuel prices eating into margins",
    "Insurance premiums climbing each year",
    "Review sites damaging reputation",
    "Cannot predict lead flow month to month"
  ]'::jsonb,
  '{
    "primary_offer": {
      "founding_price": 997,
      "retail_price": 1497,
      "target_outcome": "30 qualified move leads per month, homeowners planning moves 2-3 weeks out",
      "guarantee": "15 quotes booked in first 30 days or month free"
    },
    "upsell_offer": {
      "name": "Moving Growth Pro",
      "price": 2497,
      "includes": "Lead gen + automated quote follow-up + SMS reminders + no-show recovery + seasonal demand forecasting"
    },
    "lead_segments": {
      "residential": {
        "target": "Families and individuals planning home moves 2-3 weeks out",
        "pain_angles": ["stress of moving","packing overwhelm","avoiding damage","same-day availability"],
        "channels": ["sms","whatsapp","email","voice"]
      },
      "commercial": {
        "target": "Companies relocating offices, equipment, or warehouses",
        "pain_angles": ["business continuity during move","IT equipment handling","after-hours scheduling","multi-location logistics"],
        "channels": ["email","linkedin","voice"]
      }
    }
  }'::jsonb,
  '["sms","whatsapp","email","voice"]'::jsonb,
  'Hi, is this {name}? This is Mary from Crystallux. I work with moving companies in {city} like {company}. Most movers I talk to hit a wall during winter and lose summer jobs to last-minute cancellations. We find homeowners planning moves 2 to 3 weeks before they start calling for quotes, so you can lock them in before Two Men shows up. My founding moving clients are booking 30 quality quotes a month. I would love 15 minutes to show you how this works at {company}. Can I send you a Calendly link for tomorrow or the day after?',
  '["Owner","Founder","President","General Manager","Operations Manager","Dispatcher"]'::jsonb,
  'CASL compliance. CRTC DNCL check before voice. BBB accreditation recommended for client credibility.',
  false,
  'mixed',
  '["google_maps","facebook_local","home_sale_signals","apollo_company","linkedin"]'::jsonb
) ON CONFLICT (vertical) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 7. CLEANING_SERVICES  (INACTIVE — rank #7)
-- ─────────────────────────────────────────────────────────────────

INSERT INTO niche_overlays (
  niche_name, vertical, niche_display_name,
  claude_system_prompt, outreach_tone,
  pain_signals, offer_mapping, preferred_channels,
  voice_script_template, apollo_title_keywords,
  compliance_notes, is_active,
  lead_target_type, lead_discovery_sources
) VALUES (
  'cleaning_services', 'cleaning_services',
  'Cleaning & Janitorial Services',
  'Peer-operator tone. Cleaning is a high-churn, high-competition business. Write as someone who understands: one-time jobs are a dead-end, recurring customers are the goal, retention matters more than acquisition. Reference signals like: Merry Maids, Molly Maid competitors, cleaner turnover, last-minute cancellations, residential vs commercial mix, scaling crew without quality drop. Offer framed as: "We find homeowners who want recurring cleaning — weekly or bi-weekly. Higher LTV than one-time cleans." Direct, practical, respects operational realities.',
  'Friendly but direct, acknowledges retention challenges, focuses on LTV over one-off revenue.',
  '[
    "Customers booking one-time cleans and ghosting",
    "Losing regulars to Merry Maids or Molly Maid marketing",
    "Cleaner turnover training cost eating profit",
    "Spending on Google Ads for one-time bookings",
    "Last-minute cancellations wasting scheduled hours",
    "Trying to build recurring contracts but competitors undercut",
    "Cannot scale beyond what I can personally supervise",
    "Commercial contracts stuck in bid wars on price",
    "Customers comparing to 15-per-hour individual cleaners",
    "Review management across platforms consumes time",
    "Seasonal spikes, spring cleaning rush then quiet",
    "No retention system, customers drift away silently"
  ]'::jsonb,
  '{
    "primary_offer": {
      "founding_price": 997,
      "retail_price": 1497,
      "target_outcome": "25 qualified cleaning leads per month prioritizing recurring contracts",
      "guarantee": "10 booked cleans in first 30 days or month free"
    },
    "upsell_offer": {
      "name": "Cleaning Retention Pro",
      "price": 1997,
      "includes": "Lead gen + automated rebooking + retention SMS sequence + review request automation + referral tracking"
    },
    "lead_segments": {
      "residential": {
        "target": "Homeowners wanting recurring weekly or bi-weekly cleaning",
        "pain_angles": ["time poverty","dual-income families","house too big to manage","allergies and deep clean needs"],
        "channels": ["sms","whatsapp","email","voice"]
      },
      "commercial": {
        "target": "Office managers, property managers, retail chain operators",
        "pain_angles": ["staff turnover","inconsistent cleaning quality","after-hours access","covid protocols"],
        "channels": ["email","linkedin","voice"]
      }
    }
  }'::jsonb,
  '["sms","whatsapp","email","voice"]'::jsonb,
  'Hi, is this {name}? This is Mary from Crystallux. I work with cleaning and janitorial businesses in {city} like {company}. Most cleaning businesses I talk to hit a wall scaling past what the owner can supervise and lose regulars to big brands like Merry Maids. We find homeowners looking for weekly or bi-weekly recurring cleaning, so you get high-LTV customers not one-time jobs. My founding cleaning clients are booking 25 qualified recurring leads a month. I would love 15 minutes to show you how this works at {company}. Can I grab 15 minutes with you this week?',
  '["Owner","Founder","President","General Manager","Operations Manager","Sales Manager"]'::jsonb,
  'CASL compliance. WSIB recommended for client credibility. Commercial vs residential mix matters for messaging.',
  false,
  'mixed',
  '["google_maps","facebook_local","apollo_company","linkedin","property_manager_directories"]'::jsonb
) ON CONFLICT (vertical) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 8. VERIFICATION
-- ─────────────────────────────────────────────────────────────────

-- Expect 8 rows total (insurance_broker + 7 new)
SELECT vertical, niche_display_name, is_active,
       jsonb_array_length(pain_signals) AS pain_count,
       offer_mapping->'primary_offer'->>'founding_price' AS founding_price
FROM niche_overlays
ORDER BY is_active DESC, vertical;

-- Expect: insurance_broker untouched (still has its pre-existing prompt/seed)
SELECT niche_name, vertical,
       (claude_system_prompt IS NOT NULL) AS has_prompt,
       jsonb_array_length(pain_signals) AS pain_count
FROM niche_overlays
WHERE niche_name = 'insurance_broker' OR vertical = 'insurance_broker';


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK (uncomment sections to undo — test on staging first)
-- ═══════════════════════════════════════════════════════════════════
--
-- -- Remove the 7 seeded verticals
-- DELETE FROM niche_overlays
-- WHERE vertical IN ('consulting','real_estate','construction','dental',
--                    'legal','moving_services','cleaning_services');
--
-- -- Schema additions — only drop if this migration added them. Skip
-- -- if they already existed from an earlier migration.
-- -- DROP INDEX IF EXISTS idx_niche_overlays_vertical_uq;
-- -- ALTER TABLE niche_overlays
-- --   DROP COLUMN IF EXISTS is_active,
-- --   DROP COLUMN IF EXISTS compliance_notes,
-- --   DROP COLUMN IF EXISTS apollo_title_keywords,
-- --   DROP COLUMN IF EXISTS niche_display_name,
-- --   DROP COLUMN IF EXISTS vertical;
