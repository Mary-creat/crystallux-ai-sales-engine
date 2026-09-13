-- Connect the persona layer to the work it was built for.
--
-- THREE THINGS WERE BUILT AND NEVER WIRED TOGETHER
--
-- 1. avatars holds seven personas with personality_profile (tone, formality,
--    pace, humour, archetype). The docs say that profile is "consumed by the
--    script-generator's Claude prompt" -- and it is, for video. Email
--    outreach has never read it. clx-outreach-generation-v2 contains zero
--    references to avatars, personality_profile, preferred_persona_id or
--    agent_personalities. The layer that decides HOW something sounds was
--    never consulted when writing a message.
--
-- 2. EAZA is documented as "Eazer's 24/7 public face" -- awareness,
--    promotions, driver recruitment, merchant management. Its
--    personality_profile, branding and compliance_rules are all EMPTY.
--    Eazer's own voice was a blank row.
--
-- 3. maxi_industries.niche_overlay_id exists to join MAXI's 22-industry
--    catalogue to the 8 configured verticals. NULL on every row.
--
-- WHAT BELONGS WHERE, now that it is written down:
--
--   niche_overlays  WHAT we say   offer, segments, claims, pain signals
--   avatars         HOW it sounds tone, formality, archetype
--   clients         WHICH persona speaks for this tenant
--
-- MAXI is not part of this. Per docs/avatars/PLATFORM_ARCHITECTURE.md it is
-- the smb_growth avatar carrying Crystallux's own marketing copy across 22
-- industries. It markets Crystallux; it does not write Eazer's outreach.
-- Conflating the two is exactly the mismatch this migration exists to stop.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. EAZA gets a voice
-- ---------------------------------------------------------------------------

UPDATE avatars SET
  personality_profile = jsonb_build_object(
    'archetype',   'the operator who also runs deliveries',
    'tone',        'direct, local, unhurried',
    'formality',   'business casual - first names, no honorifics, no jargon',
    'pace',        'short sentences; one idea per sentence',
    'humour',      'none in first contact; warmth instead of wit',
    'person',      'first person singular. A person writing, not a company broadcasting.',
    'avoid', jsonb_build_array(
      'marketing adjectives (seamless, robust, cutting-edge, revolutionary)',
      'exclamation marks',
      'stacked value propositions',
      'any sentence that could open a mailshot',
      'the word solution'),
    'signature_move',
      'name the one thing this business already does that makes Eazer relevant, '
      'then ask a single question'),
  branding = jsonb_build_object(
    'primary_message',   'You sell it. Eazer delivers it.',
    'secondary_message', 'Keep your customers. Keep more of your revenue.',
    'operator',          'Crystallux Group Inc.',
    'market',            'Greater Toronto Area'),
  compliance_rules = jsonb_build_object(
    'regulatory_framework', jsonb_build_array('CASL', 'PIPEDA',
                                              'provincial_consumer_protection'),
    'must_carry', jsonb_build_array('sender identification', 'working unsubscribe'),
    'never', jsonb_build_array(
      'claim or imply an existing relationship',
      'compare Eazer unfavourably or favourably to a named competitor',
      'state a delivery time as guaranteed',
      'describe delivery as free',
      'infer ethnicity, religion or any personal attribute from a name'))
WHERE avatar_name = 'EAZA';

-- ---------------------------------------------------------------------------
-- 2. Eazer's tenants speak with EAZA's voice
-- ---------------------------------------------------------------------------

UPDATE clients SET preferred_persona_id = 'EAZA'
 WHERE client_name LIKE 'Eazer%' AND preferred_persona_id IS NULL;

-- ---------------------------------------------------------------------------
-- 3. MAXI's catalogue joined to the verticals that actually exist
--
-- Only where the match is unambiguous. MAXI lists 22 industries; 8 verticals
-- are configured. Three slugs match exactly and two are plain aliases. The
-- remaining 17 stay NULL, which is the honest state: marketed but not
-- operable, and get_vertical_context already returns vertical_not_configured
-- for them rather than pretending otherwise.
-- ---------------------------------------------------------------------------

UPDATE maxi_industries m SET niche_overlay_id = n.id
  FROM niche_overlays n
 WHERE m.niche_overlay_id IS NULL
   AND n.niche_name = CASE m.industry_slug
         WHEN 'construction' THEN 'construction'
         WHEN 'dental'       THEN 'dental'
         WHEN 'real_estate'  THEN 'real_estate'
         WHEN 'cleaning'     THEN 'cleaning_services'
         WHEN 'lawyers'      THEN 'legal'
       END;

COMMIT;

-- Verify:
--   SELECT avatar_name, personality_profile->>'archetype'
--     FROM avatars WHERE avatar_name = 'EAZA';
--   SELECT client_name, preferred_persona_id FROM clients WHERE client_name LIKE 'Eazer%';
--   SELECT count(*) FROM maxi_industries WHERE niche_overlay_id IS NOT NULL;  -- 5
