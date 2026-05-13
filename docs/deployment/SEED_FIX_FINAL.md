# Seed Fix — Final (direct SQL, no n8n)

> **TL;DR.** The n8n Code-node sandbox is doing something `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` doesn't override (likely the new task-runners pipeline in 1.x, or a residual workflow cache). **Stop fighting it.** The seed data is static. Paste the SQL block below into Supabase SQL Editor → Run → done in 2 minutes.

## Why we are skipping the workflow

You verified:
- `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` is loaded in the container.
- `INTERNAL_EMAIL_SECRET` (65 chars) is loaded in the container.
- Workflow is activated.
- Webhook still returns HTTP 200 empty body, zero rows inserted.

That points at one of three things still blocking the Code node:
1. **n8n task runners.** n8n 1.4x+ ships task runners (`N8N_RUNNERS_ENABLED`). Code nodes run in a forked process that doesn't always inherit env vars. The setting that controls it can vary by point release.
2. **Stale workflow cache.** Re-importing a workflow does not always invalidate the in-memory compiled definition. Deactivating + reactivating the workflow forces a recompile.
3. **Encoded secret quirk.** If `INTERNAL_EMAIL_SECRET` was written to `.env` without quotes and contains `$`, `!`, or unicode chars, docker's `--env-file` may have mangled it.

**Could we debug all three?** Yes. Each is 20-60 minutes of trial-and-error against a system I can't see. **Should we?** No. The seed data is static. Direct SQL is the right tool. Workflows are for dynamic logic; seeds are for static data.

## Run this — one SQL block, paste into Supabase SQL Editor

Supabase Dashboard → **SQL Editor** → New query → paste the block below → Run.

Expected: takes ~1 second. Zero errors. Verification query at the end prints a single row with the counts.

