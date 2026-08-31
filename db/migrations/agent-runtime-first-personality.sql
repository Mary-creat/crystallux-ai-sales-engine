-- ============================================================
-- Agent runtime — one personality, so the loop can run at all
--
-- The agentic layer is 9 workflows, 16 tables and 10 action tools,
-- and it has never executed once. Every agent_* table is empty,
-- agent_personalities included -- and since the decision engine reads
-- a personality before it does anything, nothing can run even when
-- triggered. Not a design gap: a missing row.
--
-- This seeds exactly one, for the existing test tenant.
--
-- WHY THIS IS SAFE TO APPLY -- corrected 2026-08-30
-- -------------------------------------------------
-- An earlier version of this comment claimed the escalation_rules below
-- make the agent recommend-only and stop it sending. That is FALSE, and
-- the correction matters more than the seed:
--
--   clx-agent-action-executor-v1 contains NO approval logic at all. It
--   validates a shared secret, inserts an agent_actions row, and routes
--   straight to Call WhatsApp / Call SMS / Call Email / Call Voice.
--   Grep it: 'require_human_approval', 'autonomy', 'approval',
--   'escalation_rules' and 'dry_run' appear nowhere. Nothing reads the
--   policy this row carries.
--
-- What actually makes this row inert is upstream and structural: the
-- decision engine's FIRST query is
--     agent_channels_enabled?enabled=eq.true
-- which returns 0 rows, so the per-client loop exits before a
-- personality is ever fetched. Seeding a personality alone therefore
-- cannot cause any agent to act.
--
-- The escalation_rules below are kept as the INTENDED policy, so the
-- contract is written down before the executor is taught to honour it.
-- They are documentation today, not enforcement.
--
-- DO NOT insert agent_channels_enabled, or seed a pending
-- behavioral_trigger, until the executor enforces approval. Those two
-- rows are what would turn this from inert configuration into an agent
-- that can message a real person.
--
-- Idempotent: keyed on (client_id, vertical_context), no-op on re-run.
-- ============================================================

INSERT INTO agent_personalities (
  id, client_id, avatar_id, vertical_context,
  voice_tone, formality_level, language, signature, intro_template,
  prohibited_topics, escalation_rules, created_at, updated_at
)
SELECT
  gen_random_uuid(),
  c.id,
  (SELECT a.id FROM avatars a WHERE a.avatar_name = 'MAXI' LIMIT 1),
  'construction',
  'direct, practical, ROI-focused',
  'professional',
  'en-CA',
  'Crystallux',
  'Hi {first_name} — noticed {signal} at {company}.',
  ARRAY[
    'pricing_commitments',
    'legal_advice',
    'refunds',
    'contract_terms',
    'payment_collection'
  ]::text[],
  -- Read-only by construction. Every category that reaches a human or
  -- moves money requires approval, so the first acceptance test cannot
  -- send, charge, or contact anyone even if the agent decides to.
  '{
    "autonomy_level": "recommend_only",
    "require_human_approval": ["send_email","send_sms","send_whatsapp","place_call","book_meeting","create_order","issue_refund","update_lead_status"],
    "auto_allowed": ["research_lead","score_lead","get_pipeline_stats","get_vertical_context","retrieve_lead_memory","log_decision"],
    "escalate_when": {"confidence_below": 0.7, "contacts_a_human": true, "spends_money": true},
    "max_actions_per_run": 25,
    "_read_only_first_proof": true
  }'::jsonb,
  now(), now()
FROM clients c
WHERE c.id = '6edc687d-07b0-4478-bb4b-820dc4eebf5d'
  AND NOT EXISTS (
    SELECT 1 FROM agent_personalities p
     WHERE p.client_id = c.id
       AND p.vertical_context = 'construction'
  );

-- ---- VERIFY ----
-- Expect 1 row, autonomy_level = recommend_only, and a resolvable vertical.
SELECT p.id,
       p.client_id,
       p.vertical_context,
       p.escalation_rules ->> 'autonomy_level'        AS autonomy,
       jsonb_array_length(p.escalation_rules -> 'require_human_approval') AS gated_actions,
       a.avatar_name,
       (get_vertical_context(p.vertical_context) ->> 'ok')::boolean       AS vertical_resolves
  FROM agent_personalities p
  LEFT JOIN avatars a ON a.id = p.avatar_id
 ORDER BY p.created_at DESC;

-- Still expect 0 everywhere: seeding a personality must not, by itself,
-- cause the runtime to act. These stay empty until something triggers it.
SELECT
  (SELECT count(*) FROM agent_decisions)  AS decisions,
  (SELECT count(*) FROM agent_actions)    AS actions,
  (SELECT count(*) FROM agent_memory)     AS memory;
