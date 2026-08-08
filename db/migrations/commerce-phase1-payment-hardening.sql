-- Crystallux commerce — Phase 1 payment hardening + settlement wiring
-- ====================================================================
-- Apply AFTER commerce-phase1-functions.sql. Idempotent.
--
-- Fixes three defects found reviewing the auction Stripe implementation on
-- 2026-08-08, and connects settlement to the new orders/inventory layer.
--
-- 1. DOUBLE CAPTURE.
--    luxi_classify_proxy_settlements() only SELECTed rows with
--    hold_status='authorized'. The settle cron runs every 60s and does not
--    finish instantly, so a slow run means the next run picks up the SAME
--    holds and captures them again. Stripe rejects the second capture, the
--    workflow reads that rejection as failure, and a payment that was actually
--    collected gets recorded as failed. Money in the bank, wrong state in the
--    database -- the worst combination.
--    Fixed by claiming atomically: the classify call now UPDATEs the rows to
--    'settling' and returns them in the same statement, so a concurrent run
--    sees nothing to do.
--
-- 2. AUTHORIZATION EXPIRY WAS NEVER RECORDED.
--    Stripe voids an uncaptured authorization after roughly 7 days. Nothing
--    stored the deadline and nothing watched it, so an auction that ran long
--    or a cron that stalled over a weekend would lose the money silently.
--
-- 3. NOTHING TURNED A CAPTURE INTO AN ORDER.
--    Capture updated hold_status and stopped. No order, no inventory movement,
--    no fulfilment. That is the "without manual database intervention" gap.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Track the authorization lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE auction_proxy_bids
  ADD COLUMN IF NOT EXISTS authorization_expires_at timestamptz;
ALTER TABLE auction_proxy_bids
  ADD COLUMN IF NOT EXISTS settling_since           timestamptz;
ALTER TABLE auction_proxy_bids
  ADD COLUMN IF NOT EXISTS capture_attempts         integer NOT NULL DEFAULT 0;
ALTER TABLE auction_proxy_bids
  ADD COLUMN IF NOT EXISTS order_id                 uuid REFERENCES orders(id);

-- 'settling' is the claim state; 'expired' records an authorization Stripe
-- voided before we captured it.
DO $$
BEGIN
  ALTER TABLE auction_proxy_bids DROP CONSTRAINT IF EXISTS apx_hold_status_check;
  ALTER TABLE auction_proxy_bids
    ADD CONSTRAINT apx_hold_status_check
    CHECK (hold_status IS NULL OR hold_status IN
      ('authorized','settling','captured','released','failed','expired'));
END $$;

CREATE INDEX IF NOT EXISTS apx_expiry_idx
  ON auction_proxy_bids (authorization_expires_at)
  WHERE hold_status = 'authorized';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Atomic claim — replaces luxi_classify_proxy_settlements as the cron entry
--    point. The old function is left in place (harmless, read-only) so nothing
--    that still calls it breaks mid-deploy.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION luxi_claim_proxy_settlements(p_limit integer DEFAULT 100)
RETURNS TABLE(
  proxy_id uuid,
  stripe_payment_intent_id text,
  action text,
  amount_cents integer,
  auction_id uuid,
  bidder_handle text
)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH claimable AS (
    SELECT pb.id
    FROM auction_proxy_bids pb
    JOIN auctions a ON a.id = pb.auction_id
    WHERE pb.hold_status = 'authorized'
      AND pb.stripe_payment_intent_id IS NOT NULL
      AND a.status IN ('closed_sold','closed_unsold','cancelled')
    ORDER BY pb.created_at
    LIMIT GREATEST(COALESCE(p_limit, 100), 1)
    -- SKIP LOCKED is what makes two concurrent cron runs safe: the second
    -- steps over rows the first already holds instead of blocking or
    -- duplicating them.
    FOR UPDATE OF pb SKIP LOCKED
  ),
  claimed AS (
    UPDATE auction_proxy_bids pb
       SET hold_status = 'settling',
           settling_since = now(),
           capture_attempts = pb.capture_attempts + 1,
           updated_at = now()
      FROM claimable c
     WHERE pb.id = c.id
     RETURNING pb.id, pb.stripe_payment_intent_id, pb.auction_id,
               pb.bidder_trust_id, pb.max_cents
  )
  SELECT cl.id,
         cl.stripe_payment_intent_id,
         CASE WHEN a.status = 'closed_sold' AND wb.bidder_trust_id = cl.bidder_trust_id
              THEN 'capture' ELSE 'release' END,
         CASE WHEN a.status = 'closed_sold' AND wb.bidder_trust_id = cl.bidder_trust_id
              THEN GREATEST(a.current_high_bid_cents, 0) ELSE cl.max_cents END,
         cl.auction_id,
         COALESCE(bt.display_name, 'bidder')
  FROM claimed cl
  JOIN auctions a ON a.id = cl.auction_id
  LEFT JOIN auction_bids wb ON wb.id = a.winning_bid_id
  LEFT JOIN bidder_trust_scores bt ON bt.id = cl.bidder_trust_id;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Record the outcome of a settlement attempt, and on a successful capture
