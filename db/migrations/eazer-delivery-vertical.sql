-- Eazer — Delivery vertical: the overlay that tenant has been missing.
--
-- WHY THIS EXISTS
--
-- `Fetch Niche Overlay` in clx-outreach-generation-v2 looks the overlay up by
-- lead.vertical and falls back to 'insurance_broker' when it finds nothing.
-- There is a row for eazer_merchant and there is not one for eazer_delivery,
-- so the moment `Eazer — Delivery` is activated, every business it discovers
-- gets written to with the insurance broker system prompt -- the exact defect
-- eazer-merchant-vertical.sql was written to fix, waiting to happen a second
-- time for the same reason.
--
-- Nothing else is missing. Verified live 2026-09-17:
--   * clients row exists, product_type 'eazer_delivery', active = false
--   * 70 rows in scan_query_tracker for that product_type, ready and inert
--   * `Process Each Business` sets p_vertical from biz.product_type, so new
--     delivery leads arrive tagged 'eazer_delivery' with no further change
-- Only the overlay row was absent. This adds it and nothing else.
--
-- THIS DOES NOT ACTIVATE ANYTHING. The client row stays active = false.
-- Activation is an owner action and a spend decision -- 14 queries x 5 cities
-- of discovery, each business found costing a research call and a scoring
-- call. Switch it on when the merchant yield justifies the second ICP:
--
--   UPDATE clients SET active = true WHERE client_name = 'Eazer — Delivery';
--
-- WHY THE SEGMENT KEYS ARE 'commercial' / 'residential' / 'unknown'
--
-- `Merge Segment Overlay` reads offer_mapping.lead_segments[lead.lead_segment].
-- lead_segment is written by ONE node -- `Decide Segment` in Campaign Router
-- v2 -- and that node can only ever emit 'residential', 'commercial' or
-- 'unknown'. Any other key is config that can never be reached.
--
-- The eazer_merchant overlay keys its branches 'bakery', 'retail', 'florist',
-- 'grocery', 'pharmacy', 'restaurant'. None of those six can ever match, so
-- that overlay's per-segment pain angles and tone have never once reached a
-- prompt. Live confirmation: all 1,380 Eazer merchant leads carry
-- lead_segment = 'unknown'. That is a separate fix and a content decision --
-- see the note at the end of this file -- but it is not repeated here.
--
-- Trade-specific guidance therefore lives in the system prompt, which always
-- applies, rather than in branches that depend on a classifier that does not
-- produce those values.

BEGIN;

INSERT INTO niche_overlays (
  niche_name, display_name, vertical, niche_display_name, lead_target_type,
  is_active, outreach_tone, compliance_notes,
  claude_system_prompt, pain_signals, offer_mapping, behavior_config,
  sales_process_config, preferred_channels)
SELECT
  'eazer_delivery',
  'Eazer Delivery',
  'eazer_delivery',
  'Eazer B2B Delivery Contracts',
  'b2b',
  true,
  'Operational and concrete. Logistics-literate peer, not a salesperson. '
  'Talks in routes, drops, windows and cost per delivery. Short sentences. '
  'No marketing adjectives. The reader already moves parcels and already has '
  'an opinion about it; respect that they know the problem better than you do.',
  'CASL: commercial electronic message to a business address, sent on the basis '
  'of a publicly listed business contact. Must carry sender identification and a '
  'working unsubscribe. Never state or imply a pre-existing relationship that '
  'does not exist.',
$PROMPT$
You write first-contact messages for Eazer Business Delivery, operating in the
Greater Toronto Area. Eazer is operated by Crystallux Group Inc.

WHO YOU ARE WRITING TO -- READ THIS FIRST

This is NOT the Eazer marketplace pitch. Do not offer a listing. Do not
mention commission. The business you are writing to already moves parcels
locally: auto parts stores, medical supply, dental laboratories, printing
companies, sign shops, florists, wholesale distributors, restaurant supply,
appliance and furniture retailers, building supply, commercial bakeries,
office supply, and courier companies with more work than vehicles.

Because they already deliver, the cost line already exists. It is on their
books as a van, a driver, fuel, insurance, or an invoice from an incumbent
courier. THE PITCH IS DISPLACEMENT, NOT EDUCATION. You are not persuading
them that same-day delivery matters. You are giving them a cheaper, more
flexible way to do a thing they are already paying for.

What that means in practice: never explain why delivery is important. They
know. Open at the operational problem, not the concept.

WHAT EAZER OFFERS THEM

  Eazer Direct           point to point, on demand
  Eazer Same Day         collected and delivered within the day
  Eazer Scheduled        recurring drops on a fixed window
  Eazer Route            multiple drops on one planned run
  Eazer Dedicated Driver a driver assigned to them for a block of time
  Eazer XL               oversized and bulky items

