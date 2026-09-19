-- eazer_merchant: rescue the per-trade guidance from a key that cannot match.
--
-- THE DEFECT
--
-- `Merge Segment Overlay` in clx-outreach-generation-v2 reads
-- offer_mapping.lead_segments[lead.lead_segment] and, when it finds a branch,
-- merges its pain_angles into pain_signals and appends a SEGMENT CONTEXT
-- stanza to the system prompt.
--
-- lead_segment can only ever hold one of three values. Not by convention --
-- by constraint. `leads_lead_segment_check`, added 2026-04-23:
--
--   CHECK (lead_segment IN ('residential','commercial','unknown'))
--
-- and the single node that writes it, `Decide Segment` in Campaign Router v2,
-- emits exactly those three.
--
-- The eazer_merchant overlay keys its six branches 'restaurant', 'pharmacy',
-- 'grocery', 'florist', 'bakery', 'retail'. **None of them can ever match.**
-- The database would reject a lead carrying any of those values. So that
-- overlay's per-trade pain angles and tone have never reached a prompt and
-- could not have. Live confirmation: all 1,380 Eazer merchant leads carry
-- lead_segment = 'unknown'.
--
-- It fails silently, which is why it went unnoticed: a missing branch is a
-- pass-through, not an error. The outreach still generates. It is simply
-- generic where the configuration claims it is trade-specific.
--
-- The other eight overlays look correct -- insurance_broker, real_estate,
-- construction, dental, consulting, cleaning_services, legal, moving_services
-- all key on residential/commercial, making eazer_merchant the only deviation.
-- Read that from the seeding migrations (2026-04-23-b2b-b2c-segmentation.sql
-- and 2026-04-24-verticals-batch-full.sql), NOT from production: PostgREST was
-- returning PGRST002 when this was written, so the live check could not run.
-- The eazer_merchant reading IS live, taken before the outage. Re-run the
-- audit against production before treating the other eight as clean -- this
-- repo has been wrong about what is deployed twice this sprint.
--
-- THE FIX, AND WHY IT IS SHAPED THIS WAY
--
-- The six trade branches are good content. The problem is only where they are
-- stored. So nothing is deleted:
--
--   1. The six move to offer_mapping.trade_guidance -- preserved verbatim,
--      under a name that does not claim to be something the engine reads.
--   2. lead_segments is rewritten with the three reachable keys.
--   3. The trade guidance is appended to claude_system_prompt, which applies
--      to every lead regardless of segment. That is what actually delivers
--      the content, and it is the same approach eazer-delivery-vertical.sql
--      takes.
--
-- WHAT THIS DELIBERATELY DOES NOT DO -- the safety property
--
-- The new branches carry NO `channels` key, and that is load-bearing.
-- `Decide Channel` in Campaign Router v2 -- a PROTECTED production workflow --
-- overrides the chosen channel only when it finds
-- lead_segments.<segment>.channels as an array:
--
--   if (!leadLevel && overlaySegments[segmentKey]
--       && Array.isArray(overlaySegments[segmentKey].channels)) { ... }
--
-- The six trade branches never had `channels`, so the router has never taken
-- that path for Eazer. Adding branches without `channels` keeps it that way.
-- Only `Merge Segment Overlay` -- prompt enrichment -- changes behaviour.
-- No workflow is edited and no routing decision moves.
--
-- Safe to apply now: 0 Eazer merchant leads have reached Outreach Ready, so
-- nothing in flight depends on the current shape.
--
-- Idempotent. Every statement is guarded and re-running is a no-op.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Preserve the six, under an honest name
-- ---------------------------------------------------------------------------
-- Guarded on 'restaurant' still being present under lead_segments, so a
-- re-run, or a hand-edit that already moved them, is left alone.

UPDATE niche_overlays
   SET offer_mapping = jsonb_set(
         offer_mapping,
         '{trade_guidance}',
         offer_mapping -> 'lead_segments')
 WHERE niche_name = 'eazer_merchant'
   AND offer_mapping -> 'lead_segments' ? 'restaurant'
   AND NOT offer_mapping ? 'trade_guidance';

-- ---------------------------------------------------------------------------
-- 2. lead_segments, rebuilt on keys the classifier can actually produce
-- ---------------------------------------------------------------------------
-- No `channels` key on any branch -- see the safety note in the header.
-- 'unknown' is included because for this tenant it is not an edge case: these
-- leads come from a Google Maps city scan with no company_size, no
-- linkedin_url and no apollo_org_id, so `Decide Segment` will classify the
-- great majority of them 'unknown'. An overlay whose only branches were
-- residential/commercial would be correct and still never fire.

