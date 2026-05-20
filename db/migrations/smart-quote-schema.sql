-- ══════════════════════════════════════════════════════════════════
-- Smart Quote schema (WS8 core)
-- ══════════════════════════════════════════════════════════════════
-- Multi-industry quote builder. Customers complete a vertical-specific
-- question flow; the engine matches answers to pricing rules + addons,
-- produces an estimate, optionally emails a PDF, and (in follow-up
-- commits) converts to onboarding.
--
-- Six tables, two helpers. No RLS — service_role from n8n only.
-- All cents-based money columns (integer); never store dollar floats.
--
-- Idempotent. Re-running `psql -f smart-quote-schema.sql` is safe.
-- ══════════════════════════════════════════════════════════════════

-- ─── 1. quote_templates ──────────────────────────────────────────
-- One row per industry. The `questions` JSONB drives the front-end
-- question flow. `pricing_basis` tells the engine which addons +
-- rules apply.
CREATE TABLE IF NOT EXISTS quote_templates (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  industry_slug     text NOT NULL UNIQUE,                    -- 'insurance_personal' / 'construction' / 'dental' / ...
  industry_name     text NOT NULL,
  vertical_id       text,                                     -- 'insurance' / 'moving' / null
  description       text,
  emoji             text,
  -- Question flow definition (array of question objects with
  --   { id, label, type:'text'|'number'|'select'|'multiselect'|'currency',
  --     options?, required, weight?, help? } )
  questions         jsonb NOT NULL DEFAULT '[]'::jsonb,
  -- Pricing basis: which strategy the engine applies
  pricing_basis     text NOT NULL DEFAULT 'tiered',           -- 'tiered' | 'volume' | 'custom' | 'flat'
  -- Base monthly subscription tier defaults (engine can override per-rule)
  base_starter_cents  integer NOT NULL DEFAULT 9900,          -- $99
  base_growth_cents   integer NOT NULL DEFAULT 29900,         -- $299
  base_scale_cents    integer NOT NULL DEFAULT 49900,         -- $499
  active            boolean NOT NULL DEFAULT true,
  sort_order        integer NOT NULL DEFAULT 100,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS qt_active_idx        ON quote_templates (active) WHERE active = true;
CREATE INDEX IF NOT EXISTS qt_vertical_idx      ON quote_templates (vertical_id) WHERE vertical_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS qt_industry_slug_idx ON quote_templates (industry_slug);

-- ─── 2. quote_pricing_rules ──────────────────────────────────────
-- Rules that adjust the base estimate based on answer values.
-- Example: industry=construction, condition={project_value_cents: gte 500000}
--   → addon_cents: +200000  (add $2000)
-- The engine evaluates ALL active rules for the template and sums
-- their effects.
CREATE TABLE IF NOT EXISTS quote_pricing_rules (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id       uuid NOT NULL REFERENCES quote_templates(id) ON DELETE CASCADE,
  rule_name         text NOT NULL,
  -- Match expression — JSON path → operator → value
  -- e.g. { "project_value_cents": { "op": "gte", "value": 50000000 } }
  conditions        jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- Effect: positive cents = surcharge, negative = discount
  adjust_cents      integer NOT NULL DEFAULT 0,
  -- Or percent (multiplied against base)
  adjust_percent    numeric(6,3) NOT NULL DEFAULT 0.0,
  description       text,
  active            boolean NOT NULL DEFAULT true,
  sort_order        integer NOT NULL DEFAULT 100,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS qpr_template_idx ON quote_pricing_rules (template_id) WHERE active = true;

-- ─── 3. quote_addons ─────────────────────────────────────────────
-- Modular options the customer can toggle on. Each addon has its
-- own price; multiple addons sum into the total.
CREATE TABLE IF NOT EXISTS quote_addons (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id       uuid NOT NULL REFERENCES quote_templates(id) ON DELETE CASCADE,
  addon_slug        text NOT NULL,
  addon_name        text NOT NULL,
  description       text,
  monthly_cents     integer NOT NULL DEFAULT 0,
  one_time_cents    integer NOT NULL DEFAULT 0,
  required          boolean NOT NULL DEFAULT false,
  active            boolean NOT NULL DEFAULT true,
  sort_order        integer NOT NULL DEFAULT 100,
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (template_id, addon_slug)
);

CREATE INDEX IF NOT EXISTS qa_template_idx ON quote_addons (template_id) WHERE active = true;

-- ─── 4. quote_drafts ─────────────────────────────────────────────
-- In-progress quotes. Customer fills out questions over time;
-- partial answers saved here. Becomes a completed quote on submit.
CREATE TABLE IF NOT EXISTS quote_drafts (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id         uuid NOT NULL REFERENCES quote_templates(id) ON DELETE CASCADE,
  industry_slug       text NOT NULL,                          -- denormalized for query speed
  client_id           uuid,                                    -- if Crystallux client originated it
  lead_id             uuid,                                    -- if associated with a lead
  email               text,                                    -- captured early; used for "save and resume"
  full_name           text,
  company             text,
  phone               text,
  -- Saved answers — same key set as template.questions[].id
  answers             jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- Live preview estimate computed on each save
  preview_total_cents integer,
  preview_monthly_cents integer,
  preview_one_time_cents integer,
  step                integer NOT NULL DEFAULT 0,             -- current question index
  status              text NOT NULL DEFAULT 'in_progress',    -- 'in_progress' | 'abandoned' | 'submitted'
  resume_token        text UNIQUE,                            -- for emailed resume links
  ip_address          inet,
  user_agent          text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  submitted_at        timestamptz
);

CREATE INDEX IF NOT EXISTS qd_status_idx        ON quote_drafts (status, updated_at DESC);
CREATE INDEX IF NOT EXISTS qd_email_idx         ON quote_drafts (email) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS qd_template_idx      ON quote_drafts (template_id);
CREATE INDEX IF NOT EXISTS qd_resume_token_idx  ON quote_drafts (resume_token) WHERE resume_token IS NOT NULL;
CREATE INDEX IF NOT EXISTS qd_client_idx        ON quote_drafts (client_id) WHERE client_id IS NOT NULL;

-- ─── 5. quote_completed ──────────────────────────────────────────
-- Final, submitted quotes. Immutable once written (engine + UI
-- never UPDATE this table). Generated from a draft via the
-- submit workflow.
CREATE TABLE IF NOT EXISTS quote_completed (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  draft_id            uuid REFERENCES quote_drafts(id) ON DELETE SET NULL,
  template_id         uuid NOT NULL REFERENCES quote_templates(id),
  industry_slug       text NOT NULL,
  client_id           uuid,
  lead_id             uuid,
  email               text NOT NULL,
  full_name           text,
  company             text,
  phone               text,
  -- Snapshot at time of quote (immutable)
  answers_snapshot    jsonb NOT NULL,
  rules_applied       jsonb NOT NULL DEFAULT '[]'::jsonb,     -- [{rule_id, rule_name, adjust_cents, adjust_percent}, ...]
  addons_selected     jsonb NOT NULL DEFAULT '[]'::jsonb,     -- [{addon_id, addon_slug, monthly_cents, one_time_cents}, ...]
  base_tier           text NOT NULL DEFAULT 'starter',        -- 'starter' | 'growth' | 'scale'
  base_monthly_cents  integer NOT NULL,
  total_monthly_cents integer NOT NULL,
  total_one_time_cents integer NOT NULL DEFAULT 0,
  total_first_year_cents integer NOT NULL,                    -- monthly*12 + one_time
  -- Lifecycle
  status              text NOT NULL DEFAULT 'open',           -- 'open' | 'sent' | 'viewed' | 'accepted' | 'declined' | 'expired'
  expires_at          timestamptz,
  -- Communication
  sent_at             timestamptz,
  viewed_at           timestamptz,
  pdf_url             text,                                    -- R2 / blob URL of generated PDF
  -- Conversion
  accepted_at         timestamptz,
  declined_at         timestamptz,
  decline_reason      text,
  converted_to_onboarding_at timestamptz,
  converted_to_client_id uuid REFERENCES clients(id) ON DELETE SET NULL,
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS qc_status_idx        ON quote_completed (status, created_at DESC);
CREATE INDEX IF NOT EXISTS qc_email_idx         ON quote_completed (email);
CREATE INDEX IF NOT EXISTS qc_industry_idx      ON quote_completed (industry_slug);
CREATE INDEX IF NOT EXISTS qc_client_idx        ON quote_completed (client_id) WHERE client_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS qc_expires_at_idx    ON quote_completed (expires_at) WHERE status IN ('open', 'sent', 'viewed');

-- ─── 6. quote_follow_ups ─────────────────────────────────────────
-- Reminder sequence for quotes that haven't been accepted.
-- Workflow `clx-smart-quote-followup-v1` walks this table on a cron.
CREATE TABLE IF NOT EXISTS quote_follow_ups (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id            uuid NOT NULL REFERENCES quote_completed(id) ON DELETE CASCADE,
  step                integer NOT NULL,                       -- 1, 2, 3 ...
  scheduled_at        timestamptz NOT NULL,
  message_template    text,                                    -- Postmark template alias or inline subject:body
  status              text NOT NULL DEFAULT 'pending',        -- 'pending' | 'sent' | 'skipped' | 'cancelled'
  sent_at             timestamptz,
  postmark_message_id text,
  result_event        text,                                    -- 'opened' | 'clicked' | 'no_response'
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (quote_id, step)
);

CREATE INDEX IF NOT EXISTS qfu_due_idx ON quote_follow_ups (status, scheduled_at) WHERE status = 'pending';

-- ─── Trigger: keep quote_drafts.updated_at fresh ─────────────────
CREATE OR REPLACE FUNCTION quote_drafts_touch() RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS quote_drafts_touch_trigger ON quote_drafts;
CREATE TRIGGER quote_drafts_touch_trigger
  BEFORE UPDATE ON quote_drafts
  FOR EACH ROW
  EXECUTE FUNCTION quote_drafts_touch();

-- ─── Seed: Insurance Personal Lines (first industry) ─────────────
-- Inserted with ON CONFLICT DO NOTHING so re-running is safe.
INSERT INTO quote_templates (id, industry_slug, industry_name, vertical_id, description, emoji, questions, pricing_basis, base_starter_cents, base_growth_cents, base_scale_cents, sort_order) VALUES (
  '00000000-1111-4001-a000-000000000001',
  'insurance_personal',
  'Insurance — Personal Lines',
  'insurance',
  'For independent brokers and small agencies selling personal-lines insurance (auto, home, tenant). Estimate monthly Crystallux platform cost based on advisor headcount + lead volume.',
  '🛡️',
  $q$[
    {
      "id": "advisor_count",
      "label": "How many licensed advisors are on your team?",
      "type": "number",
      "required": true,
      "weight": 2,
      "help": "Including yourself. Sub-agents and contracted advisors count."
    },
    {
      "id": "monthly_lead_volume",
      "label": "How many new leads do you handle per month today?",
      "type": "number",
      "required": true,
      "weight": 2,
      "help": "Rough average across all channels."
    },
    {
      "id": "carriers_appointed",
      "label": "How many carriers are you appointed with?",
      "type": "number",
      "required": true,
      "weight": 1
    },
    {
      "id": "current_crm",
      "label": "What CRM / management system do you use today?",
      "type": "select",
      "options": [
        "None / spreadsheets",
        "Applied Epic",
        "EZLynx",
        "HawkSoft",
        "AMS360",
        "Other"
      ],
      "required": true,
      "weight": 1
    },
    {
      "id": "calling_volume",
      "label": "Do you do outbound calling?",
      "type": "select",
      "options": [
        "No",
        "Light (under 50/week)",
        "Moderate (50-200/week)",
        "Heavy (200+/week)"
      ],
      "required": true,
      "weight": 1
    },
    {
      "id": "want_video_outreach",
      "label": "Interested in AI video personalization?",
      "type": "select",
      "options": [
        "Yes - high priority",
        "Maybe - show me a demo",
        "Not now"
      ],
      "required": false,
      "weight": 0
    }
  ]$q$::jsonb,
  'tiered', 9900, 29900, 49900, 10
)
ON CONFLICT (industry_slug) DO NOTHING;

-- Pricing rules for Insurance Personal Lines
INSERT INTO quote_pricing_rules (template_id, rule_name, conditions, adjust_cents, adjust_percent, description, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000001', 'Solo advisor base',     '{"advisor_count":{"op":"lte","value":1}}'::jsonb,    0,    0.0,  'Stays on starter tier', 10),
  ('00000000-1111-4001-a000-000000000001', 'Small team (2-5)',      '{"advisor_count":{"op":"between","value":[2,5]}}'::jsonb, 20000, 0.0, 'Per-seat add', 20),
  ('00000000-1111-4001-a000-000000000001', 'Mid team (6-15)',       '{"advisor_count":{"op":"between","value":[6,15]}}'::jsonb, 50000, 0.0, 'Mid team needs growth tier features', 30),
  ('00000000-1111-4001-a000-000000000001', 'High lead volume',      '{"monthly_lead_volume":{"op":"gte","value":500}}'::jsonb, 30000, 0.0, 'Volume API surcharge', 40),
  ('00000000-1111-4001-a000-000000000001', 'Heavy calling volume',  '{"calling_volume":{"op":"eq","value":"Heavy (200+/week)"}}'::jsonb, 20000, 0.0, 'Voice / Vapi metered surcharge', 50)
ON CONFLICT DO NOTHING;

-- Addons for Insurance Personal Lines
INSERT INTO quote_addons (template_id, addon_slug, addon_name, description, monthly_cents, one_time_cents, sort_order) VALUES
  ('00000000-1111-4001-a000-000000000001', 'ai_video',         'AI personalized video',           'HeyGen-rendered greeting + custom landing per lead',          15000, 0,      10),
  ('00000000-1111-4001-a000-000000000001', 'voice_outbound',   'Outbound AI voice',               'Vapi-based outbound calling with transcripts + analysis',     19900, 0,      20),
  ('00000000-1111-4001-a000-000000000001', 'compliance_pack',  'Compliance + audit log',          'FSRA-ready audit trail, license verification, E&O tracking',  9900,  0,      30),
  ('00000000-1111-4001-a000-000000000001', 'white_label',      'White-label branding',            'Your domain, your logo, your colours on advisor portal',      14900, 99900,  40),
  ('00000000-1111-4001-a000-000000000001', 'pdf_quote_gen',    'Customer-facing quote PDFs',      'Auto-generate branded quote PDFs and email to prospects',     6900,  0,      50)
ON CONFLICT DO NOTHING;

-- ─── Grants (service_role bypasses RLS; no RLS here anyway) ───────
GRANT SELECT, INSERT, UPDATE, DELETE ON quote_templates       TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON quote_pricing_rules   TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON quote_addons          TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON quote_drafts          TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON quote_completed       TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON quote_follow_ups      TO service_role;

-- ══════════════════════════════════════════════════════════════════
-- Verify
-- ══════════════════════════════════════════════════════════════════
--   SELECT industry_slug, industry_name, sort_order FROM quote_templates;
--   SELECT count(*) FROM quote_pricing_rules;
--   SELECT count(*) FROM quote_addons;
-- ══════════════════════════════════════════════════════════════════