No marketplace listing is required. No commission is charged on business
delivery. Pricing is by distance, service level, vehicle type, route density,
urgency and volume. Volume customers negotiate. If you do not know a price,
say it is quoted on the route rather than inventing a number.

COMMERCIAL TERMS -- state only what is listed here, and only when asked or
when it genuinely advances the conversation. Never invent a number.

  Business delivery: NO marketplace commission.
  Priced per delivery on the factors above. Volume is negotiable.
  Who pays the delivery fee is the customer's choice: absorb it, pass it to
  their customer at checkout, or share it.

ON THE INCUMBENT -- READ THIS TWICE

  The incumbent is usually one of three things, and which one changes the
  message entirely:

  1. THEIR OWN VAN AND DRIVER. The problem is not cost per drop, it is that
     the van is idle half the day and unavailable at the worst moment, and
     that a sick driver is a day of missed commitments. Eazer is capacity
     that flexes. Do not tell them to fire anyone -- most use both.
  2. A NATIONAL COURIER. The problem is the service window, not the brand.
     Next-day when their customer wanted it this afternoon.
  3. STAFF DOING DROPS BETWEEN OTHER WORK. The problem is that a counter
     person or a technician is in traffic instead of serving.

  Never claim Eazer is cheaper, better or faster than a named competitor.
  Never disparage anyone. Position Eazer as capacity alongside what they
  already run -- overflow first, then a conversation about volume.

NEVER OPEN WITH

  "Download our app."
  A comparison to a named courier or marketplace.
  Any claim that delivery is free. It is not.
  Any price, rate or discount not listed above.
  An explanation of why same-day delivery matters to their industry.

WRITING THE MESSAGE

  Sell the one operational problem Eazer solves for THIS business. Do not
  describe the product range. A dental lab moving crowns to clinics on a
  fixed morning window does not need to hear about oversized furniture.

  Ground every specific claim in the research you were given. If the research
  does not evidence something, use neutral language instead of inventing a
  detail to make the personalisation sound stronger. A message that is
  accurate and slightly general beats one that is specific and wrong -- the
  second loses the account on the first reply.

  Do not mechanically insert the company name and industry into a template
  and call it personalisation.

    Weak:   "Hi Sam, I noticed ABC Auto Parts is an auto parts store in
             Brampton..."
    Strong: "You are quoting same-day to shops across Brampton, which only
             works if a van is free when the call comes in."

  Before you finish, apply this test: could this exact message be sent
  unchanged to 100 unrelated businesses? If yes, rewrite it. It must contain
  at least one real, evidenced reason for contacting this specific business.

  Never infer ethnicity, religion or any personal attribute from a name. You
  may reflect a business's own public language or cultural market when the
  business itself presents that way -- a halal butcher that describes itself
  as such is a business fact, not an assumption about a person.

CALL TO ACTION

  Ask one low-friction question that invites a reply. Offer a single trial
  run -- one route, one busy afternoon, one overflow day -- rather than a
  meeting, a contract or an account setup. The goal of message one is a
  conversation, not a customer.

OUTPUT

  Return ONLY raw JSON with these string fields:
    email_subject   under 60 characters, lowercase-ish, no marketing caps,
                    reads like a person wrote it to one recipient
    email_body      120-160 words, plain sentences, one clear ask, no bullet
                    lists, no emoji, sender identification at the end
    outreach_angle  one line naming the specific reason this business was
                    contacted
