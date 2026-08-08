-- Crystallux — saved payment methods for repeat bidders
-- ======================================================
-- Apply AFTER commerce-lot-control.sql. Idempotent.
--
-- THE PROBLEM
-- A bidder re-enters their card for every lot, and again every time they raise
-- a maximum. In a live show with ten lots that is ten card entries, and each
-- one is a chance to give up. Repeat buyers are the whole economics of live
-- commerce.
--
-- THE APPROACH
-- Stripe SetupIntent: collect the card once, attached to a Stripe Customer,
-- with recorded consent for later off-session use. Subsequent bids confirm a
-- PaymentIntent against the saved payment method with no card form at all.
--
-- REUSES THE EXISTING IDENTITY PATH. bidder_trust_scores already carries
-- stripe_customer_id, and luxi_register_bidder('web', handle) already maps a
-- handle to a bidder row. This adds columns to that table rather than
-- introducing a second notion of who a customer is.
--
-- TWO THINGS VERIFIED AGAINST STRIPE'S DOCS ON 2026-08-08, NOT ASSUMED:
--
-- 1. An off-session charge may be classified MERCHANT-INITIATED, and Visa's
--    authorization window for MIT is 5 days rather than the 7 for a
--    customer-initiated one. So a saved-card hold can expire SOONER than a
--    typed-in card's. Stripe classifies on signals of cardholder
--    participation, not on the off_session flag alone, so we cannot predict
--    it -- which is exactly why capture_before is read from the charge
--    instead of being computed.
--
-- 2. An off-session confirm can still be declined with authentication_required.
--    That is NOT a dead end: the declined PaymentIntent's client_secret is
--    handed back to the browser so the bidder can complete 3DS. A bid whose
--    authentication never completes must never count as funded.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. The saved card lives with the bidder
-- ─────────────────────────────────────────────────────────────────────────────
-- Only the Stripe identifiers and a display fingerprint. No PAN, no CVC --
-- Stripe holds the card, we hold a reference and four digits.

ALTER TABLE bidder_trust_scores
  ADD COLUMN IF NOT EXISTS stripe_payment_method_id text;
ALTER TABLE bidder_trust_scores
  ADD COLUMN IF NOT EXISTS card_brand      text;
ALTER TABLE bidder_trust_scores
  ADD COLUMN IF NOT EXISTS card_last4      text;
ALTER TABLE bidder_trust_scores
  ADD COLUMN IF NOT EXISTS card_exp_month  integer;
ALTER TABLE bidder_trust_scores
  ADD COLUMN IF NOT EXISTS card_exp_year   integer;
-- Stripe requires that consent for off-session use be recorded and kept. We
-- store the exact wording shown, not a boolean, so what the bidder actually
-- agreed to can be produced later.
ALTER TABLE bidder_trust_scores
  ADD COLUMN IF NOT EXISTS saved_card_consent_at   timestamptz;
ALTER TABLE bidder_trust_scores
  ADD COLUMN IF NOT EXISTS saved_card_consent_text text;

CREATE INDEX IF NOT EXISTS bts_saved_card_idx
  ON bidder_trust_scores (stripe_customer_id)
  WHERE stripe_payment_method_id IS NOT NULL;

COMMENT ON COLUMN bidder_trust_scores.saved_card_consent_text IS
  'The exact wording the bidder agreed to. Stored verbatim because "they '
  'ticked a box" is not a defence if the wording is later disputed.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Read — safe to hand to a browser
-- ─────────────────────────────────────────────────────────────────────────────
-- Deliberately does NOT return stripe_payment_method_id or the customer id.
-- The page only needs to know a card exists and how to name it; the server
-- resolves the identifiers when it charges. A payment method id in a browser
-- is not catastrophic, but there is no reason to put it there.

CREATE OR REPLACE FUNCTION luxi_saved_card(p_handle text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b record;
BEGIN
  IF coalesce(trim(p_handle), '') = '' THEN
    RETURN jsonb_build_object('ok', true, 'has_card', false);
  END IF;

  SELECT * INTO b FROM bidder_trust_scores
   WHERE id = luxi_register_bidder('web', p_handle);

  IF b.id IS NULL OR b.stripe_payment_method_id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'has_card', false);
  END IF;

  -- An expired card is worse than no card: it looks usable and fails at the
  -- worst moment. Treat it as absent so the bidder is asked for a new one.
  IF b.card_exp_year IS NOT NULL AND b.card_exp_month IS NOT NULL THEN
    IF make_date(b.card_exp_year, b.card_exp_month, 1) + interval '1 month' <= now() THEN
      RETURN jsonb_build_object('ok', true, 'has_card', false, 'expired', true);
    END IF;
  END IF;

  IF b.banned_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'has_card', false, 'blocked', true);
  END IF;

  RETURN jsonb_build_object('ok', true, 'has_card', true,
    'brand', b.card_brand, 'last4', b.card_last4,
    'exp_month', b.card_exp_month, 'exp_year', b.card_exp_year,
    'label', COALESCE(initcap(b.card_brand), 'Card') || ' ending ' || COALESCE(b.card_last4, '****'));
