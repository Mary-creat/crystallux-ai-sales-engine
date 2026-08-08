-- Crystallux — authorization lifecycle + settlement safety
-- =========================================================
-- Apply AFTER commerce-phase1-payment-hardening.sql. Idempotent.
--
-- Three money-correctness changes.
--
-- 1. A DUPLICATE WORKER MUST NEVER MARK A CAPTURED PAYMENT AS FAILED.
--    luxi_settle_proxy_result wrote the failure branch unconditionally. The
--    atomic claim makes a duplicate unlikely, but "unlikely" is the wrong
--    standard when the consequence is a collected payment recorded as failed,
--    a refund issued for money we keep, and an order that never ships.
--    Captured is now terminal: nothing downgrades it.
--
-- 2. STOP GUESSING WHEN AN AUTHORIZATION DIES.
--    Stripe publishes the real deadline on the charge as
--    payment_method_details.card.capture_before. Seven days is the common
--    case, not a rule -- it varies by card and merchant category. We store
--    what Stripe actually says and drive warnings off that.
--
-- 3. RAISING A MAXIMUM BID NEEDS A DOCUMENTED STRATEGY, NOT AN ASSUMPTION.
--    See the note on authorization_strategy below.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Authorization lifecycle columns
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE auction_proxy_bids
  ADD COLUMN IF NOT EXISTS authorization_created_at timestamptz;
-- Stripe's own deadline, read from the charge. NOT computed by us.
ALTER TABLE auction_proxy_bids
  ADD COLUMN IF NOT EXISTS capture_before           timestamptz;
ALTER TABLE auction_proxy_bids
  ADD COLUMN IF NOT EXISTS authorization_status     text;
ALTER TABLE auction_proxy_bids
  ADD COLUMN IF NOT EXISTS expiry_warning_at        timestamptz;
-- 'available' | 'unavailable' | null, straight from Stripe. Decides whether a
-- raise can increment or must re-authorize. See below.
ALTER TABLE auction_proxy_bids
  ADD COLUMN IF NOT EXISTS incremental_auth_status  text;
-- Which strategy actually produced this authorization, so the audit trail
-- records what happened rather than what we intended.
ALTER TABLE auction_proxy_bids
  ADD COLUMN IF NOT EXISTS authorization_strategy   text;
ALTER TABLE auction_proxy_bids
  ADD COLUMN IF NOT EXISTS replaces_payment_intent_id text;

DO $$
BEGIN
  ALTER TABLE auction_proxy_bids DROP CONSTRAINT IF EXISTS apx_auth_status_check;
  ALTER TABLE auction_proxy_bids
    ADD CONSTRAINT apx_auth_status_check
    CHECK (authorization_status IS NULL OR authorization_status IN (
      'requires_action',   -- 3DS outstanding: the bid is NOT active yet
      'authorized',
      'expiring_soon',
      'reauth_required',
      'capturing',
      'captured',
      'cancelled',
      'expired',
      'failed'
    ));

  ALTER TABLE auction_proxy_bids DROP CONSTRAINT IF EXISTS apx_auth_strategy_check;
  ALTER TABLE auction_proxy_bids
    ADD CONSTRAINT apx_auth_strategy_check
    CHECK (authorization_strategy IS NULL OR authorization_strategy IN (
      'initial','increment','replace'
    ));
END $$;

CREATE INDEX IF NOT EXISTS apx_capture_before_idx
  ON auction_proxy_bids (capture_before)
  WHERE hold_status = 'authorized';

COMMENT ON COLUMN auction_proxy_bids.capture_before IS
  'Stripe payment_method_details.card.capture_before -- the real deadline. '
  'Never compute this; read it from the charge.';
COMMENT ON COLUMN auction_proxy_bids.authorization_strategy IS
  'initial | increment | replace. increment requires IC+ pricing and is '
  'Visa/MC/Amex/Discover only, so replace is the default path.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Record an authorization, including what Stripe said about it
-- ─────────────────────────────────────────────────────────────────────────────

