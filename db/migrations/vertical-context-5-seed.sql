-- ============================================================
-- Vertical configuration seed
--
-- Before this, exactly ONE of eight verticals (insurance_broker) had
-- icp_template, dashboard_labels and routing_preferences populated.
-- The other seven had the columns and nothing in them. The model was
-- never the problem; the data was.
--
-- Every value below is industry-specific. Insurance values were NOT
-- copied across -- a dentist has no "book size" and a mover has no
-- "licensing_required: FSRA". Where a number is a working assumption
-- rather than a known fact it carries "_assumed": true, so it can be
-- found and corrected later instead of hardening into folklore.
--
-- Run LAST, only after steps 1-4 verify clean. Requires the
-- behavior_config and sales_process_config columns from step 1.
--
-- No transaction wrapper: each vertical is its own statement, so one
-- bad row cannot roll back the other six.
-- Idempotent: every write is guarded so re-running cannot clobber
-- hand-tuned values.
-- ============================================================

-- ------------------------------------------------------------
-- CONSTRUCTION -- project pipeline, permits, ROI-first
-- ------------------------------------------------------------
UPDATE niche_overlays SET
  icp_template = COALESCE(icp_template, '{"geography":"Ontario, Canada","target_role":["owner","estimator","project manager","business development manager","operations manager"],"company_size_min":3,"company_size_max":150,"typical_services":["general contracting","framing","drywall","painting","roofing","concrete"],"exclude_from_target":["one-person handyman with no crew","pure equipment rental","material suppliers"],"annual_revenue_min_cad":250000,"_assumed":true}'::jsonb),
  dashboard_labels = COALESCE(dashboard_labels, '{"leads":"Prospects","contacted":"Contractors Contacted","replied":"Responses","meetings":"Site Visits / Estimates","deals":"Projects in Pipeline","closed_won":"Projects Won","deal_value":"Project Value","conversion_rate":"Win Rate","outreach_sent":"Outreach Sent"}'::jsonb),
  routing_preferences = COALESCE(routing_preferences, '{"search_keywords":["general contractor ontario","construction company","roofing contractor","framing contractor"],"exclude_keywords":["equipment rental","building supply","hardware store","architect"],"primary_platforms":["google_maps"],"secondary_platforms":["apollo"],"tertiary_platforms":["permit_registry"]}'::jsonb),
  behavior_config = CASE WHEN behavior_config = '{}'::jsonb THEN '{"signal_types":["building_permit_filed","project_awarded","hiring_trades","new_service_area","equipment_purchase","expansion"],"signal_weights":{"building_permit_filed":30,"project_awarded":28,"hiring_trades":18,"expansion":15,"new_service_area":12,"equipment_purchase":8},"intent_rules":{"hot":"permit filed or project awarded within 30 days","warm":"hiring trades within 60 days","cold":"no project signal in 90 days"},"qualification_rules":["Do they quote jobs themselves or subcontract out?","Crew size and typical project value","Are they turning work away or chasing it?"],"objection_handling":{"too_busy":"Lead with capacity, not volume — qualified projects only, no tyre-kickers.","tried_before":"Ask which channel and what the close rate was; most have tried directories, not signal-based outreach.","price":"Frame against one won project, not monthly cost."},"terminology":{"lead":"prospect","deal":"project","meeting":"site visit","quote":"estimate","customer":"client","worker":"crew"},"message_length":"short"}'::jsonb ELSE behavior_config END,
  sales_process_config = CASE WHEN sales_process_config = '{}'::jsonb THEN '{"sales_process":["DISCOVER","PROJECT_SIGNAL","QUALIFY","DECISION_MAKER","OUTREACH","ESTIMATE_MEETING","FOLLOW_UP","BOOK"],"channel_strategy":{"primary":"email","secondary":"phone","tertiary":"linkedin","avoid":["whatsapp"]},"followup_cadence":{"steps":[{"day":0,"channel":"email"},{"day":3,"channel":"email"},{"day":7,"channel":"phone"},{"day":14,"channel":"email"}],"max_touches":4},"conversion_event":"estimate_booked","average_sales_cycle_days":21,"cta_types":["book_site_visit","request_estimate_call"],"_assumed":true}'::jsonb ELSE sales_process_config END,
  updated_at = now()
