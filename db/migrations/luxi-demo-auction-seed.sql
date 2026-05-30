-- LUXI demo auction seed
-- Run AFTER avatars-platform-schema.sql (needs the `avatars` + `auctions` tables
-- and the seeded LUXI avatar row). Inserts ONE open demo auction so the LUXI
-- dashboard and the live bid-entry page have something real to show immediately.
--
-- Idempotent: re-running will not create a second copy.
-- Safe to delete when done:  DELETE FROM auctions WHERE item_title LIKE 'DEMO —%';

INSERT INTO auctions (
  avatar_id,
  item_title,
  item_description,
  item_category,
  status,
  scheduled_open_at,
  scheduled_close_at,
  reserve_price_cents,
  min_increment_cents,
  current_high_bid_cents,
  anti_snipe_window_seconds,
  anti_snipe_extend_seconds,
  anti_snipe_max_extensions
)
SELECT
  a.id,
  'DEMO — Signed Collectible (safe to delete)',
  'Test auction from the LUXI go-live seed. Open the live page, place a few bids to watch the engine + anti-snipe work, then delete it.',
  'Collectibles',
  'open',                       -- opens immediately so it shows under "Live now"
  now(),
  now() + interval '60 minutes',
  0,                            -- no reserve
  100,                          -- $1.00 min increment
  0,                            -- no bids yet
  30,                           -- anti-snipe window (s)
  30,                           -- anti-snipe extend (s)
  10                            -- max extensions
FROM avatars a
WHERE a.avatar_name = 'LUXI'
  AND NOT EXISTS (
    SELECT 1 FROM auctions
    WHERE item_title = 'DEMO — Signed Collectible (safe to delete)'
  );

-- Verify:
SELECT id, item_title, status, scheduled_open_at, scheduled_close_at
FROM auctions
WHERE item_title LIKE 'DEMO —%';
