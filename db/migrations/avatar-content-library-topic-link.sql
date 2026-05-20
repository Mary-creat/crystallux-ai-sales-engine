-- ══════════════════════════════════════════════════════════════════
-- avatar_content_library — link to source content_topic
-- ══════════════════════════════════════════════════════════════════
-- The existing avatar_content_library table tracks per-avatar broadcast
-- queue entries with content_video_id (the rendered HeyGen output)
-- and a scheduled_for timestamp. What's missing is a link back to the
-- source content_topic that the broadcast covers, so admin pages can
-- show "AVA has these 5 topics queued for this week" without joining
-- through content_videos (which doesn't exist yet for unrendered
-- broadcasts).
--
-- Idempotent. Safe to re-apply.
-- ══════════════════════════════════════════════════════════════════

DO $$ BEGIN
  ALTER TABLE avatar_content_library
    ADD COLUMN IF NOT EXISTS content_topic_id uuid REFERENCES content_topics(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_column THEN NULL; END $$;

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS acl_topic_idx ON avatar_content_library (content_topic_id) WHERE content_topic_id IS NOT NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Verify:
--   SELECT count(*) FROM avatar_content_library WHERE content_topic_id IS NOT NULL;
-- ══════════════════════════════════════════════════════════════════
