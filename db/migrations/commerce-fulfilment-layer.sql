-- Crystallux — provider-agnostic fulfilment layer
-- ================================================
-- Apply AFTER commerce-saved-cards.sql. Idempotent.
--
-- WHAT THIS IS
-- The delivery record every fulfilment provider writes into: Eazer, a
-- supplier shipping a dropship order, a tenant's own van, a carrier, customer
-- pickup, or a digital entitlement. Built now, with no external calls, so
-- integrating Eazer later is filling in one adapter rather than designing a
-- data model under deadline.
--
-- WHAT IT IS NOT
-- Not a dispatch engine. Crystallux does not match drivers, plan routes or
-- track vehicles -- Eazer already does all of that. This records WHICH
-- provider has the job, WHAT state it is in, and WHAT it cost. The provider
-- owns the movement; we own the order.
--
-- THREE DECISIONS WORTH STATING
--
-- 1. ONE DELIVERY PER ORDER, ENFORCED BY THE DATABASE. A retried webhook, a
--    double-clicked button or a re-run worker must never produce two drivers
--    for one parcel. A unique index on order_id is the guarantee; remembering
--    to check is not.
--
-- 2. PAYMENT, ORDER AND DELIVERY STATUS ARE SEPARATE. An order can be paid,
--    picking, and in transit at once. Collapsing delivery state into
--    orders.status would make 'out for delivery' compete with 'refunded' for
--    the same column, and one of them would lose.
--
-- 3. DELIVERY MONEY IS TRACKED ON BOTH SIDES. What the customer paid for
--    delivery and what the provider charged are different numbers, and the
--    gap is either margin or subsidy. Hiding the fee inside the product price
--    makes every margin figure a guess.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Warehouses need a real pickup identity
-- ─────────────────────────────────────────────────────────────────────────────
-- A courier needs an address, a contact and opening hours. One Toronto
-- warehouse today; hard-coding it would have to be undone for the second.

ALTER TABLE commerce_warehouses ADD COLUMN IF NOT EXISTS pickup_contact   text;
ALTER TABLE commerce_warehouses ADD COLUMN IF NOT EXISTS pickup_phone     text;
ALTER TABLE commerce_warehouses ADD COLUMN IF NOT EXISTS pickup_hours     text;
ALTER TABLE commerce_warehouses ADD COLUMN IF NOT EXISTS pickup_notes     text;
ALTER TABLE commerce_warehouses ADD COLUMN IF NOT EXISTS latitude         numeric(10,7);
ALTER TABLE commerce_warehouses ADD COLUMN IF NOT EXISTS longitude        numeric(10,7);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Delivery money on the order, kept apart from the goods
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_charge_cents  integer NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_cost_cents    integer NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_discount_cents integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN orders.delivery_charge_cents IS 'What the customer paid for delivery.';
COMMENT ON COLUMN orders.delivery_cost_cents IS
  'What the provider charged us. The gap against delivery_charge_cents is '
  'margin when positive and subsidy when negative -- both are real and both '
  'need to be visible.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. The delivery record
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS deliveries (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid REFERENCES commerce_tenants(id)   ON DELETE RESTRICT,
  seller_id           uuid REFERENCES commerce_sellers(id)   ON DELETE RESTRICT,
  warehouse_id        uuid REFERENCES commerce_warehouses(id) ON DELETE RESTRICT,
  order_id            uuid NOT NULL REFERENCES orders(id)    ON DELETE CASCADE,

  provider            text NOT NULL,
  -- The provider's own id for this job. Null until they give us one.
  provider_ref        text,
  provider_quote_ref  text,
  -- Their vocabulary, kept for diagnostics. Never used for logic -- mapping it
  -- to our states in one place is what stops a provider's rename from
  -- rippling through the platform.
  provider_status_raw text,

  status              text NOT NULL DEFAULT 'DELIVERY_NOT_REQUESTED',

  quoted_fee_cents    integer,
  quote_expires_at    timestamptz,
  actual_fee_cents    integer,

  recipient_name      text,
  recipient_phone     text,
  delivery_address    text,
  delivery_notes      text,

  -- Set when the warehouse says the goods are physically found and packed. No
  -- driver should be summoned before this: a courier arriving at an empty
  -- bench costs a failed pickup and a fee.
  release_ready_at    timestamptz,

  driver_name         text,
  driver_phone        text,
  vehicle_description text,
  tracking_url        text,
  proof_url           text,

  eta_at              timestamptz,
  requested_at        timestamptz,
  assigned_at         timestamptz,
  picked_up_at        timestamptz,
  delivered_at        timestamptz,
  failed_at           timestamptz,
  cancelled_at        timestamptz,
  failure_reason      text,

  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT dlv_provider_check CHECK (provider IN (
    'PICKUP','EAZER','SUPPLIER','SELLER','WAREHOUSE','DIGITAL','EXTERNAL_CARRIER')),
  CONSTRAINT dlv_status_check CHECK (status IN (
    'DELIVERY_NOT_REQUESTED','QUOTE_REQUESTED','QUOTE_READY','DELIVERY_REQUESTED',
    'DRIVER_ASSIGNING','DRIVER_ASSIGNED','READY_FOR_PICKUP','PICKED_UP','IN_TRANSIT',
    'DELIVERED','DELIVERY_FAILED','DELIVERY_CANCELLED','RETURN_IN_PROGRESS','RETURNED'))
);

