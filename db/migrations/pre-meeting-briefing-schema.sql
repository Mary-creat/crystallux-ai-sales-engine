-- ══════════════════════════════════════════════════════════════════
-- Pre-Meeting Briefing AI (Layer 1 — core engine)
-- ══════════════════════════════════════════════════════════════════
-- F6 closing-pitch enhancement. AI prepares each team member 1-2
-- hours before every meeting with client context, talking points,
-- anticipated objections, recommended products, closing techniques.
--
-- LAYER 1 PURITY:
--   - No vertical_id column (universal core).
--   - No insurance / mga / advisor terminology.
--   - meeting_type / briefing_content keys are vertical-agnostic.
--
-- Additive, idempotent.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS pre_meeting_briefings (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  lead_id               uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  meeting_time          timestamptz NOT NULL,
  meeting_type          text,
  briefing_content      jsonb NOT NULL DEFAULT '{}'::jsonb,
  generated_at          timestamptz DEFAULT now(),
  viewed_at             timestamptz,
  used_at               timestamptz,
  effectiveness_score   numeric(5,2),
  effectiveness_notes   text,
  generator_source      text DEFAULT 'claude',
  created_at            timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE pre_meeting_briefings
    ADD CONSTRAINT pmb_meeting_type_check
    CHECK (meeting_type IN ('discovery_call','product_presentation','closing_meeting','review','follow_up'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_pmb_user_upcoming
  ON pre_meeting_briefings(user_id, meeting_time)
  WHERE viewed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_pmb_lead
  ON pre_meeting_briefings(lead_id, meeting_time DESC);

CREATE INDEX IF NOT EXISTS idx_pmb_pending_generation
  ON pre_meeting_briefings(meeting_time)
  WHERE briefing_content = '{}'::jsonb;

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS pre_meeting_briefings;
