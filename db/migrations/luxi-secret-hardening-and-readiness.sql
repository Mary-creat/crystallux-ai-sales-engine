-- LUXI — stream-key secret hardening + platform readiness model
-- =============================================================
-- Apply AFTER luxi-streaming.sql.
-- Idempotent: safe to re-run.
--
-- Two changes, both driven by the 2026-08-08 hardening requirements:
--
-- 1. THE STREAM KEY IS A SECRET AND WE STOP STORING IT.
--    luxi-streaming.sql persisted the raw RTMP stream key in
--    avatar_streaming_sessions.stream_key — a normal application table read by
--    ordinary admin queries. A stream key lets anyone broadcast to every one of
--    the operator's connected platforms, so it belongs nowhere near general
--    application data.
--
--    We keep only a MASK (e.g. 're_...4f2a') which is enough to confirm which
--    key is in use, and a SOURCE so the UI knows whether it came from Restream
--    or was typed in by hand. The real key stays in Restream and is fetched
--    server-side, on demand, by an admin-gated workflow. It is never persisted
--    and never sent to a browser except through an explicit reveal action.
--
--    Existing rows are purged below. That is deliberate and not reversible.
--
-- 2. active=true DOES NOT MEAN READY TO BROADCAST.
--    Restream reports a channel as active when it is *linked*. It can still be
--    unable to broadcast: TikTok gates LIVE behind a follower threshold,
--    Instagram behind account type, YouTube behind a 24h activation wait, and
--    any platform's OAuth grant can lapse. Treating active as ready is how you
--    discover mid-show that two destinations are dark.
--
--    So we model readiness explicitly, with a per-platform requirements table
--    the operator can extend as platforms change their rules.

BEGIN;

-- ─────────────────────────────────────────────────────────────
-- 1. Stream key: purge, then keep only a mask + provenance
-- ─────────────────────────────────────────────────────────────

ALTER TABLE avatar_streaming_sessions
  ADD COLUMN IF NOT EXISTS stream_key_masked text;

ALTER TABLE avatar_streaming_sessions
  ADD COLUMN IF NOT EXISTS stream_key_source text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ass_stream_key_source_check'
  ) THEN
    ALTER TABLE avatar_streaming_sessions
      ADD CONSTRAINT ass_stream_key_source_check
      CHECK (stream_key_source IS NULL OR stream_key_source IN ('restream','manual'));
  END IF;
END $$;

-- Backfill a mask for any existing session before the raw column goes away,
-- so historical rows stay identifiable.
UPDATE avatar_streaming_sessions
   SET stream_key_masked = CASE
         WHEN stream_key IS NULL OR length(trim(stream_key)) = 0 THEN NULL
         WHEN length(stream_key) <= 4 THEN '****'
         ELSE '****' || right(stream_key, 4)
       END,
       stream_key_source = CASE
         WHEN stream_key IS NULL OR length(trim(stream_key)) = 0 THEN NULL
         ELSE 'manual'
       END
 WHERE stream_key IS NOT NULL
   AND stream_key_masked IS NULL;

-- Purge the secrets, then remove the column entirely so nothing can write one
-- back by accident. Dropping beats "we promise not to use it".
ALTER TABLE avatar_streaming_sessions DROP COLUMN IF EXISTS stream_key;

-- ─────────────────────────────────────────────────────────────
-- 2. Platform readiness
-- ─────────────────────────────────────────────────────────────
-- Five states, ordered by how much they should worry the operator:
--   CONNECTED       linked to Restream, readiness not yet confirmed
--   READY           believed able to broadcast right now
--   ACTION_REQUIRED linked but blocked by a platform rule the operator must clear
--   UNAVAILABLE     not linked, or deliberately disabled
--   ERROR           we could not determine state (API down, token rejected)

CREATE TABLE IF NOT EXISTS streaming_platform_requirements (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  platform_key        text NOT NULL,          -- tiktok | youtube | facebook | instagram | x
  requirement_code    text NOT NULL,          -- short stable slug, e.g. 'tiktok_follower_minimum'
  label               text NOT NULL,          -- human sentence shown in the admin UI
  help_url            text,
  -- When true the operator has confirmed this requirement is satisfied. Null /
  -- false means we surface ACTION_REQUIRED rather than pretending READY.
  satisfied           boolean NOT NULL DEFAULT false,
  -- Blocking requirements force ACTION_REQUIRED; advisory ones are shown but
  -- do not downgrade readiness.
  blocking            boolean NOT NULL DEFAULT true,
  notes               text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'spr_platform_requirement_unique'
  ) THEN
    ALTER TABLE streaming_platform_requirements
      ADD CONSTRAINT spr_platform_requirement_unique UNIQUE (platform_key, requirement_code);
  END IF;
END $$;

ALTER TABLE streaming_platform_requirements ENABLE ROW LEVEL SECURITY;

