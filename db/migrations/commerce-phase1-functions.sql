-- Crystallux commerce — Phase 1 transaction functions
-- ===================================================
-- Apply AFTER commerce-phase1-inventory-orders.sql. Idempotent.
--
-- These are the ONLY sanctioned ways to move stock. Every one of them takes a
-- row lock on inventory_items before reading availability, so two simultaneous
-- buyers of the last unit serialise instead of both succeeding. Application
-- code must never UPDATE inventory_items directly -- the check constraint
-- inv_reserved_within_hand is the backstop, but these functions are the door.
--
-- The rule they collectively enforce:
--     BIDDING reserves nothing.
--     WINNING or starting a Buy Now reserves.
--     PAYMENT consumes.
--     FAILURE releases.
-- A payment that never completes must leave stock exactly as it found it.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: default Crystallux ids, so callers don't have to pass them yet.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION commerce_default_tenant() RETURNS uuid
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT id FROM commerce_tenants WHERE name = 'Crystallux' LIMIT 1;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Receive stock. The only way inventory enters the system.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION commerce_receive_stock(
  p_product_id   uuid,
  p_quantity     integer,
  p_condition    text DEFAULT 'used',
  p_cost_cents   integer DEFAULT 0,
  p_is_unique    boolean DEFAULT true,
  p_lot_code     text DEFAULT NULL,
  p_actor        text DEFAULT 'admin'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tenant uuid; v_seller uuid; v_wh uuid; v_item uuid;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'status', 400, 'error', 'quantity must be positive');
  END IF;
  IF p_condition NOT IN ('new','open_box','used','as_is') THEN
    RETURN jsonb_build_object('ok', false, 'status', 400, 'error', 'invalid condition');
  END IF;
  IF p_is_unique AND p_quantity <> 1 THEN
    RETURN jsonb_build_object('ok', false, 'status', 400,
      'error', 'a unique one-off unit must have quantity 1');
  END IF;

  v_tenant := commerce_default_tenant();
  SELECT id INTO v_seller FROM commerce_sellers    WHERE tenant_id = v_tenant LIMIT 1;
  SELECT id INTO v_wh     FROM commerce_warehouses WHERE tenant_id = v_tenant LIMIT 1;

  INSERT INTO inventory_items
    (tenant_id, seller_id, warehouse_id, product_id, lot_code, condition,
     is_unique, quantity_on_hand, quantity_reserved, acquisition_cost_cents)
  VALUES
    (v_tenant, v_seller, v_wh, p_product_id, p_lot_code, p_condition,
     p_is_unique, p_quantity, 0, COALESCE(p_cost_cents, 0))
  RETURNING id INTO v_item;

  INSERT INTO inventory_ledger
    (tenant_id, inventory_item_id, movement_type, quantity_delta, reason, reference_type, actor)
  VALUES
    (v_tenant, v_item, 'receipt', p_quantity, 'Stock received', 'manual', p_actor);

  RETURN jsonb_build_object('ok', true, 'status', 200, 'inventory_item_id', v_item);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Reserve stock. Row-locks the inventory item, so concurrent callers queue.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION commerce_reserve_stock(
  p_auction_id  uuid,
  p_held_for    text,
  p_quantity    integer DEFAULT 1,
  p_ttl_minutes integer DEFAULT 20
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_item uuid; v_tenant uuid; v_avail integer; v_resv uuid; v_qty integer;
BEGIN
  v_qty := GREATEST(COALESCE(p_quantity, 1), 1);

  SELECT a.inventory_item_id INTO v_item FROM auctions a WHERE a.id = p_auction_id;
  IF v_item IS NULL THEN
    -- Not an error: an auction with no inventory link is a demo/legacy listing
    -- and simply has no stock to protect.
    RETURN jsonb_build_object('ok', true, 'status', 200, 'reservation_id', NULL,
                              'skipped', true, 'reason', 'auction has no inventory link');
  END IF;

  -- The lock. Everything after this is serialised per inventory item.
  SELECT tenant_id, (quantity_on_hand - quantity_reserved)
    INTO v_tenant, v_avail
  FROM inventory_items WHERE id = v_item FOR UPDATE;

  IF v_avail IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'inventory item not found');
  END IF;
  IF v_avail < v_qty THEN
    RETURN jsonb_build_object('ok', false, 'status', 409,
      'error', 'Out of stock', 'available', v_avail, 'requested', v_qty);
  END IF;

  UPDATE inventory_items
     SET quantity_reserved = quantity_reserved + v_qty, updated_at = now()
   WHERE id = v_item;

  INSERT INTO stock_reservations
    (tenant_id, inventory_item_id, auction_id, quantity, status, held_for, expires_at)
  VALUES
    (v_tenant, v_item, p_auction_id, v_qty, 'held', p_held_for,
     now() + make_interval(mins => GREATEST(COALESCE(p_ttl_minutes, 20), 1)))
  RETURNING id INTO v_resv;

  INSERT INTO inventory_ledger
    (tenant_id, inventory_item_id, movement_type, quantity_delta, reserved_delta,
     reason, reference_type, reference_id, actor)
  VALUES
    (v_tenant, v_item, 'reserve', 0, v_qty, 'Reserved pending payment',
     'reservation', v_resv, COALESCE(p_held_for, 'system'));

  RETURN jsonb_build_object('ok', true, 'status', 200, 'reservation_id', v_resv,
                            'inventory_item_id', v_item);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Release a reservation. Payment failed, bidder lost, or checkout abandoned.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION commerce_release_reservation(
  p_reservation_id uuid,
  p_reason         text DEFAULT 'released'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM stock_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF r.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'reservation not found');
  END IF;
  -- Idempotent: releasing twice is a no-op, not a double credit.
  IF r.status <> 'held' THEN
    RETURN jsonb_build_object('ok', true, 'status', 200, 'already', r.status);
  END IF;

  PERFORM 1 FROM inventory_items WHERE id = r.inventory_item_id FOR UPDATE;

  UPDATE inventory_items
     SET quantity_reserved = GREATEST(quantity_reserved - r.quantity, 0), updated_at = now()
   WHERE id = r.inventory_item_id;

  UPDATE stock_reservations
     SET status = 'released', released_at = now()
   WHERE id = r.id;

  INSERT INTO inventory_ledger
    (tenant_id, inventory_item_id, movement_type, quantity_delta, reserved_delta,
     reason, reference_type, reference_id, actor)
  VALUES
    (r.tenant_id, r.inventory_item_id, 'release', 0, -r.quantity,
     COALESCE(p_reason, 'released'), 'reservation', r.id, 'system');

  RETURN jsonb_build_object('ok', true, 'status', 200, 'released', true);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Expire stale reservations. Cron, every minute.