-- The idempotency guarantee. Not a convention.
CREATE UNIQUE INDEX IF NOT EXISTS deliveries_order_uniq ON deliveries (order_id);
CREATE UNIQUE INDEX IF NOT EXISTS deliveries_provider_ref_uniq
  ON deliveries (provider, provider_ref) WHERE provider_ref IS NOT NULL;
CREATE INDEX IF NOT EXISTS deliveries_status_idx ON deliveries (status, created_at DESC);

ALTER TABLE deliveries ENABLE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Append-only delivery history
-- ─────────────────────────────────────────────────────────────────────────────
-- When a customer says "nobody came", the argument is settled by the sequence
-- of events, which is only worth anything if it cannot be edited afterwards.

CREATE TABLE IF NOT EXISTS delivery_events (
  id             bigserial PRIMARY KEY,
  delivery_id    uuid NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
  order_id       uuid REFERENCES orders(id) ON DELETE SET NULL,
  event_type     text NOT NULL,
  status_before  text,
  status_after   text,
  provider_raw   text,
  payload        jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- Set from the provider's event id so a redelivered webhook is a no-op.
  idempotency_key text,
  actor          text,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS dlv_events_idx ON delivery_events (delivery_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS dlv_events_idem_uniq
  ON delivery_events (idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE OR REPLACE FUNCTION delivery_events_immutable()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'delivery_events is append-only: % is not permitted', TG_OP;
END $$;

DROP TRIGGER IF EXISTS delivery_events_no_update ON delivery_events;
CREATE TRIGGER delivery_events_no_update
  BEFORE UPDATE OR DELETE ON delivery_events
  FOR EACH ROW EXECUTE FUNCTION delivery_events_immutable();

ALTER TABLE delivery_events ENABLE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Provider status mapping, in one table instead of scattered code
-- ─────────────────────────────────────────────────────────────────────────────
-- Adding Eazer means inserting rows here, not editing a workflow. A provider
-- renaming a status is a one-row fix.

CREATE TABLE IF NOT EXISTS delivery_status_map (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider       text NOT NULL,
  provider_status text NOT NULL,
  status         text NOT NULL,
  is_terminal    boolean NOT NULL DEFAULT false,
  notes          text,
  UNIQUE (provider, provider_status)
);

ALTER TABLE delivery_status_map ENABLE ROW LEVEL SECURITY;

-- Pickup needs no provider API, so it can be mapped today and works now.
INSERT INTO delivery_status_map (provider, provider_status, status, is_terminal) VALUES
  ('PICKUP','ready',     'READY_FOR_PICKUP', false),
  ('PICKUP','collected', 'DELIVERED',        true),
  ('PICKUP','abandoned', 'DELIVERY_FAILED',  true),
  ('DIGITAL','granted',  'DELIVERED',        true)
ON CONFLICT (provider, provider_status) DO NOTHING;

CREATE OR REPLACE FUNCTION delivery_map_status(p_provider text, p_raw text)
RETURNS text
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT status FROM delivery_status_map
   WHERE provider = p_provider AND lower(provider_status) = lower(p_raw)
   LIMIT 1;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Create or return the delivery for an order
-- ─────────────────────────────────────────────────────────────────────────────
-- Idempotent by construction: an existing row is returned, never duplicated.
-- Makes no external call -- the provider adapter does that and then records
-- the result with delivery_record_status below.

CREATE OR REPLACE FUNCTION commerce_ensure_delivery(
  p_order_id     uuid,
  p_provider     text DEFAULT NULL,
  p_recipient    text DEFAULT NULL,
  p_phone        text DEFAULT NULL,
  p_address      text DEFAULT NULL,
  p_notes        text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o record; v_id uuid; v_prov text; v_wh uuid;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'order not found');
  END IF;
  -- The rule the whole brief hangs on: no successful payment, no fulfilment.
  IF o.status = 'pending_payment' THEN
    RETURN jsonb_build_object('ok', false, 'status', 409,
      'error', 'That order has not been paid. No delivery can be created for it.');
  END IF;

  SELECT id INTO v_id FROM deliveries WHERE order_id = p_order_id;
  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'status', 200, 'delivery_id', v_id,
                              'existing', true);
  END IF;

  v_prov := COALESCE(p_provider, commerce_resolve_fulfilment_provider(p_order_id), 'PICKUP');

  SELECT i.warehouse_id INTO v_wh
    FROM order_items oi JOIN inventory_items i ON i.id = oi.inventory_item_id
   WHERE oi.order_id = p_order_id LIMIT 1;

  INSERT INTO deliveries (tenant_id, seller_id, warehouse_id, order_id, provider,
                          status, recipient_name, recipient_phone, delivery_address,
                          delivery_notes)
  VALUES (o.tenant_id, o.seller_id, v_wh, p_order_id, v_prov,
          CASE WHEN v_prov = 'PICKUP' THEN 'READY_FOR_PICKUP'
               WHEN v_prov = 'DIGITAL' THEN 'DELIVERED'
               ELSE 'DELIVERY_NOT_REQUESTED' END,
          COALESCE(p_recipient, o.customer_handle), p_phone,
          COALESCE(p_address, o.fulfilment_address), p_notes)
  RETURNING id INTO v_id;

  UPDATE orders SET fulfilment_provider = COALESCE(fulfilment_provider, v_prov)
   WHERE id = p_order_id;

  INSERT INTO delivery_events (delivery_id, order_id, event_type, status_after, actor)
  VALUES (v_id, p_order_id, 'delivery.created',
          (SELECT status FROM deliveries WHERE id = v_id), 'system');

  PERFORM commerce_emit('delivery.created', 'delivery', v_id,
    jsonb_build_object('order_id', p_order_id, 'provider', v_prov),
    o.tenant_id, 'system', 'delivery.created:' || p_order_id::text);

  RETURN jsonb_build_object('ok', true, 'status', 200, 'delivery_id', v_id,
                            'provider', v_prov, 'existing', false);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Record a provider status update
-- ─────────────────────────────────────────────────────────────────────────────
-- The single entry point for webhooks and polling alike. Idempotent on the
-- provider's event id, so the same webhook arriving three times moves the
-- delivery once and notifies once.

CREATE OR REPLACE FUNCTION delivery_record_status(
  p_delivery_id   uuid,
  p_provider_raw  text,
  p_status        text DEFAULT NULL,
  p_payload       jsonb DEFAULT '{}'::jsonb,
  p_event_id      text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE d record; v_new text; v_dupe bigint;
BEGIN
  SELECT * INTO d FROM deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF d.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'delivery not found');
  END IF;

  IF p_event_id IS NOT NULL THEN
    SELECT id INTO v_dupe FROM delivery_events WHERE idempotency_key = p_event_id;
    IF v_dupe IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'status', 200, 'duplicate', true,
                                'delivery_status', d.status);
    END IF;
  END IF;

  v_new := COALESCE(p_status, delivery_map_status(d.provider, p_provider_raw));
  IF v_new IS NULL THEN
    -- An unmapped status is recorded, not guessed at. Moving a delivery on a
    -- status we do not understand is how a parcel gets marked delivered
    -- because a provider added a new word.
    INSERT INTO delivery_events (delivery_id, order_id, event_type, status_before,
                                 status_after, provider_raw, payload, idempotency_key, actor)
    VALUES (d.id, d.order_id, 'delivery.unmapped_status', d.status, d.status,
            p_provider_raw, COALESCE(p_payload,'{}'::jsonb), p_event_id, 'provider');
    UPDATE deliveries SET provider_status_raw = p_provider_raw, updated_at = now()
     WHERE id = d.id;
    RETURN jsonb_build_object('ok', true, 'status', 200, 'unmapped', true,
      'note', format('%s sent an unrecognised status (%s); recorded but not acted on',
                     d.provider, p_provider_raw));
  END IF;

  -- Terminal states are terminal. A late webhook must not drag a delivered
  -- parcel back into transit.
  IF d.status IN ('DELIVERED','RETURNED','DELIVERY_CANCELLED')
     AND v_new NOT IN ('RETURN_IN_PROGRESS','RETURNED') THEN
    INSERT INTO delivery_events (delivery_id, order_id, event_type, status_before,
                                 status_after, provider_raw, payload, idempotency_key, actor)
    VALUES (d.id, d.order_id, 'delivery.late_event', d.status, d.status,
            p_provider_raw, COALESCE(p_payload,'{}'::jsonb), p_event_id, 'provider');
    RETURN jsonb_build_object('ok', true, 'status', 200, 'ignored', true,
                              'delivery_status', d.status);
  END IF;

  UPDATE deliveries SET
    status = v_new,
    provider_status_raw = p_provider_raw,
    assigned_at   = CASE WHEN v_new = 'DRIVER_ASSIGNED' THEN COALESCE(assigned_at, now()) ELSE assigned_at END,
    picked_up_at  = CASE WHEN v_new = 'PICKED_UP'       THEN COALESCE(picked_up_at, now()) ELSE picked_up_at END,
    delivered_at  = CASE WHEN v_new = 'DELIVERED'       THEN COALESCE(delivered_at, now()) ELSE delivered_at END,
    failed_at     = CASE WHEN v_new = 'DELIVERY_FAILED' THEN COALESCE(failed_at, now()) ELSE failed_at END,
    cancelled_at  = CASE WHEN v_new = 'DELIVERY_CANCELLED' THEN COALESCE(cancelled_at, now()) ELSE cancelled_at END,
    updated_at    = now()
  WHERE id = d.id;

  INSERT INTO delivery_events (delivery_id, order_id, event_type, status_before,
                               status_after, provider_raw, payload, idempotency_key, actor)
  VALUES (d.id, d.order_id, 'delivery.status', d.status, v_new,
          p_provider_raw, COALESCE(p_payload,'{}'::jsonb), p_event_id, 'provider');

  PERFORM commerce_emit('delivery.' || lower(v_new), 'delivery', d.id,
    jsonb_build_object('order_id', d.order_id, 'provider', d.provider, 'status', v_new),
    d.tenant_id, 'provider', p_event_id);

  -- Delivered closes the order. A failed delivery does NOT unwind the sale:
  -- the goods and the payment are still real, and someone has to decide
  -- between a retry, a pickup and a refund.
  IF v_new = 'DELIVERED' THEN
    UPDATE orders SET status = 'fulfilled', fulfilled_at = COALESCE(fulfilled_at, now()),
                      updated_at = now()
     WHERE id = d.order_id AND status IN ('paid','picking','ready');
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 200, 'delivery_status', v_new);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Mark the goods physically ready
-- ─────────────────────────────────────────────────────────────────────────────
-- The gate between pick/pack and summoning a driver.

