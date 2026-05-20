-- ══════════════════════════════════════════════════════════════════
-- Smart Quote — additional industry templates
-- ══════════════════════════════════════════════════════════════════
-- Companion to smart-quote-schema.sql. Seeds 6 more industries so the
-- Estimator page shows a real grid (not just the single Insurance card).
-- Mary refines the questions / pricing rules / addons via the
-- admin Smart Quote → Estimator UI in a later commit (or directly in
-- SQL today). Defaults are sensible starting points; not gospel.
--
-- Industries:
--   construction      🏗️
--   dental            🦷
--   cleaning          🧽
--   restaurants       🍽️
--   moving            📦
--   beauty            💅
--
-- Each gets:
--   - 5-6 questions (number / select inputs)
--   - 3-5 pricing rules (team size / volume / complexity)
--   - 3-5 addons (AI video / voice / quote PDFs / industry-specific extras)
--
-- All IDs use a stable vanity-UUID prefix `00000000-1111-4001-a000-XXX`
-- so reapplying the migration is safe (ON CONFLICT DO NOTHING).
-- ══════════════════════════════════════════════════════════════════

-- ─── 1. Construction ─────────────────────────────────────────────
INSERT INTO quote_templates (id, industry_slug, industry_name, vertical_id, description, emoji, questions, pricing_basis, base_starter_cents, base_growth_cents, base_scale_cents, sort_order) VALUES (
  '00000000-1111-4001-a000-000000000002',
  'construction',
  'Construction',
  NULL,
  'General contractors, custom builders, and trades scaling beyond word-of-mouth lead flow. Estimate platform cost based on project pipeline + crew size.',
  '🏗️',
  $q$[
    { "id": "crew_size",         "label": "How many people on your crew (including subs)?", "type": "number", "required": true, "weight": 2 },
    { "id": "projects_per_year", "label": "How many projects do you complete per year?",     "type": "number", "required": true, "weight": 2 },
    { "id": "avg_project_value", "label": "Average project value (CAD)?",                    "type": "currency", "required": true, "weight": 2, "help": "Used for ROI estimates only — not stored as PII." },
    { "id": "project_types",     "label": "What kind of work do you mostly do?",            "type": "select", "options": ["Residential renovation","New residential build","Commercial fit-out","Industrial","Mixed"], "required": true, "weight": 1 },
    { "id": "lead_source",       "label": "Where do most leads come from today?",            "type": "select", "options": ["Word of mouth","HomeStars / online reviews","Google Ads","Referrals from designers","Past clients","Trade shows","Other"], "required": true, "weight": 1 }
  ]$q$::jsonb,
  'tiered', 19900, 49900, 99900, 20
)
ON CONFLICT (industry_slug) DO NOTHING;

