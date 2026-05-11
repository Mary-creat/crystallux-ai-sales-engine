-- ══════════════════════════════════════════════════════════════════
-- F7 Universal Lead Distribution (Layer 1 — core engine)
-- ══════════════════════════════════════════════════════════════════
-- Closes the F7 gap surfaced by docs/audit/2026-05-11-feature-audit.md.
-- Provides round-robin / geographic / capacity-aware / skill-match /
-- priority-queue assignment of leads to team members.
--
-- LAYER 1 PURITY:
--   - No vertical_id column (universal core).
--   - No insurance / mga / advisor terminology in column names.
--   - Uses universal terms: team_member, user, lead.
--
-- Hand-off contract with clx-campaign-router-v2 (PROTECTED, no mods):
--   - campaign-router sets lead_status='Campaign Assigned' + preferred_channel.
--   - clx-lead-distribute-v1 polls those rows where assigned_advisor_id IS NULL.
--
-- Additive, idempotent. Rollback block commented at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. lead_distribution_rules — per-client rules engine
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS lead_distribution_rules (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  rule_name       text NOT NULL,
  rule_type       text NOT NULL,                        -- round_robin | geographic | capacity_aware | skill_match | priority_queue
  config          jsonb NOT NULL DEFAULT '{}'::jsonb,   -- rule-specific knobs (eg postal_prefix_map, skill_weights)
  active          boolean DEFAULT true,
  priority        integer DEFAULT 100,                  -- lower = evaluated first
  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now(),
  UNIQUE (client_id, rule_name)
);

