-- ============================================================
-- Crystallux — combined deploy migration (2026-05-30)
-- Paste this ENTIRE file into Supabase SQL Editor and click Run.
-- Idempotent + ordered. Safe to re-run. Bundles: LUXI Buy Now +
-- auto-bid, web bidding, streaming, revenue checkout, demo auction.
-- ============================================================


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> luxi-buy-now-and-proxy-bids.sql <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

-- LUXI — Outright sales (Buy Now) + Auto-bid (proxy / max bidding)
-- Run AFTER avatars-platform-schema.sql + luxi-auction-tick-functions.sql.
-- Fully idempotent: ADD COLUMN IF NOT EXISTS / CREATE TABLE IF NOT EXISTS /
-- CREATE OR REPLACE FUNCTION. Safe to re-run.
--
-- Adds two capabilities to the existing auction engine WITHOUT touching the
-- protected place-bid flow:
--   1. listing_type ('auction' | 'buy_now' | 'both') + buy_now_price_cents, so an
--      item can be auctioned, sold outright, or both. A Buy Now purchase closes
--      the auction immediately at the listed price.
--   2. auction_proxy_bids — a bidder sets a MAX; the engine auto-bids on their
--      behalf one increment above the competition, up to that max (eBay-style
--      proxy bidding). Funds are guaranteed by a Stripe card hold (handled by the
--      n8n layer + STRIPE_SECRET_KEY).

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- digest() for the bidder identity hash

-- ─────────────────────────────────────────────────────────────────
-- 1. Outright-sale columns on auctions
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS listing_type        text NOT NULL DEFAULT 'auction';
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS buy_now_price_cents  integer;
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS sold_via             text;   -- null | 'auction' | 'buy_now'