CREATE OR REPLACE FUNCTION delivery_mark_ready(p_order_id uuid, p_actor text DEFAULT 'admin')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM deliveries WHERE order_id = p_order_id;
  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404,
      'error', 'no delivery for that order');
  END IF;
  UPDATE deliveries SET release_ready_at = COALESCE(release_ready_at, now()),
                        updated_at = now()
   WHERE id = v_id;
  INSERT INTO delivery_events (delivery_id, order_id, event_type, actor)
  VALUES (v_id, p_order_id, 'delivery.goods_ready', p_actor);
  RETURN jsonb_build_object('ok', true, 'status', 200, 'delivery_id', v_id);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Operator read model
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW delivery_board AS
  SELECT d.id AS delivery_id, d.order_id, o.order_number, d.provider, d.status,
         d.release_ready_at IS NOT NULL AS goods_ready,
         d.recipient_name, d.delivery_address, d.tracking_url, d.proof_url,
         d.driver_name, d.eta_at,
         o.total_cents, o.delivery_charge_cents, o.delivery_cost_cents,
         (o.delivery_charge_cents - o.delivery_cost_cents) AS delivery_margin_cents,
         w.name AS warehouse, d.created_at, d.delivered_at
  FROM deliveries d
  JOIN orders o ON o.id = d.order_id
  LEFT JOIN commerce_warehouses w ON w.id = d.warehouse_id;

COMMIT;

-- Verify:
-- SELECT * FROM delivery_status_map ORDER BY provider, provider_status;
-- SELECT commerce_ensure_delivery((SELECT id FROM orders LIMIT 1));
-- SELECT * FROM delivery_board;