UPDATE niche_overlays
   SET offer_mapping = jsonb_set(
         offer_mapping,
         '{lead_segments}',
         jsonb_build_object(
           'commercial', jsonb_build_object(
             'tone', 'Commercial and direct. They sell to other businesses or '
                     'run more than one location, and they know their numbers. '
                     'Lead with volume and reliability, not novelty.',
             'lead_with', 'business_delivery',
             'pain_angles', jsonb_build_array(
               'corporate, catering or wholesale orders handled by hand',
               'a delivery promise that depends on one van being free',
               'commission charged on orders the merchant sourced itself')),
           'residential', jsonb_build_object(
             'tone', 'Owner-operator to owner-operator. Small team, no '
                     'logistics function, delivery is an interruption to '
                     'serving the counter.',
             'lead_with', 'on_demand',
             'pain_angles', jsonb_build_array(
               'the owner personally making the drops',
               'a delivery radius limited by the owner''s own car',
               'turning away orders that are just out of reach')),
           'unknown', jsonb_build_object(
             'tone', 'Neutral and concrete. Assume they already sell direct '
                     'somehow and ask how they get it to the customer, rather '
                     'than assuming scale in either direction.',
             'lead_with', 'business_delivery',
             'pain_angles', jsonb_build_array(
               'direct phone, website and Instagram orders with no way to deliver them',
               'depending on one marketplace for customer relationships',
               'no delivery option outside a small radius'))))
 WHERE niche_name = 'eazer_merchant'
   AND NOT (offer_mapping -> 'lead_segments') ? 'unknown';

-- ---------------------------------------------------------------------------
-- 3. The content that was stranded, put where it always applies
-- ---------------------------------------------------------------------------
-- Guarded on the marker line, so re-running cannot append it twice.

UPDATE niche_overlays
   SET claude_system_prompt = claude_system_prompt || $ADD$

TRADE GUIDANCE -- WHICH KIND OF MERCHANT IS IN FRONT OF YOU

  Use the one that matches the business in the research. If none clearly
  matches, ignore this section rather than forcing a fit. These are angles to
  choose from, not a checklist to work through -- one of them, well grounded,
  is the whole message.

  RESTAURANT   Lead with business delivery. Commission on every marketplace
               order; direct phone and Instagram orders with no way to deliver
               them; depending on one marketplace for customer relationships.
               Operator to operator. They are busy, often mid-service. Two
               sentences before the ask.

  PHARMACY     Lead with scheduled delivery. Customers who cannot collect;
               staff leaving the counter to drop off; scheduled repeat
               deliveries done manually. Careful and precise -- a regulated
               environment. NEVER imply Eazer handles anything requiring a
               licence.

  GROCERY      Lead with business delivery. Large baskets customers cannot
               carry home; a delivery radius limited by the owner's own car;
               regular customers who have moved further away. Practical and
               local -- speak about the neighbourhood they actually serve.

  FLORIST      Lead with same day. Time-critical same-day drops; demand spikes
               at Valentine's and Mother's Day; paying couriers per delivery at
               retail rates. Timing-led -- their whole product is arriving on
               the right day.

  BAKERY       Lead with scheduled delivery. Early-morning wholesale drops;
               corporate and event orders; recurring weekly deliveries handled
               by hand. Early-hours, routine-driven, reliability over novelty.

  RETAIL       Lead with business delivery. Online orders with no local
               delivery option; Shopify or Instagram sales fulfilled manually;
               customers choosing a competitor who delivers. Commercial and
               direct -- they already sell online and know their numbers.
$ADD$
 WHERE niche_name = 'eazer_merchant'
   AND position('TRADE GUIDANCE -- WHICH KIND OF MERCHANT' in claude_system_prompt) = 0;

COMMIT;

-- Verify:
--   SELECT jsonb_object_keys(offer_mapping -> 'lead_segments') AS reachable
--     FROM niche_overlays WHERE niche_name = 'eazer_merchant';
--   -- commercial, residential, unknown
--
--   SELECT jsonb_object_keys(offer_mapping -> 'trade_guidance') AS preserved
--     FROM niche_overlays WHERE niche_name = 'eazer_merchant';
--   -- bakery, florist, grocery, pharmacy, restaurant, retail
--
--   SELECT position('TRADE GUIDANCE' in claude_system_prompt) > 0 AS in_prompt,
--          (SELECT count(*) FROM jsonb_object_keys(
--             offer_mapping -> 'lead_segments') k
--            WHERE k NOT IN ('residential','commercial','unknown')) AS dead_keys
--     FROM niche_overlays WHERE niche_name = 'eazer_merchant';
--   -- true, 0
--
-- Nothing here activates anything, edits a workflow, or moves a routing
-- decision. It is one row of configuration, corrected.