DO $$ BEGIN
  ALTER TABLE auctions
    ADD CONSTRAINT auc_listing_type_check
    CHECK (listing_type IN ('auction','buy_now','both'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE auctions
    ADD CONSTRAINT auc_sold_via_check
    CHECK (sold_via IS NULL OR sold_via IN ('auction','buy_now'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 2. auction_proxy_bids — one standing max-bid per (auction, bidder)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS auction_proxy_bids (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id         uuid NOT NULL REFERENCES auctions(id) ON DELETE CASCADE,
  bidder_trust_id    uuid NOT NULL REFERENCES bidder_trust_scores(id) ON DELETE RESTRICT,
  max_cents          integer NOT NULL,
  status             text NOT NULL DEFAULT 'active',  -- active | exhausted | cancelled | won
  -- Stripe pre-auth hold backing this max (filled by the n8n layer when a key is set)
  stripe_payment_intent_id text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (auction_id, bidder_trust_id)
);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS apx_auction_idx ON auction_proxy_bids (auction_id);
  CREATE INDEX IF NOT EXISTS apx_status_idx  ON auction_proxy_bids (status);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE auction_proxy_bids
    ADD CONSTRAINT apx_status_check
    CHECK (status IN ('active','exhausted','cancelled','won'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 3. luxi_register_bidder — hash + upsert a bidder, return its id
--    (mirrors the SHA-256 identity hash used by the place-bid flow:
--     sha256(platform + ':' + lowercased, @-stripped handle))
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION luxi_register_bidder(p_platform text, p_handle text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_norm text;
  v_hash text;
  v_id   uuid;
BEGIN
  v_norm := lower(regexp_replace(coalesce(p_handle,''), '^@+', ''));
  v_hash := encode(digest(lower(coalesce(p_platform,'')) || ':' || v_norm, 'sha256'), 'hex');
  SELECT id INTO v_id FROM bidder_trust_scores WHERE bidder_identity_hash = v_hash LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO bidder_trust_scores (bidder_identity_hash, display_name, platform, trust_tier, max_bid_cents)
    VALUES (v_hash, p_handle, lower(coalesce(p_platform,'')), 'tier_0', 0)
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────
-- 4. luxi_buy_now — outright purchase at the listed price; closes the
--    auction sold immediately, cancels any standing proxies.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION luxi_buy_now(p_auction_id uuid, p_bidder_trust_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a       auctions%ROWTYPE;
  v_bid   uuid;
  v_now   timestamptz := now();
BEGIN
  SELECT * INTO a FROM auctions WHERE id = p_auction_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'status',404,'error','auction not found'); END IF;
  IF a.listing_type NOT IN ('buy_now','both') OR a.buy_now_price_cents IS NULL THEN
    RETURN jsonb_build_object('ok',false,'status',409,'error','this item has no Buy Now price');
  END IF;
  IF a.status NOT IN ('scheduled','open','extended') THEN
    RETURN jsonb_build_object('ok',false,'status',409,'error','item not available (status='||a.status||')');
  END IF;

  INSERT INTO auction_bids (auction_id, bidder_trust_id, amount_cents, source_platform, raw_input, status, won_at)
  VALUES (p_auction_id, p_bidder_trust_id, a.buy_now_price_cents, 'buy_now', 'Buy Now purchase', 'won', v_now)
  RETURNING id INTO v_bid;

  IF a.current_high_bid_id IS NOT NULL AND a.current_high_bid_id <> v_bid THEN
    UPDATE auction_bids SET status='outbid', outbid_at=v_now
     WHERE id = a.current_high_bid_id AND status = 'active';
  END IF;

  UPDATE auction_proxy_bids SET status='cancelled', updated_at=v_now
   WHERE auction_id = p_auction_id AND status = 'active';

  UPDATE auctions
     SET status='closed_sold', sold_via='buy_now', winning_bid_id=v_bid,
         current_high_bid_cents=a.buy_now_price_cents, current_high_bid_id=v_bid,
         actual_close_at=v_now, updated_at=v_now
   WHERE id = p_auction_id;

  RETURN jsonb_build_object('ok',true,'bid_id',v_bid,'amount_cents',a.buy_now_price_cents,'sold_via','buy_now');
END;
$$;

-- ─────────────────────────────────────────────────────────────────
-- 5. luxi_apply_proxy_bids — resolve auto-bids for ONE auction.
--    Single-pass, idempotent, no ping-pong: the highest-max active proxy
--    becomes the leader at one increment above the next-best competitor
--    (a rival proxy's max, or a standing manual high from someone else),
--    capped at its own max. Marks the previous high outbid; exhausts a
--    proxy that reaches its max so a later manual bid lets the next proxy
--    take over.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION luxi_apply_proxy_bids(p_auction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a            auctions%ROWTYPE;
  v_inc        integer;
  v_high       integer;
  v_leader     uuid;       -- bidder_trust_id currently leading
  v_top        auction_proxy_bids%ROWTYPE;
  v_runner_max integer;
  v_manual     integer;
  v_competitor integer;
  v_target     integer;
  v_now        timestamptz := now();
  v_newbid     uuid;
BEGIN
  SELECT * INTO a FROM auctions WHERE id = p_auction_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','auction not found'); END IF;
  IF a.status NOT IN ('open','extended') THEN RETURN jsonb_build_object('ok',false,'error','auction not live'); END IF;

  v_inc  := COALESCE(a.min_increment_cents, 100);
  v_high := COALESCE(a.current_high_bid_cents, 0);

  SELECT bidder_trust_id INTO v_leader FROM auction_bids WHERE id = a.current_high_bid_id;

  -- highest-max active proxy = prospective winner
  SELECT * INTO v_top FROM auction_proxy_bids
   WHERE auction_id = p_auction_id AND status = 'active'
   ORDER BY max_cents DESC, created_at ASC LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',true,'auto_bid',false,'reason','no active proxy'); END IF;

  -- next-best competing proxy max (excluding the top proxy's bidder)
  SELECT COALESCE(MAX(max_cents),0) INTO v_runner_max FROM auction_proxy_bids
   WHERE auction_id = p_auction_id AND status = 'active'
     AND bidder_trust_id <> v_top.bidder_trust_id;

  -- a standing manual high counts as competition only if someone else holds it
  v_manual := CASE WHEN v_leader IS DISTINCT FROM v_top.bidder_trust_id THEN v_high ELSE 0 END;
  v_competitor := GREATEST(v_runner_max, v_manual);

  -- top can't beat the standing competition → leave as-is
  IF v_top.max_cents < v_competitor + v_inc THEN
    RETURN jsonb_build_object('ok',true,'auto_bid',false,'reason','top proxy cannot beat current high');
  END IF;

  v_target := LEAST(v_top.max_cents, v_competitor + v_inc);

  -- already leading at the right price → nothing to do (idempotent)
  IF v_leader = v_top.bidder_trust_id AND v_high >= v_target THEN
    RETURN jsonb_build_object('ok',true,'auto_bid',false,'reason','top proxy already leading');
  END IF;

  INSERT INTO auction_bids (auction_id, bidder_trust_id, amount_cents, source_platform, raw_input, status)
  VALUES (p_auction_id, v_top.bidder_trust_id, v_target, 'proxy_auto',
          'auto-bid up to ' || (v_top.max_cents/100.0)::numeric(12,2), 'active')
  RETURNING id INTO v_newbid;

  IF a.current_high_bid_id IS NOT NULL THEN
    UPDATE auction_bids SET status='outbid', outbid_at=v_now
     WHERE id = a.current_high_bid_id AND status = 'active';
  END IF;

  UPDATE auctions
     SET current_high_bid_cents = v_target, current_high_bid_id = v_newbid, updated_at = v_now
   WHERE id = p_auction_id;

  IF v_target >= v_top.max_cents THEN
    UPDATE auction_proxy_bids SET status='exhausted', updated_at=v_now WHERE id = v_top.id;
  END IF;

  RETURN jsonb_build_object('ok',true,'auto_bid',true,'bid_id',v_newbid,'amount_cents',v_target);
END;
$$;

-- ─────────────────────────────────────────────────────────────────
-- 6. luxi_set_proxy_bid — register/raise a bidder's max, then resolve.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION luxi_set_proxy_bid(p_auction_id uuid, p_bidder_trust_id uuid, p_max_cents integer)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a     auctions%ROWTYPE;
  v_res jsonb;
BEGIN
  SELECT * INTO a FROM auctions WHERE id = p_auction_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'status',404,'error','auction not found'); END IF;
  IF a.status NOT IN ('open','extended') THEN
    RETURN jsonb_build_object('ok',false,'status',409,'error','auction is not accepting bids');
  END IF;
  IF p_max_cents <= COALESCE(a.current_high_bid_cents,0) THEN
    RETURN jsonb_build_object('ok',false,'status',422,
      'error','your max must be above the current high bid ($'||(COALESCE(a.current_high_bid_cents,0)/100.0)::numeric(12,2)||')');
  END IF;

  INSERT INTO auction_proxy_bids (auction_id, bidder_trust_id, max_cents, status)
  VALUES (p_auction_id, p_bidder_trust_id, p_max_cents, 'active')
  ON CONFLICT (auction_id, bidder_trust_id)
  DO UPDATE SET max_cents = EXCLUDED.max_cents, status = 'active', updated_at = now();

  v_res := luxi_apply_proxy_bids(p_auction_id);
  RETURN jsonb_build_object('ok',true,'max_cents',p_max_cents,'resolution',v_res);
END;
$$;

-- ─────────────────────────────────────────────────────────────────
-- 7. luxi_apply_all_proxy_bids — resolve every live auction. Called by
--    the auction-tick cron so proxies respond to manual bids each tick.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION luxi_apply_all_proxy_bids()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r RECORD; v_n integer := 0;
BEGIN
  FOR r IN SELECT id FROM auctions WHERE status IN ('open','extended') LOOP
    PERFORM luxi_apply_proxy_bids(r.id);
    v_n := v_n + 1;
  END LOOP;
  RETURN jsonb_build_object('ok',true,'auctions_processed',v_n);
END;
$$;

-- ─────────────────────────────────────────────────────────────────
-- 8. Convenience wrappers so the n8n layer can act in ONE call
--    (register the bidder by handle, then buy-now / set-proxy).
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION luxi_buy_now_by_handle(p_auction_id uuid, p_platform text, p_handle text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bidder uuid;
BEGIN
  IF coalesce(trim(p_handle),'') = '' THEN RETURN jsonb_build_object('ok',false,'status',400,'error','buyer handle required'); END IF;
  v_bidder := luxi_register_bidder(p_platform, p_handle);
  RETURN luxi_buy_now(p_auction_id, v_bidder);
END;
$$;

CREATE OR REPLACE FUNCTION luxi_set_proxy_bid_by_handle(p_auction_id uuid, p_platform text, p_handle text, p_max_cents integer)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bidder uuid;
BEGIN
  IF coalesce(trim(p_handle),'') = '' THEN RETURN jsonb_build_object('ok',false,'status',400,'error','bidder handle required'); END IF;
  IF coalesce(p_max_cents,0) <= 0 THEN RETURN jsonb_build_object('ok',false,'status',400,'error','a positive max is required'); END IF;
  v_bidder := luxi_register_bidder(p_platform, p_handle);
  RETURN luxi_set_proxy_bid(p_auction_id, v_bidder, p_max_cents);
END;
$$;

-- Verify:
-- SELECT column_name FROM information_schema.columns WHERE table_name='auctions' AND column_name IN ('listing_type','buy_now_price_cents','sold_via');
-- SELECT proname FROM pg_proc WHERE proname LIKE 'luxi_%';


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> luxi-web-bidding.sql <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

-- LUXI — self-serve web bidding (fund-guaranteed auto-bid)
-- Run AFTER luxi-buy-now-and-proxy-bids.sql. Idempotent.
--
-- Adds the hold lifecycle to auction_proxy_bids so a public bidder's max is
-- backed by a Stripe PaymentIntent authorization (manual capture). On auction
-- close the winner's hold is captured for the final price (partial capture
-- auto-releases the remainder) and losers' holds are cancelled.

-- 1. Hold lifecycle columns on auction_proxy_bids
ALTER TABLE auction_proxy_bids ADD COLUMN IF NOT EXISTS hold_status     text;  -- null | authorized | captured | released | failed
ALTER TABLE auction_proxy_bids ADD COLUMN IF NOT EXISTS authorized_at   timestamptz;
ALTER TABLE auction_proxy_bids ADD COLUMN IF NOT EXISTS captured_at     timestamptz;
ALTER TABLE auction_proxy_bids ADD COLUMN IF NOT EXISTS released_at     timestamptz;
ALTER TABLE auction_proxy_bids ADD COLUMN IF NOT EXISTS settle_amount_cents integer;
ALTER TABLE auction_proxy_bids ADD COLUMN IF NOT EXISTS failure_reason  text;

DO $$ BEGIN
  ALTER TABLE auction_proxy_bids
    ADD CONSTRAINT apx_hold_status_check
    CHECK (hold_status IS NULL OR hold_status IN ('authorized','captured','released','failed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS apx_hold_status_idx ON auction_proxy_bids (hold_status);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2. luxi_set_web_proxy_bid — register a 'web' bidder + a card-backed max.
--    Returns the prior PaymentIntent id (if the bidder is raising an existing
--    max) so the caller can cancel the now-superseded hold.
CREATE OR REPLACE FUNCTION luxi_set_web_proxy_bid(
  p_auction_id        uuid,
  p_handle            text,
  p_max_cents         integer,
  p_payment_intent_id text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a          auctions%ROWTYPE;
  v_bidder   uuid;
  v_old_pi   text;
  v_res      jsonb;
BEGIN
  IF coalesce(trim(p_handle),'') = '' THEN RETURN jsonb_build_object('ok',false,'status',400,'error','name/email required'); END IF;
  IF coalesce(p_max_cents,0) <= 0 THEN RETURN jsonb_build_object('ok',false,'status',400,'error','a positive max is required'); END IF;
  IF coalesce(trim(p_payment_intent_id),'') = '' THEN RETURN jsonb_build_object('ok',false,'status',400,'error','payment authorization required'); END IF;

  SELECT * INTO a FROM auctions WHERE id = p_auction_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'status',404,'error','auction not found'); END IF;
  IF a.status NOT IN ('open','extended') THEN RETURN jsonb_build_object('ok',false,'status',409,'error','auction is not accepting bids'); END IF;
  IF p_max_cents <= COALESCE(a.current_high_bid_cents,0) THEN
    RETURN jsonb_build_object('ok',false,'status',422,
      'error','your max must be above the current high bid ($'||(COALESCE(a.current_high_bid_cents,0)/100.0)::numeric(12,2)||')');
  END IF;

  v_bidder := luxi_register_bidder('web', p_handle);

  -- capture any prior hold's PI so the caller can cancel it
  SELECT stripe_payment_intent_id INTO v_old_pi
  FROM auction_proxy_bids
  WHERE auction_id = p_auction_id AND bidder_trust_id = v_bidder
    AND hold_status = 'authorized' AND stripe_payment_intent_id IS DISTINCT FROM p_payment_intent_id;

  INSERT INTO auction_proxy_bids (auction_id, bidder_trust_id, max_cents, status, stripe_payment_intent_id, hold_status, authorized_at)
  VALUES (p_auction_id, v_bidder, p_max_cents, 'active', p_payment_intent_id, 'authorized', now())
  ON CONFLICT (auction_id, bidder_trust_id)
  DO UPDATE SET max_cents = EXCLUDED.max_cents, status = 'active',
                stripe_payment_intent_id = EXCLUDED.stripe_payment_intent_id,
                hold_status = 'authorized', authorized_at = now(), updated_at = now();

  UPDATE bidder_trust_scores
     SET stripe_card_authorized = true, stripe_authorized_at = now(), updated_at = now()
   WHERE id = v_bidder;

  v_res := luxi_apply_proxy_bids(p_auction_id);
  RETURN jsonb_build_object('ok',true,'max_cents',p_max_cents,'resolution',v_res,'cancel_payment_intent',v_old_pi);
END;
$$;

-- 3. luxi_classify_proxy_settlements — at auction close, decide capture vs
--    release for every authorized proxy hold on a terminal auction.
CREATE OR REPLACE FUNCTION luxi_classify_proxy_settlements()
RETURNS TABLE(proxy_id uuid, stripe_payment_intent_id text, action text, amount_cents integer)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT pb.id,
         pb.stripe_payment_intent_id,
         CASE WHEN a.status = 'closed_sold' AND wb.bidder_trust_id = pb.bidder_trust_id
              THEN 'capture' ELSE 'release' END,
         CASE WHEN a.status = 'closed_sold' AND wb.bidder_trust_id = pb.bidder_trust_id
              THEN GREATEST(a.current_high_bid_cents, 0) ELSE pb.max_cents END
  FROM auction_proxy_bids pb
  JOIN auctions a ON a.id = pb.auction_id
  LEFT JOIN auction_bids wb ON wb.id = a.winning_bid_id
  WHERE pb.hold_status = 'authorized'
    AND pb.stripe_payment_intent_id IS NOT NULL
    AND a.status IN ('closed_sold','closed_unsold','cancelled');
$$;

-- Verify:
-- SELECT proname FROM pg_proc WHERE proname IN ('luxi_set_web_proxy_bid','luxi_classify_proxy_settlements');
-- SELECT column_name FROM information_schema.columns WHERE table_name='auction_proxy_bids' AND column_name LIKE 'hold%';


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> luxi-streaming.sql <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> revenue-checkout.sql <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

-- Revenue wiring — self-serve Stripe Checkout provisioning
-- Idempotent. Grants a purchased product to a paying customer.
--
-- Flow: marketing page -> Stripe Checkout (subscription) -> success page calls
-- /public/checkout-complete -> verifies the session with Stripe -> this RPC.
-- If the buyer already has an auth_users account, the product is added to their
-- products[] and they're activated. If not, a clearly-flagged PAID lead is
-- created so Mary provisions + welcomes them (reuses her 1-click provisioning).
-- Avoids guessing the auth_users insert shape for brand-new self-serve accounts.

CREATE OR REPLACE FUNCTION clx_provision_paid_checkout(p_email text, p_product text, p_plan text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid     uuid;
  v_company text;
BEGIN
  IF coalesce(trim(p_email),'') = '' OR coalesce(trim(p_product),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'email and product required');
  END IF;

  -- Existing account: add the product (dedup) + activate.
  UPDATE auth_users
     SET products = (
           SELECT jsonb_agg(DISTINCT e) FROM (
             SELECT jsonb_array_elements_text(coalesce(products, '[]'::jsonb)) AS e
             UNION SELECT p_product
           ) s),
         is_active  = true,
         updated_at = now()
   WHERE lower(email) = lower(p_email)
  RETURNING id INTO v_uid;

  IF v_uid IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'account', true, 'user_id', v_uid, 'product', p_product);
  END IF;

  -- No account yet: drop a flagged PAID lead (company disambiguated by email to
  -- satisfy leads_company_unique — see the bulk-import precedent).
  v_company := left('Paid checkout | ' || lower(p_email), 200);
  INSERT INTO leads (full_name, email, phone, company, industry, city, source,
                     lead_status, product_type, lead_type, do_not_contact, unsubscribed,
                     total_emails_sent, lead_score, notes)
  VALUES (split_part(p_email, '@', 1), lower(p_email), '', v_company, 'saas', '',
          'paid_checkout', 'New Lead', p_product, 'paid_signup', false, false,
          0, 100,
          'PAID checkout: product=' || p_product || ' plan=' || coalesce(p_plan,'') ||
          '. Provision the account + send login.')
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'account', false, 'product', p_product);
END;
$$;

-- Verify:
-- SELECT clx_provision_paid_checkout('test@example.com','sentinel','sentinel_growth');


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> luxi-demo-auction-seed.sql <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

-- LUXI demo auction seed
-- Run AFTER avatars-platform-schema.sql (needs the `avatars` + `auctions` tables
-- and the seeded LUXI avatar row). Inserts ONE open demo auction so the LUXI
-- dashboard and the live bid-entry page have something real to show immediately.
--
-- Idempotent: re-running will not create a second copy.
-- Safe to delete when done:  DELETE FROM auctions WHERE item_title LIKE 'DEMO —%';

INSERT INTO auctions (
  avatar_id,
  item_title,
  item_description,
  item_category,
  status,
  scheduled_open_at,
  scheduled_close_at,
  reserve_price_cents,
  min_increment_cents,
  current_high_bid_cents,
  anti_snipe_window_seconds,
  anti_snipe_extend_seconds,
  anti_snipe_max_extensions
)
SELECT
  a.id,
  'DEMO — Signed Collectible (safe to delete)',
  'Test auction from the LUXI go-live seed. Open the live page, place a few bids to watch the engine + anti-snipe work, then delete it.',
  'Collectibles',
  'open',                       -- opens immediately so it shows under "Live now"
  now(),
  now() + interval '60 minutes',
  0,                            -- no reserve
  100,                          -- $1.00 min increment
  0,                            -- no bids yet
  30,                           -- anti-snipe window (s)
  30,                           -- anti-snipe extend (s)
  10                            -- max extensions
FROM avatars a
WHERE a.avatar_name = 'LUXI'
  AND NOT EXISTS (
    SELECT 1 FROM auctions
    WHERE item_title = 'DEMO — Signed Collectible (safe to delete)'
  );

-- Verify:
SELECT id, item_title, status, scheduled_open_at, scheduled_close_at
FROM auctions
WHERE item_title LIKE 'DEMO —%';

