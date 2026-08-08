-- Crystallux commerce — Phase 1: product → inventory → sale → order → fulfilment
-- ==============================================================================
-- Apply AFTER luxi-buy-now-and-proxy-bids.sql and luxi-secret-hardening-and-readiness.sql.
-- Idempotent: safe to re-run.
--
-- DESIGN NOTE — WHY THERE IS NO "listings" TABLE.
-- `auctions` already carries listing_type ('auction'|'buy_now'|'both'),
-- reserve_price_cents, buy_now_price_cents, status and the anti-snipe config.
-- Adding a listings table beside it would mean two rows describing one sale and
-- two places for status to drift. So `auctions` REMAINS the sale record and we
-- extend it with links to the new product/inventory layer. Everything below
-- attaches to what exists rather than replacing it.
--
-- THE INVARIANT THIS SCHEMA EXISTS TO PROTECT:
-- stock is only ever consumed by a PAID order. Bidding reserves nothing;
-- winning reserves; payment consumes; failure releases. Overselling is
-- prevented by row locks inside the reservation function, not by application
-- code remembering to check.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Multi-tenancy skeleton — real columns now, all pointing at Crystallux.
--    Present so we never have to backfill tenant_id across a live order table.
--    No tenant UI, no warehouse integrations. Deliberately minimal.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS commerce_tenants (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL UNIQUE,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS commerce_sellers (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES commerce_tenants(id) ON DELETE RESTRICT,
  name        text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name)
);

CREATE TABLE IF NOT EXISTS commerce_warehouses (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES commerce_tenants(id) ON DELETE RESTRICT,
  name        text NOT NULL,
  address     text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name)
);

INSERT INTO commerce_tenants (id, name)
VALUES ('c1000000-0000-4000-8000-000000000001', 'Crystallux')
ON CONFLICT (name) DO NOTHING;

INSERT INTO commerce_sellers (id, tenant_id, name)
SELECT 'c1000000-0000-4000-8000-000000000002', id, 'Crystallux'
FROM commerce_tenants WHERE name = 'Crystallux'
ON CONFLICT (tenant_id, name) DO NOTHING;

