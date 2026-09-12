-- Eazer merchant vertical — configuration, not a new messaging layer.
--
-- WHERE THIS GOES AND WHY
--
-- clx-outreach-generation-v2 already runs a layered pipeline:
--
--   Fetch Niche Overlay -> Merge Segment Overlay -> Fetch Signal For Outreach
--   -> Merge Signal Context -> Build Outreach Prompt -> Claude Generate Outreach
--
-- It reads exactly four fields from niche_overlays -- claude_system_prompt,
-- outreach_tone, pain_signals, offer_mapping -- and layers the lead's own
-- segment, detected signal and research on top. That IS the intelligent
-- messaging layer. Eazer needs configuration in it, not a second one.
--
-- behavior_config additionally feeds clx-business-signal-detection-v2, which
-- was wired to read it on 2026-09-12.
--
-- THE BUG THIS ALSO FIXES
--
-- Fetch Niche Overlay looks the row up by lead.vertical and falls back to
-- 'insurance_broker' when it is null. All 1,094 Eazer merchants were
-- inserted with vertical NULL, so every one of them would have been written
-- to using the insurance broker system prompt. insert_lead_if_not_exists
-- gains p_vertical, and the existing rows are backfilled.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. vertical must reach the lead, or the overlay is never found
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS insert_lead_if_not_exists(
  text, text, text, text, text, text, text, text, text, text, text, uuid, text, text);

CREATE OR REPLACE FUNCTION insert_lead_if_not_exists(
  p_full_name    text DEFAULT NULL,
  p_email        text DEFAULT NULL,
  p_phone        text DEFAULT NULL,
  p_company      text DEFAULT NULL,
  p_job_title    text DEFAULT 'Owner',
  p_industry     text DEFAULT NULL,
  p_city         text DEFAULT NULL,
  p_source       text DEFAULT 'google_maps_discovery',
  p_lead_status  text DEFAULT 'New Lead',
  p_product_type text DEFAULT NULL,
  p_notes        text DEFAULT NULL,
  p_client_id    uuid DEFAULT NULL,
  p_website      text DEFAULT NULL,
  p_place_id     text DEFAULT NULL,
  p_vertical     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_existing   leads%ROWTYPE;
  v_new_id     uuid;
  v_client_id  uuid;
  v_matched_on text;
  v_website    text := nullif(btrim(coalesce(p_website, '')), '');
  v_place_id   text := nullif(btrim(coalesce(p_place_id, '')), '');
  v_vertical   text := nullif(btrim(coalesce(p_vertical, '')), '');
BEGIN
  IF p_company IS NULL OR length(trim(p_company)) = 0 THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'company is required');
  END IF;

  IF v_place_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM leads WHERE place_id = v_place_id LIMIT 1;
    IF FOUND THEN v_matched_on := 'place_id'; END IF;
  END IF;

  IF v_matched_on IS NULL THEN
    SELECT * INTO v_existing FROM leads WHERE company = p_company LIMIT 1;
    IF FOUND THEN v_matched_on := 'company'; END IF;
  END IF;

  IF v_matched_on IS NOT NULL THEN
    UPDATE leads
       SET website  = COALESCE(website,  v_website),
           place_id = COALESCE(place_id, v_place_id),
           vertical = COALESCE(vertical, v_vertical),
           phone    = COALESCE(phone,    nullif(btrim(coalesce(p_phone,'')), '')),
           updated_at = now()
     WHERE id = v_existing.id;

    RETURN jsonb_build_object(
      'status', 'duplicate', 'id', v_existing.id, 'company', v_existing.company,
      'matched_on', v_matched_on, 'existing_city', v_existing.city,
      'existing_status', v_existing.lead_status, 'existing_pool', v_existing.lead_pool);
  END IF;

  IF p_client_id IS NOT NULL THEN
    v_client_id := p_client_id;
  ELSE
    SELECT id INTO v_client_id FROM clients
     WHERE active = true
       AND ( product_type = p_product_type
          OR (p_industry IS NOT NULL AND industry ILIKE '%' || p_industry || '%') )
     ORDER BY CASE WHEN product_type = p_product_type THEN 0 ELSE 1 END,
              CASE WHEN city = p_city THEN 0 ELSE 1 END, created_at ASC
     LIMIT 1;
  END IF;

  INSERT INTO leads (
    full_name, email, phone, company, job_title, industry, city,
    source, lead_status, product_type, notes, client_id, lead_pool,
    website, place_id, vertical)
  VALUES (
    p_full_name, p_email, p_phone, p_company, p_job_title, p_industry, p_city,
    p_source, p_lead_status, p_product_type, p_notes, v_client_id,
    CASE WHEN v_client_id IS NULL THEN 'house' ELSE 'tenant' END,
    v_website, v_place_id, COALESCE(v_vertical, p_product_type))
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'status', 'inserted', 'id', v_new_id, 'company', p_company,
    'client_id', v_client_id, 'client_matched', v_client_id IS NOT NULL,
    'lead_pool', CASE WHEN v_client_id IS NULL THEN 'house' ELSE 'tenant' END,
    'vertical', COALESCE(v_vertical, p_product_type),
    'has_website', v_website IS NOT NULL);
