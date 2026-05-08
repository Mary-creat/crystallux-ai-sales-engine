-- ══════════════════════════════════════════════════════════════════
-- Behavioral Intelligence schema (Phase B.13)
-- ══════════════════════════════════════════════════════════════════
-- Spec: docs/architecture/OPERATIONS_HANDBOOK.md §35
-- Universal multi-vertical: every table carries niche_name so the
-- same schema serves insurance, mortgage, real estate, dental,
-- construction, consulting, agencies, financial advisors, etc.
-- Per-vertical tuning happens in the seed archetype library, not
-- in the schema.
--
-- Additive only. Idempotent (IF NOT EXISTS / ON CONFLICT). Rollback
-- block at the bottom (commented).
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. behavioral_signals — per-lead, per-event signal feed
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS behavioral_signals (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id              uuid REFERENCES leads(id) ON DELETE CASCADE,
  client_id            uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  signal_type          text NOT NULL,        -- 'birthday', 'new_hire', 'policy_renewal', 'team_win', etc.
  signal_category      text NOT NULL,        -- one of the 10 categories
  niche_name           text,                 -- 'insurance_broker', 'real_estate', 'mortgage_broker', etc.
  signal_data          jsonb NOT NULL DEFAULT '{}'::jsonb,
  signal_source        text NOT NULL DEFAULT 'public',   -- 'public' | 'paid' | 'lead_supplied' | 'advisor_supplied'
  source_url           text,
  relevance_score      integer,              -- 0-100; null until classifier runs
  sensitivity_level    text DEFAULT 'low',   -- 'low' | 'medium' | 'high'
  consent_status       text DEFAULT 'inferred',  -- 'inferred' | 'explicit' | 'withdrawn'
  detected_at          timestamptz DEFAULT now(),
  expires_at           timestamptz,
  acted_on             boolean DEFAULT false,
  acted_on_at          timestamptz,
  acted_by_agent_id    uuid,
  outreach_log_id      uuid,
  archived             boolean DEFAULT false
);