WHERE niche_name = 'construction';

-- ------------------------------------------------------------
-- DENTAL -- patient acquisition, chair utilisation, PHIPA
-- ------------------------------------------------------------
UPDATE niche_overlays SET
  icp_template = COALESCE(icp_template, '{"geography":"Ontario, Canada","target_role":["practice owner","dentist","office manager","practice manager"],"company_size_min":2,"company_size_max":40,"typical_services":["general dentistry","cosmetic","orthodontics","implants","hygiene"],"exclude_from_target":["dental labs","supply distributors","corporate DSO head offices"],"operatory_count_min":2,"_assumed":true}'::jsonb),
  dashboard_labels = COALESCE(dashboard_labels, '{"leads":"Practices","contacted":"Practices Contacted","replied":"Responses","meetings":"Consultations Booked","deals":"Practices in Pipeline","closed_won":"Practices Signed","deal_value":"Contract Value","conversion_rate":"Close Rate","outreach_sent":"Outreach Sent"}'::jsonb),
  routing_preferences = COALESCE(routing_preferences, '{"search_keywords":["dental clinic ontario","dentist office","family dentistry","cosmetic dentistry"],"exclude_keywords":["dental lab","dental supply","dental school","veterinary dental"],"primary_platforms":["google_maps"],"secondary_platforms":["apollo"],"tertiary_platforms":[]}'::jsonb),
  behavior_config = CASE WHEN behavior_config = '{}'::jsonb THEN '{"signal_types":["new_practice_opening","hiring_hygienist","new_service_line","review_volume_declining","relocation","associate_added"],"signal_weights":{"new_practice_opening":30,"new_service_line":22,"hiring_hygienist":18,"associate_added":15,"review_volume_declining":12,"relocation":10},"intent_rules":{"hot":"new practice or new service line within 60 days","warm":"hiring clinical staff","cold":"no growth signal in 120 days"},"qualification_rules":["Are they accepting new patients?","Chair/operatory utilisation","Who owns marketing decisions — dentist or office manager?"],"objection_handling":{"already_full":"Shift from volume to case mix — higher-value treatment, not more patients.","have_an_agency":"Ask what the cost per booked consult is; most cannot answer.","not_interested":"Respect it quickly; this vertical talks to each other."},"terminology":{"lead":"practice","deal":"engagement","meeting":"consultation","customer":"patient","revenue":"production"},"message_length":"short","compliance_sensitivity":"high"}'::jsonb ELSE behavior_config END,
  sales_process_config = CASE WHEN sales_process_config = '{}'::jsonb THEN '{"sales_process":["DISCOVER","LOCAL_SIGNAL","QUALIFY","OFFER","OUTREACH","CONSULTATION","FOLLOW_UP","BOOK"],"channel_strategy":{"primary":"email","secondary":"phone","tertiary":"linkedin","avoid":["sms"]},"followup_cadence":{"steps":[{"day":0,"channel":"email"},{"day":4,"channel":"email"},{"day":10,"channel":"phone"}],"max_touches":3},"conversion_event":"consultation_booked","average_sales_cycle_days":28,"cta_types":["book_consultation","request_practice_review"],"_assumed":true}'::jsonb ELSE sales_process_config END,
  updated_at = now()
WHERE niche_name = 'dental';