END;
$fn$;

GRANT EXECUTE ON FUNCTION insert_lead_if_not_exists(text,text,text,text,text,text,text,text,text,text,text,uuid,text,text,text) TO service_role;

-- Backfill: without this the 1,094 merchants already discovered still
-- resolve to the insurance overlay.
UPDATE leads SET vertical = product_type
 WHERE vertical IS NULL AND product_type LIKE 'eazer%';

-- ---------------------------------------------------------------------------
-- 2. The vertical itself
-- ---------------------------------------------------------------------------

INSERT INTO niche_overlays (
  niche_name, display_name, vertical, niche_display_name, lead_target_type,
  is_active, outreach_tone, compliance_notes,
  claude_system_prompt, pain_signals, offer_mapping, behavior_config,
  sales_process_config, preferred_channels)
SELECT
  'eazer_merchant',
  'Eazer Merchants',
  'eazer_merchant',
  'Eazer Merchant Acquisition',
  'b2b',
  true,
  'Direct, local, practical. Peer-to-peer between operators, not vendor-to-lead. '
  'Short sentences. No marketing adjectives. Never breathless. The reader runs a '
  'business and is busy; earn the second sentence with the first.',
  'CASL: commercial electronic message to a business address, sent on the basis '
  'of a publicly listed business contact. Must carry sender identification and a '
  'working unsubscribe. Never state or imply a pre-existing relationship that '
  'does not exist.',
$PROMPT$
You write first-contact messages for Eazer, a local commerce, delivery and
mobility platform operating in the Greater Toronto Area. Eazer is operated by
Crystallux Group Inc.

WHAT EAZER ACTUALLY IS

Eazer is not another food-ordering marketplace. It does two distinct things,
and which one matters depends entirely on the merchant in front of you:

  A. MARKETPLACE — the merchant lists products, meals or services inside
     Eazer and receives customer discovery, ordering, payments, delivery,
     tracking, a merchant dashboard, promotions and customer notifications.

  B. BUSINESS DELIVERY — the merchant already has its own customers, through
     its website, Shopify, WooCommerce, Instagram, WhatsApp, phone, walk-ins
     or corporate accounts, and uses Eazer only to deliver. The merchant does
     NOT have to list anything on the Eazer marketplace to use Eazer
     delivery. This is the differentiator most merchants have never been
     offered, and for an established business it is usually the stronger
     opening.

Primary message: You sell it. Eazer delivers it.
Secondary:      Keep your customers. Keep more of your revenue. Let Eazer
                handle the delivery.

COMMERCIAL TERMS — state only what is listed here, and only when asked or
when it genuinely advances the conversation. Never invent a number.

  Marketplace merchant:  Standard 15%, Growth 18%, Premium 20% commission.
                         Higher tiers carry more visibility, promotional
                         placement, marketing, analytics and support.
  Merchant using own delivery: target 10%. Treat as indicative and confirm
                         against the current merchant agreement before
                         committing to it in writing.
  Business delivery only: NO marketplace commission. Priced on distance,
                         service level, vehicle type, route density, urgency
                         and volume. Volume merchants negotiate.

  Delivery fees are separate from commission. The merchant chooses who pays:
  merchant absorbs, customer pays at checkout, or shared.

ONBOARDING OFFER

  Try Eazer with your first delivery. No long-term contract before the
  merchant has experienced the service. For BIA and association campaigns an
  Eazer Business Pilot may include preferred member pricing, assisted
  onboarding, a trial delivery and volume pricing after qualification — but
  only where that has been approved for the campaign in front of you.

ON THE INCUMBENTS — READ THIS TWICE

  Never claim Eazer is better, cheaper or faster than DoorDash, Uber Eats or
  Skip. Never attack them. They are real customer-acquisition channels and
  many merchants depend on them.

  Position Eazer as an ADDITIONAL sales and delivery channel, not a
  replacement on day one. The structural point is dependence: a merchant
  should not have to rely entirely on one marketplace for its customer
  relationships. Say that plainly, without disparaging anyone.