INSERT INTO quote_pricing_rules (template_id, rule_name, conditions, adjust_cents, adjust_percent, description, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000002', 'Small crew (1-5)',   '{"crew_size":{"op":"lte","value":5}}'::jsonb,                       0,    0.0, 'Stays on starter tier',           10),
  ('00000000-1111-4001-a000-000000000002', 'Medium crew (6-20)', '{"crew_size":{"op":"between","value":[6,20]}}'::jsonb,           30000, 0.0, 'Bigger pipeline + estimator load', 20),
  ('00000000-1111-4001-a000-000000000002', 'Large crew (20+)',   '{"crew_size":{"op":"gte","value":21}}'::jsonb,                   80000, 0.0, 'Scale tier features',              30),
  ('00000000-1111-4001-a000-000000000002', 'High project value', '{"avg_project_value":{"op":"gte","value":50000000}}'::jsonb,     20000, 0.0, 'Commercial / >$500k projects',     40),
  ('00000000-1111-4001-a000-000000000002', 'Heavy ad-driven',    '{"lead_source":{"op":"eq","value":"Google Ads"}}'::jsonb,        15000, 0.0, 'Ad-spend integration + ROI tracking', 50)
ON CONFLICT DO NOTHING;

INSERT INTO quote_addons (template_id, addon_slug, addon_name, description, monthly_cents, one_time_cents, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000002', 'ai_video',           'AI personalized video',       'HeyGen-rendered intro to each prospect',                15000, 0,      10),
  ('00000000-1111-4001-a000-000000000002', 'voice_outbound',     'Outbound AI voice',           'Vapi-based outbound calling',                           19900, 0,      20),
  ('00000000-1111-4001-a000-000000000002', 'estimate_builder',   'AI estimate builder',         'Generate project estimates from photos + spec',         24900, 0,      30),
  ('00000000-1111-4001-a000-000000000002', 'pdf_quote_gen',      'Branded quote PDFs',          'Auto-generate quote PDFs and email to prospects',        6900, 0,      40),
  ('00000000-1111-4001-a000-000000000002', 'job_site_signage',   'Job-site signage QR codes',   'QR-coded yard signs that capture nearby leads',          0,   29900,  50)
ON CONFLICT DO NOTHING;

-- ─── 2. Dental ───────────────────────────────────────────────────
INSERT INTO quote_templates (id, industry_slug, industry_name, vertical_id, description, emoji, questions, pricing_basis, base_starter_cents, base_growth_cents, base_scale_cents, sort_order) VALUES (
  '00000000-1111-4001-a000-000000000003',
  'dental',
  'Dental',
  NULL,
  'Independent dental practices and small group offices. Patient-acquisition automation + recall reactivation + insurance verification.',
  '🦷',
  $q$[
    { "id": "operatories",       "label": "How many operatories?",                              "type": "number", "required": true, "weight": 2 },
    { "id": "dentists",          "label": "How many dentists in the practice?",                "type": "number", "required": true, "weight": 2 },
    { "id": "monthly_new_patients", "label": "New patients per month (current average)?",       "type": "number", "required": true, "weight": 2 },
    { "id": "patient_recall",    "label": "Recall system today?",                              "type": "select", "options": ["Manual phone calls","Email reminders","Patient management software auto-reminders","None"], "required": true, "weight": 1 },
    { "id": "specialty_focus",   "label": "Any specialty focus?",                              "type": "select", "options": ["General + family","Cosmetic / Invisalign","Implants","Periodontics","Orthodontics","Pediatric"], "required": true, "weight": 1 }
  ]$q$::jsonb,
  'tiered', 14900, 39900, 79900, 30
)
ON CONFLICT (industry_slug) DO NOTHING;

INSERT INTO quote_pricing_rules (template_id, rule_name, conditions, adjust_cents, adjust_percent, description, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000003', 'Solo dentist',        '{"dentists":{"op":"lte","value":1}}'::jsonb,            0,     0.0, 'Single-dentist starter',          10),
  ('00000000-1111-4001-a000-000000000003', 'Small group (2-4)',   '{"dentists":{"op":"between","value":[2,4]}}'::jsonb,    25000, 0.0, 'Multi-dentist coordination',      20),
  ('00000000-1111-4001-a000-000000000003', 'High patient flow',   '{"monthly_new_patients":{"op":"gte","value":50}}'::jsonb, 20000, 0.0, 'High-volume tier',                30),
  ('00000000-1111-4001-a000-000000000003', 'Cosmetic focus',      '{"specialty_focus":{"op":"in","value":["Cosmetic / Invisalign","Implants"]}}'::jsonb, 15000, 0.0, 'High-LTV vertical', 40)
ON CONFLICT DO NOTHING;

INSERT INTO quote_addons (template_id, addon_slug, addon_name, description, monthly_cents, one_time_cents, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000003', 'ai_video',         'AI personalized video',       'HeyGen-rendered patient greeting',                  15000, 0,     10),
  ('00000000-1111-4001-a000-000000000003', 'recall_engine',    'Patient recall engine',       'Auto-recall lapsed patients via SMS + email',       19900, 0,     20),
  ('00000000-1111-4001-a000-000000000003', 'review_automation','Google review automation',    'Post-visit review requests + reputation monitoring', 9900, 0,    30),
  ('00000000-1111-4001-a000-000000000003', 'pms_integration',  'PMS sync (Dentrix / Open Dental)','Bidirectional patient data sync',                    14900, 49900, 40)
ON CONFLICT DO NOTHING;

-- ─── 3. Cleaning services ────────────────────────────────────────
INSERT INTO quote_templates (id, industry_slug, industry_name, vertical_id, description, emoji, questions, pricing_basis, base_starter_cents, base_growth_cents, base_scale_cents, sort_order) VALUES (
  '00000000-1111-4001-a000-000000000004',
  'cleaning',
  'Cleaning Services',
  NULL,
  'Residential + commercial cleaning companies. Auto-booking + recurring schedule management + crew dispatch.',
  '🧽',
  $q$[
    { "id": "crew_size",       "label": "How many cleaners on your team?",       "type": "number", "required": true, "weight": 2 },
    { "id": "jobs_per_week",   "label": "How many cleaning jobs per week?",      "type": "number", "required": true, "weight": 2 },
    { "id": "service_mix",     "label": "What kind of cleaning do you do?",     "type": "select", "options": ["Residential only","Commercial only","Both","Post-construction","Move-in / move-out"], "required": true, "weight": 1 },
    { "id": "booking_today",   "label": "How do you book jobs today?",          "type": "select", "options": ["Phone calls","Form on website","Booking software","Mix"], "required": true, "weight": 1 },
    { "id": "recurring_share", "label": "What % of jobs are recurring?",        "type": "select", "options": ["Under 25%","25-50%","50-75%","Over 75%"], "required": true, "weight": 1 }
  ]$q$::jsonb,
  'tiered', 9900, 24900, 49900, 40
)
ON CONFLICT (industry_slug) DO NOTHING;

INSERT INTO quote_pricing_rules (template_id, rule_name, conditions, adjust_cents, adjust_percent, description, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000004', 'Small team (1-3)',   '{"crew_size":{"op":"lte","value":3}}'::jsonb,             0,    0.0, 'Solo + small starter',          10),
  ('00000000-1111-4001-a000-000000000004', 'Medium team (4-10)', '{"crew_size":{"op":"between","value":[4,10]}}'::jsonb,    15000, 0.0, 'Dispatch + scheduling needs',   20),
  ('00000000-1111-4001-a000-000000000004', 'High volume (50+/wk)','{"jobs_per_week":{"op":"gte","value":50}}'::jsonb,        20000, 0.0, 'Volume routing surcharge',      30),
  ('00000000-1111-4001-a000-000000000004', 'Commercial focus',   '{"service_mix":{"op":"eq","value":"Commercial only"}}'::jsonb, 10000, 0.0, 'B2B procurement features',     40)
ON CONFLICT DO NOTHING;

INSERT INTO quote_addons (template_id, addon_slug, addon_name, description, monthly_cents, one_time_cents, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000004', 'instant_quote',    'Instant online quoting',       'Customers see price + book on your site',           7900, 0,     10),
  ('00000000-1111-4001-a000-000000000004', 'route_optimizer',  'Crew route optimizer',         'Daily dispatch routes + drive-time minimization',  12900, 0,     20),
  ('00000000-1111-4001-a000-000000000004', 'recurring_billing','Recurring billing + auto-charge','Stripe subscriptions for recurring clients',       9900, 0,     30),
  ('00000000-1111-4001-a000-000000000004', 'review_automation','Review automation',            'Post-clean review requests',                        6900, 0,     40)
ON CONFLICT DO NOTHING;

-- ─── 4. Restaurants ──────────────────────────────────────────────
INSERT INTO quote_templates (id, industry_slug, industry_name, vertical_id, description, emoji, questions, pricing_basis, base_starter_cents, base_growth_cents, base_scale_cents, sort_order) VALUES (
  '00000000-1111-4001-a000-000000000005',
  'restaurants',
  'Restaurants',
  NULL,
  'Independent restaurants, cafés, and small chains. Reservation marketing + reactivation campaigns + review automation.',
  '🍽️',
  $q$[
    { "id": "seat_count",         "label": "How many seats?",                                "type": "number", "required": true, "weight": 2 },
    { "id": "locations",          "label": "How many locations?",                            "type": "number", "required": true, "weight": 2 },
    { "id": "restaurant_type",    "label": "What kind of restaurant?",                       "type": "select", "options": ["Fine dining","Casual dining","Quick service","Café / coffee","Bar / pub","Food truck"], "required": true, "weight": 1 },
    { "id": "current_reservations","label": "Reservations system today?",                    "type": "select", "options": ["OpenTable","Tock","Resy","Phone only","Walk-in only"], "required": true, "weight": 1 },
    { "id": "loyalty_program",    "label": "Loyalty / repeat-customer program?",             "type": "select", "options": ["None","Punch cards","App-based","Email list"], "required": true, "weight": 1 }
  ]$q$::jsonb,
  'tiered', 12900, 29900, 59900, 50
)
ON CONFLICT (industry_slug) DO NOTHING;

INSERT INTO quote_pricing_rules (template_id, rule_name, conditions, adjust_cents, adjust_percent, description, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000005', 'Single location',       '{"locations":{"op":"lte","value":1}}'::jsonb,           0,    0.0, 'Independent starter',                10),
  ('00000000-1111-4001-a000-000000000005', 'Small chain (2-5)',     '{"locations":{"op":"between","value":[2,5]}}'::jsonb, 20000, 0.0, 'Multi-location coordination',        20),
  ('00000000-1111-4001-a000-000000000005', 'Larger chain (5+)',     '{"locations":{"op":"gt","value":5}}'::jsonb,          50000, 0.0, 'Scale tier — central marketing',     30),
  ('00000000-1111-4001-a000-000000000005', 'High seat count (100+)','{"seat_count":{"op":"gte","value":100}}'::jsonb,      10000, 0.0, 'Higher-volume reservation load',     40)
ON CONFLICT DO NOTHING;

INSERT INTO quote_addons (template_id, addon_slug, addon_name, description, monthly_cents, one_time_cents, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000005', 'reservation_marketing','Reservation marketing',       'Last-minute table promotions to past guests',       12900, 0,    10),
  ('00000000-1111-4001-a000-000000000005', 'review_automation',    'Review automation',           'Post-meal review requests via SMS',                  7900, 0,    20),
  ('00000000-1111-4001-a000-000000000005', 'loyalty_engine',       'Loyalty engine',              'Auto-rewards + birthday + lapsed-guest offers',     11900, 0,    30),
  ('00000000-1111-4001-a000-000000000005', 'menu_qr_landing',      'QR menu + landing page',      'Per-table QR codes + branded mobile menu',           4900, 14900, 40)
ON CONFLICT DO NOTHING;

-- ─── 5. Moving services ──────────────────────────────────────────
INSERT INTO quote_templates (id, industry_slug, industry_name, vertical_id, description, emoji, questions, pricing_basis, base_starter_cents, base_growth_cents, base_scale_cents, sort_order) VALUES (
  '00000000-1111-4001-a000-000000000006',
  'moving',
  'Moving Services',
  'moving',
  'Local + long-distance moving companies. Lead capture + quote-to-book flow + crew dispatch.',
  '📦',
  $q$[
    { "id": "trucks",            "label": "How many trucks in your fleet?",                "type": "number", "required": true, "weight": 2 },
    { "id": "moves_per_week",    "label": "Average moves per week?",                       "type": "number", "required": true, "weight": 2 },
    { "id": "service_radius",    "label": "Service area?",                                 "type": "select", "options": ["Local (single city)","Regional","Cross-province","Cross-border / international"], "required": true, "weight": 1 },
    { "id": "moves_type",        "label": "What kind of moves?",                          "type": "select", "options": ["Residential only","Commercial only","Both","Specialized (pianos / fine art / etc.)"], "required": true, "weight": 1 },
    { "id": "quote_method",      "label": "How do you give quotes today?",                "type": "select", "options": ["In-home estimate","Phone estimate","Online form","Mix"], "required": true, "weight": 1 }
  ]$q$::jsonb,
  'tiered', 14900, 34900, 69900, 60
)
ON CONFLICT (industry_slug) DO NOTHING;

INSERT INTO quote_pricing_rules (template_id, rule_name, conditions, adjust_cents, adjust_percent, description, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000006', 'Small fleet (1-3)',     '{"trucks":{"op":"lte","value":3}}'::jsonb,                       0, 0.0, 'Small operator starter',         10),
  ('00000000-1111-4001-a000-000000000006', 'Mid fleet (4-10)',      '{"trucks":{"op":"between","value":[4,10]}}'::jsonb,           20000, 0.0, 'Dispatch + multi-crew coordination', 20),
  ('00000000-1111-4001-a000-000000000006', 'High volume (30+/wk)',  '{"moves_per_week":{"op":"gte","value":30}}'::jsonb,           15000, 0.0, 'Volume tier',                    30),
  ('00000000-1111-4001-a000-000000000006', 'Long-distance focus',   '{"service_radius":{"op":"in","value":["Cross-province","Cross-border / international"]}}'::jsonb, 10000, 0.0, 'Long-haul logistics features', 40)
ON CONFLICT DO NOTHING;

INSERT INTO quote_addons (template_id, addon_slug, addon_name, description, monthly_cents, one_time_cents, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000006', 'instant_quote',   'Instant online quote',   'Live calculator on your site — book in one flow', 9900,  0,     10),
  ('00000000-1111-4001-a000-000000000006', 'video_intake',    'Video pre-move intake',  'Customer video-tours their home; AI estimates volume', 14900, 0,    20),
  ('00000000-1111-4001-a000-000000000006', 'route_optimizer', 'Crew dispatch + routes', 'Daily routing minimizes drive time',                12900, 0,     30),
  ('00000000-1111-4001-a000-000000000006', 'review_automation','Review automation',     'Post-move review requests',                          6900, 0,     40)
ON CONFLICT DO NOTHING;

-- ─── 6. Beauty / wellness ────────────────────────────────────────
INSERT INTO quote_templates (id, industry_slug, industry_name, vertical_id, description, emoji, questions, pricing_basis, base_starter_cents, base_growth_cents, base_scale_cents, sort_order) VALUES (
  '00000000-1111-4001-a000-000000000007',
  'beauty',
  'Beauty & Wellness',
  NULL,
  'Salons, spas, med-spas, barber shops. Booking automation + client retention + reactivation.',
  '💅',
  $q$[
    { "id": "stations",        "label": "How many stations / chairs / treatment rooms?",   "type": "number", "required": true, "weight": 2 },
    { "id": "stylists",        "label": "How many stylists / techs (including yourself)?","type": "number", "required": true, "weight": 2 },
    { "id": "service_focus",   "label": "Primary service focus?",                          "type": "select", "options": ["Hair salon","Barber shop","Nails","Esthetics / facials","Massage","Med-spa (botox / lasers)","Multi-service"], "required": true, "weight": 1 },
    { "id": "booking_today",   "label": "Booking system today?",                           "type": "select", "options": ["Phone calls","Booking software (Mindbody / Vagaro / etc.)","Instagram DMs","Walk-in"], "required": true, "weight": 1 },
    { "id": "retail_sales",    "label": "Sell retail products?",                           "type": "select", "options": ["No","Some — under 10% of revenue","Significant — 10-30%","Major — over 30%"], "required": true, "weight": 1 }
  ]$q$::jsonb,
  'tiered', 9900, 22900, 44900, 70
)
ON CONFLICT (industry_slug) DO NOTHING;

INSERT INTO quote_pricing_rules (template_id, rule_name, conditions, adjust_cents, adjust_percent, description, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000007', 'Solo operator',    '{"stylists":{"op":"lte","value":1}}'::jsonb,         0,    0.0, 'Single-stylist starter',          10),
  ('00000000-1111-4001-a000-000000000007', 'Small team (2-5)', '{"stylists":{"op":"between","value":[2,5]}}'::jsonb, 13000, 0.0, 'Multi-stylist scheduling',        20),
  ('00000000-1111-4001-a000-000000000007', 'Larger team (6+)', '{"stylists":{"op":"gte","value":6}}'::jsonb,         30000, 0.0, 'Salon / spa coordination tier',   30),
  ('00000000-1111-4001-a000-000000000007', 'Med-spa premium',  '{"service_focus":{"op":"eq","value":"Med-spa (botox / lasers)"}}'::jsonb, 20000, 0.0, 'High-LTV med-spa', 40)
ON CONFLICT DO NOTHING;

INSERT INTO quote_addons (template_id, addon_slug, addon_name, description, monthly_cents, one_time_cents, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000007', 'instagram_booking',  'Instagram DM auto-booking', 'AI books clients straight from DMs',          12900, 0,     10),
  ('00000000-1111-4001-a000-000000000007', 'reactivation_engine','Client reactivation',      'Lapsed-client reach-out + win-back offers',    9900, 0,     20),
  ('00000000-1111-4001-a000-000000000007', 'review_automation',  'Review automation',         'Post-visit review requests',                   6900, 0,     30),
  ('00000000-1111-4001-a000-000000000007', 'retail_recommender', 'Retail upsell recommender', 'Auto-suggest products at checkout',            7900, 0,     40)
ON CONFLICT DO NOTHING;

-- ══════════════════════════════════════════════════════════════════
-- Verify
-- ══════════════════════════════════════════════════════════════════
--   SELECT industry_slug, industry_name, sort_order FROM quote_templates ORDER BY sort_order;
--     → Expect 7 rows: insurance_personal, construction, dental,
--       cleaning, restaurants, moving, beauty.
--   SELECT count(*) FROM quote_pricing_rules;  -- expect 5 + (5+4+4+4+4+4) = 30
--   SELECT count(*) FROM quote_addons;          -- expect 5 + (5+4+4+4+4+4) = 30
-- ══════════════════════════════════════════════════════════════════
