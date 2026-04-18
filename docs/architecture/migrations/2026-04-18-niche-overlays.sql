-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX NICHE OVERLAYS MIGRATION
-- File: docs/architecture/migrations/2026-04-18-niche-overlays.sql
--
-- Adds the niche_overlays table — the configuration layer that
-- adapts the universal platform to specific industries.
--
-- Per the Architecture Doctrine (three-layer architecture):
--   Layer 1 (Core) = universal engine, stays shared
--   Layer 2 (Modules) = Pipeline, Content, Coach, Manager, Operator
--   Layer 3 (Niche Overlays) = THIS TABLE — config per industry
--
-- Adding a new niche = inserting a row here. No code changes required.
--
-- Idempotent — safe to re-run.
-- Run AFTER 2026-04-18-full-platform-foundation.sql
-- Run BEFORE 2026-04-18-closing-intelligence.sql
-- ═══════════════════════════════════════════════════════════════════


CREATE TABLE IF NOT EXISTS niche_overlays (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  niche_name TEXT UNIQUE NOT NULL,
  display_name TEXT,
  icp_template JSONB,
  routing_preferences JSONB,
  pain_signals TEXT[],
  claude_system_prompt TEXT,
  outreach_tone TEXT,
  offer_mapping JSONB,
  dashboard_labels JSONB,
  compliance_notes TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);


CREATE INDEX IF NOT EXISTS idx_niche_overlays_active
  ON niche_overlays(is_active)
  WHERE is_active = TRUE;


-- ─────────────────────────────────────────────────────
-- SEED DATA — Insurance Broker (first vertical)
-- ─────────────────────────────────────────────────────

INSERT INTO niche_overlays (
  niche_name,
  display_name,
  icp_template,
  routing_preferences,
  pain_signals,
  claude_system_prompt,
  outreach_tone,
  offer_mapping,
  dashboard_labels,
  compliance_notes
)
VALUES (
  'insurance_broker',
  'Insurance Brokers (Ontario)',

  '{
    "target_role": ["insurance advisor", "insurance broker", "licensed advisor", "account executive"],
    "experience_years_min": 2,
    "experience_years_max": 25,
    "book_size_min": 100,
    "book_size_max": 2000,
    "typical_products": ["life insurance", "disability", "critical illness", "group benefits", "P&C", "CHIP reverse mortgage"],
    "geography": "Ontario, Canada",
    "company_size_min": 1,
    "company_size_max": 20,
    "licensing_required": ["FSRA", "LLQP"],
    "exclude_from_target": ["captive agents unable to use outside lead sources", "unlicensed assistants", "new-licensed with under 6 months experience"]
  }'::jsonb,

  '{
    "primary_platforms": ["google_maps", "linkedin_sn"],
    "secondary_platforms": ["apollo"],
    "tertiary_platforms": ["ontario_broker_registry"],
    "search_keywords": ["insurance broker ontario", "insurance advisor ontario", "licensed insurance", "financial advisor insurance"],
    "exclude_keywords": ["captive agent", "call center", "claims adjuster"]
  }'::jsonb,

  ARRAY[
    'stale website content last updated 2+ years ago',
    'no online booking for consultations',
    'under 25 Google reviews',
    'no visible advisor specialization',
    'no LinkedIn content activity in 6+ months',
    'no client portal or digital policy access',
    'contact form only, no direct phone',
    'no automated follow-up system apparent',
    'no visible cross-sell strategy',
    'no renewal retention system visible',
    'generic carrier logos without strategic positioning',
    'no video content despite trust-based industry',
    'no testimonials with specific dollar outcomes'
  ],

  'You are writing for an audience of licensed Ontario insurance advisors. They are commission-based, relationship-driven, and regulatory-aware (FSRA, CASL). They hate prospecting but love closing. They respect peers who speak their industry language.

Use these insurance-specific terms correctly: policy, premium, underwriting, commission, renewals, KYC (Know Your Customer), LLQP, FSRA, MGA, carrier, E&O insurance, continuing education (CE), book of business, client suitability, needs analysis, beneficiaries.

Never sound like a tech vendor. Always sound like a peer advisor who happens to have built software. Reference the daily reality: time spent on prospecting vs closing, renewal notifications, cross-sell opportunities, carrier relationships, MGA overrides.

Key pain points to reference: prospecting burnout, revenue plateau, single-product client trap, renewal leakage, slow response time to inbound leads, referral dependency, difficulty building book in first 2 years.

Key aspirations to tap into: $200K+ income, financial freedom, helping families, building succession-worthy book, independence from MGA pressure, time with family.

Compliance: CASL applies to all Canadian outreach. Always include unsubscribe. Never imply guaranteed outcomes on insurance products. Respect professional standards.',

  'peer-to-peer, licensed-advisor-to-licensed-advisor, direct but respectful, specific with numbers and industry references, never salesy, always addresses a real observed pain point',

  '{
    "primary_offer": {
      "module": "pipeline",
      "tier": "growth",
      "price_monthly": 2997,
      "founding_price": 1997,
      "target_outcome": "20-30 qualified prospect meetings per month"
    },
    "upsell_30_day": {
      "module": "coach",
      "tier": "guided",
      "price_monthly": 497,
      "bundle_price": 3247,
      "rationale": "solo advisors benefit from accountability + playbook access"
    },
    "upsell_60_day": {
      "module": "content",
      "tier": "professional",
      "price_monthly": 1497,
      "rationale": "LinkedIn content production for personal brand building"
    },
    "mga_principal_offer": {
      "module": "operator",
      "tier": "business",
      "price_monthly": 5997,
      "rationale": "brokerage principals managing 5-15 advisors need Manager + Pipeline bundle"
    }
  }'::jsonb,

  '{
    "leads": "Prospects",
    "outreach_sent": "Outreach Campaigns",
    "contacted": "Prospects Contacted",
    "replied": "Responses Received",
    "meetings": "Discovery Calls",
    "deals": "Policies in Pipeline",
    "closed_won": "Policies Written",
    "deal_value": "Estimated Commission",
    "conversion_rate": "Close Rate"
  }'::jsonb,

  'CASL (Canadian Anti-Spam Legislation) strictly applies. All outreach must include:
(1) Valid sender identification
(2) Mailing address
(3) One-click unsubscribe
(4) CASL-compliant consent basis (business purpose for B2B advisor-to-advisor outreach)

FSRA regulations: Advisors are regulated. Avoid promising guaranteed outcomes on insurance products. Do not recommend specific policies in outreach — only offer pipeline services.

E&O considerations: Platform services should not constitute advice on insurance matters. Client advisors retain all fiduciary responsibility for client suitability and recommendations.

License verification: For MGA recruitment use cases, verify target advisor holds active FSRA license before proceeding with pitch.'
)
ON CONFLICT (niche_name) DO NOTHING;


-- ─────────────────────────────────────────────────────
-- VERIFICATION
-- ─────────────────────────────────────────────────────

-- Confirm table exists
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = 'niche_overlays';

-- Confirm insurance broker seed data
SELECT niche_name, display_name, is_active
FROM niche_overlays;

-- Expected: 1 row with niche_name='insurance_broker'