--    Without this an abandoned checkout holds the last unit forever.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION commerce_expire_reservations()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; n integer := 0;
BEGIN
  FOR r IN
    SELECT id FROM stock_reservations
     WHERE status = 'held' AND expires_at < now()
     ORDER BY expires_at LIMIT 500
  LOOP
    PERFORM commerce_release_reservation(r.id, 'reservation expired');
    UPDATE stock_reservations SET status = 'expired' WHERE id = r.id;
    n := n + 1;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'expired', n);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. THE money path. Turn a captured payment into an order and consume stock.
--    Called by the Buy Now confirm workflow and by the auction settle cron
--    once Stripe reports the capture succeeded -- never before.
--
--    Idempotent on stripe_payment_intent_id: the settle cron can and does
--    retry, and Stripe webhooks arrive more than once. A second call returns
--    the first order rather than double-decrementing stock.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION commerce_fulfil_paid_sale(
  p_auction_id        uuid,
  p_customer_handle   text,
  p_amount_cents      integer,
  p_payment_intent_id text,
  p_channel           text DEFAULT 'auction',
  p_reservation_id    uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a record; inv record; v_order uuid; v_existing uuid;
  v_tenant uuid; v_seller uuid; v_qty integer; v_cost integer;
  -- Scalars, not a record: a record variable that is never SELECTed INTO
  -- raises "record is not assigned yet" the moment you read a field, and the
  -- reservation lookup below is conditional.
  v_resv_id uuid; v_resv_qty integer;
BEGIN
  IF p_payment_intent_id IS NULL OR length(trim(p_payment_intent_id)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'status', 400,
      'error', 'payment_intent_id is required -- an order is only created against a real payment');
  END IF;

  -- Idempotency gate, checked before anything is locked or moved.
  SELECT id INTO v_existing FROM orders
   WHERE stripe_payment_intent_id = p_payment_intent_id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'status', 200, 'order_id', v_existing,
                              'idempotent', true);
  END IF;

  SELECT * INTO a FROM auctions WHERE id = p_auction_id;
  IF a.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'auction not found');
  END IF;

  v_tenant := COALESCE(a.tenant_id, commerce_default_tenant());
  SELECT id INTO v_seller FROM commerce_sellers WHERE tenant_id = v_tenant LIMIT 1;
  v_qty := GREATEST(COALESCE(a.quantity_listed, 1), 1);

  -- No inventory link: still record the order so the money is accounted for,
  -- but touch no stock. Legacy/demo auctions must not silently vanish.
  IF a.inventory_item_id IS NULL THEN
    INSERT INTO orders (tenant_id, seller_id, channel, status, customer_handle,
                        customer_email, auction_id, stripe_payment_intent_id,
                        subtotal_cents, total_cents, cost_cents, paid_at)
    VALUES (v_tenant, v_seller, p_channel, 'paid', p_customer_handle,
            CASE WHEN p_customer_handle LIKE '%@%' THEN p_customer_handle END,
            p_auction_id, p_payment_intent_id,
            p_amount_cents, p_amount_cents, 0, now())
    RETURNING id INTO v_order;
    RETURN jsonb_build_object('ok', true, 'status', 200, 'order_id', v_order,
                              'inventory_touched', false);
  END IF;

  -- Lock the stock for the rest of the transaction.
  SELECT * INTO inv FROM inventory_items WHERE id = a.inventory_item_id FOR UPDATE;
  IF inv.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'inventory item not found');
  END IF;

  -- Prefer consuming the reservation made when the sale started; it already
  -- holds the units. Without one, take from free stock -- and refuse if there
  -- is none, which surfaces an oversell as a loud failure rather than negative
  -- inventory.
  IF p_reservation_id IS NOT NULL THEN
    SELECT id, quantity INTO v_resv_id, v_resv_qty
      FROM stock_reservations
     WHERE id = p_reservation_id AND status = 'held' FOR UPDATE;
  END IF;

  IF v_resv_id IS NOT NULL THEN
    UPDATE inventory_items
       SET quantity_on_hand  = quantity_on_hand  - v_resv_qty,
           quantity_reserved = GREATEST(quantity_reserved - v_resv_qty, 0),
           updated_at = now()
     WHERE id = inv.id;
    UPDATE stock_reservations SET status = 'consumed', consumed_at = now() WHERE id = v_resv_id;
    v_qty := v_resv_qty;
  ELSE
    IF (inv.quantity_on_hand - inv.quantity_reserved) < v_qty THEN
      RETURN jsonb_build_object('ok', false, 'status', 409,
        'error', 'Paid but out of stock -- refund required',
        'available', inv.quantity_on_hand - inv.quantity_reserved, 'requested', v_qty);
    END IF;
    UPDATE inventory_items
       SET quantity_on_hand = quantity_on_hand - v_qty, updated_at = now()
     WHERE id = inv.id;
  END IF;

  v_cost := COALESCE(inv.acquisition_cost_cents, 0) * v_qty;

  INSERT INTO orders (tenant_id, seller_id, channel, status, customer_handle,
                      customer_email, auction_id, stripe_payment_intent_id,
                      subtotal_cents, total_cents, cost_cents, paid_at)
  VALUES (v_tenant, v_seller, p_channel, 'paid', p_customer_handle,
          CASE WHEN p_customer_handle LIKE '%@%' THEN p_customer_handle END,
          p_auction_id, p_payment_intent_id,
          p_amount_cents, p_amount_cents, v_cost, now())
  RETURNING id INTO v_order;

  INSERT INTO order_items
    (order_id, product_id, inventory_item_id, reservation_id, title_snapshot,
     condition_snapshot, quantity, unit_price_cents, unit_cost_cents)
  VALUES
    (v_order, COALESCE(a.product_id, inv.product_id), inv.id,
     v_resv_id,
     COALESCE(a.item_title, 'Item'), inv.condition, v_qty,
     CASE WHEN v_qty > 0 THEN p_amount_cents / v_qty ELSE p_amount_cents END,
     COALESCE(inv.acquisition_cost_cents, 0));

  INSERT INTO inventory_ledger
    (tenant_id, inventory_item_id, movement_type, quantity_delta, reserved_delta,
     reason, reference_type, reference_id, actor)
  VALUES
    (v_tenant, inv.id, 'sold', -v_qty,
     CASE WHEN v_resv_id IS NOT NULL THEN -v_resv_qty ELSE 0 END,
     'Sold via ' || p_channel, 'order', v_order, COALESCE(p_customer_handle, 'system'));

  RETURN jsonb_build_object('ok', true, 'status', 200, 'order_id', v_order,
                            'inventory_touched', true, 'quantity', v_qty);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Fulfilment transitions. Server-side so the UI cannot invent a state.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION commerce_advance_order(
  p_order_id uuid,
  p_status   text,
  p_actor    text DEFAULT 'admin'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o record; v_allowed boolean := false;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'order not found');
  END IF;

  -- Only forward moves along the documented path, plus cancel/refund.
  v_allowed := (o.status = 'paid'    AND p_status IN ('picking','cancelled','refunded'))
            OR (o.status = 'picking' AND p_status IN ('ready','cancelled','refunded'))
            OR (o.status = 'ready'   AND p_status IN ('fulfilled','cancelled','refunded'))
            OR (o.status = 'pending_payment' AND p_status = 'cancelled');

  IF NOT v_allowed THEN
    RETURN jsonb_build_object('ok', false, 'status', 409,
      'error', format('cannot move an order from %s to %s', o.status, p_status));
  END IF;

  UPDATE orders
     SET status = p_status,
         picked_at    = CASE WHEN p_status = 'picking'   THEN now() ELSE picked_at END,
         ready_at     = CASE WHEN p_status = 'ready'     THEN now() ELSE ready_at END,
         fulfilled_at = CASE WHEN p_status = 'fulfilled' THEN now() ELSE fulfilled_at END,
         cancelled_at = CASE WHEN p_status IN ('cancelled','refunded') THEN now() ELSE cancelled_at END,
         updated_at   = now()
   WHERE id = o.id;

  -- A cancelled or refunded order puts the goods back. Without this a refund
  -- quietly destroys inventory.
  IF p_status IN ('cancelled','refunded') THEN
    INSERT INTO inventory_ledger
      (tenant_id, inventory_item_id, movement_type, quantity_delta, reason,
       reference_type, reference_id, actor)
    SELECT o.tenant_id, oi.inventory_item_id, 'return', oi.quantity,
           'Order ' || p_status, 'order', o.id, p_actor
    FROM order_items oi WHERE oi.order_id = o.id;

    UPDATE inventory_items i
       SET quantity_on_hand = i.quantity_on_hand + oi.quantity, updated_at = now()
      FROM order_items oi
     WHERE oi.order_id = o.id AND i.id = oi.inventory_item_id;
  END IF;

  IF p_status = 'picking' THEN
    INSERT INTO inventory_ledger
      (tenant_id, inventory_item_id, movement_type, quantity_delta, reason,
       reference_type, reference_id, actor)
    SELECT o.tenant_id, oi.inventory_item_id, 'pick', 0, 'Picked for fulfilment',
           'order', o.id, p_actor
    FROM order_items oi WHERE oi.order_id = o.id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 200, 'order_status', p_status);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Bid audit writer. Records the attempt whatever the outcome.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION commerce_record_bid_attempt(
  p_auction_id  uuid,
  p_handle      text,
  p_cents       integer,
  p_outcome     text,
  p_reason      text DEFAULT NULL,
  p_source      text DEFAULT 'web',
  p_bid_id      uuid DEFAULT NULL,
  p_high_before integer DEFAULT NULL,
  p_high_after  integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO auction_bid_audit
    (auction_id, bid_id, bidder_handle, source, attempted_cents, outcome, reason,
     high_bid_before, high_bid_after)
  VALUES
    (p_auction_id, p_bid_id, p_handle, COALESCE(p_source,'web'), p_cents,
     p_outcome, p_reason, p_high_before, p_high_after)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'audit_id', v_id);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. One-call product creation straight into the live sale queue.