-- ------------------------------------------------------------
-- REAL ESTATE -- listings, agent recruitment, fast and competitive
-- ------------------------------------------------------------
UPDATE niche_overlays SET
  icp_template = COALESCE(icp_template, '{"geography":"Ontario, Canada","target_role":["broker","broker-owner","team leader","realtor","sales representative"],"company_size_min":1,"company_size_max":200,"typical_services":["residential resale","pre-construction","luxury","commercial","leasing"],"exclude_from_target":["mortgage-only brokerages","property management only","unlicensed assistants"],"annual_transactions_min":6,"_assumed":true}'::jsonb),
  dashboard_labels = COALESCE(dashboard_labels, '{"leads":"Agents & Brokerages","contacted":"Agents Contacted","replied":"Responses","meetings":"Strategy Calls","deals":"Agents in Pipeline","closed_won":"Agents Signed","deal_value":"Contract Value","conversion_rate":"Close Rate","outreach_sent":"Outreach Sent"}'::jsonb),
  routing_preferences = COALESCE(routing_preferences, '{"search_keywords":["real estate brokerage ontario","realtor team","real estate agent"],"exclude_keywords":["property management","mortgage broker","appraiser","home inspector"],"primary_platforms":["google_maps","linkedin_sn"],"secondary_platforms":["apollo"],"tertiary_platforms":[]}'::jsonb),
  behavior_config = CASE WHEN behavior_config = '{}'::jsonb THEN '{"signal_types":["listing_volume_spike","team_expansion","agent_hiring","new_development_launch","territory_growth","social_activity_spike"],"signal_weights":{"listing_volume_spike":28,"team_expansion":25,"new_development_launch":20,"agent_hiring":15,"territory_growth":12,"social_activity_spike":8},"intent_rules":{"hot":"listing spike or team expansion within 30 days","warm":"consistent listing activity","cold":"no listings in 90 days"},"qualification_rules":["Solo agent, team, or brokerage?","Transactions per year","Are they buying leads today, and at what cost?"],"objection_handling":{"buy_leads_already":"Compare cost per closed transaction, not cost per lead.","market_is_slow":"Slow markets are when pipeline building matters most.","no_time":"Lead with automation — the pitch is fewer hours, not more leads."},"terminology":{"lead":"lead","deal":"transaction","meeting":"strategy call","customer":"client","listing":"listing","closed_won":"closing"},"message_length":"very_short"}'::jsonb ELSE behavior_config END,
  sales_process_config = CASE WHEN sales_process_config = '{}'::jsonb THEN '{"sales_process":["DISCOVER","MARKET_SIGNAL","PERSON","OFFER","OUTREACH","STRATEGY_CALL","FOLLOW_UP","BOOK"],"channel_strategy":{"primary":"email","secondary":"sms","tertiary":"linkedin","avoid":[]},"followup_cadence":{"steps":[{"day":0,"channel":"email"},{"day":2,"channel":"sms"},{"day":5,"channel":"email"},{"day":9,"channel":"phone"}],"max_touches":4},"conversion_event":"strategy_call_booked","average_sales_cycle_days":14,"cta_types":["book_strategy_call","request_market_report"],"_assumed":true}'::jsonb ELSE sales_process_config END,
  updated_at = now()
WHERE niche_name = 'real_estate';

