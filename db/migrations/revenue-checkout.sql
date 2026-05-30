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