DO $$ BEGIN
  ALTER TABLE behavioral_signals
    ADD CONSTRAINT bs_category_check
    CHECK (signal_category IN ('personal','business','industry','sports','news','social','vertical_specific','financial','geographic','calendar'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE behavioral_signals
    ADD CONSTRAINT bs_sensitivity_check
    CHECK (sensitivity_level IN ('low','medium','high'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE behavioral_signals
    ADD CONSTRAINT bs_source_check
    CHECK (signal_source IN ('public','paid','lead_supplied','advisor_supplied'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE behavioral_signals
    ADD CONSTRAINT bs_consent_check
    CHECK (consent_status IN ('inferred','explicit','withdrawn'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_bs_lead_active     ON behavioral_signals(lead_id, detected_at DESC) WHERE archived = false;
CREATE INDEX IF NOT EXISTS idx_bs_client_unread   ON behavioral_signals(client_id, detected_at DESC) WHERE acted_on = false AND archived = false;
CREATE INDEX IF NOT EXISTS idx_bs_type            ON behavioral_signals(signal_type);
CREATE INDEX IF NOT EXISTS idx_bs_category        ON behavioral_signals(signal_category);
CREATE INDEX IF NOT EXISTS idx_bs_niche           ON behavioral_signals(niche_name);
CREATE INDEX IF NOT EXISTS idx_bs_unclassified    ON behavioral_signals(detected_at DESC) WHERE relevance_score IS NULL;

-- ─────────────────────────────────────────────────────────────────
-- 2. signal_archetypes — per-vertical compound trigger archetypes
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS signal_archetypes (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  niche_name               text NOT NULL,
  archetype_name           text NOT NULL,
  description              text,
  trigger_signals          jsonb NOT NULL DEFAULT '[]'::jsonb,
  optional_signals         jsonb DEFAULT '[]'::jsonb,
  recommended_action       text,                              -- 'send_email' | 'send_sms' | 'send_whatsapp' | 'send_video' | 'phone_call' | 'wait' | 'queue_for_review'
  recommended_channel      text,
  message_template_id      uuid,                              -- FK to closing_scripts.id (vertical script library, §28)
  message_template_inline  text,                              -- inline template if not using closing_scripts
  sensitivity_floor        text DEFAULT 'low',                -- minimum sensitivity at which this archetype fires
  cool_down_days           integer DEFAULT 30,
  conversion_rate          numeric(5,2),                      -- learning loop, recomputed by clx-behavioral-learning-loop-v1
  acted_on_count           integer DEFAULT 0,
  fired_count              integer DEFAULT 0,
  active                   boolean DEFAULT true,
  created_at               timestamptz DEFAULT now(),
  updated_at               timestamptz DEFAULT now(),
  UNIQUE (niche_name, archetype_name)
);

CREATE INDEX IF NOT EXISTS idx_sa_niche  ON signal_archetypes(niche_name) WHERE active = true;

-- ─────────────────────────────────────────────────────────────────
-- 3. behavioral_triggers — fired triggers per lead
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS behavioral_triggers (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id                  uuid REFERENCES leads(id) ON DELETE CASCADE,
  client_id                uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  archetype_id             uuid REFERENCES signal_archetypes(id),
  contributing_signals     uuid[] DEFAULT ARRAY[]::uuid[],
  composite_score          integer,
  status                   text DEFAULT 'pending',            -- 'pending' | 'queued' | 'sent' | 'acted' | 'rejected' | 'expired'
  recommended_action       text,
  generated_message        text,
  generated_message_lang   text DEFAULT 'en',
  acted_on_at              timestamptz,
  outcome                  text,                              -- 'no_response' | 'engaged' | 'meeting_booked' | 'closed' | 'unsubscribed'
  outcome_recorded_at      timestamptz,
  created_at               timestamptz DEFAULT now(),
  expires_at               timestamptz
);

DO $$ BEGIN
  ALTER TABLE behavioral_triggers
    ADD CONSTRAINT bt_status_check
    CHECK (status IN ('pending','queued','sent','acted','rejected','expired'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_bt_lead     ON behavioral_triggers(lead_id);
CREATE INDEX IF NOT EXISTS idx_bt_client   ON behavioral_triggers(client_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bt_status   ON behavioral_triggers(status, created_at DESC);

-- ─────────────────────────────────────────────────────────────────
-- 4. signal_subscriptions — per-client opt-in matrix
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS signal_subscriptions (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                   uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  signal_category             text NOT NULL,
  enabled                     boolean DEFAULT true,
  sensitivity_threshold       integer DEFAULT 50,           -- only fire archetypes with composite_score >= this
  sensitivity_ceiling         text DEFAULT 'medium',       -- low | medium | high — caps auto-send
  channels_allowed            text[] DEFAULT ARRAY['email']::text[],
  cooldown_days               integer DEFAULT 7,
  daily_signal_cap_per_lead   integer DEFAULT 3,
  notify_role                 text DEFAULT 'client',
  consent_disclosure_version  text,
  created_at                  timestamptz DEFAULT now(),
  updated_at                  timestamptz DEFAULT now(),
  UNIQUE (client_id, signal_category)
);

DO $$ BEGIN
  ALTER TABLE signal_subscriptions
    ADD CONSTRAINT ss_category_check
    CHECK (signal_category IN ('personal','business','industry','sports','news','social','vertical_specific','financial','geographic','calendar'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE signal_subscriptions
    ADD CONSTRAINT ss_sensitivity_ceiling_check
    CHECK (sensitivity_ceiling IN ('low','medium','high'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_ss_client ON signal_subscriptions(client_id) WHERE enabled = true;

-- ─────────────────────────────────────────────────────────────────
-- 5. clients tier flag (additive)
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE clients ADD COLUMN IF NOT EXISTS behavioral_intel_enabled    boolean DEFAULT false;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS behavioral_intel_enabled_at timestamptz;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS behavioral_intel_price      numeric(10,2);

-- ─────────────────────────────────────────────────────────────────
-- 6. RLS — service_role-only on every table (defence in depth)
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE behavioral_signals      ENABLE ROW LEVEL SECURITY;
ALTER TABLE signal_archetypes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE behavioral_triggers     ENABLE ROW LEVEL SECURITY;
ALTER TABLE signal_subscriptions    ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY behavioral_signals_service_role     ON behavioral_signals     FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY signal_archetypes_service_role      ON signal_archetypes      FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY behavioral_triggers_service_role    ON behavioral_triggers    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY signal_subscriptions_service_role   ON signal_subscriptions   FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 7. RPCs (4) — SECURITY DEFINER, service_role-only EXECUTE
-- ─────────────────────────────────────────────────────────────────

-- 7.1 record_behavioral_signal — consent-gated insert
CREATE OR REPLACE FUNCTION record_behavioral_signal(
  p_lead_id            uuid,
  p_client_id          uuid,
  p_signal_type        text,
  p_signal_category    text,
  p_niche_name         text,
  p_signal_data        jsonb,
  p_signal_source      text,
  p_relevance_score    integer DEFAULT NULL,
  p_sensitivity_level  text DEFAULT 'low',
  p_expires_at         timestamptz DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription   record;
  v_signal_id      uuid;
BEGIN
  -- Consent gate. Returns NULL silently if the client hasn't subscribed
  -- to this category — caller should not treat NULL as an error.
  SELECT * INTO v_subscription
    FROM signal_subscriptions
    WHERE client_id = p_client_id
      AND signal_category = p_signal_category
      AND enabled = true
    LIMIT 1;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  INSERT INTO behavioral_signals (
    lead_id, client_id, signal_type, signal_category, niche_name,
    signal_data, signal_source, relevance_score, sensitivity_level, expires_at
  ) VALUES (
    p_lead_id, p_client_id, p_signal_type, p_signal_category, p_niche_name,
    COALESCE(p_signal_data, '{}'::jsonb), p_signal_source, p_relevance_score,
    p_sensitivity_level, p_expires_at
  ) RETURNING id INTO v_signal_id;

  RETURN v_signal_id;
END;
$$;

REVOKE ALL ON FUNCTION record_behavioral_signal(uuid,uuid,text,text,text,jsonb,text,integer,text,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION record_behavioral_signal(uuid,uuid,text,text,text,jsonb,text,integer,text,timestamptz) TO service_role;

-- 7.2 match_signal_to_trigger — return ranked archetypes for a lead
CREATE OR REPLACE FUNCTION match_signal_to_trigger(
  p_lead_id   uuid,
  p_signal_id uuid
) RETURNS TABLE (
  archetype_id        uuid,
  archetype_name      text,
  composite_score     integer,
  recommended_action  text,
  recommended_channel text,
  contributing_signals uuid[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lead       record;
  v_signal     record;
  v_window     timestamptz := now() - interval '14 days';
BEGIN
  SELECT * INTO v_lead   FROM leads             WHERE id = p_lead_id   LIMIT 1;
  SELECT * INTO v_signal FROM behavioral_signals WHERE id = p_signal_id LIMIT 1;
  IF NOT FOUND OR v_lead IS NULL THEN RETURN; END IF;

  -- Per-vertical archetype match. Find archetypes for the lead's niche
  -- whose required trigger_signals all appear in this lead's recent
  -- (last 14 days) un-acted-on signals.
  RETURN QUERY
  WITH recent_signals AS (
    SELECT id, signal_type
      FROM behavioral_signals
      WHERE lead_id = p_lead_id
        AND archived = false
        AND acted_on = false
        AND detected_at >= v_window
  ),
  matched AS (
    SELECT
      a.id           AS archetype_id,
      a.archetype_name,
      a.recommended_action,
      a.recommended_channel,
      a.conversion_rate,
      ARRAY(
        SELECT rs.id FROM recent_signals rs
          WHERE rs.signal_type IN (
            SELECT jsonb_array_elements_text(a.trigger_signals)
          )
      ) AS contributing
    FROM signal_archetypes a
    WHERE a.active = true
      AND a.niche_name = v_lead.niche_name
      AND (
        SELECT count(*) FROM jsonb_array_elements_text(a.trigger_signals) ts
          WHERE ts IN (SELECT signal_type FROM recent_signals)
      ) = jsonb_array_length(a.trigger_signals)
  )
  SELECT
    m.archetype_id,
    m.archetype_name,
    LEAST(100, COALESCE(50 + array_length(m.contributing, 1) * 15, 50)) AS composite_score,
    m.recommended_action,
    m.recommended_channel,
    m.contributing
  FROM matched m
  ORDER BY m.conversion_rate DESC NULLS LAST, array_length(m.contributing, 1) DESC
  LIMIT 5;
END;
$$;

REVOKE ALL ON FUNCTION match_signal_to_trigger(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION match_signal_to_trigger(uuid,uuid) TO service_role;

-- 7.3 mark_signal_acted_on — close the loop
CREATE OR REPLACE FUNCTION mark_signal_acted_on(
  p_signal_id      uuid,
  p_agent_id       uuid,
  p_outreach_log_id uuid DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE behavioral_signals
    SET acted_on        = true,
        acted_on_at     = now(),
        acted_by_agent_id = p_agent_id,
        outreach_log_id = p_outreach_log_id
    WHERE id = p_signal_id;
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION mark_signal_acted_on(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mark_signal_acted_on(uuid,uuid,uuid) TO service_role;

-- 7.4 enable_behavioral_intelligence — flip the per-client tier
CREATE OR REPLACE FUNCTION enable_behavioral_intelligence(
  p_client_id     uuid,
  p_monthly_price numeric DEFAULT 1500
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE clients
    SET behavioral_intel_enabled    = true,
        behavioral_intel_enabled_at = now(),
        behavioral_intel_price      = p_monthly_price
    WHERE id = p_client_id;

  -- Seed default category subscriptions (low sensitivity ceiling, queue mode).
  -- Mary tunes per-client after the fact.
  INSERT INTO signal_subscriptions (client_id, signal_category, enabled, sensitivity_ceiling, channels_allowed)
    SELECT p_client_id, cat, true, 'low', ARRAY['email']
      FROM (VALUES
        ('personal'),('business'),('vertical_specific'),('calendar')
      ) AS c(cat)
    ON CONFLICT (client_id, signal_category) DO NOTHING;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION enable_behavioral_intelligence(uuid,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION enable_behavioral_intelligence(uuid,numeric) TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- 8. Verification queries (run manually after migration)
-- ─────────────────────────────────────────────────────────────────

-- SELECT count(*) AS bs_table FROM behavioral_signals;
-- SELECT count(*) AS sa_table FROM signal_archetypes;
-- SELECT count(*) AS bt_table FROM behavioral_triggers;
-- SELECT count(*) AS ss_table FROM signal_subscriptions;
-- SELECT proname FROM pg_proc WHERE proname IN ('record_behavioral_signal','match_signal_to_trigger','mark_signal_acted_on','enable_behavioral_intelligence');

-- ═════════════════════════════════════════════════════════════════
-- ROLLBACK (commented — uncomment + run only if rolling back)
-- ═════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS enable_behavioral_intelligence(uuid,numeric);
-- DROP FUNCTION IF EXISTS mark_signal_acted_on(uuid,uuid,uuid);
-- DROP FUNCTION IF EXISTS match_signal_to_trigger(uuid,uuid);
-- DROP FUNCTION IF EXISTS record_behavioral_signal(uuid,uuid,text,text,text,jsonb,text,integer,text,timestamptz);
-- DROP TABLE IF EXISTS signal_subscriptions;
-- DROP TABLE IF EXISTS behavioral_triggers;
-- DROP TABLE IF EXISTS signal_archetypes;
-- DROP TABLE IF EXISTS behavioral_signals;
-- ALTER TABLE clients DROP COLUMN IF EXISTS behavioral_intel_enabled;
-- ALTER TABLE clients DROP COLUMN IF EXISTS behavioral_intel_enabled_at;
-- ALTER TABLE clients DROP COLUMN IF EXISTS behavioral_intel_price;
