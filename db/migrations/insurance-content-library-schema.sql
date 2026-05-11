-- ══════════════════════════════════════════════════════════════════
-- Insurance Content Library (Layer 2 — Insurance MGA)
-- ══════════════════════════════════════════════════════════════════
-- Per-vertical content templates for the insurance vertical. The
-- universal content marketing schema (content_topics, content_videos,
-- content_publications, content_engagement) is Layer 1 and serves
-- every vertical. THIS table adds insurance-flavoured templates that
-- the content topic generator can pull from when client.vertical='insurance'.
--
-- vertical_id is mandatory + defaulted to 'insurance'.
--
-- Additive only. Idempotent.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS insurance_content_templates (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id         text NOT NULL DEFAULT 'insurance',
  topic_category      text NOT NULL,    -- life_insurance_basics | critical_illness | disability | estate_planning | business_insurance | mortgage_protection | retirement | health_benefits
  topic_title         text NOT NULL,
  topic_summary       text,
  target_audience     text,             -- young_families | business_owners | high_net_worth | seniors | first_time_buyers
  script_template     text,
  call_to_action      text,
  compliance_notes    text,
  educational_value   text,
  seo_keywords        text[] DEFAULT ARRAY[]::text[],
  is_active           boolean DEFAULT true,
  created_at          timestamptz DEFAULT now(),
  updated_at          timestamptz DEFAULT now(),
  UNIQUE (vertical_id, topic_title)
);

CREATE INDEX IF NOT EXISTS idx_ict_category
  ON insurance_content_templates(vertical_id, topic_category)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_ict_audience
  ON insurance_content_templates(vertical_id, target_audience)
  WHERE is_active = true;

-- ══════════════════════════════════════════════════════════════════
-- Rollback
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS insurance_content_templates;