--    "Admin must be able to create a product and put it into the live-sale
--    queue quickly" -- product, stock and lot in a single atomic call.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION commerce_quick_list(
  p_title           text,
  p_condition       text DEFAULT 'used',
  p_cost_cents      integer DEFAULT 0,
  p_start_bid_cents integer DEFAULT 100,
  p_reserve_cents   integer DEFAULT 0,
  p_buy_now_cents   integer DEFAULT NULL,
  p_listing_type    text DEFAULT 'both',
  p_quantity        integer DEFAULT 1,
  p_description     text DEFAULT NULL,
  p_category        text DEFAULT NULL,
  p_retail_cents    integer DEFAULT NULL,
  p_lot_number      text DEFAULT NULL,
  p_queue_position  integer DEFAULT NULL,
  p_duration_mins   integer DEFAULT 10,
  p_actor           text DEFAULT 'admin'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tenant uuid; v_seller uuid; v_wh uuid; v_avatar uuid;
  v_product uuid; v_recv jsonb; v_item uuid; v_auction uuid; v_lot text;
BEGIN
  IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'status', 400, 'error', 'title is required');
  END IF;
  IF p_listing_type NOT IN ('auction','buy_now','both') THEN
    RETURN jsonb_build_object('ok', false, 'status', 400, 'error', 'invalid listing_type');
  END IF;
  IF p_listing_type IN ('buy_now','both') AND COALESCE(p_buy_now_cents, 0) <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'status', 400,
      'error', 'a Buy Now price is required for buy_now/both listings');
  END IF;

  v_tenant := commerce_default_tenant();
  SELECT id INTO v_seller FROM commerce_sellers    WHERE tenant_id = v_tenant LIMIT 1;
  SELECT id INTO v_wh     FROM commerce_warehouses WHERE tenant_id = v_tenant LIMIT 1;
  SELECT id INTO v_avatar FROM avatars WHERE avatar_name = 'LUXI';
  IF v_avatar IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'LUXI avatar not found');
  END IF;

  INSERT INTO products (tenant_id, seller_id, title, description, category, retail_reference_cents)
  VALUES (v_tenant, v_seller, trim(p_title), p_description, p_category, p_retail_cents)
  RETURNING id INTO v_product;

  v_recv := commerce_receive_stock(v_product, GREATEST(COALESCE(p_quantity,1),1),
                                   p_condition, COALESCE(p_cost_cents,0),
                                   COALESCE(p_quantity,1) = 1, p_lot_number, p_actor);
  IF NOT (v_recv->>'ok')::boolean THEN RETURN v_recv; END IF;
  v_item := (v_recv->>'inventory_item_id')::uuid;

  v_lot := COALESCE(p_lot_number, 'LOT-' || nextval('lot_number_seq')::text);

  -- Created in 'scheduled', NOT open. The server opens it when the show
  -- reaches that lot; nothing goes live merely by existing.
  INSERT INTO auctions (
    avatar_id, tenant_id, seller_id, warehouse_id, product_id, inventory_item_id,
    lot_number, queue_position, quantity_listed,
    item_title, item_description, item_category, status,
    scheduled_open_at, scheduled_close_at,
    start_bid_cents, reserve_price_cents, min_increment_cents, current_high_bid_cents,
    listing_type, buy_now_price_cents,
    anti_snipe_window_seconds, anti_snipe_extend_seconds, anti_snipe_max_extensions
  ) VALUES (
    v_avatar, v_tenant, v_seller, v_wh, v_product, v_item,
    v_lot, p_queue_position, GREATEST(COALESCE(p_quantity,1),1),
    trim(p_title), p_description, p_category, 'scheduled',
    now(), now() + make_interval(mins => GREATEST(COALESCE(p_duration_mins,10),1)),
    COALESCE(p_start_bid_cents,100), COALESCE(p_reserve_cents,0),
    GREATEST(COALESCE(p_start_bid_cents,100),100), 0,
    p_listing_type, p_buy_now_cents,
    30, 30, 10
  ) RETURNING id INTO v_auction;

  RETURN jsonb_build_object('ok', true, 'status', 200,
    'product_id', v_product, 'inventory_item_id', v_item,
    'auction_id', v_auction, 'lot_number', v_lot);
END $$;

COMMIT;

-- Verify:
-- SELECT commerce_quick_list('Test Patio Set','open_box',4000,500,0,12000,'both',1);
-- SELECT quantity_on_hand, quantity_reserved FROM inventory_items ORDER BY created_at DESC LIMIT 1;
-- SELECT movement_type, quantity_delta, reserved_delta FROM inventory_ledger ORDER BY created_at DESC LIMIT 5;
