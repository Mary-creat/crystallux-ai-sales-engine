-- ============================================================
-- Agent runtime — one personality, so the loop can run at all
--
-- The agentic layer is 9 workflows, 16 tables and 10 action tools,
-- and it has never executed once. Every agent_* table is empty,
-- agent_personalities included -- and since the decision engine reads
-- a personality before it does anything, nothing can run even when
-- triggered. Not a design gap: a missing row.
--
-- This seeds exactly one, for the existing test tenant, deliberately
-- configured so that the first proof is READ-ONLY:
--
--   * escalation_rules require human approval for every outbound
--     action, so an agent can plan a message and cannot send one
--   * prohibited_topics block the categories that move money or
--     touch a real customer
--   * vertical_context points at 'construction', which is configured,
--     active, and resolvable through get_vertical_context()
--
-- Reuses the tenant of record (clients) and the existing avatar
-- registry. Creates no new table and no new concept.
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
