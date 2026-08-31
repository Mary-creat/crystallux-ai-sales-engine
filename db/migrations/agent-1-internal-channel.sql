-- ============================================================
-- Agent runtime — an 'internal' channel, so a read-only proof is possible
--
-- WHY THIS IS NEEDED, and why the authorized activation could not simply
-- be performed as described:
--
-- The decision engine finds tenants with
--     agent_channels_enabled?enabled=eq.true&select=client_id
-- so a tenant cannot enter the loop at all without an enabled channel
-- row. But the live CHECK constraint allows only:
--
--     voice, whatsapp, sms, email, instagram, facebook,
--     linkedin, x, calendar, tiktok, youtube
--
-- Every one is an OUTBOUND channel. There is no value meaning "this
-- tenant may be reasoned about but not contacted", so the only way to
-- start the runtime today is to declare a real contact channel enabled --
-- which is precisely what a read-only proof must not do.
--
-- 'internal' closes that gap. It is a channel the agent can be enabled on
-- while no outbound capability is declared.
--
-- WHY IT IS SAFE. Two independent reasons, and neither relies on the
-- other:
--
--   1. The engine only reads client_id from this table. The channel value
--      does not route anything; it is a membership marker.
--   2. Sending is gated elsewhere. The Policy Gate in
--      clx-agent-action-executor-v1 refuses every CONTACT_HUMAN,
--      FINANCIAL, DESTRUCTIVE and REGULATED capability under
--      autonomy_level recommend_only -- even when a valid approval object
--      is attached. 35 tests cover that, and enabling a channel row does
--      not touch it.
--
-- This ADDS a value. No existing value is removed, so nothing that is
-- enabled today changes behaviour.
--
-- Applying this migration enables nothing by itself: it only makes the
-- row insertable. The insert is the separate, explicit step below.
-- ============================================================

ALTER TABLE agent_channels_enabled
  DROP CONSTRAINT IF EXISTS ace_channel_check;

ALTER TABLE agent_channels_enabled
  ADD CONSTRAINT ace_channel_check CHECK (
    channel = ANY (ARRAY[
      'voice','whatsapp','sms','email','instagram','facebook',
      'linkedin','x','calendar','tiktok','youtube',
      'internal'
    ])
  );

COMMENT ON COLUMN agent_channels_enabled.channel IS
  'Outbound channel this tenant has enabled, or ''internal'' -- a membership '
  'marker that lets the agent runtime reason about a tenant while declaring no '
  'outbound capability. Sending is gated by the action executor''s policy gate, '
  'not by this column.';

-- ------------------------------------------------------------
-- TEST-ONLY activation, for the designated test tenant.
--
-- One row. No outbound channel, no schedule, no behavioural trigger, no
-- other tenant.
-- ------------------------------------------------------------

INSERT INTO agent_channels_enabled (client_id, channel, enabled, enabled_at, configuration)
SELECT '6edc687d-07b0-4478-bb4b-820dc4eebf5d'::uuid, 'internal', true, now(),
       '{"purpose":"read-only agentic proof","authorized_by":"owner","outbound":false}'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM agent_channels_enabled
   WHERE client_id = '6edc687d-07b0-4478-bb4b-820dc4eebf5d'::uuid
     AND channel = 'internal'
);

-- ---- VERIFY ----
-- Expect exactly one row, channel 'internal', for the test tenant only.
SELECT c.client_name, a.channel, a.enabled, a.configuration
  FROM agent_channels_enabled a JOIN clients c ON c.id = a.client_id;

-- Expect 0: no outbound channel is enabled for anyone.
SELECT count(*) AS outbound_channels_enabled
  FROM agent_channels_enabled
 WHERE enabled = true AND channel <> 'internal';

-- Expect 0/0/0 still: enabling membership must not, by itself, cause the
-- runtime to act.
SELECT (SELECT count(*) FROM agent_decisions) AS decisions,
       (SELECT count(*) FROM agent_actions)   AS actions,
       (SELECT count(*) FROM agent_memory)    AS memory;
