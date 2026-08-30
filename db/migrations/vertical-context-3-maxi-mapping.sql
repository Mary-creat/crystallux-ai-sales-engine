-- ============================================================
-- Vertical context, step 3 of 5 — map MAXI slugs to verticals
--
-- Writes niche_overlay_id for the five industries that are genuinely
-- the same thing in both taxonomies, and resolves two slug drifts:
--     cleaning  -> cleaning_services
--     lawyers   -> legal
--
-- Judgement calls are deliberately left NULL rather than guessed.
-- MAXI's "coaches" is not niche_overlays' "consulting", and "mortgage"
-- is not "insurance_broker". A wrong mapping would route a campaign
-- with the wrong ICP, which is worse than no mapping at all.
--
-- Idempotent: only fills rows that are still NULL, so a re-run cannot
-- overwrite a mapping corrected by hand later.
-- Requires step 2. Safe to re-run.
-- ============================================================

UPDATE maxi_industries mi
   SET niche_overlay_id = no.id
  FROM niche_overlays no
 WHERE mi.niche_overlay_id IS NULL
   AND no.niche_name = CASE mi.industry_slug
         WHEN 'construction' THEN 'construction'
         WHEN 'dental'       THEN 'dental'
         WHEN 'real_estate'  THEN 'real_estate'
         WHEN 'cleaning'     THEN 'cleaning_services'
         WHEN 'lawyers'      THEN 'legal'
         ELSE NULL
       END;

-- ---- VERIFY ----
-- Expect exactly 5 mapped, 17 unmapped, 22 total.
SELECT
  count(*) FILTER (WHERE niche_overlay_id IS NOT NULL) AS mapped,
  count(*) FILTER (WHERE niche_overlay_id IS NULL)     AS unmapped_marketing_only,
  count(*)                                              AS total_industries
FROM maxi_industries;

-- The five that should be mapped, with the vertical each resolves to.
SELECT mi.industry_slug, no.niche_name AS mapped_to_vertical
  FROM maxi_industries mi
  JOIN niche_overlays no ON no.id = mi.niche_overlay_id
 ORDER BY mi.industry_slug;
