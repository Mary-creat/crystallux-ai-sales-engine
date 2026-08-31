-- ============================================================
-- Backend product entitlement — one check, reusing what exists
--
-- Today entitlement is enforced in the browser and nowhere else:
--   admin-dashboard/shared/auth.js:181  products.indexOf(name) !== -1
--   client-dashboard/shared/auth.js:158 products.indexOf(name) !== -1
-- Two of 326 workflows so much as mention `products`. A caller holding a
-- valid session token reaches client/* regardless of what was bought,
-- because the backend has never had anything to check against.
--
-- WHY IT COULD NOT: validate_session returns
--   TABLE(user_id, email, user_role, client_id, expires_at)
-- and no products. The gate that all 126 session-protected endpoints
-- call has no entitlement data in its hands.
--
-- WHY validate_session IS NOT CHANGED HERE: adding a column to a
-- RETURNS TABLE needs DROP + CREATE, on the single function every
-- authenticated endpoint on the platform depends on, with a PostgREST
-- schema reload behind it. That is the wrong thing to attach to a
-- feature migration. A separate function costs one extra RPC per gated
-- endpoint and risks nothing.
--
-- CANONICAL STORE: auth_users.products (jsonb array). Chosen because
-- both dashboards already read it and both grant paths already write
-- it -- clx-stripe-webhook-v1 and clx-admin-provision-client-v1, whose
-- allow-list is exactly
--   sales_engine, sentinel, ava, luxi, maxi, ciro, mga, smart_quote
-- clients.subscription_* and client_subscriptions are the other two
-- candidates; both are entirely empty and neither is read by any
-- frontend. This adds no fourth store.
--
-- Idempotent. The check functions read only; grant_product writes an
-- entitlement but is called by nothing until the Stripe grant node is
-- wired, so applying this migration entitles no one.
-- ============================================================

CREATE OR REPLACE FUNCTION check_product_entitlement(
  p_client_id uuid,
  p_product   text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_ok boolean := false;
BEGIN
  -- Fail closed on missing input. An absent tenant or product is not a
  -- reason to allow; it is a reason to refuse.
  IF p_client_id IS NULL OR p_product IS NULL OR btrim(p_product) = '' THEN
    RETURN false;
  END IF;

  -- Entitlement is held per user and asserted per tenant: the client is
  -- entitled when at least one of its active users holds the product.
  -- A suspended or deactivated user cannot carry an entitlement for the
  -- rest of the tenant.
  SELECT EXISTS (
    SELECT 1
      FROM auth_users u
     WHERE u.client_id = p_client_id
       AND u.is_active IS NOT FALSE
       AND u.suspended_at IS NULL
       AND u.products @> to_jsonb(ARRAY[p_product])
  ) INTO v_ok;

  RETURN COALESCE(v_ok, false);
END;
$fn$;

COMMENT ON FUNCTION check_product_entitlement(uuid, text) IS
  'True when an active, unsuspended user of this tenant holds the product in '
  'auth_users.products. Fails closed on NULL input. The single backend '
  'entitlement check -- frontend product gating is convenience, not security.';

GRANT EXECUTE ON FUNCTION check_product_entitlement(uuid, text) TO service_role;

-- ------------------------------------------------------------
-- Session + tenant + entitlement in one call
--
-- What a gated endpoint actually needs to know. Returning the reason
-- separately from the boolean lets a workflow answer 401 for a bad
-- session and 403 product_not_entitled for a good session without a
-- purchase -- two different failures that must not look alike.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION validate_session_for_product(
  p_token   text,
  p_product text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_user record;
BEGIN
  SELECT u.id, u.email, u.user_role, u.client_id, s.expires_at
    INTO v_user
    FROM auth_sessions s
    JOIN auth_users u ON u.id = s.user_id
   WHERE s.session_token = p_token
     AND s.revoked_at IS NULL
     AND s.expires_at > now()
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'status', 401, 'error', 'Invalid or expired session');
  END IF;

  -- Admin policy is unchanged: platform admins are not tenant-scoped and
  -- are not gated on a purchase. This mirrors the existing Check Admin
  -- convention rather than inventing a second rule.
  IF v_user.user_role = 'admin' THEN
    RETURN jsonb_build_object(
      'ok', true, 'user_id', v_user.id, 'email', v_user.email,
      'user_role', v_user.user_role, 'client_id', v_user.client_id,
      'entitled', true, 'entitlement_basis', 'admin');
  END IF;

  IF v_user.client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 403, 'error', 'No client associated with this user');
  END IF;

  IF NOT check_product_entitlement(v_user.client_id, p_product) THEN
    RETURN jsonb_build_object(
      'ok', false, 'status', 403, 'error', 'product_not_entitled',
      'product', p_product, 'client_id', v_user.client_id);
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'user_id', v_user.id, 'email', v_user.email,
    'user_role', v_user.user_role, 'client_id', v_user.client_id,
    'entitled', true, 'entitlement_basis', 'purchase');
END;
$fn$;

COMMENT ON FUNCTION validate_session_for_product(text, text) IS
  'Session + tenant + entitlement in one call. 401 for a bad session, 403 '
  'product_not_entitled for a valid session without the purchase. Admins pass '
  'per existing admin policy. validate_session is untouched.';

GRANT EXECUTE ON FUNCTION validate_session_for_product(text, text) TO service_role;

-- ------------------------------------------------------------
-- Granting, idempotently
--
-- clx-stripe-webhook-v1 touches auth_users.products in exactly one
-- place -- 'Suspend Auth Users', which sets it to [] on cancellation.
-- It can revoke an entitlement and has never had any code to grant
-- one. That, and not a configuration mistake, is why products = [] on
-- every user who has ever existed.
--
-- One function so the Stripe path and clx-admin-provision-client-v1
-- share the same grant, rather than each hand-rolling jsonb append.
-- Duplicate Stripe events are ordinary, so appending twice must be
-- harmless.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION grant_product(
  p_client_id uuid,
  p_product   text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_allowed text[] := ARRAY['sales_engine','sentinel','ava','luxi','maxi','ciro','mga','smart_quote'];
  v_count   integer;
BEGIN
  IF p_client_id IS NULL OR p_product IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'client_id and product required');
  END IF;

  -- Same allow-list clx-admin-provision-client-v1 already enforces. A
  -- typo must not silently mint an entitlement nobody can revoke.
  IF NOT (p_product = ANY (v_allowed)) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown product', 'product', p_product);
  END IF;

  UPDATE auth_users
     SET products = CASE
           WHEN products @> to_jsonb(ARRAY[p_product]) THEN products
           ELSE COALESCE(products, '[]'::jsonb) || to_jsonb(ARRAY[p_product])
         END,
         updated_at = now()
   WHERE client_id = p_client_id
     AND suspended_at IS NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true, 'product', p_product, 'client_id', p_client_id,
    'users_updated', v_count,
    'entitled', check_product_entitlement(p_client_id, p_product));
END;
$fn$;

COMMENT ON FUNCTION grant_product(uuid, text) IS
  'Idempotent product grant across a tenant''s active users. Re-running is a '
  'no-op, so a replayed Stripe event cannot double-grant. Allow-list matches '
  'clx-admin-provision-client-v1.';

GRANT EXECUTE ON FUNCTION grant_product(uuid, text) TO service_role;

-- ---- VERIFY ----
-- Expect both functions.
SELECT proname, pg_get_function_result(oid) AS returns
  FROM pg_proc WHERE proname IN ('check_product_entitlement', 'validate_session_for_product')
 ORDER BY proname;

-- Expect false everywhere: no user holds any product yet, which is the
-- finding this migration exists to make enforceable rather than to hide.
SELECT c.client_name,
       check_product_entitlement(c.id, 'sales_engine') AS sales_engine_entitled
  FROM clients c ORDER BY c.client_name;

-- Expect false: fails closed on NULL tenant.
SELECT check_product_entitlement(NULL, 'sales_engine') AS null_tenant_denied;

-- Expect ok=false, unknown product: a typo cannot mint an entitlement.
SELECT grant_product('00000000-0000-0000-0000-000000000000'::uuid, 'not_a_product') AS typo_refused;
