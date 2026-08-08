-- Crystallux — fix quantity semantics in commerce_quick_list
-- ===========================================================
-- Apply AFTER commerce-phase1-tenant-reconcile.sql. Idempotent.
--
-- THE BUG
-- commerce_quick_list set auctions.quantity_listed = p_quantity, and
-- commerce_fulfil_paid_sale deducts quantity_listed on a sale. So "Air fryer,
-- quantity 5, cost $50, Buy Now $157" created ONE lot that, when sold once,
-- removed all five units and booked cost at 5 x $50 = $250 against $157 of
-- revenue: a $93 recorded loss and four units silently gone.
--
-- Two different things were sharing one number:
--   how many units we RECEIVED  (stock)
--   how many units ONE SALE transfers (quantity_listed)
--
-- THE FIX
-- p_quantity now means units received. p_units_per_lot (default 1) means units
-- per sale. Lots created = quantity / units_per_lot, so five air fryers become
-- five lots of one -- which is what a live show actually runs, and what the
-- Lot 101 / 102 / 103 model implies.
--
-- All lots share one product and one inventory row. Each sale deducts one unit;
-- the availability check in commerce_fulfil_paid_sale still prevents overselling
-- if two of those lots somehow sell past the stock on hand.
--
-- Also: p_cost_cents is PER UNIT, not the pallet total. Named and documented
-- here because getting it backwards silently corrupts every margin figure.

BEGIN;

DROP FUNCTION IF EXISTS commerce_quick_list(
  text, text, integer, integer, integer, integer, text, integer,
  text, text, integer, text, integer, integer, text);

CREATE OR REPLACE FUNCTION commerce_quick_list(
  p_title           text,
  p_condition       text    DEFAULT 'used',
  p_cost_cents      integer DEFAULT 0,        -- PER UNIT
  p_start_bid_cents integer DEFAULT 100,
  p_reserve_cents   integer DEFAULT 0,
  p_buy_now_cents   integer DEFAULT NULL,
  p_listing_type    text    DEFAULT 'both',
  p_quantity        integer DEFAULT 1,        -- units RECEIVED into stock
  p_description     text    DEFAULT NULL,
  p_category        text    DEFAULT NULL,
  p_retail_cents    integer DEFAULT NULL,
  p_lot_number      text    DEFAULT NULL,
  p_queue_position  integer DEFAULT NULL,
  p_duration_mins   integer DEFAULT 10,
  p_actor           text    DEFAULT 'admin',
  p_units_per_lot   integer DEFAULT 1         -- units ONE SALE transfers
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tenant uuid; v_seller uuid; v_wh uuid; v_avatar uuid;
  v_product uuid; v_recv jsonb; v_item uuid;
  v_qty integer; v_per integer; v_lots integer; i integer;
  v_auction uuid; v_lot text; v_ids jsonb := '[]'::jsonb; v_first uuid;
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

  v_qty := GREATEST(COALESCE(p_quantity, 1), 1);
  v_per := GREATEST(COALESCE(p_units_per_lot, 1), 1);
  IF v_per > v_qty THEN
    RETURN jsonb_build_object('ok', false, 'status', 400,
      'error', format('units per lot (%s) cannot exceed the quantity received (%s)', v_per, v_qty));
  END IF;
  -- Leftovers stay in stock rather than being quietly bundled into the last
  -- lot, which would misprice it.
  v_lots := v_qty / v_per;

  -- A hard cap: a mistyped quantity should not create 900 lots.
  IF v_lots > 100 THEN
    RETURN jsonb_build_object('ok', false, 'status', 400,
      'error', format('that would create %s lots; split it into smaller batches', v_lots));
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

  -- One inventory row holding every unit. is_unique only when there is
  -- genuinely a single unit.
  v_recv := commerce_receive_stock(v_product, v_qty, p_condition,
                                   COALESCE(p_cost_cents, 0), v_qty = 1,
                                   p_lot_number, p_actor);
  IF NOT (v_recv->>'ok')::boolean THEN RETURN v_recv; END IF;
  v_item := (v_recv->>'inventory_item_id')::uuid;

  FOR i IN 1..v_lots LOOP
    -- An explicit lot number only applies to a single lot; numbering N lots
    -- from one label would collide on auctions_lot_uniq.
    v_lot := CASE
      WHEN p_lot_number IS NOT NULL AND v_lots = 1 THEN p_lot_number
      ELSE 'LOT-' || nextval('lot_number_seq')::text
    END;

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
      v_lot,
      CASE WHEN p_queue_position IS NOT NULL THEN p_queue_position + i - 1 END,
      v_per,
      trim(p_title), p_description, p_category, 'scheduled',
      now(), now() + make_interval(mins => GREATEST(COALESCE(p_duration_mins,10),1)),
      COALESCE(p_start_bid_cents,100), COALESCE(p_reserve_cents,0),
      GREATEST(COALESCE(p_start_bid_cents,100),100), 0,
      p_listing_type, p_buy_now_cents,
      30, 30, 10
    ) RETURNING id INTO v_auction;

    IF v_first IS NULL THEN v_first := v_auction; END IF;
    v_ids := v_ids || jsonb_build_object('auction_id', v_auction, 'lot_number', v_lot);
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true, 'status', 200,
    'product_id', v_product,
    'inventory_item_id', v_item,
    'auction_id', v_first,                       -- kept for existing callers
    'lot_number', v_ids->0->>'lot_number',
    'lots_created', v_lots,
    'units_per_lot', v_per,
    'units_received', v_qty,
    'units_unlotted', v_qty - (v_lots * v_per),
    'lots', v_ids);
END $$;

COMMIT;

-- Verify:
-- SELECT commerce_quick_list('Air fryer','new',5000,100,0,15700,'both',5);
--   -> lots_created 5, units_per_lot 1, units_received 5
-- SELECT lot_number, quantity_listed FROM auctions WHERE item_title='Air fryer';
--   -> five rows, quantity_listed = 1 on each
-- SELECT quantity_on_hand FROM inventory_items ORDER BY created_at DESC LIMIT 1;  -> 5
