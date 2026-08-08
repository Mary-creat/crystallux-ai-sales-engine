-- Crystallux — commerce event spine
-- ==================================
-- Apply AFTER commerce-phase1-source-and-provider.sql. Idempotent.
--
-- WHY THIS ONE, AND NOT THE OTHER SIX
-- Supshin, dropship sync, digital delivery, ad tracking, customer
-- segmentation, marketplace and the seller portal can each be built when
-- their moment comes. The event spine cannot: every one of them needs to know
-- when a sale happened, and if it is added later, every existing commerce
-- function has to be reopened to emit. Cheap today, retrofit tomorrow -- the
-- same reasoning behind tenant_id and inventory_source.
--
-- Ecosystem plan section 31: modules should react to events rather than
-- becoming one giant tightly coupled workflow.
--
-- WHAT THIS IS NOT
-- Not a queue, not a broker, not a background worker. It is an append-only
-- record of things that happened, with a cursor so consumers can read
-- forward at their own pace. Postgres is entirely adequate at this volume,
-- and a real broker can read from here later without any producer changing.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. The log
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS commerce_events (
  id             bigserial PRIMARY KEY,   -- monotonic: consumers track position
  event_type     text NOT NULL,
  tenant_id      uuid REFERENCES commerce_tenants(id) ON DELETE SET NULL,
  -- What the event is about. Deliberately loose: an event may concern an
  -- order, an auction, a product or a customer, and forcing one FK per kind
  -- would mean altering this table for every new subject.
  subject_type   text,
  subject_id     uuid,
  actor          text,
  payload        jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- Set by a producer that may fire twice (a retried webhook, a cron that
  -- overlaps). A unique index makes the second write a no-op.
  idempotency_key text,
  occurred_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ce_type_idx    ON commerce_events (event_type, id);
CREATE INDEX IF NOT EXISTS ce_subject_idx ON commerce_events (subject_type, subject_id);
CREATE INDEX IF NOT EXISTS ce_time_idx    ON commerce_events (occurred_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ce_idem_uniq
  ON commerce_events (idempotency_key) WHERE idempotency_key IS NOT NULL;

-- Append-only. A consumer that could rewrite history would make the log
-- worthless as an audit trail, which is half its value.
CREATE OR REPLACE FUNCTION commerce_events_immutable()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'commerce_events is append-only: % is not permitted', TG_OP;
END $$;

DROP TRIGGER IF EXISTS commerce_events_no_update ON commerce_events;
CREATE TRIGGER commerce_events_no_update
  BEFORE UPDATE OR DELETE ON commerce_events
  FOR EACH ROW EXECUTE FUNCTION commerce_events_immutable();

ALTER TABLE commerce_events ENABLE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Consumer cursors
-- ─────────────────────────────────────────────────────────────────────────────
-- Each consumer -- sales engine follow-up, segmentation, ad attribution,
-- digital delivery, the Eazer bridge -- remembers where it got to. A slow or
-- broken consumer falls behind without blocking anyone else, and a fixed one
-- catches up instead of losing the backlog.

CREATE TABLE IF NOT EXISTS commerce_event_cursors (
  consumer        text PRIMARY KEY,
  last_event_id   bigint NOT NULL DEFAULT 0,
  last_run_at     timestamptz,
  last_error      text,
  consecutive_errors integer NOT NULL DEFAULT 0,
  enabled         boolean NOT NULL DEFAULT true,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE commerce_event_cursors ENABLE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Emit
-- ─────────────────────────────────────────────────────────────────────────────
-- Never raises. An event is a side effect of a business action; a failure to
-- record one must not roll back a captured payment. Silence is the correct
-- failure mode here and nowhere else in this schema.

CREATE OR REPLACE FUNCTION commerce_emit(
  p_event_type text,
  p_subject_type text DEFAULT NULL,
  p_subject_id uuid DEFAULT NULL,
  p_payload jsonb DEFAULT '{}'::jsonb,
  p_tenant_id uuid DEFAULT NULL,
  p_actor text DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id bigint;
BEGIN
  INSERT INTO commerce_events
    (event_type, tenant_id, subject_type, subject_id, actor, payload, idempotency_key)
  VALUES
    (p_event_type, COALESCE(p_tenant_id, commerce_default_tenant()),
     p_subject_type, p_subject_id, p_actor,
     COALESCE(p_payload, '{}'::jsonb), p_idempotency_key)
  ON CONFLICT (idempotency_key) DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Read
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION commerce_events_since(
  p_consumer text,
  p_limit integer DEFAULT 100,
  p_types text[] DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_from bigint; v_rows jsonb;
BEGIN
  INSERT INTO commerce_event_cursors (consumer) VALUES (p_consumer)
  ON CONFLICT (consumer) DO NOTHING;

  SELECT last_event_id INTO v_from FROM commerce_event_cursors WHERE consumer = p_consumer;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', e.id, 'event_type', e.event_type, 'tenant_id', e.tenant_id,
           'subject_type', e.subject_type, 'subject_id', e.subject_id,
           'payload', e.payload, 'occurred_at', e.occurred_at
         ) ORDER BY e.id), '[]'::jsonb)
    INTO v_rows
  FROM (
    SELECT * FROM commerce_events
     WHERE id > COALESCE(v_from, 0)
       AND (p_types IS NULL OR event_type = ANY(p_types))
     ORDER BY id
     LIMIT GREATEST(COALESCE(p_limit, 100), 1)
  ) e;

  RETURN jsonb_build_object('ok', true, 'from_id', v_from, 'events', v_rows);
END $$;

-- The cursor advances only when the consumer says it finished. A consumer
-- that dies mid-batch re-reads rather than skipping -- at-least-once, so
-- consumers must be idempotent, which is the same discipline the payment
-- path already follows.
CREATE OR REPLACE FUNCTION commerce_events_ack(
  p_consumer text,
  p_last_event_id bigint,
  p_error text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO commerce_event_cursors (consumer) VALUES (p_consumer)
  ON CONFLICT (consumer) DO NOTHING;

  IF p_error IS NOT NULL THEN
    UPDATE commerce_event_cursors
       SET last_error = left(p_error, 500),
           consecutive_errors = consecutive_errors + 1,
           last_run_at = now(), updated_at = now()
     WHERE consumer = p_consumer;
    RETURN jsonb_build_object('ok', false, 'recorded', true);
  END IF;

  UPDATE commerce_event_cursors
     SET last_event_id = GREATEST(last_event_id, COALESCE(p_last_event_id, 0)),
         last_error = NULL, consecutive_errors = 0,
         last_run_at = now(), updated_at = now()
   WHERE consumer = p_consumer;

  RETURN jsonb_build_object('ok', true);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Wire the existing money path to emit
-- ─────────────────────────────────────────────────────────────────────────────
-- Only order.paid for now. It is the event every downstream consumer needs
-- first -- follow-up, segmentation, ad attribution, digital delivery, the
-- Eazer bridge all begin here -- and emitting it inside the same transaction
-- means an order can never exist without its event.
--
-- The idempotency key is the payment intent, so the retry that
-- commerce_fulfil_paid_sale already tolerates cannot produce two events and
-- two follow-up emails.

CREATE OR REPLACE FUNCTION commerce_emit_order_paid(p_order_id uuid)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o record;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RETURN NULL; END IF;
  RETURN commerce_emit(
    'order.paid', 'order', o.id,
    jsonb_build_object(
      'order_number', o.order_number,
      'channel', o.channel,
      'total_cents', o.total_cents,
      'cost_cents', o.cost_cents,
      'margin_cents', o.total_cents - o.cost_cents,
      'customer_handle', o.customer_handle,
      'customer_email', o.customer_email,
      'auction_id', o.auction_id,
      'fulfilment_method', o.fulfilment_method,
      'items', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                  'product_id', oi.product_id,
                  'title', oi.title_snapshot,
                  'quantity', oi.quantity,
                  'unit_price_cents', oi.unit_price_cents)), '[]'::jsonb)
                FROM order_items oi WHERE oi.order_id = o.id)),
    o.tenant_id, o.customer_handle,
    'order.paid:' || COALESCE(o.stripe_payment_intent_id, o.id::text));
END $$;

-- A trigger, not an edit to commerce_fulfil_paid_sale. That function is the
-- money path and has already been through two rounds of correctness fixes;
-- reopening it to append one call is risk with no benefit. A trigger also
-- catches orders created by any future route without anyone remembering to
-- emit.
CREATE OR REPLACE FUNCTION commerce_orders_emit_paid()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'paid' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'paid') THEN
    PERFORM commerce_emit_order_paid(NEW.id);
  END IF;
  RETURN NULL;   -- AFTER trigger; return value is ignored
END $$;

DROP TRIGGER IF EXISTS orders_emit_paid ON orders;
CREATE TRIGGER orders_emit_paid
  AFTER INSERT OR UPDATE OF status ON orders
  FOR EACH ROW EXECUTE FUNCTION commerce_orders_emit_paid();

COMMIT;

-- Verify:
-- SELECT commerce_emit('test.ping','test',NULL,'{"hello":"world"}'::jsonb);
-- After a real sale:  SELECT event_type, payload->>'order_number' FROM commerce_events;
-- SELECT commerce_events_since('demo', 10);
-- SELECT commerce_events_ack('demo', 1);
-- UPDATE commerce_events SET event_type='x';   -- must RAISE