$PROMPT$,
  jsonb_build_array(
    'own van and driver idle between drops but unavailable at peak',
    'a sick or absent driver turns into a day of missed delivery commitments',
    'next-day courier service when the customer expected it this afternoon',
    'counter staff or technicians leaving the shop to make deliveries',
    'quoting same-day but unable to honour it outside a small radius',
    'no way to absorb a seasonal or one-off spike in delivery volume',
    'paying fixed vehicle cost for variable delivery demand',
    'no proof of delivery or tracking to settle a customer dispute',
    'cannot offer a fixed delivery window to commercial accounts',
    'turning down or delaying orders because delivery cannot be arranged',
    'recurring wholesale drops still coordinated by phone and memory'
  ),
  jsonb_build_object(
    'primary_offer', jsonb_build_object(
      'name', 'Try Eazer on one route',
      'target_outcome', 'one trial run, then a conversation about volume',
      'no_contract_required', true,
      'products', jsonb_build_array('Eazer Direct','Eazer Same Day',
                    'Eazer Scheduled','Eazer Route','Eazer Dedicated Driver','Eazer XL')),
    'commission', jsonb_build_object(
      'business_delivery_commission', 0,
      'note', 'Business delivery carries no marketplace commission. Priced on '
              'distance, service level, vehicle type, route density, urgency and '
              'volume. Never quote a rate in outreach -- it is quoted on the route.'),
    'lead_segments', jsonb_build_object(
      'commercial', jsonb_build_object(
        'tone', 'Operational and measurable. They run an account book; speak to '
                'service levels, windows and cost per drop.',
        'lead_with', 'route_or_scheduled',
        'pain_angles', jsonb_build_array(
          'fixed vehicle cost carried against variable demand',
          'commercial accounts expecting a guaranteed delivery window',
          'recurring drops that still depend on one driver being available')),
      'residential', jsonb_build_object(
        'tone', 'Plain and practical, owner-operator to owner-operator. Small '
                'team, no logistics function, delivery is an interruption.',
        'lead_with', 'on_demand',
        'pain_angles', jsonb_build_array(
          'the owner personally making the drops',
          'closing the counter to deliver an order')),
      'unknown', jsonb_build_object(
        'tone', 'Neutral and concrete. Assume they already deliver somehow and '
                'ask how, rather than assuming scale either way.',
        'lead_with', 'overflow_capacity',
        'pain_angles', jsonb_build_array(
          'delivery handled by whoever is free that afternoon',
          'no cover when the usual driver is unavailable'))),
    'delivery_fee_owner', jsonb_build_array('merchant absorbs','customer pays','shared')),
  jsonb_build_object(
    'terminology', jsonb_build_object(
      'lead', 'business', 'customer', 'delivery customer',
      'deal', 'delivery agreement', 'meeting', 'call',
      'revenue', 'delivery volume', 'closed_won', 'onboarded'),
    'message_length', 'short',
    'intent_rules', jsonb_build_object(
      'hot',  'advertises same-day or a delivery radius, or is hiring drivers',
      'warm', 'delivers but on a limited radius, schedule or next-day basis',
      'cold', 'no evidence of any delivery offering at all'),
    'signal_types', jsonb_build_array(
      'offers_own_delivery',
      'delivery_radius_limited',
      'hiring_drivers',
      'advertises_same_day',
      'new_location_opened',
      'wholesale_or_trade_counter',
      'commercial_accounts_served',
      'seasonal_demand_peak',
      'extended_opening_hours',
      'online_ordering_added'),
    'approved_claims', jsonb_build_array(
      'Eazer delivers for businesses that already have their own customers',
      'No marketplace listing is required to use Eazer delivery',
      'No commission is charged on business delivery',
      'Pricing is by route and service level, quoted per job',
      'Same-day, scheduled, multi-drop and dedicated-driver options exist',
      'A trial run is available without a long-term contract')),
  jsonb_build_object(
    'sales_process', jsonb_build_array(
      'discover','research','first contact','trial run',
      'volume conversation','delivery agreement'),
    'cta_types', jsonb_build_array('reply','trial run','short call'),
    'channel_strategy', jsonb_build_object(
      'primary', 'email',
      'secondary', 'phone',
      'avoid', jsonb_build_array('sms')),
    'channel_voice', jsonb_build_object(
      'email', 'Professional and concise. One operational observation, one ask.',
      'phone', 'Talking points, never a script. Ask how they deliver today.',
      'whatsapp', 'Warm and direct. Write as a person, not a company.',
      'linkedin', 'Short and conversational. Relationship before proposition.',
      'enterprise', 'Operational and measurable. Volumes, routes, service levels.'),
    'conversion_event', 'first trial run booked',
    'average_sales_cycle_days', 28,
    'follow_up', jsonb_build_object(
      'max_touches', 3,
      'steps', jsonb_build_array(
        jsonb_build_object('day', 0,  'channel', 'email'),
        jsonb_build_object('day', 5,  'channel', 'email'),
        jsonb_build_object('day', 12, 'channel', 'phone')))),
  '["email","phone"]'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM niche_overlays WHERE niche_name = 'eazer_delivery');

COMMIT;

-- Verify:
--   SELECT vertical, is_active,
--          jsonb_array_length(pain_signals) AS pains,
--          offer_mapping -> 'lead_segments' ? 'commercial' AS segment_reachable
--     FROM niche_overlays WHERE vertical LIKE 'eazer%';
--   -- expect two rows; eazer_delivery pains = 11, segment_reachable = true
--
-- The client row enables email only (clients.channels_enabled = ["email"]).
-- preferred_channels lists phone as the human follow-up, not as an automated
-- channel -- nothing here turns on a second sending channel.
--
-- STILL OPEN, and a content decision rather than a migration:
--   The eazer_merchant overlay keys lead_segments on six trade names that
--   `Decide Segment` cannot emit, so none has ever reached a prompt. Either
--   remap them onto residential/commercial/unknown (loses the per-trade
--   detail), move that detail into its claude_system_prompt (keeps it, and is
--   where this file puts the equivalent), or teach `Decide Segment` to
--   classify by trade (changes a protected workflow). Owner's call.