END $$;

-- Server-side resolution of the identifiers. Separate function so the public
-- one above cannot leak them by accident.
CREATE OR REPLACE FUNCTION luxi_saved_card_secrets(p_handle text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b record;
BEGIN
  SELECT * INTO b FROM bidder_trust_scores
   WHERE id = luxi_register_bidder('web', p_handle);
  IF b.id IS NULL THEN RETURN jsonb_build_object('ok', false); END IF;
  RETURN jsonb_build_object('ok', true,
    'bidder_id', b.id,
    'customer_id', b.stripe_customer_id,
    'payment_method_id', b.stripe_payment_method_id,
    'banned', b.banned_at IS NOT NULL);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Write
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION luxi_attach_stripe_customer(
  p_handle text,
  p_customer_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bidder uuid; v_existing text;
BEGIN
  v_bidder := luxi_register_bidder('web', p_handle);
  SELECT stripe_customer_id INTO v_existing FROM bidder_trust_scores WHERE id = v_bidder;
  -- Never overwrite an existing customer id: doing so orphans every payment
  -- method already attached to it.
  IF v_existing IS NOT NULL AND v_existing <> '' THEN
    RETURN jsonb_build_object('ok', true, 'bidder_id', v_bidder,
                              'customer_id', v_existing, 'reused', true);
  END IF;
  UPDATE bidder_trust_scores
     SET stripe_customer_id = p_customer_id, updated_at = now()
   WHERE id = v_bidder;
  RETURN jsonb_build_object('ok', true, 'bidder_id', v_bidder,
                            'customer_id', p_customer_id, 'reused', false);
END $$;

CREATE OR REPLACE FUNCTION luxi_record_saved_card(
  p_handle        text,
  p_payment_method_id text,
  p_brand         text DEFAULT NULL,
  p_last4         text DEFAULT NULL,
  p_exp_month     integer DEFAULT NULL,
  p_exp_year      integer DEFAULT NULL,
  p_consent_text  text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bidder uuid;
BEGIN
  IF coalesce(trim(p_payment_method_id), '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'status', 400,
                              'error', 'payment_method_id required');
  END IF;
  v_bidder := luxi_register_bidder('web', p_handle);

  UPDATE bidder_trust_scores
     SET stripe_payment_method_id = p_payment_method_id,
         card_brand = p_brand, card_last4 = p_last4,
         card_exp_month = p_exp_month, card_exp_year = p_exp_year,
         saved_card_consent_at = now(),
         saved_card_consent_text = COALESCE(p_consent_text, saved_card_consent_text),
         updated_at = now()
   WHERE id = v_bidder;

  PERFORM commerce_emit('customer.card_saved', 'bidder', v_bidder,
    jsonb_build_object('brand', p_brand, 'last4', p_last4),
    NULL, p_handle, 'card_saved:' || p_payment_method_id);

  RETURN jsonb_build_object('ok', true, 'status', 200, 'bidder_id', v_bidder);
END $$;

-- A bidder must be able to remove a stored card. Consumer-protection basics,
-- and the absence of it is the kind of thing that turns a complaint into a
-- regulator's letter.
CREATE OR REPLACE FUNCTION luxi_forget_saved_card(p_handle text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bidder uuid; v_pm text;
BEGIN
  v_bidder := luxi_register_bidder('web', p_handle);
  SELECT stripe_payment_method_id INTO v_pm FROM bidder_trust_scores WHERE id = v_bidder;

  UPDATE bidder_trust_scores
     SET stripe_payment_method_id = NULL, card_brand = NULL, card_last4 = NULL,
         card_exp_month = NULL, card_exp_year = NULL, updated_at = now()
   WHERE id = v_bidder;

  -- The caller detaches it at Stripe; we return the id so it can.
  RETURN jsonb_build_object('ok', true, 'status', 200,
                            'detach_payment_method_id', v_pm);
END $$;

COMMIT;

-- Verify:
-- SELECT luxi_saved_card('someone@example.com');   -- {"ok":true,"has_card":false}
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name='bidder_trust_scores' AND column_name LIKE '%card%';
