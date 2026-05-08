-- ══════════════════════════════════════════════════════════════════
-- AI Sales Agent schema (Phase 3 foundation)
-- ══════════════════════════════════════════════════════════════════
-- Spec: docs/agent/AGENT_VISION.md + docs/agent/build-phases.md
-- Universal vertical-agnostic. Supports voice (in/out), WhatsApp, SMS,
-- email, social DM/comments. Same schema serves every Crystallux
-- vertical (insurance, mortgage, real estate, dental, consulting,
-- construction, agencies, financial advisors, etc.).
--
-- Additive only. Idempotent (IF NOT EXISTS). Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. agent_decisions — every choice the agent makes + reasoning
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_decisions (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id             uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  lead_id               uuid REFERENCES leads(id) ON DELETE SET NULL,
  decision_type         text NOT NULL,    -- 'send_message' | 'place_call' | 'reschedule' | 'escalate' | 'wait' | 'mark_unresponsive' | 'request_human_review'
  reasoning             text,             -- Claude's stated rationale
  context_used          jsonb DEFAULT '{}'::jsonb,    -- behavioral signals, lead history, channel preferences
  target_role           text,             -- 'client' | 'advisor' | 'supervisor' | 'mga_principal' if escalation
  confidence_score      numeric(4,3),     -- 0-1
  outcome               text,             -- 'success' | 'failed' | 'no_response' | 'pending'
  outcome_recorded_at   timestamptz,
  created_at            timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ad_client     ON agent_decisions(client_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ad_lead       ON agent_decisions(lead_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ad_type       ON agent_decisions(decision_type);

-- ─────────────────────────────────────────────────────────────────
-- 2. agent_actions — concrete things the agent did (sends + calls)
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_actions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_id     uuid REFERENCES agent_decisions(id) ON DELETE SET NULL,
  client_id       uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  lead_id         uuid REFERENCES leads(id) ON DELETE SET NULL,
  action_type     text NOT NULL,    -- 'voice_call_outbound' | 'voice_call_inbound' | 'whatsapp_send' | 'whatsapp_reply' | 'sms_send' | 'sms_reply' | 'email_send' | 'email_reply' | 'social_comment_reply' | 'social_dm_reply' | 'meeting_book' | 'meeting_reschedule' | 'meeting_cancel'
  channel         text NOT NULL,    -- 'voice' | 'whatsapp' | 'sms' | 'email' | 'instagram' | 'facebook' | 'linkedin' | 'x' | 'calendar'
  action_data     jsonb DEFAULT '{}'::jsonb,  -- payload sent
  external_id     text,             -- Twilio SID / Postmark message id / Vapi call id / etc.
  status          text DEFAULT 'pending',     -- 'pending' | 'completed' | 'failed' | 'queued'
  error_message   text,
  cost_cents      integer,          -- track API/service cost
  taken_by_role   text DEFAULT 'agent',       -- 'agent' | 'human' (human override audit)
  taken_at        timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE agent_actions
    ADD CONSTRAINT aa_channel_check
    CHECK (channel IN ('voice','whatsapp','sms','email','instagram','facebook','linkedin','x','calendar','tiktok','youtube'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE agent_actions
    ADD CONSTRAINT aa_status_check
    CHECK (status IN ('pending','queued','completed','failed','cancelled'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_aa_client     ON agent_actions(client_id, taken_at DESC);
CREATE INDEX IF NOT EXISTS idx_aa_lead       ON agent_actions(lead_id, taken_at DESC);
CREATE INDEX IF NOT EXISTS idx_aa_channel    ON agent_actions(channel);
CREATE INDEX IF NOT EXISTS idx_aa_status     ON agent_actions(status);
CREATE INDEX IF NOT EXISTS idx_aa_decision   ON agent_actions(decision_id);

-- ─────────────────────────────────────────────────────────────────
-- 3. agent_conversations — per-channel thread state
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_conversations (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id                 uuid REFERENCES leads(id) ON DELETE CASCADE,
  client_id               uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  channel                 text NOT NULL,
  thread_external_id      text,         -- Twilio conversation id / social thread id / email thread id
  message_count           integer DEFAULT 0,
  last_message_at         timestamptz,
  last_message_direction  text,         -- 'inbound' | 'outbound'
  current_status          text DEFAULT 'active',     -- 'active' | 'ended' | 'escalated' | 'archived'
  agent_active            boolean DEFAULT true,      -- false if human took over
  created_at              timestamptz DEFAULT now(),
  updated_at              timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ac_lead           ON agent_conversations(lead_id);
CREATE INDEX IF NOT EXISTS idx_ac_channel        ON agent_conversations(channel);
CREATE INDEX IF NOT EXISTS idx_ac_status         ON agent_conversations(current_status);
CREATE INDEX IF NOT EXISTS idx_ac_thread_ext     ON agent_conversations(thread_external_id);

-- ─────────────────────────────────────────────────────────────────
-- 4. agent_memory — pgvector-backed semantic memory layer
-- ─────────────────────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS agent_memory (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id             uuid REFERENCES leads(id) ON DELETE CASCADE,
  client_id           uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  memory_type         text NOT NULL,    -- 'conversation_summary' | 'behavioral_pattern' | 'preference' | 'objection_history' | 'successful_close_pattern'
  content             text NOT NULL,
  embedding           vector(1536),     -- OpenAI text-embedding-3-small (1536-dim) or Claude-emb
  importance_score    numeric(4,3) DEFAULT 0.5,
  source_action_id    uuid REFERENCES agent_actions(id) ON DELETE SET NULL,
  created_at          timestamptz DEFAULT now(),
  expires_at          timestamptz
);

CREATE INDEX IF NOT EXISTS idx_am_lead       ON agent_memory(lead_id);
CREATE INDEX IF NOT EXISTS idx_am_client     ON agent_memory(client_id);
CREATE INDEX IF NOT EXISTS idx_am_type       ON agent_memory(memory_type);
-- ivfflat index for cosine similarity search. Tune `lists` per scale.
CREATE INDEX IF NOT EXISTS idx_am_embedding  ON agent_memory USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ─────────────────────────────────────────────────────────────────
-- 5. agent_escalations — when the agent hands off to a human
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_escalations (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id                  uuid REFERENCES leads(id) ON DELETE CASCADE,
  client_id                uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  conversation_id          uuid REFERENCES agent_conversations(id) ON DELETE SET NULL,
  reason                   text NOT NULL,
  escalated_to_role        text NOT NULL,     -- 'client' | 'advisor' | 'supervisor' | 'admin' | 'compliance_officer'
  escalated_to_user_id     uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  context_summary          text,              -- packaged context for the human
  status                   text DEFAULT 'pending',  -- 'pending' | 'acknowledged' | 'resolved'
  acknowledged_at          timestamptz,
  resolved_at              timestamptz,
  resolution_notes         text,
  created_at               timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ae_status     ON agent_escalations(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ae_role       ON agent_escalations(escalated_to_role);
CREATE INDEX IF NOT EXISTS idx_ae_user       ON agent_escalations(escalated_to_user_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_ae_client     ON agent_escalations(client_id, created_at DESC);

-- ─────────────────────────────────────────────────────────────────
-- 6. agent_performance — daily rollup per client
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_performance (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                  uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  date                       date NOT NULL,
  messages_sent              integer DEFAULT 0,
  messages_received          integer DEFAULT 0,
  calls_outbound             integer DEFAULT 0,
  calls_inbound              integer DEFAULT 0,
  meetings_booked            integer DEFAULT 0,
  meetings_attended          integer DEFAULT 0,
  escalations_triggered      integer DEFAULT 0,
  total_cost_cents           integer DEFAULT 0,
  conversion_rate            numeric(6,4),     -- meetings_booked / messages_sent
  created_at                 timestamptz DEFAULT now(),
  UNIQUE (client_id, date)
);

CREATE INDEX IF NOT EXISTS idx_ap_client_date ON agent_performance(client_id, date DESC);

-- ─────────────────────────────────────────────────────────────────
-- 7. agent_costs — per-action vendor cost ledger
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_costs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id         uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  action_id         uuid REFERENCES agent_actions(id) ON DELETE SET NULL,
  cost_type         text NOT NULL,    -- 'voice_minute' | 'whatsapp_message' | 'sms_message' | 'email_send' | 'claude_token' | 'whisper_minute' | 'heygen_credit' | 'embedding'
  units             numeric(12,4),
  unit_cost_cents   numeric(10,4),
  total_cents       numeric(12,4) GENERATED ALWAYS AS (units * unit_cost_cents) STORED,
  vendor            text,             -- 'twilio' | 'vapi' | 'retell' | 'anthropic' | 'openai' | 'heygen' | 'postmark'
  recorded_at       timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ac_client_date  ON agent_costs(client_id, recorded_at);
CREATE INDEX IF NOT EXISTS idx_ac_vendor       ON agent_costs(vendor, recorded_at);

-- ─────────────────────────────────────────────────────────────────
-- 8. agent_personalities — per-client tone tuning
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_personalities (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id              uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE UNIQUE,
  voice_tone             text DEFAULT 'professional',     -- 'professional' | 'friendly' | 'consultative' | 'enthusiastic'
  formality_level        text DEFAULT 'business_casual',  -- 'formal' | 'business_casual' | 'casual'
  language               text DEFAULT 'en-CA',
  signature              text,                            -- agent sign-off
  intro_template         text,                            -- agent intro
  escalation_rules       jsonb DEFAULT '{}'::jsonb,
  vertical_context       text,                            -- 'insurance' | 'mortgage' | 'real_estate' | etc. — tunes language
  prohibited_topics      text[] DEFAULT ARRAY[]::text[],
  custom_voice_id        text,                            -- ElevenLabs / Vapi voice id if cloned
  created_at             timestamptz DEFAULT now(),
  updated_at             timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────
-- 9. agent_channels_enabled — per-client per-channel switch
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_channels_enabled (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  channel         text NOT NULL,
  enabled         boolean DEFAULT false,
  configuration   jsonb DEFAULT '{}'::jsonb,    -- channel-specific (Twilio number, social handle, oauth token id)
  enabled_at      timestamptz,
  UNIQUE (client_id, channel)
);

DO $$ BEGIN
  ALTER TABLE agent_channels_enabled
    ADD CONSTRAINT ace_channel_check
    CHECK (channel IN ('voice','whatsapp','sms','email','instagram','facebook','linkedin','x','calendar','tiktok','youtube'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_ace_client ON agent_channels_enabled(client_id) WHERE enabled = true;

-- ─────────────────────────────────────────────────────────────────
-- 10. agent_schedules — quiet hours, caps, weekend/holiday rules
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_schedules (
  id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                     uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE UNIQUE,
  quiet_hours_start             time DEFAULT '21:00',
  quiet_hours_end               time DEFAULT '08:00',
  timezone                      text DEFAULT 'America/Toronto',
  max_actions_per_day           integer DEFAULT 100,
  max_actions_per_lead_per_week integer DEFAULT 3,
  weekend_active                boolean DEFAULT false,
  holidays_active               boolean DEFAULT false,
  custom_rules                  jsonb DEFAULT '{}'::jsonb,
  created_at                    timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────
-- 11. RLS — service_role-only on every agent_* table
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE agent_decisions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_actions            ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_conversations      ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_memory             ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_escalations        ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_performance        ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_costs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_personalities      ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_channels_enabled   ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_schedules          ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN CREATE POLICY ad_service_role  ON agent_decisions        FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY aa_service_role  ON agent_actions          FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY ac_service_role  ON agent_conversations    FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY am_service_role  ON agent_memory           FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY ae_service_role  ON agent_escalations      FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY ap_service_role  ON agent_performance      FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY acost_service    ON agent_costs            FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY aper_service     ON agent_personalities    FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY ace_service      ON agent_channels_enabled FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY ash_service      ON agent_schedules        FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 12. Verification (run after migration)
-- ─────────────────────────────────────────────────────────────────

-- SELECT tablename FROM pg_tables WHERE tablename LIKE 'agent_%' ORDER BY tablename;
-- SELECT extname FROM pg_extension WHERE extname = 'vector';

-- ═════════════════════════════════════════════════════════════════
-- ROLLBACK (commented — uncomment + run only to roll back)
-- ═════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS agent_schedules;
-- DROP TABLE IF EXISTS agent_channels_enabled;
-- DROP TABLE IF EXISTS agent_personalities;
-- DROP TABLE IF EXISTS agent_costs;
-- DROP TABLE IF EXISTS agent_performance;
-- DROP TABLE IF EXISTS agent_escalations;
-- DROP TABLE IF EXISTS agent_memory;
-- DROP TABLE IF EXISTS agent_conversations;
-- DROP TABLE IF EXISTS agent_actions;
-- DROP TABLE IF EXISTS agent_decisions;
-- DROP EXTENSION IF EXISTS vector;
