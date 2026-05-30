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
