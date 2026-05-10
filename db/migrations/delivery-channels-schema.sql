-- ══════════════════════════════════════════════════════════════════
-- Delivery channels schema (Phase 2 — video pipeline + multichannel)
-- ══════════════════════════════════════════════════════════════════
-- Spec: Phase 2/3 build brief (commit-author note in SESSION_LOG).
-- Universal multi-vertical: every table is vertical-agnostic. The
-- same engine renders + delivers for insurance, mortgage, real estate,
-- dental, construction, consulting, agencies, financial advisors —
-- per-vertical tuning lives in client.preferred_persona_id (and the
-- archetype message templates), never in the schema.
--
-- Additive only. Idempotent (IF NOT EXISTS). Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. video_renders — every HeyGen render lifecycle
-- ─────────────────────────────────────────────────────────────────
-- Lifecycle: pending → rendering → ready → delivered → archived
--                                 │
--                                 └→ failed (terminal)
-- Storage flow: HeyGen URL (7-day expiry) → R2 (permanent) → public CDN
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS video_renders (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id               uuid REFERENCES leads(id) ON DELETE SET NULL,
  client_id             uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  -- script + persona inputs
  script                text,
  intent                text,                            -- 'book_meeting' | 're_engage' | 'nurture' | 'content_marketing'
  persona_id            text,                            -- one of james|sarah|marcus|maria
  look_id               text,                            -- variant within persona (suit|casual|polo|warm|...)
  voice_id              text,                            -- ElevenLabs cloned voice id
  -- HeyGen render handles
  heygen_avatar_id      text,
  heygen_video_id       text UNIQUE,
  source_video_url      text,                            -- HeyGen-hosted URL (expires ~7 days)
  -- R2 permanent storage
  storage_provider      text DEFAULT 'cloudflare_r2',
  storage_key           text,                            -- e.g. videos/<uuid>.mp4
  storage_url           text,                            -- public R2 URL
  file_size_bytes       bigint,
  duration_seconds      integer,
  -- landing page
  landing_page_token    text UNIQUE,                     -- 16+ char random token in URL
  landing_page_url      text,
  -- lifecycle
  status                text DEFAULT 'pending',          -- pending | rendering | ready | delivered | archived | failed
  error_message         text,
  cost_cents            integer,
  -- dual-purpose: outreach (1:1) vs content_marketing (1:N) — drives retention policy
  content_type          text DEFAULT 'outreach',         -- 'outreach' | 'content_marketing'
  retention_until       timestamptz,                     -- outreach: now()+90d; content_marketing: NULL (keep forever)
  -- timestamps
  created_at            timestamptz DEFAULT now(),
  rendered_at           timestamptz,
  delivered_at          timestamptz
);