-- ------------------------------------------------------------
-- CONSULTING -- peer tone, project pipeline, feast-or-famine
-- ------------------------------------------------------------
UPDATE niche_overlays SET
  icp_template = COALESCE(icp_template, '{"geography":"Canada","target_role":["founder","managing partner","principal","president","practice lead"],"company_size_min":1,"company_size_max":50,"typical_services":["management consulting","strategy","operations","HR advisory","IT consulting"],"exclude_from_target":["staffing agencies","large global firms","one-off freelancers"],"annual_revenue_min_cad":150000,"_assumed":true}'::jsonb),
  dashboard_labels = COALESCE(dashboard_labels, '{"leads":"Firms","contacted":"Firms Contacted","replied":"Responses","meetings":"Discovery Calls","deals":"Engagements in Pipeline","closed_won":"Engagements Won","deal_value":"Engagement Value","conversion_rate":"Win Rate","outreach_sent":"Outreach Sent"}'::jsonb),
  routing_preferences = COALESCE(routing_preferences, '{"search_keywords":["management consulting firm","business consultant","strategy consulting"],"exclude_keywords":["staffing agency","recruiter","franchise consultant","immigration consultant"],"primary_platforms":["apollo","linkedin_sn"],"secondary_platforms":["google_maps"],"tertiary_platforms":[]}'::jsonb),
  behavior_config = CASE WHEN behavior_config = '{}'::jsonb THEN '{"signal_types":["hiring_consultants","new_service_line","speaking_engagement","content_publishing","client_logo_added","funding_or_award"],"signal_weights":{"hiring_consultants":25,"new_service_line":22,"client_logo_added":18,"content_publishing":15,"speaking_engagement":12,"funding_or_award":10},"intent_rules":{"hot":"hiring or new service line within 45 days","warm":"active content publishing","cold":"no visible activity in 120 days"},"qualification_rules":["Where does their pipeline come from today — referral or outbound?","Utilisation vs bench time","Who sells: the founder, or a team?"],"objection_handling":{"referrals_are_enough":"Referrals are unpredictable; ask about their last 60-day dry spell.","we_are_the_experts":"Peer framing — this is pipeline plumbing, not consulting advice.","no_bandwidth":"That is the argument for automation, not against it."},"terminology":{"lead":"prospect","deal":"engagement","meeting":"discovery call","customer":"client","revenue":"billings"},"message_length":"medium"}'::jsonb ELSE behavior_config END,
  sales_process_config = CASE WHEN sales_process_config = '{}'::jsonb THEN '{"sales_process":["DISCOVER","RESEARCH","QUALIFY","INTENT","OUTREACH","DISCOVERY_CALL","FOLLOW_UP","BOOK"],"channel_strategy":{"primary":"email","secondary":"linkedin","tertiary":"voice","avoid":["sms","whatsapp"]},"followup_cadence":{"steps":[{"day":0,"channel":"email"},{"day":4,"channel":"linkedin"},{"day":9,"channel":"email"},{"day":16,"channel":"email"}],"max_touches":4},"conversion_event":"discovery_call_booked","average_sales_cycle_days":30,"cta_types":["book_discovery_call","request_pipeline_audit"],"_assumed":true}'::jsonb ELSE sales_process_config END,
  updated_at = now()
WHERE niche_name = 'consulting';

-- ------------------------------------------------------------
-- CLEANING SERVICES -- recurring contracts, route density
-- ------------------------------------------------------------
UPDATE niche_overlays SET
  icp_template = COALESCE(icp_template, '{"geography":"Ontario, Canada","target_role":["owner","operations manager","general manager","account manager"],"company_size_min":2,"company_size_max":100,"typical_services":["commercial janitorial","residential cleaning","post-construction","carpet and floor care"],"exclude_from_target":["single-operator with no staff","equipment retailers","franchise head offices"],"recurring_contract_focus":true,"_assumed":true}'::jsonb),
  dashboard_labels = COALESCE(dashboard_labels, '{"leads":"Prospects","contacted":"Businesses Contacted","replied":"Responses","meetings":"Walkthroughs Booked","deals":"Contracts in Pipeline","closed_won":"Contracts Won","deal_value":"Contract Value","conversion_rate":"Win Rate","outreach_sent":"Outreach Sent"}'::jsonb),
  routing_preferences = COALESCE(routing_preferences, '{"search_keywords":["commercial cleaning ontario","janitorial services","office cleaning company"],"exclude_keywords":["dry cleaning","laundromat","cleaning supplies","pressure washer rental"],"primary_platforms":["google_maps"],"secondary_platforms":["apollo"],"tertiary_platforms":[]}'::jsonb),
  behavior_config = CASE WHEN behavior_config = '{}'::jsonb THEN '{"signal_types":["new_contract_won","hiring_cleaners","new_service_area","office_reopening","franchise_expansion","review_volume_growth"],"signal_weights":{"new_contract_won":26,"hiring_cleaners":22,"new_service_area":20,"office_reopening":16,"franchise_expansion":10,"review_volume_growth":6},"intent_rules":{"hot":"hiring cleaners or new service area within 30 days","warm":"steady review growth","cold":"no signal in 90 days"},"qualification_rules":["Recurring contracts or one-off jobs?","Crew count and route density","Do they quote on site or by phone?"],"objection_handling":{"word_of_mouth_works":"Ask what happens when a large contract ends unexpectedly.","margins_too_thin":"Target contract size, not job count.","no_capacity":"Qualify for contract value so they can trade up, not just add work."},"terminology":{"lead":"prospect","deal":"contract","meeting":"walkthrough","quote":"estimate","customer":"client","worker":"crew"},"message_length":"short"}'::jsonb ELSE behavior_config END,
  sales_process_config = CASE WHEN sales_process_config = '{}'::jsonb THEN '{"sales_process":["DISCOVER","LOCAL_SIGNAL","QUALIFY","OFFER","OUTREACH","WALKTHROUGH","FOLLOW_UP","BOOK"],"channel_strategy":{"primary":"email","secondary":"phone","tertiary":"sms","avoid":[]},"followup_cadence":{"steps":[{"day":0,"channel":"email"},{"day":3,"channel":"phone"},{"day":8,"channel":"email"}],"max_touches":3},"conversion_event":"walkthrough_booked","average_sales_cycle_days":18,"cta_types":["book_walkthrough","request_quote"],"_assumed":true}'::jsonb ELSE sales_process_config END,
  updated_at = now()