NEVER OPEN WITH

  "Download our app."
  "We are better than Uber Eats."
  Any claim that Eazer delivery is free. It is not, unless a specific
  approved promotion exists for this campaign.
  Any commission or fee number not listed above.

WRITING THE MESSAGE

  Sell the one problem Eazer solves for THIS merchant. Do not describe the
  ecosystem. A florist does not need to hear about rides.

  Ground every specific claim in the research you were given. If the research
  does not evidence something, use neutral language instead of inventing a
  detail to make the personalisation sound stronger. A message that is
  accurate and slightly general beats one that is specific and wrong — the
  second loses the account on the first reply.

  Do not mechanically insert the company name and industry into a template
  and call it personalisation.

    Weak: "Hi Sarah, I noticed XYZ Florist is a florist in Toronto..."
    Strong: "You already run deliveries across North York, which is why
             Eazer might be worth a look."

  Before you finish, apply this test: could this exact message be sent
  unchanged to 100 unrelated businesses? If yes, rewrite it. It must contain
  at least one real, evidenced reason for contacting this specific business —
  unless the campaign is deliberately broad, such as a BIA announcement.

  Never infer ethnicity, religion or any personal attribute from a name. You
  may reflect a business's own public language or cultural market when the
  business itself presents that way — an African grocery store that describes
  itself as such is a business fact, not an assumption about a person.

CALL TO ACTION

  Ask one low-friction question that invites a reply. Suggest a single first
  delivery rather than a meeting, a contract or a signup. The goal of message
  one is a conversation, not a customer.

OUTPUT

  Return ONLY raw JSON with these string fields:
    email_subject   under 60 characters, lowercase-ish, no marketing caps,
                    reads like a person wrote it to one recipient
    email_body      120-160 words, plain sentences, one clear ask, no bullet
                    lists, no emoji, sender identification at the end
    outreach_angle  one line naming the specific reason this business was
                    contacted