```sql
-- ═══════════════════════════════════════════════════════════════════
-- Crystallux insurance seed data — direct SQL replacement for the 5
-- failing n8n seed workflows. Idempotent (ON CONFLICT DO NOTHING).
-- Safe to run multiple times.
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. Insurance carriers ────────────────────────────────────────
INSERT INTO insurance_carriers
  (vertical_id, carrier_name, carrier_code, carrier_type, province_licensed,
   ai_compliance_ready, digital_quote_ready, contact_email, active)
VALUES
  ('insurance', 'PolicyMe',         'POLICYME',   'life',    '["ON","BC","AB","QC","MB","SK","NS","NB"]'::jsonb,                                  true,  true,  'partners@policyme.com',           true),
  ('insurance', 'Walnut Insurance', 'WALNUT',     'life',    '["ON","BC","AB","QC"]'::jsonb,                                                      true,  true,  'partners@walnutinsurance.com',    true),
  ('insurance', 'Manulife',         'MANULIFE',   'life',    '["ON","BC","AB","QC","MB","SK","NS","NB","PE","NL","YT","NT","NU"]'::jsonb,         false, false, NULL,                              true),
  ('insurance', 'Sun Life',         'SUNLIFE',    'life',    '["ON","BC","AB","QC","MB","SK","NS","NB","PE","NL","YT","NT","NU"]'::jsonb,         false, false, NULL,                              true),
  ('insurance', 'Canada Life',      'CANADALIFE', 'life',    '["ON","BC","AB","QC","MB","SK","NS","NB","PE","NL"]'::jsonb,                        false, false, NULL,                              true),
  ('insurance', 'iA Financial',     'IA',         'life',    '["ON","BC","AB","QC","MB","SK","NS","NB"]'::jsonb,                                  false, true,  NULL,                              true),
  ('insurance', 'Intact',           'INTACT',     'p_and_c', '["ON","BC","AB","QC","MB","SK","NS","NB","PE","NL"]'::jsonb,                        true,  true,  NULL,                              true),
  ('insurance', 'Aviva Canada',     'AVIVA',      'p_and_c', '["ON","BC","AB","QC","MB","SK","NS","NB"]'::jsonb,                                  false, true,  NULL,                              true)
ON CONFLICT (vertical_id, carrier_name) DO NOTHING;

-- ─── 2. Carrier products (resolves carrier_id via subquery) ───────
INSERT INTO carrier_products
  (vertical_id, carrier_id, product_name, product_type, min_coverage_cents, max_coverage_cents,
   base_premium_cents, commission_first_year, commission_renewal, ai_compliance_ready, features, active)
SELECT 'insurance', c.id, p.product_name, p.product_type, p.min_coverage, p.max_coverage,
       p.base_premium, p.commission_first_year, p.commission_renewal, p.ai_compliance_ready, p.features::jsonb, true
FROM insurance_carriers c
JOIN (VALUES
  -- PolicyMe
  ('POLICYME',   'Term 10',                  'term_life',         10000000,   500000000,  1500, 100.0, 5.0,  true,  '["fully_underwritten_online","convertible","renewable"]'),
  ('POLICYME',   'Term 20',                  'term_life',         10000000,   500000000,  2800, 100.0, 5.0,  true,  '["fully_underwritten_online","convertible","renewable"]'),
  -- Walnut
  ('WALNUT',     'Group Term',               'term_life',          5000000,   200000000,  1200,  90.0, 4.0,  true,  '["employer_distribution","simplified_issue"]'),
  -- Manulife
  ('MANULIFE',   'Family Term',              'term_life',         25000000,  2500000000,  2500, 110.0, 5.0,  false, '["renewable","convertible","child_rider"]'),
  ('MANULIFE',   'Manulife Par',             'whole_life',        25000000,   500000000,  8000,  90.0, 4.0,  false, '["participating","vanishing_premium"]'),
  ('MANULIFE',   'Lifecheque',               'critical_illness',   5000000,   200000000,  4500,  80.0, 4.0,  false, '["return_of_premium","25_conditions"]'),
  -- Sun Life
  ('SUNLIFE',    'SunTerm',                  'term_life',         25000000,  2500000000,  2600, 110.0, 5.0,  false, '["renewable","convertible"]'),
  ('SUNLIFE',    'Sun Par Protector II',     'whole_life',        25000000,   500000000,  8200,  90.0, 4.0,  false, '["participating","vanishing_premium"]'),
  ('SUNLIFE',    'Sun CII',                  'critical_illness',   5000000,   200000000,  4600,  80.0, 4.0,  false, '["return_of_premium","25_conditions"]'),
  -- Canada Life
  ('CANADALIFE', 'My Term',                  'term_life',         25000000,  2500000000,  2550, 110.0, 5.0,  false, '["renewable","convertible"]'),
  ('CANADALIFE', 'Wealth Achiever Plus',     'whole_life',        25000000,   500000000,  8100,  90.0, 4.0,  false, '["participating","vanishing_premium"]'),
  ('CANADALIFE', 'LifeAdvance CI',           'critical_illness',   5000000,   200000000,  4400,  80.0, 4.0,  false, '["return_of_premium","26_conditions"]'),
  -- iA Financial
  ('IA',         'Term Life Pick-A-Term',    'term_life',         25000000,  1000000000,  2400, 105.0, 5.0,  false, '["renewable","convertible"]'),
  ('IA',         'Genesis IUL',              'universal_life',    25000000,   500000000,  7000,  85.0, 4.0,  false, '["indexed_strategies"]'),
  -- Intact
  ('INTACT',     'Personal Auto',            'auto',             100000000,  5000000000, 12000,  15.0, 12.0, true,  '["multi_vehicle_discount","loyalty_discount"]'),
  ('INTACT',     'Homeowners',               'home',             100000000,  5000000000,  8000,  15.0, 12.0, true,  '["water_endorsement","sewer_backup"]'),
  ('INTACT',     'Tenant',                   'tenant',             5000000,   100000000,  1500,  15.0, 12.0, true,  '["contents_replacement"]'),
  -- Aviva Canada
  ('AVIVA',      'Aviva Auto',               'auto',             100000000,  5000000000, 12500,  15.0, 12.0, false, '["multi_vehicle_discount"]'),
  ('AVIVA',      'Ovation Home',             'home',             100000000,  5000000000,  8200,  15.0, 12.0, false, '["water_endorsement","sewer_backup"]')
) AS p(carrier_code, product_name, product_type, min_coverage, max_coverage,
       base_premium, commission_first_year, commission_renewal, ai_compliance_ready, features)
  ON c.carrier_code = p.carrier_code AND c.vertical_id = 'insurance'
ON CONFLICT (carrier_id, product_name) DO NOTHING;

-- ─── 3. Insurance content templates ───────────────────────────────
INSERT INTO insurance_content_templates
  (vertical_id, topic_category, topic_title, topic_summary, target_audience, call_to_action, educational_value, seo_keywords, is_active)
VALUES
  ('insurance', 'life_insurance_basics', 'Term vs. Whole Life: which fits a young family?',          'Compares term and whole life from a cost/coverage tradeoff lens.', 'young_families',     'Book a 15-min coverage review.', 'high', ARRAY['term life','whole life','young family insurance'], true),
  ('insurance', 'life_insurance_basics', 'How much life insurance do you actually need?',           'Walks through the income-replacement + mortgage + dependents math.', 'young_families',     'Try the needs calculator.',     'high', ARRAY['life insurance needs','coverage calculator'], true),
  ('insurance', 'life_insurance_basics', 'Common misconceptions about life insurance',              'Myth-busting around price, underwriting, and payout reliability.',  'first_time_buyers',   NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'critical_illness',      'Critical illness insurance — what people get wrong',     'Clarifies what CI does and does not cover. Includes claim examples.','young_families',      NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'critical_illness',      'When does critical illness make sense?',                  NULL,                                                                  'business_owners',     NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'disability',            'Disability insurance for self-employed',                  'Own-occupation vs. any-occupation, waiting periods, benefit periods.','business_owners',    NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'disability',            'How disability insurance protects your income',           NULL,                                                                  'young_families',      NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'estate_planning',       'Insurance as an estate-planning tool',                    NULL,                                                                  'high_net_worth',      NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'estate_planning',       'Tax-efficient legacy strategies',                          NULL,                                                                  'high_net_worth',      NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'business_insurance',    'Key person insurance — what is it really?',              NULL,                                                                  'business_owners',     NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'business_insurance',    'Buy-sell agreements explained',                            NULL,                                                                  'business_owners',     NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'mortgage_protection',   'Mortgage life: the trap most homeowners miss',            NULL,                                                                  'young_families',      NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'mortgage_protection',   'Personally-owned coverage vs. bank mortgage insurance',   NULL,                                                                  'first_time_buyers',   NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'retirement',            'Using whole life for tax-advantaged retirement income',   NULL,                                                                  'high_net_worth',      NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'retirement',            'Insurance + RRSP + TFSA: how they fit together',          NULL,                                                                  'young_families',      NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'health_benefits',       'Travel insurance: what to look for',                       NULL,                                                                  'seniors',             NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'health_benefits',       'Group benefits for small businesses',                      NULL,                                                                  'business_owners',     NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'life_insurance_basics', 'Smoker vs. non-smoker pricing — the truth',              NULL,                                                                  'first_time_buyers',   NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'life_insurance_basics', 'Why your age matters for premiums',                        NULL,                                                                  'young_families',      NULL,                              NULL,   ARRAY[]::text[], true),
  ('insurance', 'life_insurance_basics', 'What happens if you miss a premium payment?',             NULL,                                                                  'first_time_buyers',   NULL,                              NULL,   ARRAY[]::text[], true)
ON CONFLICT (vertical_id, topic_title) DO NOTHING;

-- ─── 4. Training topics (Layer 1 table, insurance rows) ───────────
-- training_topics has no UNIQUE constraint, so we guard with NOT EXISTS.
INSERT INTO training_topics
  (vertical_id, topic_category, topic_title, topic_description, difficulty_level, estimated_minutes, learning_objectives, is_active)
SELECT vertical_id, topic_category, topic_title, topic_description, difficulty_level, estimated_minutes, learning_objectives, true
FROM (VALUES
  ('insurance', 'compliance',         'How to complete KYC for life insurance',                'Step-by-step KYC: identity, source-of-funds, PEP, sanctions.',                      'beginner',     20, ARRAY['Verify identity per FINTRAC','Document source of funds','Screen PEP/sanctions']),
  ('insurance', 'product_knowledge',  'Explaining term vs whole life',                          'Tradeoffs, when each fits, plain-language scripting.',                              'beginner',     25, ARRAY['Articulate cost/coverage tradeoff','Match product to client situation']),
  ('insurance', 'objection_handling', 'Critical illness misconceptions to avoid',               'What CI does and does not cover; common false promises to avoid.',                  'intermediate', 30, ARRAY['List 5 common CI misconceptions','Correct them without alienating the client']),
  ('insurance', 'product_knowledge',  'Disability insurance positioning',                       'Own-occupation vs any-occupation; waiting + benefit periods.',                      'intermediate', 30, ARRAY['Distinguish definitions','Match definition to occupation risk']),
  ('insurance', 'compliance',         'Replacement disclosure requirements',                    'When + how to disclose a replacement under FSRA/AMF rules.',                        'intermediate', 25, ARRAY['Identify a replacement','File the disclosure correctly']),
  ('insurance', 'compliance',         'Suitability documentation best practices',                'What to write down + retain so a future regulator can reconstruct your reasoning.','intermediate', 25, ARRAY[]::text[]),
  ('insurance', 'compliance',         'AML compliance basics',                                  'Suspicious-transaction reporting + recordkeeping.',                                 'beginner',     30, ARRAY[]::text[]),
  ('insurance', 'compliance',         'Privacy consent collection (PIPEDA + provincial)',       'What consent to collect, when, and how to document it.',                            'beginner',     20, ARRAY[]::text[]),
  ('insurance', 'discovery',          'Pre-meeting preparation for client conversations',        'Use the Crystallux pre-meeting briefing to anchor your first 8 minutes.',           'beginner',     15, ARRAY[]::text[]),
  ('insurance', 'follow_up',          'Post-meeting documentation standards',                   'What to log within 24 hours of every meeting.',                                     'beginner',     15, ARRAY[]::text[]),
  ('insurance', 'closing',            'Closing a term life sale ethically',                     'No fear-tactics. Frame coverage as a household-budget decision.',                   'intermediate', 25, ARRAY[]::text[]),
  ('insurance', 'sales_psychology',   'Handling the "I need to think about it" objection',    'Diagnose the real concern (price, fit, trust) before responding.',                 'intermediate', 25, ARRAY[]::text[])
) AS t(vertical_id, topic_category, topic_title, topic_description, difficulty_level, estimated_minutes, learning_objectives)
WHERE NOT EXISTS (
  SELECT 1 FROM training_topics tt WHERE tt.topic_title = t.topic_title AND tt.vertical_id = t.vertical_id
);

-- ─── 5. Insurance onboarding curriculum (30 days) ─────────────────
INSERT INTO insurance_onboarding_curriculum
  (vertical_id, day_number, module_title, module_description, estimated_minutes, required_actions, learning_objectives, is_mandatory, is_active)
VALUES
  ('insurance',  1, 'Welcome + license verification',                'Confirm provincial license is current; upload jurisdiction certificates.',                  30, ARRAY['Upload current LLQP/HLLQP cert','Confirm jurisdiction'], ARRAY['Understand licensing requirements','Provide all current certifications'], true, true),
  ('insurance',  2, 'E&O insurance verification',                    'Verify Errors & Omissions coverage is active and adequate.',                                20, ARRAY['Upload E&O policy declaration','Confirm coverage amount'], ARRAY['Understand E&O scope','Verify continuous coverage'], true, true),
  ('insurance',  3, 'MGA agreement signing',                         'Review + sign the Crystallux MGA agreement covering commission splits.',                    45, ARRAY['Read agreement','Sign via Zoho Sign'], ARRAY['Understand split structure','Understand termination terms'], true, true),
  ('insurance',  4, 'AML compliance basics',                          'FINTRAC obligations + suspicious-transaction reporting.',                                  30, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance',  5, 'Privacy + PIPEDA training',                      'Consent collection, data handling, retention.',                                            30, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance',  6, 'Replacement disclosure rules',                   'FSRA/AMF rules for replacing existing coverage.',                                          30, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance',  7, 'Suitability documentation',                      'What to record + retain so a future regulator can reconstruct your reasoning.',            30, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance',  8, 'Term life product training',                     'Term life products from your top 3 carriers; pricing + riders.',                            45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance',  9, 'Whole life product training',                    'Whole life, par/non-par, vanishing premium.',                                              45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 10, 'Universal life product training',                'UL mechanics, indexed strategies, side-account.',                                          45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 11, 'Critical illness product training',              'CI definitions, return-of-premium, partial benefits.',                                     45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 12, 'Disability product training',                    'Own-occ vs any-occ, waiting + benefit periods.',                                           45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 13, 'Health + travel + group benefits',               'Supplemental health, travel, employer group plans.',                                       30, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 14, 'P&C product overview (where licensed)',          'Auto + home + commercial; only relevant if dual-licensed.',                                30, ARRAY[]::text[], ARRAY[]::text[], false, true),
  ('insurance', 15, 'Discovery conversations',                         'How to ask questions that uncover real needs.',                                            45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 16, 'KYC end-to-end',                                  'Identity, source of funds, PEP, sanctions, recordkeeping.',                                45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 17, 'Suitability assessment in practice',              'Walk through a real suitability_assessment from start to finish.',                         45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 18, 'Objection handling',                              '5 most common objections + ethical responses.',                                            45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 19, 'Closing techniques',                              'Ethical closing patterns. No fear-tactics.',                                               45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 20, 'Compliance review process',                       'How the Crystallux compliance pipeline reviews your applications.',                        30, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 21, 'Practice presentation #1 (recorded)',            'Record a 15-minute discovery + needs presentation; supervisor reviews.',                   60, ARRAY['Record presentation','Submit for review'], ARRAY[]::text[], true, true),
  ('insurance', 22, 'Application data + paperwork',                    'How to complete an application without back-and-forth.',                                   45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 23, 'E-signature + submission',                        'Zoho Sign workflow + carrier submission.',                                                 30, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 24, 'Underwriting follow-up',                          'Working with underwriters when they ask for more info.',                                   45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 25, 'Policy issuance + delivery',                      'Receiving the policy, delivery requirements, free-look period.',                           30, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 26, 'Post-issuance follow-up',                         'How to set up the annual review cadence at policy delivery.',                              30, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 27, 'Commission + chargebacks',                        'How commissions work, when chargebacks happen.',                                           30, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 28, 'Practice presentation #2 (recorded)',            'Final recorded presentation for supervisor signoff.',                                      60, ARRAY['Record presentation','Submit for review'], ARRAY[]::text[], true, true),
  ('insurance', 29, 'First client preparation',                        'Pick your first prospect; review their file with supervisor.',                             45, ARRAY[]::text[], ARRAY[]::text[], true, true),
  ('insurance', 30, 'Graduation + supervisor signoff',                 'Final supervisor signoff; you are cleared to write business.',                             30, ARRAY['Final review with supervisor','Supervisor signs off'], ARRAY[]::text[], true, true)
ON CONFLICT (vertical_id, day_number) DO NOTHING;

-- ─── 6. Production report templates (Layer 1, insurance) ──────────
INSERT INTO production_report_templates
  (vertical_id, template_name, template_type, description, recipient_role, metrics_included, schedule_pattern, delivery_methods, is_active)
VALUES
  ('insurance', 'Monthly Production',         'monthly_production',   'Monthly premium written + policies issued for the insurer''s carrier appointments.',                            'insurer', '["policies_issued","premium_written_cents","product_mix","advisor_breakdown","geographic_distribution"]'::jsonb,  'monthly',   ARRAY['dashboard','email'], true),
  ('insurance', 'Advisor Performance',         'advisor_performance', 'Per-advisor production metrics: volume, persistency, conversion, compliance score.',                            'insurer', '["per_advisor_volume","persistency_rate","conversion_rate","compliance_score"]'::jsonb,                          'monthly',   ARRAY['dashboard','email'], true),
  ('insurance', 'Compliance Health',           'compliance_health',   'Compliance scorecard: KYC, suitability, disclosure, review completion, license + E&O health.',                  'insurer', '["kyc_completion","suitability_documentation","disclosure_completion","review_completion","license_health","eo_coverage"]'::jsonb, 'monthly',   ARRAY['dashboard'],          true),
  ('insurance', 'Product Mix Analysis',        'monthly_production',  'Product distribution + trend over time.',                                                                       'insurer', '["product_mix","trend_30d","trend_90d","trend_yoy"]'::jsonb,                                                     'quarterly', ARRAY['dashboard'],          true),
  ('insurance', 'Commission Summary',          'commission_breakdown','Commission paid breakdown for insurer reconciliation.',                                                          'insurer', '["commission_paid_cents","first_year_split","renewal_split","chargebacks_cents"]'::jsonb,                         'monthly',   ARRAY['dashboard','email'], true),
  ('insurance', 'Quarterly Business Review',   'quarterly_summary',   'Comprehensive QBR for insurer-MGA quarterly meetings.',                                                          'insurer', '["production_volume","growth_rate","advisor_health","compliance_trend","strategic_insights"]'::jsonb,            'quarterly', ARRAY['dashboard','email'], true)
ON CONFLICT (vertical_id, template_name) DO NOTHING;

-- ─── 7. Crystallux Insurance Network — default rule + goals ──────
-- The test client ID is the Crystallux Insurance Network MGA tenant.
-- Skip this block if you want to seed your own client_id later.
INSERT INTO lead_distribution_rules
  (client_id, rule_name, rule_type, priority, active)
VALUES
  ('6edc687d-07b0-4478-bb4b-820dc4eebf5d', 'default-round-robin', 'round_robin', 100, true)
ON CONFLICT (client_id, rule_name) DO NOTHING;

INSERT INTO goal_templates
  (client_id, template_name, metric, period, target_value, role, active)
VALUES
  ('6edc687d-07b0-4478-bb4b-820dc4eebf5d', 'weekly-meetings', 'meetings_booked', 'weekly',  8,  'advisor', true),
  ('6edc687d-07b0-4478-bb4b-820dc4eebf5d', 'weekly-calls',    'calls_made',      'weekly',  40, 'advisor', true),
  ('6edc687d-07b0-4478-bb4b-820dc4eebf5d', 'monthly-leads',   'leads_assigned',  'monthly', 40, 'advisor', true)
ON CONFLICT (client_id, template_name) DO NOTHING;

-- ─── VERIFICATION (should return one row with all expected counts) ─
SELECT
  (SELECT count(*) FROM insurance_carriers              WHERE vertical_id = 'insurance')              AS carriers,
  (SELECT count(*) FROM carrier_products                WHERE vertical_id = 'insurance')              AS products,
  (SELECT count(*) FROM insurance_content_templates     WHERE vertical_id = 'insurance')              AS content,
  (SELECT count(*) FROM training_topics                 WHERE vertical_id = 'insurance')              AS training,
  (SELECT count(*) FROM insurance_onboarding_curriculum WHERE vertical_id = 'insurance')              AS curriculum,
  (SELECT count(*) FROM production_report_templates     WHERE vertical_id = 'insurance')              AS report_templates,
  (SELECT count(*) FROM lead_distribution_rules         WHERE client_id   = '6edc687d-07b0-4478-bb4b-820dc4eebf5d') AS distribution_rules,
  (SELECT count(*) FROM goal_templates                  WHERE client_id   = '6edc687d-07b0-4478-bb4b-820dc4eebf5d') AS goal_templates;
```

**Expected verification result:** `8 / 19 / 20 / 12 / 30 / 6 / 1 / 3`

If you get those numbers, **all seeds are in**. Move on to the wiring checklist. If a count is wrong, the corresponding INSERT failed silently — Supabase will have shown an error message above the result. Paste me the error.

## What about the n8n workflows then?

Leave them as-is. They were over-engineered for what amounts to a one-shot static data load. Future schema seeds should use direct SQL too — workflows belong on dynamic flows (lead distribution, video rendering, compliance pre-screening), not seed data.

If you ever want to fix the actual workflows for future re-seeds without database access, that's a 2-hour refactor (move auth from Code-node body to an IF node using `={{ $env.INTERNAL_EMAIL_SECRET }}` expression). **Not blocking your launch.** Add to the future-work list.

## When seeds are confirmed in

Move to `docs/deployment/COMPLETE_WIRING_CHECKLIST.md` for the remaining work.