WHERE niche_name = 'cleaning_services';

-- ------------------------------------------------------------
-- LEGAL -- credibility first, Law Society advertising rules
-- ------------------------------------------------------------
UPDATE niche_overlays SET
  icp_template = COALESCE(icp_template, '{"geography":"Ontario, Canada","target_role":["managing partner","principal lawyer","partner","firm administrator"],"company_size_min":1,"company_size_max":60,"typical_services":["family law","real estate law","personal injury","corporate/commercial","immigration","wills and estates"],"exclude_from_target":["in-house legal departments","paralegal-only practices where prohibited","legal aid clinics"],"licensing_required":["LSO"],"_assumed":true}'::jsonb),
  dashboard_labels = COALESCE(dashboard_labels, '{"leads":"Firms","contacted":"Firms Contacted","replied":"Responses","meetings":"Consultations Booked","deals":"Matters in Pipeline","closed_won":"Retainers Signed","deal_value":"Retainer Value","conversion_rate":"Retention Rate","outreach_sent":"Outreach Sent"}'::jsonb),
  routing_preferences = COALESCE(routing_preferences, '{"search_keywords":["law firm ontario","family lawyer","personal injury lawyer","real estate lawyer"],"exclude_keywords":["legal aid","court reporter","process server","law school"],"primary_platforms":["google_maps","linkedin_sn"],"secondary_platforms":["apollo"],"tertiary_platforms":["lso_directory"]}'::jsonb),
  behavior_config = CASE WHEN behavior_config = '{}'::jsonb THEN '{"signal_types":["hiring_associates","new_practice_area","office_expansion","partner_added","content_publishing","award_or_ranking"],"signal_weights":{"new_practice_area":26,"hiring_associates":24,"partner_added":18,"office_expansion":16,"award_or_ranking":10,"content_publishing":6},"intent_rules":{"hot":"new practice area or associate hire within 45 days","warm":"visible publishing or ranking activity","cold":"no signal in 120 days"},"qualification_rules":["Which practice areas do they want more of?","Intake handled in-house or answering service?","Who approves marketing — managing partner or administrator?"],"objection_handling":{"referrals_only":"Ask what happens when a referral source retires.","ethics_concerns":"Lead with compliance posture; nothing is sent that a regulator could not read.","too_expensive":"Frame against one retained matter."},"terminology":{"lead":"prospective client","deal":"matter","meeting":"consultation","customer":"client","closed_won":"retainer","revenue":"billings"},"message_length":"medium","compliance_sensitivity":"high"}'::jsonb ELSE behavior_config END,
  sales_process_config = CASE WHEN sales_process_config = '{}'::jsonb THEN '{"sales_process":["DISCOVER","RESEARCH","QUALIFY","COMPLIANCE_CHECK","OUTREACH","CONSULTATION","FOLLOW_UP","BOOK"],"channel_strategy":{"primary":"email","secondary":"linkedin","tertiary":"phone","avoid":["sms","whatsapp"]},"followup_cadence":{"steps":[{"day":0,"channel":"email"},{"day":5,"channel":"linkedin"},{"day":12,"channel":"email"}],"max_touches":3},"conversion_event":"consultation_booked","average_sales_cycle_days":35,"cta_types":["book_consultation","request_intake_review"],"_assumed":true}'::jsonb ELSE sales_process_config END,
  updated_at = now()
