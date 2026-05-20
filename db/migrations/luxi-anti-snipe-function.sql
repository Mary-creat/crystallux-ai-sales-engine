-- ══════════════════════════════════════════════════════════════════
-- LUXI anti-snipe extension function — T1.7 follow-up
-- ══════════════════════════════════════════════════════════════════
-- Companion to luxi-auction-tick-functions.sql (commit feb7fc2).
-- Called by the same cron tick workflow before close-expired runs:
--
--   Schedule (every N sec)
--     → luxi_tick_anti_snipe_extension()    ← THIS function
--     → luxi_tick_close_expired_auctions()
--     → Shape Response
--
-- For every open / extended auction whose newest active bid landed
-- inside the `anti_snipe_window_seconds` window AND extensions_used
-- < anti_snipe_max_extensions, push the scheduled_close_at forward
-- by `anti_snipe_extend_seconds`, mark status='extended', and
-- increment extensions_used.
--
-- Pure SQL state transition. Atomic per auction. No external calls.
-- Re-running the migration replaces the function (CREATE OR REPLACE).
-- Idempotent — safe to apply alongside the existing migration.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION luxi_tick_anti_snipe_extension()
RETURNS TABLE (
  auction_id        uuid,
  previous_close_at timestamptz,
  new_close_at      timestamptz,
  extensions_used   integer,
  extending_bid_id  uuid,
  extending_amount_cents integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auction         RECORD;
  v_latest_bid      RECORD;
  v_now             timestamptz := now();
  v_extend_to       timestamptz;
BEGIN
  -- For each open/extended auction where the *last* active bid landed
  -- within the anti-snipe window of the scheduled close, extend the
  -- close. Selecting `FOR UPDATE` to avoid two concurrent ticks both
  -- bumping the same auction.
  FOR v_auction IN
    SELECT a.id,
           a.scheduled_close_at,
           a.anti_snipe_window_seconds,
           a.anti_snipe_extend_seconds,
           a.anti_snipe_max_extensions,
           a.extensions_used
    FROM auctions a
    WHERE a.status IN ('open', 'extended')
      AND a.scheduled_close_at > v_now                              -- still open
      AND a.extensions_used < a.anti_snipe_max_extensions           -- room for another extension
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Look at the most-recent active bid on this auction
    SELECT b.id, b.amount_cents, b.placed_at
      INTO v_latest_bid
    FROM auction_bids b
    WHERE b.auction_id = v_auction.id
      AND b.status = 'active'
    ORDER BY b.placed_at DESC
    LIMIT 1;

    -- Skip if no active bids OR latest bid landed outside the anti-snipe
    -- window (i.e. with enough time to spare before close).
    IF v_latest_bid IS NULL THEN
      CONTINUE;
    END IF;

    IF v_latest_bid.placed_at < (v_auction.scheduled_close_at - (v_auction.anti_snipe_window_seconds || ' seconds')::interval) THEN
      CONTINUE;
    END IF;

    -- Extend the close by anti_snipe_extend_seconds from the bid time
    -- (NOT from now()) so back-to-back snipers each get a fair window.
    v_extend_to := v_latest_bid.placed_at + (v_auction.anti_snipe_extend_seconds || ' seconds')::interval;

    -- Only extend if it actually moves the close forward.
    IF v_extend_to <= v_auction.scheduled_close_at THEN
      CONTINUE;
    END IF;

    UPDATE auctions
    SET scheduled_close_at = v_extend_to,
        status             = 'extended',
        extensions_used    = v_auction.extensions_used + 1,
        updated_at         = v_now
    WHERE id = v_auction.id;

    auction_id             := v_auction.id;
    previous_close_at      := v_auction.scheduled_close_at;
    new_close_at           := v_extend_to;
    extensions_used        := v_auction.extensions_used + 1;
    extending_bid_id       := v_latest_bid.id;
    extending_amount_cents := v_latest_bid.amount_cents;
    RETURN NEXT;
  END LOOP;

  RETURN;
END;
$$;

GRANT EXECUTE ON FUNCTION luxi_tick_anti_snipe_extension() TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- Verify after applying
-- ─────────────────────────────────────────────────────────────────
--   SELECT * FROM luxi_tick_anti_snipe_extension();
--   -- Expect: 0 rows if no auctions are currently in the snipe window.
--
-- To exercise in a test session:
--   1. Insert an auction with scheduled_close_at = now() + 20 seconds,
--      status='open', anti_snipe_window_seconds=30 (so a bid placed in
--      the next 20s triggers extension).
--   2. Insert an active auction_bid placed_at = now().
--   3. SELECT * FROM luxi_tick_anti_snipe_extension();
--      -> Expect 1 row with new_close_at = bid.placed_at + 30s.
-- ══════════════════════════════════════════════════════════════════
