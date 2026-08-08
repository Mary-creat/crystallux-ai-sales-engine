-- Crystallux — inventory source + fulfilment provider
-- ====================================================
-- Apply AFTER commerce-phase1-quicklist-quantity-fix.sql. Idempotent.
--
-- WHY NOW, WHEN NOTHING ELSE FROM THE ECOSYSTEM PLAN IS BEING BUILT YET
-- These two fields decide, per line of stock, WHERE the goods come from and
-- WHO delivers them. Every later stage -- Supshin dropship, digital products,
-- consignment, tenant inventory, Eazer, supplier fulfilment -- reads them.
--
-- They cost nothing today (one column each, defaulted) and a painful backfill
-- later, because by then orders and ledger rows exist and every one of them
-- needs a source assigned retroactively. Same reasoning that put tenant_id in
-- on day one. Nothing else from the master plan is being built here.
--
-- NO BEHAVIOUR CHANGE. Everything defaults to what Crystallux does today:
-- owned/liquidation stock, delivered by pickup or Eazer. The commerce
-- functions are untouched.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Where the goods come from
-- ─────────────────────────────────────────────────────────────────────────────
-- OWNED            bought outright, sitting in our warehouse
-- LIQUIDATION      pallet/returns stock. Owned, but priced and graded
--                  differently, so worth distinguishing for margin analysis
-- DROPSHIP         we never hold it; a supplier ships on our behalf
-- CONSIGNMENT      we hold it but do not own it; the seller is paid on sale
-- WAREHOUSE        third-party warehouse holds it
-- DIGITAL          no physical unit exists; delivery is access, not shipping
-- TENANT_INVENTORY another tenant's stock sold through our engine

ALTER TABLE inventory_items
  ADD COLUMN IF NOT EXISTS inventory_source text NOT NULL DEFAULT 'LIQUIDATION';

DO $$
BEGIN
  ALTER TABLE inventory_items DROP CONSTRAINT IF EXISTS inv_source_check;
  ALTER TABLE inventory_items
    ADD CONSTRAINT inv_source_check CHECK (inventory_source IN (
      'OWNED','LIQUIDATION','DROPSHIP','CONSIGNMENT','WAREHOUSE',
      'DIGITAL','TENANT_INVENTORY'));
END $$;

-- Digital goods have no unit to run out of. Quantity tracking on them is
-- meaningless and would eventually cause a course to "sell out".
ALTER TABLE inventory_items
  ADD COLUMN IF NOT EXISTS unlimited_stock boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS inventory_source_idx ON inventory_items (inventory_source);

COMMENT ON COLUMN inventory_items.inventory_source IS
  'Where the goods come from. Drives fulfilment routing and margin analysis. '
  'Defaults to LIQUIDATION because that is what Crystallux sells today.';
COMMENT ON COLUMN inventory_items.unlimited_stock IS
  'DIGITAL rows only: no unit to deplete. Physical stock must leave this false '
  'or the oversell guard stops meaning anything.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Who delivers it
-- ─────────────────────────────────────────────────────────────────────────────
-- Distinct from orders.fulfilment_method (pickup | delivery), which is what
-- the CUSTOMER chose. This is WHO executes it. A customer choosing "delivery"
-- could be served by Eazer, by a supplier, or by the seller's own van, and
-- those are different operational paths.

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS fulfilment_provider text;

DO $$
BEGIN
  ALTER TABLE orders DROP CONSTRAINT IF EXISTS ord_fulfilment_provider_check;
  ALTER TABLE orders
    ADD CONSTRAINT ord_fulfilment_provider_check CHECK (
      fulfilment_provider IS NULL OR fulfilment_provider IN (
        'PICKUP','EAZER','SUPPLIER','SELLER','WAREHOUSE','DIGITAL','EXTERNAL_CARRIER'));
END $$;

-- Default provider for stock of this source, so an order can be routed without
-- anyone choosing by hand. Advisory: the order may still override it.
ALTER TABLE inventory_items
  ADD COLUMN IF NOT EXISTS default_fulfilment_provider text;

DO $$
BEGIN
  ALTER TABLE inventory_items DROP CONSTRAINT IF EXISTS inv_default_provider_check;
  ALTER TABLE inventory_items
    ADD CONSTRAINT inv_default_provider_check CHECK (
      default_fulfilment_provider IS NULL OR default_fulfilment_provider IN (
        'PICKUP','EAZER','SUPPLIER','SELLER','WAREHOUSE','DIGITAL','EXTERNAL_CARRIER'));
END $$;

CREATE INDEX IF NOT EXISTS orders_provider_idx ON orders (fulfilment_provider)
  WHERE fulfilment_provider IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Delivery sizing — enough for a courier to quote, no more
-- ─────────────────────────────────────────────────────────────────────────────
-- Liquidation items range from an air fryer to a sofa, and that decides
-- vehicle and price. Nullable: most of it is unknown at intake and should not
-- block listing something.

ALTER TABLE products ADD COLUMN IF NOT EXISTS weight_grams   integer;
ALTER TABLE products ADD COLUMN IF NOT EXISTS length_mm      integer;
ALTER TABLE products ADD COLUMN IF NOT EXISTS width_mm       integer;
ALTER TABLE products ADD COLUMN IF NOT EXISTS height_mm      integer;
ALTER TABLE products ADD COLUMN IF NOT EXISTS delivery_class text;

DO $$
BEGIN
  ALTER TABLE products DROP CONSTRAINT IF EXISTS prod_delivery_class_check;
  ALTER TABLE products
    ADD CONSTRAINT prod_delivery_class_check CHECK (
      delivery_class IS NULL OR delivery_class IN
        ('SMALL','STANDARD','LARGE','OVERSIZED','DIGITAL'));
END $$;

COMMENT ON COLUMN products.delivery_class IS
  'SMALL / STANDARD / LARGE / OVERSIZED / DIGITAL. A courier needs the vehicle '
  'class more than exact millimetres; dimensions refine the quote when known.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Route an order without hard-coding the answer
-- ─────────────────────────────────────────────────────────────────────────────
-- Deliberately a pure function of the data. When Eazer is integrated it reads
-- this rather than a chain of ifs scattered through the workflows.

CREATE OR REPLACE FUNCTION commerce_resolve_fulfilment_provider(p_order_id uuid)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o record; src text; dflt text;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RETURN NULL; END IF;
  -- An explicit choice on the order always wins.
  IF o.fulfilment_provider IS NOT NULL THEN RETURN o.fulfilment_provider; END IF;

  SELECT i.inventory_source, i.default_fulfilment_provider INTO src, dflt
    FROM order_items oi
    JOIN inventory_items i ON i.id = oi.inventory_item_id
   WHERE oi.order_id = p_order_id
   LIMIT 1;

  IF dflt IS NOT NULL THEN RETURN dflt; END IF;
  IF src = 'DIGITAL'  THEN RETURN 'DIGITAL';  END IF;
  IF src = 'DROPSHIP' THEN RETURN 'SUPPLIER'; END IF;
  -- Customer's stated preference, then the safe default: they collect it.
  IF o.fulfilment_method = 'pickup' THEN RETURN 'PICKUP'; END IF;
  IF o.fulfilment_method = 'delivery' THEN RETURN 'EAZER'; END IF;
  RETURN 'PICKUP';
END $$;

COMMIT;

-- Verify:
-- SELECT inventory_source, default_fulfilment_provider FROM inventory_items LIMIT 5;
-- SELECT commerce_resolve_fulfilment_provider((SELECT id FROM orders LIMIT 1));