WHERE niche_name = 'legal';

-- ------------------------------------------------------------
-- MOVING SERVICES -- seasonal, capacity-driven, quote-led
-- ------------------------------------------------------------
UPDATE niche_overlays SET
  icp_template = COALESCE(icp_template, '{"geography":"Ontario, Canada","target_role":["owner","operations manager","dispatch manager","sales manager"],"company_size_min":2,"company_size_max":120,"typical_services":["residential moving","commercial relocation","long distance","storage","packing"],"exclude_from_target":["truck rental only","freight brokers","international freight forwarders"],"fleet_size_min":1,"_assumed":true}'::jsonb),
  dashboard_labels = COALESCE(dashboard_labels, '{"leads":"Prospects","contacted":"Companies Contacted","replied":"Responses","meetings":"Estimates Booked","deals":"Jobs in Pipeline","closed_won":"Jobs Booked","deal_value":"Job Value","conversion_rate":"Booking Rate","outreach_sent":"Outreach Sent"}'::jsonb),
  routing_preferences = COALESCE(routing_preferences, '{"search_keywords":["moving company ontario","movers","relocation services","long distance movers"],"exclude_keywords":["truck rental","self storage only","freight forwarder","courier"],"primary_platforms":["google_maps"],"secondary_platforms":["apollo"],"tertiary_platforms":[]}'::jsonb),
  behavior_config = CASE WHEN behavior_config = '{}'::jsonb THEN '{"signal_types":["fleet_expansion","hiring_movers","new_service_area","seasonal_peak_approaching","storage_added","review_volume_growth"],"signal_weights":{"fleet_expansion":26,"new_service_area":24,"hiring_movers":20,"seasonal_peak_approaching":18,"storage_added":8,"review_volume_growth":4},"intent_rules":{"hot":"fleet expansion or new service area within 30 days","warm":"approaching seasonal peak (Apr-Sep)","cold":"off-season with no expansion signal"},"qualification_rules":["Residential, commercial, or both?","Trucks and crews available","How are quotes produced today — phone, form, or on site?"],"objection_handling":{"seasonal_business":"Off-season is exactly when pipeline should be built.","already_booked_out":"Target job value and route density, not volume.","leads_are_junk":"Qualification happens before contact, not after."},"terminology":{"lead":"prospect","deal":"job","meeting":"estimate","quote":"estimate","customer":"customer","worker":"crew"},"message_length":"short","seasonality":{"peak_months":[4,5,6,7,8,9],"low_months":[12,1,2]}}'::jsonb ELSE behavior_config END,
  sales_process_config = CASE WHEN sales_process_config = '{}'::jsonb THEN '{"sales_process":["DISCOVER","LOCAL_SIGNAL","QUALIFY","OFFER","OUTREACH","ESTIMATE","FOLLOW_UP","BOOK"],"channel_strategy":{"primary":"email","secondary":"phone","tertiary":"sms","avoid":[]},"followup_cadence":{"steps":[{"day":0,"channel":"email"},{"day":2,"channel":"phone"},{"day":6,"channel":"email"}],"max_touches":3},"conversion_event":"estimate_booked","average_sales_cycle_days":10,"cta_types":["book_estimate","request_quote"],"_assumed":true}'::jsonb ELSE sales_process_config END,
  updated_at = now()