--    create the order + move the stock. One call, one transaction: a captured
--    payment and its order are never half-written.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION luxi_settle_proxy_result(
  p_proxy_id  uuid,
  p_action    text,             -- 'capture' | 'release'
  p_succeeded boolean,
  p_amount_cents integer DEFAULT NULL,
  p_error     text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pb record; v_handle text; v_order jsonb; v_order_id uuid;
BEGIN
  SELECT * INTO pb FROM auction_proxy_bids WHERE id = p_proxy_id FOR UPDATE;
  IF pb.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'proxy bid not found');
  END IF;

  IF NOT p_succeeded THEN
    UPDATE auction_proxy_bids
       SET hold_status = CASE
             -- A capture that fails because the authorization expired is a
             -- different problem from a declined card, and needs a different
             -- response (re-invoice, not retry).
             WHEN p_error ILIKE '%expired%' OR p_error ILIKE '%not_capturable%'
               THEN 'expired' ELSE 'failed' END,
           failure_reason = left(COALESCE(p_error, 'settlement failed'), 500),
           settling_since = NULL,
           updated_at = now()
     WHERE id = pb.id;
    RETURN jsonb_build_object('ok', false, 'status', 200, 'recorded', true,
                              'hold_status', 'failed');
  END IF;

  IF p_action = 'release' THEN
    UPDATE auction_proxy_bids
       SET hold_status = 'released', released_at = now(),
           settle_amount_cents = COALESCE(p_amount_cents, settle_amount_cents),
           settling_since = NULL, updated_at = now()
     WHERE id = pb.id;
    RETURN jsonb_build_object('ok', true, 'status', 200, 'hold_status', 'released');
  END IF;

  -- Captured. Record it, then turn it into an order + inventory movement.
  SELECT COALESCE(bt.display_name, 'bidder') INTO v_handle
    FROM bidder_trust_scores bt WHERE bt.id = pb.bidder_trust_id;

  UPDATE auction_proxy_bids
     SET hold_status = 'captured', captured_at = now(),
         settle_amount_cents = COALESCE(p_amount_cents, settle_amount_cents),
         settling_since = NULL, updated_at = now()
   WHERE id = pb.id;

  v_order := commerce_fulfil_paid_sale(
    pb.auction_id,
    COALESCE(v_handle, 'bidder'),
    COALESCE(p_amount_cents, pb.settle_amount_cents, pb.max_cents),
    pb.stripe_payment_intent_id,
    'auction',
    NULL
  );

  IF (v_order->>'ok')::boolean THEN
    v_order_id := (v_order->>'order_id')::uuid;
    UPDATE auction_proxy_bids SET order_id = v_order_id WHERE id = pb.id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 200, 'hold_status', 'captured',
                            'order', v_order);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Watch for authorizations about to lapse.
--    Stripe voids uncaptured auths after ~7 days. This surfaces the ones
--    running out so the auction can be closed early or the bidder re-charged,
--    instead of the money quietly evaporating.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION luxi_authorizations_at_risk(p_hours integer DEFAULT 24)
RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'proxy_id', pb.id,
           'auction_id', pb.auction_id,
           'auction_title', a.item_title,
           'auction_status', a.status,
           'max_cents', pb.max_cents,
           'expires_at', pb.authorization_expires_at,
           'payment_intent_id', pb.stripe_payment_intent_id
         ) ORDER BY pb.authorization_expires_at), '[]'::jsonb)
  FROM auction_proxy_bids pb
  JOIN auctions a ON a.id = pb.auction_id
  WHERE pb.hold_status = 'authorized'
    AND pb.authorization_expires_at IS NOT NULL
    AND pb.authorization_expires_at < now() + make_interval(hours => GREATEST(COALESCE(p_hours,24),1));
$$;

-- Settlements that claimed a row and then died mid-flight would sit in
-- 'settling' forever. Return anything stuck for more than 15 minutes so the
-- next cron run retries it.
CREATE OR REPLACE FUNCTION luxi_requeue_stuck_settlements()
RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH stuck AS (
    UPDATE auction_proxy_bids
       SET hold_status = 'authorized', settling_since = NULL, updated_at = now()
     WHERE hold_status = 'settling'
       AND settling_since < now() - interval '15 minutes'
     RETURNING id
  )
  SELECT jsonb_build_object('ok', true, 'requeued', (SELECT count(*) FROM stuck));
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Buy Now settlement — same one-transaction guarantee as the auction path.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION commerce_settle_buy_now(
  p_auction_id        uuid,
  p_handle            text,
  p_amount_cents      integer,
  p_payment_intent_id text,
  p_reservation_id    uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order jsonb;
BEGIN
  v_order := commerce_fulfil_paid_sale(
    p_auction_id, p_handle, p_amount_cents, p_payment_intent_id,
    'buy_now', p_reservation_id
  );
  -- Only a genuinely fulfilled sale closes the auction. If stock ran out the
  -- order call fails, the auction stays open, and the operator gets a refund
  -- to make -- rather than a closed auction with nothing behind it.
  IF (v_order->>'ok')::boolean THEN
    UPDATE auctions
       SET status = 'closed_sold', sold_via = 'buy_now',
           current_high_bid_cents = GREATEST(COALESCE(p_amount_cents,0), 0),
           actual_close_at = COALESCE(actual_close_at, now())
     WHERE id = p_auction_id AND status IN ('open','extended','scheduled');
  END IF;
  RETURN v_order;
END $$;

COMMIT;

-- Verify:
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='auction_proxy_bids' AND column_name IN
--     ('authorization_expires_at','settling_since','capture_attempts','order_id');
-- SELECT * FROM luxi_claim_proxy_settlements(10);   -- empty until an auction closes
-- SELECT luxi_authorizations_at_risk(24);