DO $$ BEGIN
  ALTER TABLE lead_distribution_rules
    ADD CONSTRAINT ldr_type_check
    CHECK (rule_type IN ('round_robin','geographic','capacity_aware','skill_match','priority_queue'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_ldr_client_priority
  ON lead_distribution_rules(client_id, priority)
  WHERE active = true;

-- ─────────────────────────────────────────────────────────────────
-- 2. team_member_preferences — opt-in capacity + zone preferences
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS team_member_preferences (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                uuid NOT NULL REFERENCES team_members(id) ON DELETE CASCADE,
  is_accepting_leads     boolean DEFAULT true,
  daily_capacity         integer DEFAULT 20,
  weekly_capacity        integer DEFAULT 80,
  preferred_zones        jsonb DEFAULT '[]'::jsonb,     -- array of postal_code prefixes ['M5V','M4Y',...]
  preferred_lead_types   jsonb DEFAULT '[]'::jsonb,     -- array of lead_segment values
  skills                 jsonb DEFAULT '[]'::jsonb,     -- array of skill tags for skill_match rules
  out_of_office_until    timestamptz,
  last_assigned_at       timestamptz,
  created_at             timestamptz DEFAULT now(),
  updated_at             timestamptz DEFAULT now(),
  UNIQUE (user_id)
);

CREATE INDEX IF NOT EXISTS idx_tmp_accepting
  ON team_member_preferences(user_id)
  WHERE is_accepting_leads = true;

-- ─────────────────────────────────────────────────────────────────
-- 3. lead_assignments — append-only history of every assignment
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS lead_assignments (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id             uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  assigned_user_id    uuid NOT NULL REFERENCES team_members(id),
  rule_id             uuid REFERENCES lead_distribution_rules(id),
  assigned_at         timestamptz DEFAULT now(),
  unassigned_at       timestamptz,
  unassign_reason     text,
  assignment_method   text NOT NULL DEFAULT 'auto',     -- auto | manual | self_claim | reshuffle
  created_at          timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE lead_assignments
    ADD CONSTRAINT la_method_check
    CHECK (assignment_method IN ('auto','manual','self_claim','reshuffle'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_la_lead_active
  ON lead_assignments(lead_id, assigned_at DESC)
  WHERE unassigned_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_la_user_active
  ON lead_assignments(assigned_user_id, assigned_at DESC)
  WHERE unassigned_at IS NULL;

-- ─────────────────────────────────────────────────────────────────
-- 4. team_capacity_log — daily rollup for capacity_aware decisions
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS team_capacity_log (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  uuid NOT NULL REFERENCES team_members(id) ON DELETE CASCADE,
  log_date                 date NOT NULL,
  leads_assigned_today     integer DEFAULT 0,
  leads_capacity_today     integer DEFAULT 0,
  utilization_pct          numeric(5,2) GENERATED ALWAYS AS (
                             CASE WHEN leads_capacity_today > 0
                                  THEN (leads_assigned_today * 100.0 / leads_capacity_today)
                                  ELSE 0 END
                           ) STORED,
  created_at               timestamptz DEFAULT now(),
  UNIQUE (user_id, log_date)
);

CREATE INDEX IF NOT EXISTS idx_tcl_date
  ON team_capacity_log(log_date DESC, utilization_pct);

-- ─────────────────────────────────────────────────────────────────
-- 5. Extend leads with assignment columns (idempotent — column may
-- already exist from insurance-mga-operations-schema.sql:350).
-- This makes Layer 1 self-contained going forward.
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS assigned_advisor_id  uuid REFERENCES team_members(id),
  ADD COLUMN IF NOT EXISTS assigned_at          timestamptz,
  ADD COLUMN IF NOT EXISTS assignment_method    text;

CREATE INDEX IF NOT EXISTS idx_leads_unassigned_campaign
  ON leads(client_id, lead_status, preferred_channel)
  WHERE assigned_advisor_id IS NULL AND lead_status = 'Campaign Assigned';

-- ─────────────────────────────────────────────────────────────────
-- 6. RPC: assign_lead_to_user — atomic claim with capacity check
-- ─────────────────────────────────────────────────────────────────
-- Used by clx-lead-self-claim-v1 and clx-lead-distribute-v1.
-- Returns assignment_id on success, null if user at capacity or
-- lead already assigned.
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION assign_lead_to_user(
  p_lead_id      uuid,
  p_user_id      uuid,
  p_rule_id      uuid,
  p_method       text
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_assignment_id  uuid;
  v_today          date := current_date;
  v_used           integer;
  v_cap            integer;
BEGIN
  -- Lock the lead row to prevent double-claim.
  PERFORM 1 FROM leads WHERE id = p_lead_id AND assigned_advisor_id IS NULL FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Capacity check (skipped if no preferences row).
  SELECT COALESCE(leads_assigned_today, 0), COALESCE(leads_capacity_today, 0)
    INTO v_used, v_cap
    FROM team_capacity_log
   WHERE user_id = p_user_id AND log_date = v_today;

  IF v_cap > 0 AND v_used >= v_cap THEN
    RETURN NULL;
  END IF;

  -- Insert assignment row.
  INSERT INTO lead_assignments (lead_id, assigned_user_id, rule_id, assignment_method)
       VALUES (p_lead_id, p_user_id, p_rule_id, p_method)
    RETURNING id INTO v_assignment_id;

  -- Mark lead.
  UPDATE leads
     SET assigned_advisor_id = p_user_id,
         assigned_at         = now(),
         assignment_method   = p_method
   WHERE id = p_lead_id;

  -- Bump capacity log (upsert).
  INSERT INTO team_capacity_log (user_id, log_date, leads_assigned_today, leads_capacity_today)
       VALUES (p_user_id, v_today, 1, COALESCE((SELECT daily_capacity FROM team_member_preferences WHERE user_id = p_user_id), 20))
  ON CONFLICT (user_id, log_date)
  DO UPDATE SET leads_assigned_today = team_capacity_log.leads_assigned_today + 1;

  -- Bump last_assigned_at on the preferences row (for round-robin).
  UPDATE team_member_preferences
     SET last_assigned_at = now()
   WHERE user_id = p_user_id;

  RETURN v_assignment_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────
-- 7. RPC: unassign_lead — used by reassign workflow
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION unassign_lead(
  p_lead_id   uuid,
  p_reason    text
) RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE lead_assignments
     SET unassigned_at   = now(),
         unassign_reason = p_reason
   WHERE lead_id = p_lead_id
     AND unassigned_at IS NULL;

  UPDATE leads
     SET assigned_advisor_id = NULL,
         assigned_at         = NULL,
         assignment_method   = NULL
   WHERE id = p_lead_id;

  RETURN true;
END;
$$;

-- ─────────────────────────────────────────────────────────────────
-- 8. RPC: distribute_pending_leads — bulk round-robin assignment
-- ─────────────────────────────────────────────────────────────────
-- Picks the highest-priority active distribution rule for the client.
-- For 'round_robin' rule_type: assigns the next N pending leads to
-- eligible team members ordered by last_assigned_at NULLS FIRST.
-- Other rule_types fall through to round_robin in v1 (full matrix
-- evaluation can be added later — see LEAD_DISTRIBUTION_ARCHITECTURE.md).
-- Returns the count of leads actually assigned.
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION distribute_pending_leads(
  p_client_id    uuid,
  p_lead_id      uuid DEFAULT NULL,            -- if set, distribute this one lead only
  p_max_leads    integer DEFAULT 50
) RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_rule         lead_distribution_rules%ROWTYPE;
  v_lead         RECORD;
  v_user_id      uuid;
  v_assignment   uuid;
  v_count        integer := 0;
BEGIN
  -- Pick top-priority active rule for the client.
  SELECT * INTO v_rule
    FROM lead_distribution_rules
   WHERE client_id = p_client_id AND active = true
   ORDER BY priority
   LIMIT 1;

  -- Loop through pending leads.
  FOR v_lead IN
    SELECT id
      FROM leads
     WHERE client_id = p_client_id
       AND assigned_advisor_id IS NULL
       AND (lead_status = 'Campaign Assigned' OR p_lead_id IS NOT NULL)
       AND (p_lead_id IS NULL OR id = p_lead_id)
     ORDER BY created_at
     LIMIT p_max_leads
  LOOP
    -- Find the next eligible user via round-robin: NULL last_assigned_at first,
    -- then oldest assignment time. Filtered by is_accepting_leads + out_of_office.
    SELECT tmp.user_id INTO v_user_id
      FROM team_member_preferences tmp
      JOIN team_members tm ON tm.id = tmp.user_id
      LEFT JOIN team_capacity_log tcl
        ON tcl.user_id = tmp.user_id AND tcl.log_date = current_date
     WHERE tm.client_id = p_client_id
       AND tmp.is_accepting_leads = true
       AND (tmp.out_of_office_until IS NULL OR tmp.out_of_office_until < now())
       AND COALESCE(tcl.leads_assigned_today, 0) <
           COALESCE(tcl.leads_capacity_today, tmp.daily_capacity, 20)
     ORDER BY tmp.last_assigned_at ASC NULLS FIRST
     LIMIT 1;

    IF v_user_id IS NULL THEN
      EXIT;  -- no available users — stop here
    END IF;

    v_assignment := assign_lead_to_user(v_lead.id, v_user_id, v_rule.id, 'auto');

    IF v_assignment IS NOT NULL THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented — uncomment one block to revert)
-- ══════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS distribute_pending_leads(uuid, uuid, integer);
-- DROP FUNCTION IF EXISTS unassign_lead(uuid, text);
-- DROP FUNCTION IF EXISTS assign_lead_to_user(uuid, uuid, uuid, text);
-- DROP TABLE IF EXISTS team_capacity_log;
-- DROP TABLE IF EXISTS lead_assignments;
-- DROP TABLE IF EXISTS team_member_preferences;
-- DROP TABLE IF EXISTS lead_distribution_rules;
-- (leads.assigned_advisor_id intentionally NOT dropped — owned by insurance-mga-operations-schema.sql)