-- Keyed on the payment intent rather than the proxy id: the caller is the
-- confirm-bid workflow, which holds the intent id but would otherwise have to
-- thread a proxy id through two more nodes to get here.
CREATE OR REPLACE FUNCTION luxi_record_authorization(
  p_payment_intent_id text,
  p_capture_before    timestamptz DEFAULT NULL,
  p_incremental       text DEFAULT NULL,
  p_strategy          text DEFAULT 'initial',
  p_replaces_pi       text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_warn timestamptz; v_rows integer;
BEGIN
  IF p_payment_intent_id IS NULL OR length(trim(p_payment_intent_id)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'status', 400,
                              'error', 'payment_intent_id required');
  END IF;
  -- Warn a day before Stripe's deadline, or at the midpoint if the window is
  -- shorter than two days. Anchored to the real deadline, never to a guess.
  IF p_capture_before IS NOT NULL THEN
    v_warn := CASE
      WHEN p_capture_before - now() > interval '2 days' THEN p_capture_before - interval '24 hours'
      ELSE now() + ((p_capture_before - now()) / 2)
    END;
  END IF;

  UPDATE auction_proxy_bids
     SET authorization_created_at  = COALESCE(authorization_created_at, now()),
         capture_before            = COALESCE(p_capture_before, capture_before),
         expiry_warning_at         = COALESCE(v_warn, expiry_warning_at),
         incremental_auth_status   = COALESCE(p_incremental, incremental_auth_status),
         authorization_strategy    = COALESCE(p_strategy, authorization_strategy),
         replaces_payment_intent_id= COALESCE(p_replaces_pi, replaces_payment_intent_id),
         authorization_status      = 'authorized',
         authorized_at             = COALESCE(authorized_at, now()),
         updated_at                = now()
   -- Only ever annotate a live hold. Never resurrect one that already
   -- captured, released or expired.
   WHERE stripe_payment_intent_id = p_payment_intent_id
     AND COALESCE(hold_status, 'authorized') IN ('authorized','settling');

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'status', 200, 'updated', v_rows,
                            'capture_before', p_capture_before,
                            'expiry_warning_at', v_warn);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Settlement result -- captured is terminal
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION luxi_settle_proxy_result(
  p_proxy_id  uuid,
  p_action    text,
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

  -- CAPTURED IS TERMINAL. A late or duplicate worker reporting failure against
  -- an already-captured payment is reporting on a stale view of the world, not
  -- on money that moved. Downgrading here would mean refunding a payment we
  -- kept and never shipping the order.
  IF pb.hold_status = 'captured' THEN
    RETURN jsonb_build_object('ok', true, 'status', 200, 'hold_status', 'captured',
                              'ignored', true,
                              'note', 'already captured; refusing to change a terminal state');
  END IF;

  IF NOT p_succeeded THEN
    UPDATE auction_proxy_bids
       SET hold_status = CASE
             WHEN p_error ILIKE '%expired%' OR p_error ILIKE '%not_capturable%'
               THEN 'expired' ELSE 'failed' END,
           authorization_status = CASE
             WHEN p_error ILIKE '%expired%' OR p_error ILIKE '%not_capturable%'
               THEN 'expired' ELSE 'failed' END,
           failure_reason = left(COALESCE(p_error, 'settlement failed'), 500),
           settling_since = NULL,
           updated_at = now()
     WHERE id = pb.id;
    RETURN jsonb_build_object('ok', false, 'status', 200, 'recorded', true);
  END IF;

  IF p_action = 'release' THEN
    UPDATE auction_proxy_bids
       SET hold_status = 'released', authorization_status = 'cancelled',
           released_at = now(),
           settle_amount_cents = COALESCE(p_amount_cents, settle_amount_cents),
           settling_since = NULL, updated_at = now()
     WHERE id = pb.id;
    RETURN jsonb_build_object('ok', true, 'status', 200, 'hold_status', 'released');
  END IF;

  SELECT COALESCE(bt.display_name, 'bidder') INTO v_handle
    FROM bidder_trust_scores bt WHERE bt.id = pb.bidder_trust_id;

  UPDATE auction_proxy_bids
     SET hold_status = 'captured', authorization_status = 'captured',
         captured_at = now(),
         settle_amount_cents = COALESCE(p_amount_cents, settle_amount_cents),
         settling_since = NULL, updated_at = now()
   WHERE id = pb.id;

  v_order := commerce_fulfil_paid_sale(
    pb.auction_id, COALESCE(v_handle, 'bidder'),
    COALESCE(p_amount_cents, pb.settle_amount_cents, pb.max_cents),
    pb.stripe_payment_intent_id, 'auction', NULL);

  IF (v_order->>'ok')::boolean THEN
    v_order_id := (v_order->>'order_id')::uuid;
    UPDATE auction_proxy_bids SET order_id = v_order_id WHERE id = pb.id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 200, 'hold_status', 'captured',
                            'order', v_order);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Health view driven by Stripe's deadline, not a hard-coded window
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION luxi_authorization_health()
RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'proxy_id', pb.id,
           'auction_id', pb.auction_id,
           'auction_title', a.item_title,
           'auction_status', a.status,
           'auction_closes_at', a.scheduled_close_at,
           'max_cents', pb.max_cents,
           'capture_before', pb.capture_before,
           'payment_intent_id', pb.stripe_payment_intent_id,
           'state', CASE
             WHEN pb.capture_before IS NULL                  THEN 'UNKNOWN'
             WHEN pb.capture_before <= now()                 THEN 'EXPIRED'
             -- The one that actually loses money: the auction is scheduled to
             -- end AFTER the authorization dies, so the winner cannot be
             -- charged. Surfaced before the show, not after.
             WHEN a.scheduled_close_at > pb.capture_before   THEN 'REAUTH_REQUIRED'
             WHEN pb.expiry_warning_at <= now()              THEN 'EXPIRING_SOON'
             ELSE 'SAFE' END
         ) ORDER BY pb.capture_before NULLS LAST), '[]'::jsonb)
  FROM auction_proxy_bids pb
  JOIN auctions a ON a.id = pb.auction_id
  WHERE pb.hold_status IN ('authorized','settling')
    AND a.status IN ('scheduled','open','extended','closed_sold');
