-- LUXI live streaming — session control layer
-- Run AFTER avatars-platform-schema.sql. Idempotent.
--
-- LUXI is a live-streaming avatar that broadcasts to every platform it's listed
-- on (TikTok / Facebook / YouTube / Instagram Live, etc.). The A/V TRANSPORT is
-- an external service: the operator connects those platforms once in Restream.io
-- (one RTMP in -> all platforms out) and points HeyGen Interactive (real-time AI
-- avatar) OR OBS at the RTMP ingest. This layer is the orchestration + tracking:
-- start/end a session, target platforms, link the live auction, expose a LIVE
-- badge + watch links to bidders. (Schema note in avatars-platform-schema.sql.)

-- Operator-facing fields on the existing session table
ALTER TABLE avatar_streaming_sessions ADD COLUMN IF NOT EXISTS title            text;
ALTER TABLE avatar_streaming_sessions ADD COLUMN IF NOT EXISTS rtmp_ingest_url  text;   -- from Restream (or any RTMP service)
ALTER TABLE avatar_streaming_sessions ADD COLUMN IF NOT EXISTS stream_key       text;
ALTER TABLE avatar_streaming_sessions ADD COLUMN IF NOT EXISTS watch_urls       jsonb DEFAULT '{}'::jsonb;  -- { tiktok: url, youtube: url, ... }

-- 1. luxi_stream_start — go live. Ends any prior live LUXI session, creates a new
--    one targeting the given platforms (defaults to the 4 majors), optionally
--    links the auction so the bid page shows it LIVE.
CREATE OR REPLACE FUNCTION luxi_stream_start(
  p_platforms   text[],
  p_title       text,
  p_auction_id  uuid,
  p_rtmp        text,
  p_stream_key  text,
  p_watch_urls  jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_avatar uuid; v_sid uuid;
BEGIN
  SELECT id INTO v_avatar FROM avatars WHERE avatar_name = 'LUXI' LIMIT 1;
  IF v_avatar IS NULL THEN RETURN jsonb_build_object('ok',false,'status',404,'error','LUXI avatar not found — apply avatars-platform-schema.sql'); END IF;

  UPDATE avatar_streaming_sessions
     SET session_status = 'ended', actual_end_at = now(), updated_at = now()
   WHERE avatar_id = v_avatar AND session_status = 'live';

  INSERT INTO avatar_streaming_sessions
    (avatar_id, session_status, scheduled_start_at, actual_start_at, platforms_targeted, title, rtmp_ingest_url, stream_key, watch_urls)
  VALUES
    (v_avatar, 'live', now(), now(),
     COALESCE(NULLIF(p_platforms, ARRAY[]::text[]), ARRAY['tiktok_live','facebook_live','youtube_live','instagram_live']),
     NULLIF(trim(coalesce(p_title,'')),''), p_rtmp, p_stream_key, COALESCE(p_watch_urls,'{}'::jsonb))
  RETURNING id INTO v_sid;

  IF p_auction_id IS NOT NULL THEN
    UPDATE auctions SET streaming_session_id = v_sid, updated_at = now() WHERE id = p_auction_id;
  END IF;

  RETURN jsonb_build_object('ok',true,'session_id',v_sid,'status','live','rtmp_ingest_url',p_rtmp);
END;
$$;

-- 2. luxi_stream_end — end a live session.
CREATE OR REPLACE FUNCTION luxi_stream_end(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n integer;
BEGIN
  UPDATE avatar_streaming_sessions
     SET session_status = 'ended', actual_end_at = now(), updated_at = now()
   WHERE id = p_session_id AND session_status = 'live';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('ok',true,'ended',v_n);
END;
$$;

-- 3. luxi_stream_current — the live LUXI session (public; drives the LIVE badge +
--    watch links). Never exposes rtmp/stream_key.
CREATE OR REPLACE FUNCTION luxi_stream_current()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  SELECT s.id, s.title, s.platforms_targeted, s.watch_urls, s.actual_start_at
    INTO r
  FROM avatar_streaming_sessions s
  JOIN avatars a ON a.id = s.avatar_id
  WHERE a.avatar_name = 'LUXI' AND s.session_status = 'live'
  ORDER BY s.actual_start_at DESC NULLS LAST
  LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',true,'live',false); END IF;
  RETURN jsonb_build_object('ok',true,'live',true,
    'session_id', r.id, 'title', r.title,
    'platforms', r.platforms_targeted, 'watch_urls', COALESCE(r.watch_urls,'{}'::jsonb),
    'started_at', r.actual_start_at);
END;
$$;

-- Verify:
-- SELECT proname FROM pg_proc WHERE proname LIKE 'luxi_stream_%';
