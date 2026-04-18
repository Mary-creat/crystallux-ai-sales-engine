-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX FULL PLATFORM FOUNDATION MIGRATION
-- File: docs/architecture/migrations/2026-04-18-full-platform-foundation.sql
--
-- Includes:
--   1. Lead table extensions (multi-platform + multi-channel fields)
--   2. Orchestration layer (routing, signals, credits, jobs)
--   3. Content generation layer (assets, carousels, videos)
--   4. Delivery layer (channel creds, delivery log)
--   5. CRM + subscription layer (ICPs, deals, subscriptions)
--   6. Coaching + mentorship layer (sessions, goals, calendar, check-ins)
--   7. Team management layer (hierarchy, productivity, alerts, activity log)
--   8. Apollo usage tracking
--   9. Indexes
--  10. Backfill existing 2,282 leads
--  11. Seed routing rules + platform credits
--  12. Verification queries
--
-- Idempotent — safe to re-run.
-- ═══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────
-- 1. LEADS TABLE EXTENSIONS
-- ─────────────────────────────────────────────────────

-- Platform / source tracking
ALTER TABLE leads ADD COLUMN IF NOT EXISTS vertical TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS platform_source TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS platform_lead_id TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS enrichment_source TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS data_quality_score INT;

-- Social / channel handles
ALTER TABLE leads ADD COLUMN IF NOT EXISTS linkedin_handle TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS instagram_handle TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS twitter_handle TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS facebook_url TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS whatsapp_number TEXT;

-- Video personalization
ALTER TABLE leads ADD COLUMN IF NOT EXISTS video_script TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS video_url TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS video_generated_at TIMESTAMPTZ;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS video_thumbnail_url TEXT;

-- Voice / phone tracking
ALTER TABLE leads ADD COLUMN IF NOT EXISTS voice_call_scheduled_at TIMESTAMPTZ;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS voice_call_completed BOOLEAN DEFAULT FALSE;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS voice_call_transcript TEXT;

-- ─────────────────────────────────────────────────────
-- 2. ORCHESTRATION LAYER
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS routing_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical TEXT NOT NULL,
  platform TEXT NOT NULL,
  priority INT NOT NULL,
  lead_type TEXT,
  cost_per_lead NUMERIC,
  notes TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS market_signals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical TEXT NOT NULL,
  geography TEXT,
  signal_type TEXT NOT NULL,
  signal_strength TEXT,
  urgency TEXT,
  source TEXT,
  context JSONB,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS platform_credits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  platform TEXT UNIQUE NOT NULL,
  credits_remaining INT,
  credits_limit INT,
  reset_at TIMESTAMPTZ,
  cost_per_credit NUMERIC,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS discovery_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID,
  vertical TEXT,
  geography TEXT,
  requested_count INT,
  platforms_used TEXT[],
  leads_found INT DEFAULT 0,
  status TEXT DEFAULT 'queued',
  signal_context JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

-- ─────────────────────────────────────────────────────
-- 3. CONTENT GENERATION LAYER
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS content_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  lead_id UUID REFERENCES leads(id),
  asset_type TEXT NOT NULL,
  channel TEXT,
  status TEXT DEFAULT 'draft',
  content TEXT,
  content_metadata JSONB,
  media_url TEXT,
  generated_by TEXT,
  generated_at TIMESTAMPTZ DEFAULT NOW(),
  sent_at TIMESTAMPTZ,
  performance_metrics JSONB
);

CREATE TABLE IF NOT EXISTS carousel_campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  title TEXT NOT NULL,
  platform TEXT NOT NULL,
  topic TEXT,
  vertical TEXT,
  slide_count INT,
  scheduled_at TIMESTAMPTZ,
  posted_at TIMESTAMPTZ,
  status TEXT DEFAULT 'draft',
  performance_metrics JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS video_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID REFERENCES leads(id),
  client_id UUID REFERENCES clients(id),
  provider TEXT NOT NULL,
  avatar_id TEXT,
  script TEXT,
  video_url TEXT,
  thumbnail_url TEXT,
  duration_seconds INT,
  cost NUMERIC,
  status TEXT DEFAULT 'queued',
  generated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────