INSERT INTO commerce_warehouses (id, tenant_id, name, address)
SELECT 'c1000000-0000-4000-8000-000000000003', id, 'Crystallux Main', NULL
FROM commerce_tenants WHERE name = 'Crystallux'
ON CONFLICT (tenant_id, name) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Products — what a thing IS. Not how many we have.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS products (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL REFERENCES commerce_tenants(id)   ON DELETE RESTRICT,
  seller_id             uuid NOT NULL REFERENCES commerce_sellers(id)   ON DELETE RESTRICT,
  sku                   text,
  title                 text NOT NULL,
  description           text,
  category              text,
  brand                 text,
  model                 text,
  -- Reference/retail price: what it sells for new, used to show a saving and
  -- to sanity-check margin. NOT the sale price.
  retail_reference_cents integer CHECK (retail_reference_cents IS NULL OR retail_reference_cents >= 0),
  images                jsonb NOT NULL DEFAULT '[]'::jsonb,
  archived_at           timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS products_tenant_sku_uniq
  ON products (tenant_id, sku) WHERE sku IS NOT NULL;
CREATE INDEX IF NOT EXISTS products_tenant_idx ON products (tenant_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Inventory — physical stock. Handles BOTH liquidation modes:
--      unique one-off unit  -> is_unique=true,  quantity_on_hand=1
--      quantity-tracked lot -> is_unique=false, quantity_on_hand=N
--    Condition lives here, not on the product: a liquidation pallet routinely
--    contains the same product in New, Open Box and As-Is condition, and each
--    commands a different price.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS inventory_items (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL REFERENCES commerce_tenants(id)    ON DELETE RESTRICT,
  seller_id             uuid NOT NULL REFERENCES commerce_sellers(id)    ON DELETE RESTRICT,
  warehouse_id          uuid NOT NULL REFERENCES commerce_warehouses(id) ON DELETE RESTRICT,
  product_id            uuid NOT NULL REFERENCES products(id)            ON DELETE RESTRICT,
  lot_code              text,
  condition             text NOT NULL DEFAULT 'used',
  condition_notes       text,
  is_unique             boolean NOT NULL DEFAULT true,
  quantity_on_hand      integer NOT NULL DEFAULT 0,
  quantity_reserved     integer NOT NULL DEFAULT 0,
  acquisition_cost_cents integer NOT NULL DEFAULT 0,
  location_hint         text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT inv_condition_check
    CHECK (condition IN ('new','open_box','used','as_is')),
  CONSTRAINT inv_qty_nonneg          CHECK (quantity_on_hand >= 0),
  CONSTRAINT inv_reserved_nonneg     CHECK (quantity_reserved >= 0),
  -- The oversell guard, enforced by the database rather than trusted to code.
  CONSTRAINT inv_reserved_within_hand CHECK (quantity_reserved <= quantity_on_hand),
  CONSTRAINT inv_unique_is_single    CHECK (NOT is_unique OR quantity_on_hand <= 1),
  CONSTRAINT inv_cost_nonneg         CHECK (acquisition_cost_cents >= 0)
);

CREATE INDEX IF NOT EXISTS inventory_product_idx   ON inventory_items (product_id);
CREATE INDEX IF NOT EXISTS inventory_tenant_idx    ON inventory_items (tenant_id);
CREATE INDEX IF NOT EXISTS inventory_available_idx
  ON inventory_items ((quantity_on_hand - quantity_reserved));

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Immutable inventory ledger — every movement, append only.
--    quantity_on_hand is a cache; THIS is the truth. If they ever disagree the
--    ledger wins, which is only meaningful if nothing can rewrite history.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS inventory_ledger (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL REFERENCES commerce_tenants(id) ON DELETE RESTRICT,
  inventory_item_id uuid NOT NULL REFERENCES inventory_items(id)  ON DELETE RESTRICT,
  movement_type     text NOT NULL,
  -- Signed against ON HAND. Reserve/release move quantity_reserved only and
  -- therefore carry delta 0 -- they are recorded because "who reserved what,
  -- when" is exactly what you need when a sale is disputed.
  quantity_delta    integer NOT NULL,
  reserved_delta    integer NOT NULL DEFAULT 0,
  reason            text,
  reference_type    text,     -- 'order' | 'auction' | 'reservation' | 'manual'
  reference_id      uuid,
  actor             text,
  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ledger_movement_check CHECK (movement_type IN (
    'receipt','reserve','release','sold','return','damage','adjustment','pick','writeoff'
  ))
);

CREATE INDEX IF NOT EXISTS ledger_item_idx ON inventory_ledger (inventory_item_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ledger_ref_idx  ON inventory_ledger (reference_type, reference_id);

CREATE OR REPLACE FUNCTION inventory_ledger_immutable()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'inventory_ledger is append-only: % is not permitted', TG_OP;
END $$;

DROP TRIGGER IF EXISTS inventory_ledger_no_update ON inventory_ledger;
CREATE TRIGGER inventory_ledger_no_update
  BEFORE UPDATE OR DELETE ON inventory_ledger
  FOR EACH ROW EXECUTE FUNCTION inventory_ledger_immutable();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Stock reservations — the bridge between "someone wants it" and "paid for".
--    Every reservation expires. An abandoned checkout must not hold stock
--    hostage, and a failed payment must never consume it.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS stock_reservations (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL REFERENCES commerce_tenants(id) ON DELETE RESTRICT,
  inventory_item_id uuid NOT NULL REFERENCES inventory_items(id)  ON DELETE RESTRICT,
  auction_id        uuid REFERENCES auctions(id) ON DELETE SET NULL,
  quantity          integer NOT NULL CHECK (quantity > 0),
  status            text NOT NULL DEFAULT 'held',
  held_for          text,            -- bidder handle / customer email
  expires_at        timestamptz NOT NULL,
  consumed_at       timestamptz,
  released_at       timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT resv_status_check CHECK (status IN ('held','consumed','released','expired'))
);

CREATE INDEX IF NOT EXISTS resv_item_idx    ON stock_reservations (inventory_item_id, status);
CREATE INDEX IF NOT EXISTS resv_expiry_idx  ON stock_reservations (status, expires_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Orders
-- ─────────────────────────────────────────────────────────────────────────────

CREATE SEQUENCE IF NOT EXISTS order_number_seq START 1001;
-- Lots get their own sequence so lot numbers stay contiguous per show instead
-- of interleaving with order numbers.
CREATE SEQUENCE IF NOT EXISTS lot_number_seq START 101;

CREATE TABLE IF NOT EXISTS orders (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL REFERENCES commerce_tenants(id) ON DELETE RESTRICT,
  seller_id             uuid NOT NULL REFERENCES commerce_sellers(id) ON DELETE RESTRICT,
  order_number          text NOT NULL UNIQUE
                          DEFAULT ('CLX-' || nextval('order_number_seq')::text),
  channel               text NOT NULL,     -- 'buy_now' | 'auction'
  status                text NOT NULL DEFAULT 'pending_payment',
  customer_handle       text NOT NULL,     -- email or name captured at bid/checkout
  customer_email        text,
  auction_id            uuid REFERENCES auctions(id) ON DELETE SET NULL,
  -- Payment is recorded here so an order can always be reconciled against
  -- Stripe without joining through the bidding tables.
  stripe_payment_intent_id text,
  subtotal_cents        integer NOT NULL DEFAULT 0 CHECK (subtotal_cents >= 0),
  tax_cents             integer NOT NULL DEFAULT 0 CHECK (tax_cents >= 0),
  shipping_cents        integer NOT NULL DEFAULT 0 CHECK (shipping_cents >= 0),
  total_cents           integer NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  cost_cents            integer NOT NULL DEFAULT 0 CHECK (cost_cents >= 0),
  fulfilment_method     text,              -- 'pickup' | 'delivery'
  fulfilment_address    text,
  fulfilment_notes      text,
  paid_at               timestamptz,
  picked_at             timestamptz,
  ready_at              timestamptz,
  fulfilled_at          timestamptz,
  cancelled_at          timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ord_channel_check CHECK (channel IN ('buy_now','auction')),
  CONSTRAINT ord_status_check  CHECK (status IN (
    'pending_payment','paid','picking','ready','fulfilled','cancelled','refunded'
  )),
  CONSTRAINT ord_fulfilment_check CHECK (
    fulfilment_method IS NULL OR fulfilment_method IN ('pickup','delivery')
  )
);

CREATE INDEX IF NOT EXISTS orders_status_idx  ON orders (status, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_auction_idx ON orders (auction_id);
CREATE UNIQUE INDEX IF NOT EXISTS orders_pi_uniq
  ON orders (stripe_payment_intent_id) WHERE stripe_payment_intent_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS order_items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id          uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id        uuid NOT NULL REFERENCES products(id)       ON DELETE RESTRICT,
  inventory_item_id uuid NOT NULL REFERENCES inventory_items(id) ON DELETE RESTRICT,
  reservation_id    uuid REFERENCES stock_reservations(id) ON DELETE SET NULL,
  title_snapshot    text NOT NULL,   -- frozen: the catalog may change later
  condition_snapshot text,
  quantity          integer NOT NULL CHECK (quantity > 0),
  unit_price_cents  integer NOT NULL CHECK (unit_price_cents >= 0),
  unit_cost_cents   integer NOT NULL DEFAULT 0 CHECK (unit_cost_cents >= 0),
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS order_items_order_idx ON order_items (order_id);

-- Margin, derived rather than stored, so it cannot drift from its inputs.
CREATE OR REPLACE VIEW order_margin AS
  SELECT o.id AS order_id, o.order_number, o.status, o.channel,
         o.total_cents, o.cost_cents,
         (o.total_cents - o.cost_cents) AS margin_cents,
         CASE WHEN o.total_cents > 0
              THEN round(((o.total_cents - o.cost_cents)::numeric / o.total_cents) * 100, 2)
              ELSE NULL END AS margin_pct
  FROM orders o;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Extend `auctions` into the commerce layer (no duplicate sale record)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE auctions ADD COLUMN IF NOT EXISTS tenant_id         uuid REFERENCES commerce_tenants(id);
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS seller_id         uuid REFERENCES commerce_sellers(id);
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS warehouse_id      uuid REFERENCES commerce_warehouses(id);
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS product_id        uuid REFERENCES products(id);
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS inventory_item_id uuid REFERENCES inventory_items(id);
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS lot_number        text;
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS queue_position    integer;
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS start_bid_cents   integer;
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS quantity_listed   integer NOT NULL DEFAULT 1;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'auc_quantity_positive') THEN
    ALTER TABLE auctions ADD CONSTRAINT auc_quantity_positive CHECK (quantity_listed > 0);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS auctions_queue_idx ON auctions (queue_position)
  WHERE queue_position IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS auctions_lot_uniq ON auctions (tenant_id, lot_number)
  WHERE lot_number IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Complete bid audit — every ATTEMPT, accepted or not.
--    auction_bids records bids that landed. When a sale is challenged the
--    interesting rows are usually the ones that did NOT land: the too-low bid,
--    the bid on a closed auction, the proxy that hit its ceiling.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS auction_bid_audit (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id      uuid NOT NULL REFERENCES auctions(id) ON DELETE CASCADE,
  bid_id          uuid,      -- auction_bids.id when the attempt was accepted
  bidder_handle   text,
  source          text NOT NULL DEFAULT 'web',   -- web | admin | proxy | comment
  attempted_cents integer,
  outcome         text NOT NULL,
  reason          text,
  high_bid_before integer,
  high_bid_after  integer,
  request_ip      text,
  created_at      timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT bid_audit_outcome_check CHECK (outcome IN (
    'accepted','rejected_too_low','rejected_closed','rejected_auth',
    'rejected_duplicate','proxy_exhausted','error'
  ))
);

CREATE INDEX IF NOT EXISTS bid_audit_auction_idx ON auction_bid_audit (auction_id, created_at DESC);

CREATE OR REPLACE FUNCTION auction_bid_audit_immutable()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'auction_bid_audit is append-only: % is not permitted', TG_OP;
END $$;

DROP TRIGGER IF EXISTS auction_bid_audit_no_update ON auction_bid_audit;
CREATE TRIGGER auction_bid_audit_no_update
  BEFORE UPDATE OR DELETE ON auction_bid_audit
  FOR EACH ROW EXECUTE FUNCTION auction_bid_audit_immutable();

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. RLS — on for everything. n8n uses the service_role key and bypasses it;
--    nothing else should read this data.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE commerce_tenants    ENABLE ROW LEVEL SECURITY;
ALTER TABLE commerce_sellers    ENABLE ROW LEVEL SECURITY;
ALTER TABLE commerce_warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE products            ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_items     ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_ledger    ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_reservations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders              ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items         ENABLE ROW LEVEL SECURITY;
ALTER TABLE auction_bid_audit   ENABLE ROW LEVEL SECURITY;

COMMIT;

-- Verify:
-- SELECT table_name FROM information_schema.tables
--  WHERE table_name IN ('products','inventory_items','inventory_ledger',
--                       'stock_reservations','orders','order_items','auction_bid_audit')
--  ORDER BY 1;   -- expect 7 rows
-- SELECT name FROM commerce_tenants;                 -- Crystallux
-- INSERT INTO inventory_ledger (tenant_id, inventory_item_id, movement_type, quantity_delta)
--   VALUES (...); UPDATE inventory_ledger SET reason='x';  -- must RAISE
