-- ══════════════════════════════════════════════════════════════════
-- LUXI auction-tick functions — T1.7 / Tranche 1 wrap-up
-- ══════════════════════════════════════════════════════════════════
-- Companion to clx-luxi-auction-tick-v1.json. The workflow runs on a
-- cron (every 5 min initially; Mary tunes down to every 5 s once LUXI
-- goes live) and calls luxi_tick_close_expired_auctions() over HTTP
-- via PostgREST. ALL state transitions happen inside this SQL function
-- so the close + winner-selection + bid-outbid are atomic per
-- auction — no race where two concurrent ticks see the same auction
-- as still open.
--
-- Tables touched (all defined in avatars-platform-schema.sql):
--   auctions          — status, actual_close_at, winning_bid_id,
--                       current_high_bid_*, updated_at
--   auction_bids      — status, won_at, outbid_at
--
-- Tables intentionally NOT touched in this commit:
--   auction_payment_holds — Stripe capture is its own workflow, will
--                            land in a separate commit when Mary has
--                            the Stripe credential configured + tested.
--                            For now the hold stays in 'authorized'.
--   bidder_trust_scores  — outcomes (forfeit, chargeback) need their
--                            own state-transition function. Out of T1.7.
--
-- Anti-snipe extension is intentionally NOT in this function — Mary's
-- spec calls it out but it's a separate concern from "close expired
-- auctions": the extension fires BEFORE close, the close fires AFTER.
-- See the function `luxi_tick_anti_snipe_extension()` stub at the end
-- (commented) for the shape; ship in the follow-up commit alongside
-- the bid parser.
--
-- Idempotent. Re-running the migration replaces the function via
-- CREATE OR REPLACE. No rollback required (drop function if removing).
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- luxi_tick_close_expired_auctions()
-- ─────────────────────────────────────────────────────────────────
-- Cron-callable. Iterates auctions whose scheduled_close_at has
-- passed and whose status is still 'open' or 'extended'. For each:
--   - Finds the highest 'active' bid (tiebreak: earlier placed_at wins)
--   - Sets auction.status = 'closed_sold' + winning_bid_id, OR
--     'closed_unsold' if no active bids
--   - Sets the winner bid → 'won' + won_at = now()
--   - Sets the runner-up (second-highest active) → 'runner_up'
--   - Outbids all remaining 'active' bids → 'outbid' + outbid_at
--
-- Returns one row per processed auction so the workflow can log/alert.
-- SECURITY DEFINER + GRANT EXECUTE so the service_role credential
-- bypasses RLS on auctions / auction_bids (which are scoped to
-- service_role-only writes).
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION luxi_tick_close_expired_auctions()
RETURNS TABLE (
  auction_id            uuid,
  new_status            text,
  winning_bid_id        uuid,
  winning_amount_cents  integer,
  runner_up_bid_id      uuid,
  bids_outbid_count     integer,
  closed_at             timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auction       RECORD;
  v_winner_id     uuid;
  v_winner_amount integer;
  v_runner_up_id  uuid;
  v_outbid_count  integer;
  v_now           timestamptz := now();
BEGIN
  FOR v_auction IN
    SELECT id
    FROM auctions
    WHERE status IN ('open', 'extended')
      AND scheduled_close_at <= v_now
    ORDER BY scheduled_close_at ASC
  LOOP
    -- Top active bid (winner candidate). Tiebreak by placed_at ASC
    -- so the earlier of two equal-amount bids wins.
    SELECT b.id, b.amount_cents
      INTO v_winner_id, v_winner_amount
    FROM auction_bids b
    WHERE b.auction_id = v_auction.id
      AND b.status = 'active'
    ORDER BY b.amount_cents DESC, b.placed_at ASC
    LIMIT 1;

    -- Second active bid → runner-up
    SELECT b.id INTO v_runner_up_id
    FROM auction_bids b
    WHERE b.auction_id = v_auction.id
      AND b.status = 'active'
      AND (v_winner_id IS NULL OR b.id <> v_winner_id)
    ORDER BY b.amount_cents DESC, b.placed_at ASC
    LIMIT 1;

    IF v_winner_id IS NOT NULL THEN
      -- Auction sold. Close + mark winner + runner-up + outbid rest.
      UPDATE auctions
      SET status                 = 'closed_sold',
          actual_close_at        = v_now,
          winning_bid_id         = v_winner_id,
          current_high_bid_cents = v_winner_amount,
          current_high_bid_id    = v_winner_id,
          updated_at             = v_now
      WHERE id = v_auction.id;

      UPDATE auction_bids
      SET status = 'won', won_at = v_now
      WHERE id = v_winner_id;

      IF v_runner_up_id IS NOT NULL THEN
        UPDATE auction_bids
        SET status = 'runner_up'
        WHERE id = v_runner_up_id;
      END IF;

      -- Outbid every remaining 'active' bid (winner and runner_up
      -- have already been moved to 'won' / 'runner_up' above so
      -- they don't get hit by this update).
      WITH outbid AS (
        UPDATE auction_bids
        SET status = 'outbid', outbid_at = v_now
        WHERE auction_bids.auction_id = v_auction.id
          AND status = 'active'
        RETURNING 1
      )
      SELECT count(*) INTO v_outbid_count FROM outbid;
    ELSE
      -- No bids; auction closes unsold.
      UPDATE auctions
      SET status          = 'closed_unsold',
          actual_close_at = v_now,
          updated_at      = v_now
      WHERE id = v_auction.id;

      v_outbid_count := 0;
    END IF;

    -- Return row for the caller's summary
    auction_id           := v_auction.id;
    new_status           := CASE WHEN v_winner_id IS NOT NULL
                                  THEN 'closed_sold'
                                  ELSE 'closed_unsold' END;
    winning_bid_id       := v_winner_id;
    winning_amount_cents := COALESCE(v_winner_amount, 0);
    runner_up_bid_id     := v_runner_up_id;
    bids_outbid_count    := v_outbid_count;
    closed_at            := v_now;
    RETURN NEXT;

    -- Reset locals for next iteration
    v_winner_id := NULL;
    v_winner_amount := NULL;
    v_runner_up_id := NULL;
    v_outbid_count := 0;
  END LOOP;

  RETURN;
END;
$$;

-- Allow the n8n service_role credential to call this over PostgREST.
GRANT EXECUTE ON FUNCTION luxi_tick_close_expired_auctions() TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- Anti-snipe extension — DEFERRED to T1.7 follow-up commit
-- ─────────────────────────────────────────────────────────────────
-- The function below is a placeholder showing the intended shape.
-- It is NOT created — uncomment + adjust when shipping the anti-snipe
-- logic. Reason for deferral: separate concern from close-expired,
-- needs its own correctness test (race against the closing tick),
-- and the schema already supports it via anti_snipe_* columns on
-- auctions. Ship the simpler close-tick first.
--
-- CREATE OR REPLACE FUNCTION luxi_tick_anti_snipe_extension()
-- RETURNS TABLE (auction_id uuid, new_close_at timestamptz, extensions_used integer)
-- LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
-- AS $$ ... [select auctions where a bid landed inside the
--          anti_snipe_window_seconds AND extensions_used <
--          anti_snipe_max_extensions; extend scheduled_close_at;
--          increment extensions_used; set status='extended'] ... $$;
--
-- GRANT EXECUTE ON FUNCTION luxi_tick_anti_snipe_extension() TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- Verify after applying
-- ─────────────────────────────────────────────────────────────────
-- Manual sanity check from psql:
--   SELECT * FROM luxi_tick_close_expired_auctions();
--   -- Expect: 0 rows if no auctions are eligible.
--   -- Insert a test auction with scheduled_close_at in the past and
--   -- one active bid, then re-run; expect 1 row with new_status='closed_sold'.
-- ══════════════════════════════════════════════════════════════════