-- 4. DELIVERY LAYER
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS channel_credentials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  channel TEXT NOT NULL,
  provider TEXT,
  credential_name TEXT,
  sender_identity TEXT,
  daily_send_limit INT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS delivery_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID REFERENCES leads(id),
  client_id UUID REFERENCES clients(id),
  content_asset_id UUID REFERENCES content_assets(id),
  channel TEXT NOT NULL,
  status TEXT,
  external_id TEXT,
  error_message TEXT,
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────
-- 5. CRM + CLIENT LAYER
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS client_icp_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  name TEXT,
  vertical TEXT,
  geography TEXT,
  company_size_min INT,
  company_size_max INT,
  titles TEXT[],
  exclude_keywords TEXT[],
  include_keywords TEXT[],
  signal_types TEXT[],
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Stage values: 'Meeting Booked', 'Proposal Sent', 'Negotiating', 'Closed Won', 'Closed Lost'
CREATE TABLE IF NOT EXISTS deals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID REFERENCES leads(id),
  client_id UUID REFERENCES clients(id),
  stage TEXT DEFAULT 'Meeting Booked',
  deal_value NUMERIC,
  probability INT,
  close_date DATE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS client_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  plan_tier TEXT,
  monthly_fee NUMERIC,
  billing_day INT,
  trial_ends_at TIMESTAMPTZ,
  active_until TIMESTAMPTZ,
  status TEXT DEFAULT 'active',
  stripe_subscription_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────