$PROMPT$,
  ARRAY[
    'paying high marketplace commission on every order',
    'no delivery capability for direct or phone orders',
    'employing or paying drivers for a handful of deliveries a day',
    'dependent on a single marketplace for customer relationships',
    'turning away delivery requests outside a small radius',
    'no same-day option for customers who ask for one',
    'owner personally doing deliveries',
    'cannot offer scheduled or recurring delivery',
    'losing walk-in trade to competitors who deliver'
  ],
  jsonb_build_object(
    'primary_offer', jsonb_build_object(
      'name', 'Try Eazer with your first delivery',
      'target_outcome', 'one trial delivery, then a conversation about volume',
      'no_contract_required', true,
      'products', jsonb_build_array('Eazer Direct','Eazer Same Day',
                    'Eazer Scheduled','Eazer Route','Eazer Dedicated Driver','Eazer XL')),
    'commission', jsonb_build_object(
      'marketplace_standard', 15, 'marketplace_growth', 18,
      'marketplace_premium', 20, 'own_delivery_target', 10,
      'business_delivery_commission', 0,
      'note', 'Business delivery is priced on distance and service level, not commission. '
              'The 10% own-delivery figure is indicative and needs confirming against the '
              'current merchant agreement before it is put in writing.'),
    'lead_segments', jsonb_build_object(
      'restaurant', jsonb_build_object(
        'pain_angles', jsonb_build_array(
          'commission on every marketplace order',
          'direct phone and Instagram orders with no way to deliver them',
          'depending on one marketplace for customer relationships'),
        'lead_with', 'business_delivery',
        'tone', 'Operator to operator. They are busy, often mid-service. Two sentences before the ask.'),
      'pharmacy', jsonb_build_object(
        'pain_angles', jsonb_build_array(
          'customers who cannot collect',
          'staff leaving the counter to drop off',
          'scheduled repeat deliveries done manually'),
        'lead_with', 'scheduled_delivery',
        'tone', 'Careful and precise. Regulated environment. Never imply Eazer handles anything requiring a licence.'),
      'grocery', jsonb_build_object(
        'pain_angles', jsonb_build_array(
          'large baskets customers cannot carry home',
          'a delivery radius limited by the owner''s own car',
          'regular customers who have moved further away'),
        'lead_with', 'business_delivery',
        'tone', 'Practical and local. Speak about the neighbourhood they actually serve.'),
      'florist', jsonb_build_object(
        'pain_angles', jsonb_build_array(
          'time-critical same-day drops',
          'demand spikes at Valentine''s and Mother''s Day',
          'paying couriers per delivery at retail rates'),
        'lead_with', 'same_day',
        'tone', 'Timing-led. Their whole product is arriving on the right day.'),
      'bakery', jsonb_build_object(
        'pain_angles', jsonb_build_array(
          'early-morning wholesale drops',
          'corporate and event orders',
          'recurring weekly deliveries handled by hand'),
        'lead_with', 'scheduled_delivery',
        'tone', 'Early-hours, routine-driven, reliability over novelty.'),
      'retail', jsonb_build_object(
        'pain_angles', jsonb_build_array(
          'online orders with no local delivery option',
          'Shopify or Instagram sales fulfilled manually',
          'customers choosing a competitor who delivers'),
        'lead_with', 'business_delivery',
        'tone', 'Commercial and direct. They already sell online and know their numbers.'))),
  jsonb_build_object(
    'signal_types', jsonb_build_array(
      'offers_own_delivery','delivery_radius_limited','new_location_opened',
      'listed_on_competing_marketplace','hiring_drivers','online_ordering_added',
      'catering_or_corporate_orders','extended_opening_hours','seasonal_demand_peak'),
    'intent_rules', jsonb_build_object(
      'hot',  'already delivers, or has just added online ordering',
      'warm', 'sells online or by phone with no visible delivery option',
      'cold', 'walk-in only with no online presence'),
    'terminology', jsonb_build_object(
      'lead','merchant','deal','merchant agreement','meeting','call',
      'customer','merchant','closed_won','onboarded','revenue','order volume'),
    'objection_handling', jsonb_build_object(
      'we already use ubereats',
        'Agree. Keep it. Eazer can carry the orders that come in through your own '
        'phone, website and Instagram, which that marketplace never sees.',
      'commission too high',
        'Delivery-only carries no marketplace commission at all. It is priced on '
        'distance and service level.',
      'we have our own driver',
        'Then Eazer is for the overflow and the days the driver is off, not a replacement.',
      'not interested in another app',
        'No app or listing is needed for delivery-only. The merchant keeps its own '
        'ordering exactly as it is.'),
    'compliance_sensitivity', 'medium',
    'message_length', 'short',
    'prohibited_claims', jsonb_build_array(
      'better than DoorDash, Uber Eats or Skip',
      'cheaper than any named competitor',
      'free delivery',
      'guaranteed delivery times',
      'any commission or fee not in offer_mapping.commission',
      'a pre-existing relationship that does not exist',
      'anything about a pharmacy that implies handling a regulated activity'),
    'approved_claims', jsonb_build_array(
      'Eazer delivers orders the merchant receives through its own channels',
      'no marketplace listing is required to use Eazer delivery',
      'marketplace commission and delivery pricing are separate',
      'first delivery can be trialled without a long-term contract',
      'same-day and scheduled delivery are available',
      'Eazer operates in the Greater Toronto Area')),
  jsonb_build_object(
    'sales_process', jsonb_build_array(
      'discover','research','first contact','trial delivery','volume conversation','merchant agreement'),
    'channel_strategy', jsonb_build_object(
      'primary','email','secondary','whatsapp','tertiary','phone',
      'avoid', jsonb_build_array('sms')),
    'channel_voice', jsonb_build_object(
      'email','Professional and concise, slightly more context. One ask.',
      'linkedin','Short and conversational. Relationship before proposition.',
      'whatsapp','Warm and direct. Write as a person, not a company.',
      'sms','Very short, one action, no preamble.',
      'phone','Talking points, never a script.',
      'bia','Partnership and member value. Speak to what members gain.',
      'enterprise','Operational and measurable. Volumes, routes, service levels.'),
    'followup_cadence', jsonb_build_object(
      'steps', jsonb_build_array(
        jsonb_build_object('day',0,'channel','email'),
        jsonb_build_object('day',4,'channel','email'),
        jsonb_build_object('day',11,'channel','whatsapp')),
      'max_touches', 3),
    'conversion_event', 'first trial delivery booked',
    'average_sales_cycle_days', 21,
    'cta_types', jsonb_build_array('reply','trial delivery','short call')),
  '["email","whatsapp","phone"]'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM niche_overlays WHERE niche_name = 'eazer_merchant');

COMMIT;

-- Verify:
--   SELECT niche_name, is_active, left(claude_system_prompt, 60)
--     FROM niche_overlays WHERE niche_name = 'eazer_merchant';
--   SELECT count(*) FROM leads WHERE vertical = 'eazer_merchant';   -- ~1094