DO $$ BEGIN
  ALTER TABLE video_renders
    ADD CONSTRAINT vr_status_check
    CHECK (status IN ('pending','rendering','ready','delivered','archived','failed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE video_renders
    ADD CONSTRAINT vr_content_type_check
    CHECK (content_type IN ('outreach','content_marketing'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_vr_lead       ON video_renders(lead_id);
CREATE INDEX IF NOT EXISTS idx_vr_client     ON video_renders(client_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_vr_status     ON video_renders(status);
CREATE INDEX IF NOT EXISTS idx_vr_retention  ON video_renders(retention_until) WHERE retention_until IS NOT NULL AND status != 'archived';
CREATE INDEX IF NOT EXISTS idx_vr_token      ON video_renders(landing_page_token) WHERE landing_page_token IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────
-- 2. video_engagement — landing-page + watch analytics
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS video_engagement (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  video_render_id     uuid REFERENCES video_renders(id) ON DELETE CASCADE,
  lead_id             uuid REFERENCES leads(id) ON DELETE SET NULL,
  event_type          text NOT NULL,    -- 'page_view' | 'video_play' | 'video_25' | 'video_50' | 'video_75' | 'video_complete' | 'cta_click' | 'booking_started' | 'booking_completed'
  event_data          jsonb DEFAULT '{}'::jsonb,
  ip_address          text,
  user_agent          text,
  occurred_at         timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE video_engagement
    ADD CONSTRAINT ve_event_type_check
    CHECK (event_type IN ('page_view','video_play','video_25','video_50','video_75','video_complete','cta_click','booking_started','booking_completed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_ve_render       ON video_engagement(video_render_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_ve_lead         ON video_engagement(lead_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_ve_event        ON video_engagement(event_type);

-- ─────────────────────────────────────────────────────────────────
-- 3. messages_sent — universal channel send log
-- ─────────────────────────────────────────────────────────────────
-- Mirrors agent_actions for human-readability + dashboard surfaces.
-- AI Agent writes to BOTH agent_actions (audit) and messages_sent
-- (operational view). Activity feed reads messages_sent.
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS messages_sent (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id         uuid REFERENCES leads(id) ON DELETE SET NULL,
  client_id       uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  channel         text NOT NULL,    -- 'whatsapp' | 'sms' | 'email' | 'voice' | 'video_link'
  direction       text DEFAULT 'outbound',   -- 'outbound' | 'inbound'
  content         text,
  external_id     text,             -- Twilio SID, Postmark MessageID, Vapi call id
  status          text DEFAULT 'pending',    -- pending | sent | delivered | read | replied | failed | bounced
  cost_cents      integer,
  agent_action_id uuid REFERENCES agent_actions(id) ON DELETE SET NULL,
  video_render_id uuid REFERENCES video_renders(id) ON DELETE SET NULL,
  error_message   text,
  sent_at         timestamptz DEFAULT now(),
  delivered_at    timestamptz,
  read_at         timestamptz,
  replied_at      timestamptz
);

DO $$ BEGIN
  ALTER TABLE messages_sent
    ADD CONSTRAINT ms_channel_check
    CHECK (channel IN ('whatsapp','sms','email','voice','video_link'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE messages_sent
    ADD CONSTRAINT ms_status_check
    CHECK (status IN ('pending','sent','delivered','read','replied','failed','bounced'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE messages_sent
    ADD CONSTRAINT ms_direction_check
    CHECK (direction IN ('outbound','inbound'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_ms_lead     ON messages_sent(lead_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_ms_client   ON messages_sent(client_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_ms_channel  ON messages_sent(channel);
CREATE INDEX IF NOT EXISTS idx_ms_status   ON messages_sent(status);
CREATE INDEX IF NOT EXISTS idx_ms_external ON messages_sent(external_id) WHERE external_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────
-- 4. bookings — Cal.com / Calendly normalised booking row
-- ─────────────────────────────────────────────────────────────────
-- Note: appointment_log already exists from §29. bookings is the
-- universal vertical-agnostic version that the AI Agent writes to.
-- The 7 protected v2/v3 production workflows continue to use
-- appointment_log; new agent-orchestrated bookings land here.
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS bookings (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id           uuid REFERENCES leads(id) ON DELETE SET NULL,
  client_id         uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  advisor_id        uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  scheduled_at      timestamptz NOT NULL,
  duration_minutes  integer DEFAULT 30,
  status            text DEFAULT 'scheduled',     -- scheduled | confirmed | completed | cancelled | no_show
  -- provider linking
  provider          text,                          -- 'cal_com' | 'calendly' | 'manual'
  cal_event_id      text,
  calendly_event_id text,
  -- intake + meeting
  intake_answers    jsonb DEFAULT '{}'::jsonb,
  meeting_link      text,
  notes             text,
  -- created by which agent action (if AI booked it)
  source_action_id  uuid REFERENCES agent_actions(id) ON DELETE SET NULL,
  created_at        timestamptz DEFAULT now(),
  updated_at        timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE bookings
    ADD CONSTRAINT b_status_check
    CHECK (status IN ('scheduled','confirmed','completed','cancelled','no_show'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE bookings
    ADD CONSTRAINT b_provider_check
    CHECK (provider IS NULL OR provider IN ('cal_com','calendly','manual'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_b_lead         ON bookings(lead_id);
CREATE INDEX IF NOT EXISTS idx_b_client       ON bookings(client_id, scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_b_advisor      ON bookings(advisor_id, scheduled_at DESC) WHERE advisor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_b_upcoming     ON bookings(client_id, scheduled_at) WHERE status IN ('scheduled','confirmed');
CREATE INDEX IF NOT EXISTS idx_b_status       ON bookings(status);

-- ─────────────────────────────────────────────────────────────────
-- 5. clients additive columns — persona defaults + custom avatar
-- ─────────────────────────────────────────────────────────────────
-- Per-vertical fallback (insurance → james_suit, real_estate →
-- james_casual, etc.) lives in the workflow code. Per-client override
-- lives in these columns.
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE clients ADD COLUMN IF NOT EXISTS preferred_persona_id   text;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS preferred_look_id      text;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS preferred_voice_id     text;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS custom_avatar_id       text;     -- nullable; Scale tier only
ALTER TABLE clients ADD COLUMN IF NOT EXISTS custom_voice_id        text;     -- nullable; Scale tier only
ALTER TABLE clients ADD COLUMN IF NOT EXISTS niche_name             text;     -- universal vertical id, mirrors signal_archetypes.niche_name

-- ─────────────────────────────────────────────────────────────────
-- 6. RLS — service_role-only (defence in depth; n8n uses service role)
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE video_renders     ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_engagement  ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages_sent     ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings          ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN CREATE POLICY vr_service_role ON video_renders    FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY ve_service_role ON video_engagement FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY ms_service_role ON messages_sent    FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY b_service_role  ON bookings         FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 7. Verification (run manually after migration)
-- ─────────────────────────────────────────────────────────────────

-- SELECT count(*) AS vr FROM video_renders;
-- SELECT count(*) AS ve FROM video_engagement;
-- SELECT count(*) AS ms FROM messages_sent;
-- SELECT count(*) AS b  FROM bookings;
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'clients' AND column_name LIKE '%persona%' OR column_name LIKE '%voice%';

-- ═════════════════════════════════════════════════════════════════
-- ROLLBACK (commented — uncomment + run only to roll back)
-- ═════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS video_engagement;
-- DROP TABLE IF EXISTS bookings;
-- DROP TABLE IF EXISTS messages_sent;
-- DROP TABLE IF EXISTS video_renders;
-- ALTER TABLE clients DROP COLUMN IF EXISTS niche_name;
-- ALTER TABLE clients DROP COLUMN IF EXISTS custom_voice_id;
-- ALTER TABLE clients DROP COLUMN IF EXISTS custom_avatar_id;
-- ALTER TABLE clients DROP COLUMN IF EXISTS preferred_voice_id;
-- ALTER TABLE clients DROP COLUMN IF EXISTS preferred_look_id;
-- ALTER TABLE clients DROP COLUMN IF EXISTS preferred_persona_id;
