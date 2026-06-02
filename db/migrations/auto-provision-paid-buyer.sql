-- Auto-provisioning on paid checkout (self-serve).
-- Idempotent. When someone pays a Stripe Payment Link, this fully provisions
-- them so they can log straight in — no manual step:
--   * Existing account  -> grant the product + activate + mark verified.
--   * Brand-new buyer    -> create their tenant (clients row) AND their client
--                           login (auth_users, role=client, verified, product
--                           granted, password NULL so they set it via the
--                           normal "forgot password" flow).
--
-- The auth_users CHECK constraint requires a client to have a client_id, which
-- is why we create the clients row first. The new clients row is left
-- active=false with industry='unspecified' — the buyer (or Mary) sets their
-- industry + city in onboarding to start lead-gen; access to the dashboard is
-- immediate either way.
--
-- Called by: clx-stripe-provision-on-payment-v1 (the Stripe webhook).
--   SELECT clx_provision_paid_buyer('test@example.com','sales_engine','growth');

CREATE OR REPLACE FUNCTION clx_provision_paid_buyer(p_email text, p_product text, p_plan text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid;
  v_cid uuid;
BEGIN
  IF coalesce(trim(p_email),'') = '' OR coalesce(trim(p_product),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'email and product required');
  END IF;

  -- 1) Existing account: grant the product (dedup), activate, mark verified.
  UPDATE auth_users
     SET products = (
           SELECT jsonb_agg(DISTINCT e) FROM (
             SELECT jsonb_array_elements_text(coalesce(products, '[]'::jsonb)) AS e
             UNION SELECT p_product
           ) s),
         is_active      = true,
         email_verified = true,
         updated_at     = now()
   WHERE lower(email) = lower(p_email)
  RETURNING id INTO v_uid;

  IF v_uid IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'account_created', false,
                              'user_id', v_uid, 'email', lower(p_email), 'product', p_product);
  END IF;

  -- 2) New buyer: create their tenant, then their client login.
  INSERT INTO clients (client_name, industry, product_type, notification_email, active, notes)
  VALUES (left('Client | ' || lower(p_email), 200),
          'unspecified', p_product, lower(p_email), false,
          'Auto-provisioned on paid checkout. Set industry + city to start lead-gen. plan=' || coalesce(p_plan,''))
  RETURNING id INTO v_cid;

  INSERT INTO auth_users (email, password_hash, user_role, client_id,
                          email_verified, email_verified_at, products, is_active)
  VALUES (lower(p_email), NULL, 'client', v_cid,
          true, now(), jsonb_build_array(p_product), true)
  ON CONFLICT (email) DO UPDATE
     SET products = (
           SELECT jsonb_agg(DISTINCT e) FROM (
             SELECT jsonb_array_elements_text(coalesce(auth_users.products, '[]'::jsonb)) AS e
             UNION SELECT p_product
           ) s),
         is_active      = true,
         email_verified = true,
         updated_at     = now()
  RETURNING id INTO v_uid;

  RETURN jsonb_build_object('ok', true, 'account_created', true,
                            'user_id', v_uid, 'client_id', v_cid,
                            'email', lower(p_email), 'product', p_product);
END;
$$;

-- Verify:
-- SELECT clx_provision_paid_buyer('newbuyer@example.com','sales_engine','growth');