-- Seed the rules that actually bite in practice. Each ships satisfied=false so
-- a platform reads ACTION_REQUIRED until the operator confirms it — the safe
-- default, because the failure mode of assuming READY is a dark destination
-- during a live show.
INSERT INTO streaming_platform_requirements (platform_key, requirement_code, label, help_url, blocking)
VALUES
  ('tiktok',    'tiktok_follower_minimum',
   'TikTok LIVE requires a minimum follower count on the account (commonly 1,000). Confirm the account can start a LIVE.',
   'https://support.tiktok.com/en/live-gifts-wallet/tiktok-live', true),
  ('tiktok',    'tiktok_live_permission_active',
   'TikTok LIVE access has not been restricted or revoked on this account.', NULL, true),
  ('youtube',   'youtube_live_enabled_24h',
   'YouTube live streaming must be enabled, and first-time activation takes up to 24 hours.',
   'https://support.google.com/youtube/answer/2474026', true),
  ('youtube',   'youtube_no_strikes',
   'No active community-guidelines strike (a strike disables live streaming for 14 days).', NULL, true),
  ('facebook',  'facebook_page_live_permission',
   'Publishing to a Facebook Page via a third-party tool requires the page role and live-video permission to be granted.', NULL, true),
  ('instagram', 'instagram_rtmp_support',
   'Instagram does not accept third-party RTMP for most accounts. Verify before relying on it for a show.', NULL, true),
  ('x',         'x_live_producer_access',
   'X live producer access must be enabled on the account.', NULL, true)
ON CONFLICT (platform_key, requirement_code) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 3. luxi_stream_start — same signature, but never stores the key
-- ─────────────────────────────────────────────────────────────
-- Signature is unchanged so the existing admin workflow keeps working; the
-- p_stream_key argument is now reduced to a mask on the way in and the raw
-- value is discarded. Manual entry therefore still works exactly as before.

CREATE OR REPLACE FUNCTION luxi_stream_start(
  p_platforms   text[],
  p_title       text DEFAULT NULL,
  p_auction_id  uuid DEFAULT NULL,
  p_rtmp        text DEFAULT NULL,
  p_stream_key  text DEFAULT NULL,
  p_watch_urls  jsonb DEFAULT '{}'::jsonb,
  p_key_source  text DEFAULT 'manual'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_avatar uuid;
  v_id     uuid;
  v_mask   text;
BEGIN
  SELECT id INTO v_avatar FROM avatars WHERE avatar_name = 'LUXI';
  IF v_avatar IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'LUXI avatar not found');
  END IF;

  -- Reduce the key to a mask immediately. The raw value is never assigned to a
  -- column and never leaves this function.
  v_mask := CASE
    WHEN p_stream_key IS NULL OR length(trim(p_stream_key)) = 0 THEN NULL
    WHEN length(p_stream_key) <= 4 THEN '****'
    ELSE '****' || right(p_stream_key, 4)
  END;

  UPDATE avatar_streaming_sessions
     SET session_status = 'ended', actual_end_at = now(), updated_at = now()
   WHERE avatar_id = v_avatar AND session_status = 'live';

  INSERT INTO avatar_streaming_sessions
    (avatar_id, session_status, scheduled_start_at, actual_start_at,
     platforms_targeted, title, rtmp_ingest_url, stream_key_masked,
     stream_key_source, watch_urls)
  VALUES
    (v_avatar, 'live', now(), now(),
     COALESCE(p_platforms, ARRAY[]::text[]),
     NULLIF(trim(coalesce(p_title,'')),''),
     p_rtmp,
     v_mask,
     CASE WHEN v_mask IS NULL THEN NULL
          WHEN p_key_source IN ('restream','manual') THEN p_key_source
          ELSE 'manual' END,
     COALESCE(p_watch_urls,'{}'::jsonb))
  RETURNING id INTO v_id;

  IF p_auction_id IS NOT NULL THEN
    UPDATE auctions SET streaming_session_id = v_id WHERE id = p_auction_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 200, 'session_id', v_id,
                            'stream_key_masked', v_mask);
END $$;

-- ─────────────────────────────────────────────────────────────
-- 4. Readiness read model
-- ─────────────────────────────────────────────────────────────
-- Returns the blocking, unsatisfied requirements per platform. The workflow
-- combines this with what Restream reports to produce the final state, because
-- neither source alone is sufficient: Restream knows what is linked, this table
-- knows what the platform demands on top of that.

CREATE OR REPLACE FUNCTION luxi_platform_requirements()
RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_object_agg(platform_key, reqs), '{}'::jsonb)
  FROM (
    SELECT platform_key,
           jsonb_agg(jsonb_build_object(
             'code', requirement_code,
             'label', label,
             'help_url', help_url,
             'satisfied', satisfied,
             'blocking', blocking
           ) ORDER BY blocking DESC, requirement_code) AS reqs
    FROM streaming_platform_requirements
    GROUP BY platform_key
  ) t;
$$;

COMMIT;

-- Verify:
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='avatar_streaming_sessions' AND column_name LIKE 'stream_key%';
--   -> expect stream_key_masked + stream_key_source, and NO bare stream_key
-- SELECT platform_key, requirement_code, satisfied FROM streaming_platform_requirements ORDER BY 1,2;
-- SELECT luxi_platform_requirements();