$$;

-- Flip warnings without touching Stripe. Cron, every few minutes.
CREATE OR REPLACE FUNCTION luxi_mark_expiring_authorizations()
RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH upd AS (
    UPDATE auction_proxy_bids
       SET authorization_status = CASE
             WHEN capture_before <= now() THEN 'expired'
             ELSE 'expiring_soon' END,
           hold_status = CASE
             WHEN capture_before <= now() THEN 'expired'
             ELSE hold_status END,
           updated_at = now()
     WHERE hold_status = 'authorized'
       AND capture_before IS NOT NULL
       AND (capture_before <= now() OR expiry_warning_at <= now())
       AND COALESCE(authorization_status,'') NOT IN ('expiring_soon','expired')
     RETURNING id
  )
  SELECT jsonb_build_object('ok', true, 'marked', (SELECT count(*) FROM upd));
$$;

COMMIT;

-- ═════════════════════════════════════════════════════════════════════════════
-- RAISING A MAXIMUM BID -- the documented strategy
-- ═════════════════════════════════════════════════════════════════════════════
-- Verified against Stripe's incremental-authorization docs on 2026-08-08:
--
--   * increment_authorization is an IC+ PRICING FEATURE. On standard pricing
--     you must contact Stripe for access. Assume it is UNAVAILABLE.
--   * Visa / Mastercard / Amex / Discover only, with merchant-category limits
--     on Discover that liquidation auctions do not obviously satisfy.
--   * It must be requested at creation via
--     payment_method_options[card][request_incremental_authorization]=if_available,
--     and support is reported at
--     latest_charge.payment_method_details.card.incremental_authorization.status
--     as 'available' or 'unavailable'.
--   * Max 10 increments; each capped at the greater of 500 USD or 500%.
--   * It does NOT extend capture_before. A raise buys amount, never time.
--
-- Therefore the default path is REPLACE, not increment:
--
--   1. Create and confirm a NEW authorization for the higher maximum.
--   2. Only once it reaches requires_capture, point the proxy bid at it.
--   3. THEN cancel the old authorization.
--
-- The old hold is never released before the replacement succeeds. A brief
-- double hold is the acceptable cost: the alternative is a bidder who is
-- leading an auction with no funds behind them, which is the failure this
-- whole design exists to prevent. Tell the bidder both holds may appear
-- briefly.
--
-- If incremental_auth_status = 'available', increment is preferred (one hold,
-- no second 3DS) and authorization_strategy records 'increment'. Otherwise
-- 'replace'.
--
-- Verify:
-- SELECT luxi_authorization_health();
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name='auction_proxy_bids' AND column_name LIKE '%auth%';