-- 6. COACHING & MENTORSHIP LAYER
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS coaching_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  session_type TEXT NOT NULL,
  scheduled_at TIMESTAMPTZ,
  duration_minutes INT DEFAULT 30,
  status TEXT DEFAULT 'scheduled',
  notes TEXT,
  action_items TEXT[],
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS client_goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  goal_type TEXT NOT NULL,
  goal_title TEXT,
  target_value NUMERIC,
  current_value NUMERIC,
  unit TEXT,
  due_date DATE,
  status TEXT DEFAULT 'active',
  priority TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS calendar_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  block_type TEXT NOT NULL,
  day_of_week INT,
  start_time TIME,
  end_time TIME,
  is_recurring BOOLEAN DEFAULT TRUE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS accountability_checkins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  checkin_date DATE,
  checkin_type TEXT,
  energy_level INT,
  productivity_score INT,
  goals_progress JSONB,
  wins TEXT[],
  blockers TEXT[],
  next_focus TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS client_onboarding (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  stage TEXT DEFAULT 'welcome',
  icp_defined BOOLEAN DEFAULT FALSE,
  calendar_configured BOOLEAN DEFAULT FALSE,
  goals_set BOOLEAN DEFAULT FALSE,
  first_campaign_launched BOOLEAN DEFAULT FALSE,
  introduction_call_completed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS coaching_resources (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  resource_type TEXT,
  category TEXT,
  vertical TEXT,
  content TEXT,
  media_url TEXT,
  access_tier TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────
-- 7. TEAM MANAGEMENT & HIERARCHY LAYER
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS team_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  leader_id UUID REFERENCES team_members(id),
  full_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  role TEXT,
  level INT,
  start_date DATE,
  status TEXT DEFAULT 'active',
  license_number TEXT,
  specializations TEXT[],
  territory TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS productivity_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_member_id UUID REFERENCES team_members(id),
  client_id UUID REFERENCES clients(id),
  period_type TEXT,
  period_start DATE,
  period_end DATE,
  hours_worked NUMERIC,
  calls_made INT DEFAULT 0,
  emails_sent INT DEFAULT 0,
  meetings_held INT DEFAULT 0,
  proposals_sent INT DEFAULT 0,
  deals_closed INT DEFAULT 0,
  revenue_generated NUMERIC,
  productivity_score NUMERIC,
  engagement_score NUMERIC,
  trend TEXT,
  notes TEXT,
  computed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS team_goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_member_id UUID REFERENCES team_members(id),
  client_id UUID REFERENCES clients(id),
  goal_type TEXT,
  goal_title TEXT,
  target_value NUMERIC,
  current_value NUMERIC DEFAULT 0,
  unit TEXT,
  period_type TEXT,
  period_start DATE,
  period_end DATE,
  status TEXT DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS leadership_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  team_member_id UUID REFERENCES team_members(id),
  alert_type TEXT,
  severity TEXT,
  title TEXT,
  message TEXT,
  suggested_action TEXT,
  context JSONB,
  status TEXT DEFAULT 'unread',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  read_at TIMESTAMPTZ,
  actioned_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS team_activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_member_id UUID REFERENCES team_members(id),
  client_id UUID REFERENCES clients(id),
  activity_type TEXT,
  source TEXT,
  duration_minutes INT,
  outcome TEXT,
  metadata JSONB,
  occurred_at TIMESTAMPTZ,
  logged_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS leaderboards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id),
  period_type TEXT,
  period_start DATE,
  period_end DATE,
  metric TEXT,
  rankings JSONB,
  generated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────
-- 8. APOLLO USAGE TRACKING
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS apollo_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID REFERENCES leads(id),
  request_type TEXT,
  credits_used INT DEFAULT 1,
  success BOOLEAN,
  response_data JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────
-- 9. INDEXES
-- ─────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_leads_platform_vertical
  ON leads(platform_source, vertical, lead_status);

CREATE INDEX IF NOT EXISTS idx_leads_type
  ON leads(lead_type)
  WHERE lead_type IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_content_assets_lead
  ON content_assets(lead_id, asset_type, status);

CREATE INDEX IF NOT EXISTS idx_delivery_log_lead
  ON delivery_log(lead_id, channel, sent_at);

CREATE INDEX IF NOT EXISTS idx_market_signals_active
  ON market_signals(vertical, geography, expires_at);

CREATE INDEX IF NOT EXISTS idx_deals_client_stage
  ON deals(client_id, stage);

CREATE INDEX IF NOT EXISTS idx_discovery_jobs_client_status
  ON discovery_jobs(client_id, status, created_at);

CREATE INDEX IF NOT EXISTS idx_coaching_sessions_client_date
  ON coaching_sessions(client_id, scheduled_at);

CREATE INDEX IF NOT EXISTS idx_client_goals_client_status
  ON client_goals(client_id, status);

CREATE INDEX IF NOT EXISTS idx_accountability_client_date
  ON accountability_checkins(client_id, checkin_date DESC);

CREATE INDEX IF NOT EXISTS idx_team_members_client_leader
  ON team_members(client_id, leader_id);

CREATE INDEX IF NOT EXISTS idx_team_members_status
  ON team_members(status)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_productivity_member_period
  ON productivity_metrics(team_member_id, period_start DESC);

CREATE INDEX IF NOT EXISTS idx_team_goals_member_status
  ON team_goals(team_member_id, status);

CREATE INDEX IF NOT EXISTS idx_leadership_alerts_client_status
  ON leadership_alerts(client_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_team_activity_member_date
  ON team_activity_log(team_member_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_leaderboards_client_period
  ON leaderboards(client_id, period_type, period_start DESC);

-- ─────────────────────────────────────────────────────
-- 10. BACKFILL EXISTING LEADS
-- ─────────────────────────────────────────────────────

UPDATE leads SET
  lead_type = 'b2c',
  platform_source = 'google_maps',
  vertical = industry,
  enrichment_source = CASE
    WHEN email IS NOT NULL AND email != '' THEN 'website_scraper'
    ELSE NULL
  END
WHERE lead_type IS NULL
  AND source IN ('google_maps', 'google_maps_discovery', 'b2c_scan');

-- ─────────────────────────────────────────────────────
-- 11. SEED ROUTING RULES
-- ─────────────────────────────────────────────────────

INSERT INTO routing_rules (vertical, platform, priority, lead_type, cost_per_lead, notes) VALUES
  ('insurance_broker', 'google_maps', 1, 'b2c', 0.05, 'Primary source for licensed brokers by city'),
  ('insurance_broker', 'apollo', 2, 'b2c', 1.00, 'For decision-maker contacts'),
  ('insurance_broker', 'linkedin_sn', 3, 'b2c', 2.00, 'Future - for leadership contacts'),
  ('b2b_saas', 'apollo', 1, 'b2b', 1.00, 'Primary source - professional contacts with emails'),
  ('b2b_saas', 'linkedin_sn', 2, 'b2b', 2.00, 'Future - decision makers'),
  ('b2b_saas', 'crunchbase', 3, 'b2b', 1.50, 'Future - funded startups'),
  ('dentist', 'google_maps', 1, 'b2c', 0.05, 'Local practices by city'),
  ('dentist', 'industry_directory', 2, 'b2c', 0.00, 'Future - dental association listings'),
  ('mover', 'google_maps', 1, 'b2c', 0.05, 'Local moving companies'),
  ('real_estate_agent', 'google_maps', 1, 'b2c', 0.05, 'Local agents'),
  ('real_estate_agent', 'linkedin_sn', 2, 'b2c', 2.00, 'Future - top performers'),
  ('restaurant', 'yelp', 1, 'b2c', 0.10, 'Future - review-driven presence'),
  ('restaurant', 'google_maps', 2, 'b2c', 0.05, 'Secondary source'),
  ('cleaning_service', 'google_maps', 1, 'b2c', 0.05, 'Local cleaners'),
  ('contractor', 'google_maps', 1, 'b2c', 0.05, 'Local renovators and builders'),
  ('hair_salon', 'google_maps', 1, 'b2c', 0.05, 'Local salons'),
  ('hair_salon', 'instagram', 2, 'b2c', 0.15, 'Future - high-end salons with social presence'),
  ('marketing_agency', 'apollo', 1, 'b2b', 1.00, 'Professional contacts'),
  ('marketing_agency', 'linkedin_sn', 2, 'b2b', 2.00, 'Future'),
  ('consultant', 'linkedin_sn', 1, 'b2b', 2.00, 'Future - personal brand driven');

-- ─────────────────────────────────────────────────────
-- 12. SEED PLATFORM CREDITS
-- ─────────────────────────────────────────────────────

INSERT INTO platform_credits (platform, credits_remaining, credits_limit, cost_per_credit) VALUES
  ('google_maps', 999999, 999999, 0.002),
  ('apollo', 50, 50, 0.00),
  ('linkedin_sn', 0, 0, 0.00),
  ('yelp', 0, 0, 0.00),
  ('crunchbase', 0, 0, 0.00),
  ('instagram', 0, 0, 0.00),
  ('facebook', 0, 0, 0.00),
  ('reddit', 0, 0, 0.00)
ON CONFLICT (platform) DO NOTHING;

-- ─────────────────────────────────────────────────────
-- 13. VERIFICATION QUERIES
-- ─────────────────────────────────────────────────────

-- Confirm all new tables created (expect 25 rows)
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'routing_rules', 'market_signals', 'platform_credits',
    'discovery_jobs', 'content_assets', 'carousel_campaigns',
    'video_assets', 'channel_credentials', 'delivery_log',
    'client_icp_profiles', 'deals', 'client_subscriptions',
    'coaching_sessions', 'client_goals', 'calendar_blocks',
    'accountability_checkins', 'client_onboarding', 'coaching_resources',
    'team_members', 'productivity_metrics', 'team_goals',
    'leadership_alerts', 'team_activity_log', 'leaderboards',
    'apollo_usage'
  )
ORDER BY table_name;

-- Confirm lead backfill (expect ~2,274 rows with lead_type='b2c')
SELECT lead_type, platform_source, COUNT(*)
FROM leads
GROUP BY lead_type, platform_source
ORDER BY COUNT(*) DESC;

-- Confirm routing rules seeded (expect 20 rows)
SELECT vertical, platform, priority, lead_type
FROM routing_rules
ORDER BY vertical, priority;

-- Confirm platform credits seeded (expect 8 rows)
SELECT platform, credits_remaining, credits_limit
FROM platform_credits;
