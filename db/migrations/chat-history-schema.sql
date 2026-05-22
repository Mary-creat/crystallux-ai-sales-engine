-- ══════════════════════════════════════════════════════════════════
-- Admin Chat history (MCP widget v3)
-- ══════════════════════════════════════════════════════════════════
-- Stores conversations between admins and the in-dashboard Crystallux
-- Assistant. One row per session, one row per message. Tool calls and
-- tool results (added by v2) ride on the messages table as JSONB.
--
-- Idempotent. Re-applying is safe.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS admin_chat_sessions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  started_at        timestamptz DEFAULT now(),
  last_message_at   timestamptz DEFAULT now(),
  message_count     integer DEFAULT 0,
  title             text,
  archived          boolean DEFAULT false,
  metadata          jsonb DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_acs_user_active
  ON admin_chat_sessions(user_id, last_message_at DESC)
  WHERE archived = false;

CREATE TABLE IF NOT EXISTS admin_chat_messages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id    uuid NOT NULL REFERENCES admin_chat_sessions(id) ON DELETE CASCADE,
  role          text NOT NULL,
  content       text,
  tool_calls    jsonb,
  tool_results  jsonb,
  model         text,
  stop_reason   text,
  usage         jsonb,
  created_at    timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE admin_chat_messages
    ADD CONSTRAINT acm_role_check
    CHECK (role IN ('user', 'assistant', 'tool', 'system'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_acm_session_recent
  ON admin_chat_messages(session_id, created_at DESC);

-- ══════════════════════════════════════════════════════════════════
-- Helper RPC: find_or_create_active_chat_session(user_id)
-- ══════════════════════════════════════════════════════════════════
-- Returns the id of the user's most recent non-archived session, or
-- creates a new one if none exists. Bumps last_message_at if found.
CREATE OR REPLACE FUNCTION find_or_create_active_chat_session(p_user_id uuid)
  RETURNS uuid
  LANGUAGE plpgsql
AS $$
DECLARE
  v_session_id uuid;
BEGIN
  SELECT id INTO v_session_id
    FROM admin_chat_sessions
   WHERE user_id = p_user_id
     AND archived = false
     AND last_message_at > now() - interval '7 days'
   ORDER BY last_message_at DESC
   LIMIT 1;

  IF v_session_id IS NULL THEN
    INSERT INTO admin_chat_sessions (user_id) VALUES (p_user_id) RETURNING id INTO v_session_id;
  END IF;

  RETURN v_session_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS find_or_create_active_chat_session(uuid);
-- DROP TABLE IF EXISTS admin_chat_messages;
-- DROP TABLE IF EXISTS admin_chat_sessions;