WHERE niche_name = 'moving_services';

-- ------------------------------------------------------------
-- INSURANCE BROKER -- already had ICP/labels/routing; only the two
-- new config fields are added, matching its existing consultative,
-- compliance-first posture.
-- ------------------------------------------------------------
UPDATE niche_overlays SET
  behavior_config = CASE WHEN behavior_config = '{}'::jsonb THEN '{"signal_types":["advisor_recruitment","new_brokerage_licensed","book_expansion","producer_hiring","new_carrier_appointment","growth_campaign"],"signal_weights":{"advisor_recruitment":28,"new_brokerage_licensed":25,"book_expansion":20,"producer_hiring":15,"new_carrier_appointment":8,"growth_campaign":4},"intent_rules":{"hot":"advisor recruitment or new licensing within 45 days","warm":"book expansion signals","cold":"no growth signal in 120 days"},"qualification_rules":["Licensed and in good standing (FSRA/LLQP)?","Book size and product mix","Captive or independent — can they use outside lead sources?"],"objection_handling":{"compliance_worry":"Every message is reviewable and CASL-compliant by construction.","have_leads":"Compare cost per placed policy, not per lead.","too_busy":"Lead with qualified appointments, not lead volume."},"terminology":{"lead":"prospect","deal":"policy","meeting":"discovery call","customer":"client","closed_won":"policy written","revenue":"commission"},"message_length":"medium","compliance_sensitivity":"high"}'::jsonb ELSE behavior_config END,
  sales_process_config = CASE WHEN sales_process_config = '{}'::jsonb THEN '{"sales_process":["DISCOVER","VERIFY","RESEARCH","COMPLIANCE_CHECK","OUTREACH","CONSULTATION","FOLLOW_UP","APPOINTMENT"],"channel_strategy":{"primary":"email","secondary":"linkedin","tertiary":"voice","avoid":["whatsapp"]},"followup_cadence":{"steps":[{"day":0,"channel":"email"},{"day":4,"channel":"email"},{"day":10,"channel":"linkedin"},{"day":18,"channel":"voice"}],"max_touches":4},"conversion_event":"appointment_booked","average_sales_cycle_days":30,"cta_types":["book_consultation","request_book_review"],"_assumed":true}'::jsonb ELSE sales_process_config END,
  updated_at = now()
WHERE niche_name = 'insurance_broker';


-- ------------------------------------------------------------
-- Verify (run separately)
-- ------------------------------------------------------------
-- select niche_name, is_active,
--        icp_template is not null        as has_icp,
--        dashboard_labels is not null    as has_labels,
--        routing_preferences is not null as has_routing,
--        behavior_config      <> '{}'::jsonb as has_behavior,
--        sales_process_config <> '{}'::jsonb as has_process
--   from niche_overlays order by niche_name;
--
-- Everything marked "_assumed": true is a working default, not a
-- researched figure. Find them with:
-- select niche_name from niche_overlays
--  where behavior_config::text like '%_assumed%'
--     or sales_process_config::text like '%_assumed%';

-- ---- VERIFY ----
-- Expect 8 rows, every column true except where noted.
SELECT niche_name,
       is_active,
       icp_template            IS NOT NULL   AS has_icp,
       dashboard_labels        IS NOT NULL   AS has_labels,
       routing_preferences     IS NOT NULL   AS has_routing,
       behavior_config      <> '{}'::jsonb   AS has_behavior,
       sales_process_config <> '{}'::jsonb   AS has_process
  FROM niche_overlays
 ORDER BY niche_name;

-- Working assumptions that still need your commercial judgement.
SELECT niche_name AS verticals_with_assumed_values
  FROM niche_overlays
 WHERE behavior_config::text      LIKE '%_assumed%'
    OR sales_process_config::text LIKE '%_assumed%'
 ORDER BY niche_name;
