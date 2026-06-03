-- Trial login for free (sales-assisted) signups.
-- The public signup form previously tried a raw INSERT into auth_users with
-- user_role='client' but NO client_id -> that violates the auth_users CHECK
-- (a client must have a client_id), so it silently failed and no account was
-- ever created. This RPC fixes that and gives the signer an immediate TRIAL
-- login they can look around in:
--   * New signer    -> create their tenant (clients row, active=false so the
--                      lead engine does NOT run/bill for an unpaid trial) +
--                      their client login (verified, can log in, password NULL
--                      so they set it via the normal forgot-password flow).
--   * Existing user -> just make sure they can log in (verified + active) and
--                      note the product they're interested in.
--
-- Trial vs paid: this grants dashboard ACCESS (a look-around), with the tenant
-- left active=false. The paid path (clx_provision_paid_buyer) is what turns the
-- engine on. Idempotent.
--
-- Called by: clx-public-client-signup-v1 (the public signup webhook).
--   SELECT clx_provision_trial_signup('lead@example.com','sales_engine','Acme Co');

CREATE OR REPLACE FUNCTION clx_provision_trial_signup(p_email text, p_product text, p_company text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid;
  v_cid uuid;
  v_product text := nullif(lower(trim(coalesce(p_product, ''))), 'unspecified');
  v_products jsonb := CASE WHEN v_product IS NULL THEN '[]'::jsonb ELSE jsonb_build_array(v_product) END;
BEGIN
  IF coalesce(trim(p_email), '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'email required');
  END IF;

  -- 1) Existing account: just make sure they can log in; note the interest.
  UPDATE auth_users
     SET is_active      = true,
         email_verified = true,
         products       = CASE WHEN v_product IS NULL THEN products ELSE (
                            SELECT jsonb_agg(DISTINCT e) FROM (
                              SELECT jsonb_array_elements_text(coalesce(products, '[]'::jsonb)) AS e
                              UNION SELECT v_product
                            ) s) END,
         updated_at     = now()
   WHERE lower(email) = lower(p_email)
  RETURNING id INTO v_uid;

  IF v_uid IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'account_created', false, 'trial', true,
                              'user_id', v_uid, 'email', lower(p_email));
  END IF;

  -- 2) New signer: create their trial tenant (engine OFF), then their login.
  INSERT INTO clients (client_name, industry, product_type, notification_email, active, notes)
  VALUES (left(coalesce(nullif(trim(p_company), ''), 'Trial | ' || lower(p_email)), 200),
          'unspecified', coalesce(v_product, 'trial'), lower(p_email), false,
          'Free trial signup. Engine off until they upgrade. Interested in: ' || coalesce(v_product, 'unspecified'))
  RETURNING id INTO v_cid;

  INSERT INTO auth_users (email, password_hash, user_role, client_id,
                          email_verified, email_verified_at, products, is_active)
  VALUES (lower(p_email), NULL, 'client', v_cid,
          true, now(), v_products, true)
  ON CONFLICT (email) DO UPDATE
     SET is_active = true, email_verified = true, updated_at = now()
  RETURNING id INTO v_uid;

  RETURN jsonb_build_object('ok', true, 'account_created', true, 'trial', true,
                            'user_id', v_uid, 'client_id', v_cid, 'email', lower(p_email));
END;
$$;

-- Verify:
-- SELECT clx_provision_trial_signup('trial@example.com','sales_engine','Acme Co');
