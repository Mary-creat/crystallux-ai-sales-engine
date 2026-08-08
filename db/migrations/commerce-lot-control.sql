-- Crystallux — lot control (open / close / reschedule a lot)
-- ===========================================================
-- Apply AFTER commerce-event-spine.sql. Idempotent.
--
-- THE GAP
-- commerce_quick_list creates lots as 'scheduled' on purpose -- nothing should
-- go live merely by existing. But nothing could open one either, so a loaded
-- queue could never be sold. This is the operator's hand on the show.
--
-- Server-authoritative by design: the page asks, the database decides. It
-- refuses to open a lot with no stock behind it, refuses to reopen a finished
-- one, and closes by bringing the deadline forward rather than forcing a
-- status -- so the existing auction tick still decides sold vs unsold, picks
-- the winner and triggers settlement. Forcing 'closed_sold' here would strand
-- authorizations that the settle cron never sees.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Open a lot. This is the moment it becomes sellable.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION commerce_open_lot(
  p_auction_id    uuid,
  p_duration_mins integer DEFAULT NULL,
  p_actor         text DEFAULT 'admin'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE a record; v_avail integer; v_mins integer; v_close timestamptz;
BEGIN
  SELECT * INTO a FROM auctions WHERE id = p_auction_id FOR UPDATE;
  IF a.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'Lot not found');
  END IF;
  IF a.status IN ('closed_sold','closed_unsold','cancelled') THEN
    RETURN jsonb_build_object('ok', false, 'status', 409,
      'error', 'That lot has already finished. Create a new one.');
  END IF;
  IF a.status IN ('open','extended') THEN
    RETURN jsonb_build_object('ok', true, 'status', 200, 'already_open', true,
                              'closes_at', a.scheduled_close_at);
  END IF;

  -- Refuse to open a lot with nothing behind it. Selling something we cannot
  -- ship is worse than a gap in the running order.
  IF a.inventory_item_id IS NOT NULL THEN
    SELECT (quantity_on_hand - quantity_reserved) INTO v_avail
      FROM inventory_items WHERE id = a.inventory_item_id;
    IF COALESCE(v_avail, 0) < COALESCE(a.quantity_listed, 1) THEN
      RETURN jsonb_build_object('ok', false, 'status', 409,
        'error', format('Out of stock: %s available, this lot needs %s',
                        COALESCE(v_avail,0), COALESCE(a.quantity_listed,1)));
    END IF;
  END IF;

  -- Reuse the length it was created with unless told otherwise.
  v_mins := COALESCE(p_duration_mins,
    GREATEST(CEIL(EXTRACT(EPOCH FROM (a.scheduled_close_at - a.scheduled_open_at)) / 60)::integer, 1),
    10);
  v_close := now() + make_interval(mins => GREATEST(v_mins, 1));

  UPDATE auctions
     SET status = 'open', scheduled_open_at = now(), scheduled_close_at = v_close
   WHERE id = a.id;

  PERFORM commerce_emit('auction.started', 'auction', a.id,
    jsonb_build_object('lot_number', a.lot_number, 'title', a.item_title,
                       'closes_at', v_close), a.tenant_id, p_actor, NULL);

  RETURN jsonb_build_object('ok', true, 'status', 200, 'lot_status', 'open',
                            'closes_at', v_close);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Close a lot early -- "going once, going twice, sold".
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION commerce_close_lot(
  p_auction_id uuid,
  p_actor      text DEFAULT 'admin'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE a record;
BEGIN
  SELECT * INTO a FROM auctions WHERE id = p_auction_id FOR UPDATE;
  IF a.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'Lot not found');
  END IF;
  IF a.status NOT IN ('open','extended') THEN
    RETURN jsonb_build_object('ok', false, 'status', 409,
      'error', 'That lot is not open.');
  END IF;

  -- Bring the deadline forward and let the auction tick do the rest. It knows
  -- how to pick a winner, honour the reserve and hand off to settlement;
  -- setting a terminal status here would skip all of that and strand the
  -- winner's authorization.
  UPDATE auctions SET scheduled_close_at = now() WHERE id = a.id;

  PERFORM commerce_emit('auction.closing', 'auction', a.id,
    jsonb_build_object('lot_number', a.lot_number,
                       'high_bid_cents', a.current_high_bid_cents),
    a.tenant_id, p_actor, NULL);

  RETURN jsonb_build_object('ok', true, 'status', 200,
    'note', 'Closing now. The auction engine settles it within a minute.');
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cancel a lot that should never have been listed.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION commerce_cancel_lot(
  p_auction_id uuid,
  p_reason     text DEFAULT NULL,
  p_actor      text DEFAULT 'admin'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE a record;
BEGIN
  SELECT * INTO a FROM auctions WHERE id = p_auction_id FOR UPDATE;
  IF a.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'Lot not found');
  END IF;
  IF a.status IN ('closed_sold','cancelled') THEN
    RETURN jsonb_build_object('ok', false, 'status', 409,
      'error', 'That lot is already finished.');
  END IF;

  UPDATE auctions
     SET status = 'cancelled', actual_close_at = COALESCE(actual_close_at, now())
   WHERE id = a.id;

  -- Any authorizations on it are released by the settle cron, which already
  -- treats 'cancelled' as terminal. Nothing to unwind here.
  PERFORM commerce_emit('auction.cancelled', 'auction', a.id,
    jsonb_build_object('lot_number', a.lot_number, 'reason', p_reason),
    a.tenant_id, p_actor, NULL);

  RETURN jsonb_build_object('ok', true, 'status', 200, 'lot_status', 'cancelled');
END $$;

COMMIT;

-- Verify:
-- SELECT commerce_open_lot((SELECT id FROM auctions WHERE lot_number='LOT-101'));
-- SELECT status, scheduled_close_at FROM auctions WHERE lot_number='LOT-101';
-- SELECT event_type FROM commerce_events ORDER BY id DESC LIMIT 3;
