-- ══════════════════════════════════════════════════════════════════
-- Multi-avatar broadcasting platform — Tranche 1 schema
-- ══════════════════════════════════════════════════════════════════
-- Spec: docs/avatars/AUDIT_REPORT.md + docs/avatars/EXTENSION_PLAN.md.
--
-- This migration adds the avatar registry + supporting tables that
-- the existing single-avatar video / content / agent pipeline plugs
-- into. The existing pipeline is NOT rewritten — workflows continue
-- to use the hard-coded vertical→persona lookup as a fallback when
-- avatar_id is null. Once each workflow is extended to read avatar
-- config from `avatars`, behaviour flips per row.
--
-- Tables added in this migration:
--   1. avatars                       — the 7-avatar registry
--   2. avatar_knowledge_topics       — avatar ↔ content_topics join
--   3. avatar_content_library        — avatar ↔ content_videos join
--   4. avatar_streaming_sessions     — live-stream session log (LUXI/EAZA)
--   5. avatar_comment_responses      — per-platform comment moderation log
--
-- LUXI-specific (live commerce, no live-streaming infrastructure in
-- this commit — just the bidding state machine that can run against
-- any video surface, batch or live):
--   6. bidder_trust_scores           — anti-fraud / per-bidder trust state
--   7. auctions                      — live auction lifecycle
--   8. auction_bids                  — every bid with outbid/won/runner-up state
--   9. auction_payment_holds         — Stripe PaymentIntent authorization holds
--
-- MAXI-specific (SMB growth, multi-industry):
--   10. maxi_industries              — supported industry taxonomy (20+)
--   11. maxi_industry_value_props    — value-prop bullets per industry
--
-- Extensions to existing tables (additive, nullable, indexed):
--   - content_topics.avatar_id        FK to avatars.id ON DELETE SET NULL
--   - content_videos.avatar_id        FK to avatars.id ON DELETE SET NULL
--   - video_renders.avatar_id         FK to avatars.id ON DELETE SET NULL
--   - agent_personalities.avatar_id   FK to avatars.id ON DELETE SET NULL
--
-- Avatars seeded:
--   3 ready (AVA, LUXI, MAXI) with full personality / schedule / branding
--   4 placeholder (LUMI, LUMA, LETY, EAZA) — name + vertical only,
--   active=false so the registry is complete and future tranches
--   fill in details rather than insert new rows.
--
-- Additive only. Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. avatars — the registry
-- ─────────────────────────────────────────────────────────────────
-- Crystallux runs N brand voices in parallel (each addressing a
-- different vertical) from the same parent platform. This inverts
-- the older "tenant picks one persona" model; the avatar layer
-- supersedes the hard-coded vertical→persona lookup used by
-- clx-video-script-generator-v1 and friends.
--
-- All external-service IDs (HeyGen, ElevenLabs) are nullable —
-- workflows fall back to the vertical defaults when an avatar's
-- IDs are not yet populated. This lets us ship the registry and
-- routing layer without external accounts being live yet.
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS avatars (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  avatar_name              text UNIQUE NOT NULL,           -- 'AVA' | 'LUXI' | 'MAXI' | 'LUMI' | 'LUMA' | 'LETY' | 'EAZA'
  business_vertical        text NOT NULL,                  -- 'insurance' | 'live_commerce' | 'smb_growth' | 'wellness' | 'entertainment' | 'education' | 'logistics'
  display_name             text NOT NULL,                  -- 'AVA — Insurance Growth' (human-readable)
  tagline                  text,                           -- short marketing line
  catchphrase              text,                           -- signature line per spec
  -- External-service IDs (nullable until Mary signs up for HeyGen + ElevenLabs)
  heygen_avatar_id         text,
  heygen_avatar_id_alt     text,                           -- secondary HeyGen avatar for A/B
  elevenlabs_voice_id      text,
  elevenlabs_voice_id_alt  text,
  -- Personality + visual profile (JSON for flexibility while we iterate)
  personality_profile      jsonb NOT NULL DEFAULT '{}'::jsonb,
  visual_profile           jsonb NOT NULL DEFAULT '{}'::jsonb,
  branding                 jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- Operating schedule (broadcast windows, timezone, days-of-week)
  content_schedule         jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- Per-avatar guardrails (FSRA / wellness disclaimers / consumer-protection / etc.)
  compliance_rules         jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- Default channel routing for outbound (whatsapp | sms | email | voice)
  default_outbound_channel text DEFAULT 'whatsapp',
  -- Lifecycle
  active                   boolean NOT NULL DEFAULT false, -- dormant by default per CLAUDE.md
  launched_at              timestamptz,                    -- when first activated
  archived_at              timestamptz,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS av_active_idx     ON avatars (active);
  CREATE INDEX IF NOT EXISTS av_vertical_idx   ON avatars (business_vertical);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE avatars
    ADD CONSTRAINT av_vertical_check
    CHECK (business_vertical IN (
      'insurance','live_commerce','smb_growth',
      'wellness','entertainment','education','logistics'
    ));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE avatars
    ADD CONSTRAINT av_channel_check
    CHECK (default_outbound_channel IN (
      'whatsapp','sms','email','voice','none'
    ));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 2. avatar_knowledge_topics — which topics belong to which avatar
-- ─────────────────────────────────────────────────────────────────
-- Replaces the spec's avatars.knowledge_base_ids text[] with a
-- normalized join. Lets us soft-delete topics without breaking
-- avatars, and lets us weight which topics each avatar prefers.
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS avatar_knowledge_topics (
  avatar_id        uuid NOT NULL REFERENCES avatars(id) ON DELETE CASCADE,
  content_topic_id uuid NOT NULL REFERENCES content_topics(id) ON DELETE CASCADE,
  weight           integer NOT NULL DEFAULT 50,           -- 0-100, higher = topic shown more often
  added_at         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (avatar_id, content_topic_id)
);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS akt_avatar_idx ON avatar_knowledge_topics (avatar_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 3. avatar_content_library — content_videos owned by each avatar
-- ─────────────────────────────────────────────────────────────────
-- A content_video row already exists in the system (clx-content-
-- script-writer-v1 inserts them). This table tags each video with
-- the avatar that rendered it + tracks publishing intent.
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS avatar_content_library (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  avatar_id        uuid NOT NULL REFERENCES avatars(id) ON DELETE CASCADE,
  content_video_id uuid REFERENCES content_videos(id) ON DELETE SET NULL,
  status           text NOT NULL DEFAULT 'queued',         -- queued | rendering | ready | published | archived
  intended_platforms text[] DEFAULT ARRAY[]::text[],       -- ['tiktok','instagram','youtube',...]
  scheduled_for    timestamptz,
  published_at     timestamptz,
  notes            text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS acl_avatar_idx   ON avatar_content_library (avatar_id);
  CREATE INDEX IF NOT EXISTS acl_status_idx   ON avatar_content_library (status);
  CREATE INDEX IF NOT EXISTS acl_schedule_idx ON avatar_content_library (scheduled_for);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE avatar_content_library
    ADD CONSTRAINT acl_status_check
    CHECK (status IN ('queued','rendering','ready','published','archived','failed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 4. avatar_streaming_sessions — live broadcast lifecycle log
-- ─────────────────────────────────────────────────────────────────
-- The actual live streaming INFRASTRUCTURE (HeyGen Interactive,
-- Restream.io, multi-platform fan-out) is its own track —
-- see docs/avatars/EXTENSION_PLAN.md Tranche 5 / pending RFC. This
-- table is the persistence layer for whichever runtime ends up
-- driving the broadcasts; it does not commit us to one architecture.
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS avatar_streaming_sessions (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  avatar_id            uuid NOT NULL REFERENCES avatars(id) ON DELETE CASCADE,
  session_status       text NOT NULL DEFAULT 'scheduled',  -- scheduled | live | ended | failed | cancelled
  scheduled_start_at   timestamptz NOT NULL,
  actual_start_at      timestamptz,
  actual_end_at        timestamptz,
  -- Distribution
  platforms_targeted   text[] DEFAULT ARRAY[]::text[],     -- ['tiktok_live','facebook_live','youtube_live','instagram_live']
  restream_session_id  text,                               -- Restream.io session reference
  heygen_session_id    text,                               -- HeyGen Interactive session reference
  -- Telemetry summary
  peak_concurrent      integer DEFAULT 0,
  total_unique_viewers integer DEFAULT 0,
  comments_received    integer DEFAULT 0,
  bids_received        integer DEFAULT 0,                  -- LUXI only
  -- Notes + error capture
  failure_reason       text,
  notes                text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS ass_avatar_idx ON avatar_streaming_sessions (avatar_id);
  CREATE INDEX IF NOT EXISTS ass_status_idx ON avatar_streaming_sessions (session_status);
  CREATE INDEX IF NOT EXISTS ass_scheduled_idx ON avatar_streaming_sessions (scheduled_start_at);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE avatar_streaming_sessions
    ADD CONSTRAINT ass_status_check
    CHECK (session_status IN ('scheduled','live','ended','failed','cancelled'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 5. avatar_comment_responses — moderation log across platforms
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS avatar_comment_responses (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  avatar_id             uuid NOT NULL REFERENCES avatars(id) ON DELETE CASCADE,
  streaming_session_id  uuid REFERENCES avatar_streaming_sessions(id) ON DELETE SET NULL,
  platform              text NOT NULL,                    -- 'tiktok' | 'facebook' | 'instagram' | 'youtube' | 'twitter'
  inbound_comment_id    text,                             -- platform-side ID
  inbound_user_handle   text,
  inbound_text          text NOT NULL,
  detected_intent       text,                             -- 'bid' | 'question' | 'compliment' | 'complaint' | 'spam' | 'other'
  response_text         text,
  response_status       text NOT NULL DEFAULT 'pending',  -- pending | sent | suppressed | escalated
  responded_at          timestamptz,
  responder             text DEFAULT 'avatar_auto',       -- 'avatar_auto' | 'human' | 'suppressed_by_moderation'
  created_at            timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS acr_avatar_idx       ON avatar_comment_responses (avatar_id);
  CREATE INDEX IF NOT EXISTS acr_session_idx      ON avatar_comment_responses (streaming_session_id);
  CREATE INDEX IF NOT EXISTS acr_status_idx       ON avatar_comment_responses (response_status);
  CREATE INDEX IF NOT EXISTS acr_platform_idx     ON avatar_comment_responses (platform);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE avatar_comment_responses
    ADD CONSTRAINT acr_status_check
    CHECK (response_status IN ('pending','sent','suppressed','escalated','failed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- LUXI live-commerce: bidding + anti-fraud
-- ─────────────────────────────────────────────────────────────────
-- These tables are LUXI-shaped today; the bidder_trust_scores +
-- payment-hold pattern generalises to any avatar that needs
-- payment-bonded actions (e.g. AVA premium quote escrow, MAXI
-- subscription trials with a hold). For now: scoped to auctions.
-- ─────────────────────────────────────────────────────────────────

-- 6. bidder_trust_scores — per-bidder verification + tier
-- 4 tiers per Mary's spec:
--   tier_0 = unverified — view only, cannot bid
--   tier_1 = phone-verified — can bid up to $50
--   tier_2 = phone + social-verified — can bid up to $500
--   tier_3 = phone + social + stripe-authorized — no per-bid cap
CREATE TABLE IF NOT EXISTS bidder_trust_scores (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bidder_identity_hash     text UNIQUE NOT NULL,         -- hash of (platform, platform_user_id); avoid storing raw handle as PK
  display_name             text,                          -- last-known handle, informational only
  platform                 text,                          -- 'tiktok' | 'facebook' | 'instagram' | 'youtube' | 'sms' | 'web'
  -- Verification gates
  phone_verified           boolean NOT NULL DEFAULT false,
  phone_e164               text,
  phone_verified_at        timestamptz,
  social_verified          boolean NOT NULL DEFAULT false,
  social_verified_at       timestamptz,
  social_signals           jsonb DEFAULT '{}'::jsonb,    -- {account_age_days, followers, prior_purchases, ...}
  stripe_customer_id       text,
  stripe_card_authorized   boolean NOT NULL DEFAULT false,
  stripe_authorized_at     timestamptz,
  -- Derived tier
  trust_tier               text NOT NULL DEFAULT 'tier_0',
  -- Per-bid limits (denormalized from tier for fast read; updated by trigger or app logic)
  max_bid_cents            integer DEFAULT 0,
  -- Fraud history
  forfeited_count          integer NOT NULL DEFAULT 0,
  chargebacks_count        integer NOT NULL DEFAULT 0,
  banned_at                timestamptz,
  ban_reason               text,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS bts_tier_idx          ON bidder_trust_scores (trust_tier);
  CREATE INDEX IF NOT EXISTS bts_phone_idx         ON bidder_trust_scores (phone_e164);
  CREATE INDEX IF NOT EXISTS bts_stripe_idx        ON bidder_trust_scores (stripe_customer_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE bidder_trust_scores
    ADD CONSTRAINT bts_tier_check
    CHECK (trust_tier IN ('tier_0','tier_1','tier_2','tier_3','banned'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 7. auctions — live auction lifecycle
CREATE TABLE IF NOT EXISTS auctions (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  avatar_id                uuid NOT NULL REFERENCES avatars(id) ON DELETE RESTRICT,
  streaming_session_id     uuid REFERENCES avatar_streaming_sessions(id) ON DELETE SET NULL,
  -- Item
  item_title               text NOT NULL,
  item_description         text,
  item_category            text,
  item_photos              jsonb DEFAULT '[]'::jsonb,      -- array of image URLs
  reserve_price_cents      integer NOT NULL DEFAULT 0,    -- 0 = no reserve
  -- Auction state
  status                   text NOT NULL DEFAULT 'scheduled',  -- scheduled | open | extended | closed_sold | closed_unsold | cancelled
  scheduled_open_at        timestamptz NOT NULL,
  actual_open_at           timestamptz,
  scheduled_close_at       timestamptz NOT NULL,
  actual_close_at          timestamptz,
  -- Anti-sniping: extend by `anti_snipe_extend_seconds` if bid in last `anti_snipe_window_seconds`
  anti_snipe_window_seconds  integer NOT NULL DEFAULT 30,
  anti_snipe_extend_seconds  integer NOT NULL DEFAULT 30,
  anti_snipe_max_extensions  integer NOT NULL DEFAULT 10,
  extensions_used          integer NOT NULL DEFAULT 0,
  -- Pricing
  current_high_bid_cents   integer NOT NULL DEFAULT 0,
  current_high_bid_id      uuid,                          -- soft-FK to auction_bids.id (recursive, fill after insert)
  min_increment_cents      integer NOT NULL DEFAULT 100,  -- $1 minimum bump
  winning_bid_id           uuid,
  -- Seller (optional — for Phase-2 consignment; null for direct-sale items)
  seller_id                uuid,                          -- soft-FK; consignment table arrives in LUXI Phase 2
  -- Audit
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS auc_status_idx     ON auctions (status);
  CREATE INDEX IF NOT EXISTS auc_avatar_idx     ON auctions (avatar_id);
  CREATE INDEX IF NOT EXISTS auc_open_idx       ON auctions (scheduled_open_at);
  CREATE INDEX IF NOT EXISTS auc_close_idx      ON auctions (scheduled_close_at);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE auctions
    ADD CONSTRAINT auc_status_check
    CHECK (status IN ('scheduled','open','extended','closed_sold','closed_unsold','cancelled','disputed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 8. auction_bids — every bid with state machine
CREATE TABLE IF NOT EXISTS auction_bids (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id               uuid NOT NULL REFERENCES auctions(id) ON DELETE CASCADE,
  bidder_trust_id          uuid NOT NULL REFERENCES bidder_trust_scores(id) ON DELETE RESTRICT,
  amount_cents             integer NOT NULL,
  -- Bid intent source (where the bid came from)
  source_platform          text NOT NULL,                 -- 'tiktok_comment' | 'facebook_comment' | 'instagram_dm' | 'web_form' | 'sms' | 'whatsapp'
  source_comment_id        uuid REFERENCES avatar_comment_responses(id) ON DELETE SET NULL,
  raw_input                text,                          -- the original "BID 50" text or equivalent
  -- State machine
  status                   text NOT NULL DEFAULT 'active', -- pending_verification | active | outbid | won | runner_up | forfeited | rejected
  rejected_reason          text,
  placed_at                timestamptz NOT NULL DEFAULT now(),
  outbid_at                timestamptz,
  won_at                   timestamptz,
  forfeited_at             timestamptz
);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS ab_auction_idx       ON auction_bids (auction_id);
  CREATE INDEX IF NOT EXISTS ab_bidder_idx        ON auction_bids (bidder_trust_id);
  CREATE INDEX IF NOT EXISTS ab_status_idx        ON auction_bids (status);
  CREATE INDEX IF NOT EXISTS ab_auction_amount    ON auction_bids (auction_id, amount_cents DESC);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE auction_bids
    ADD CONSTRAINT ab_status_check
    CHECK (status IN ('pending_verification','active','outbid','won','runner_up','forfeited','rejected'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 9. auction_payment_holds — Stripe PaymentIntent authorizations
-- One row per bid that triggered a hold; charges happen on `won`,
-- holds released on `forfeited` or `outbid` (after grace period).
CREATE TABLE IF NOT EXISTS auction_payment_holds (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bid_id                   uuid NOT NULL REFERENCES auction_bids(id) ON DELETE CASCADE,
  auction_id               uuid NOT NULL REFERENCES auctions(id) ON DELETE CASCADE,
  bidder_trust_id          uuid NOT NULL REFERENCES bidder_trust_scores(id) ON DELETE RESTRICT,
  stripe_payment_intent_id text NOT NULL,
  amount_cents             integer NOT NULL,
  status                   text NOT NULL DEFAULT 'authorized',   -- authorized | captured | released | failed | cancelled
  authorized_at            timestamptz NOT NULL DEFAULT now(),
  captured_at              timestamptz,
  released_at              timestamptz,
  failure_reason           text,
  notes                    text
);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS aph_bid_idx           ON auction_payment_holds (bid_id);
  CREATE INDEX IF NOT EXISTS aph_auction_idx       ON auction_payment_holds (auction_id);
  CREATE INDEX IF NOT EXISTS aph_status_idx        ON auction_payment_holds (status);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE auction_payment_holds
    ADD CONSTRAINT aph_status_check
    CHECK (status IN ('authorized','captured','released','failed','cancelled'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- MAXI multi-industry: 20+ SMB verticals
-- ─────────────────────────────────────────────────────────────────

-- 10. maxi_industries — the supported-industry taxonomy
CREATE TABLE IF NOT EXISTS maxi_industries (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  industry_slug         text UNIQUE NOT NULL,             -- 'construction' | 'dental' | 'beauty' | ...
  industry_name         text NOT NULL,                    -- 'Construction & Trades' (display)
  category              text NOT NULL,                    -- 'home_services' | 'health_beauty' | 'professional' | 'food' | 'other'
  description           text,
  emoji                 text,                              -- '🛠️' (visual nav)
  active                boolean NOT NULL DEFAULT true,    -- 'your industry? reach out' is a special pseudo-row
  sort_order            integer NOT NULL DEFAULT 100,
  created_at            timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS mi_category_idx ON maxi_industries (category, active);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 11. maxi_industry_value_props — per-industry value-prop bullets
-- Drives the per-industry pages on MAXI's landing surface + the
-- content-script-writer's per-industry prompting.
CREATE TABLE IF NOT EXISTS maxi_industry_value_props (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  industry_id           uuid NOT NULL REFERENCES maxi_industries(id) ON DELETE CASCADE,
  capability_slug       text NOT NULL,                    -- 'lead_gen' | 'booking' | 'follow_up' | 'reach_out' | 'ai_employees' | 'content_creation' | 'payment_automation' | 'analytics'
  capability_label      text NOT NULL,
  industry_specific_copy text,                            -- one-paragraph per industry-capability
  sort_order            integer NOT NULL DEFAULT 100,
  active                boolean NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (industry_id, capability_slug)
);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS mivp_industry_idx ON maxi_industry_value_props (industry_id, active);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- Extensions to existing tables — additive avatar_id FKs (nullable)
-- ─────────────────────────────────────────────────────────────────
-- These are additive ONLY. Existing rows stay NULL until the new
-- avatar-aware workflows write to them. The hard-coded vertical
-- defaults in clx-video-script-generator-v1 etc. continue to serve
-- legacy rows.
-- ─────────────────────────────────────────────────────────────────

DO $$ BEGIN
  ALTER TABLE content_topics
    ADD COLUMN IF NOT EXISTS avatar_id uuid REFERENCES avatars(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_column THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE content_videos
    ADD COLUMN IF NOT EXISTS avatar_id uuid REFERENCES avatars(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_column THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE video_renders
    ADD COLUMN IF NOT EXISTS avatar_id uuid REFERENCES avatars(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_column THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE agent_personalities
    ADD COLUMN IF NOT EXISTS avatar_id uuid REFERENCES avatars(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_column THEN NULL; END $$;

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS ct_avatar_idx          ON content_topics (avatar_id);
  CREATE INDEX IF NOT EXISTS cv_avatar_idx          ON content_videos (avatar_id);
  CREATE INDEX IF NOT EXISTS vr_avatar_idx          ON video_renders (avatar_id);
  CREATE INDEX IF NOT EXISTS ap_avatar_idx          ON agent_personalities (avatar_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE avatars                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE avatar_knowledge_topics     ENABLE ROW LEVEL SECURITY;
ALTER TABLE avatar_content_library      ENABLE ROW LEVEL SECURITY;
ALTER TABLE avatar_streaming_sessions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE avatar_comment_responses    ENABLE ROW LEVEL SECURITY;
ALTER TABLE bidder_trust_scores         ENABLE ROW LEVEL SECURITY;
ALTER TABLE auctions                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE auction_bids                ENABLE ROW LEVEL SECURITY;
ALTER TABLE auction_payment_holds       ENABLE ROW LEVEL SECURITY;
ALTER TABLE maxi_industries             ENABLE ROW LEVEL SECURITY;
ALTER TABLE maxi_industry_value_props   ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY av_service_all       ON avatars                   FOR ALL TO service_role USING (true) WITH CHECK (true);
  CREATE POLICY akt_service_all      ON avatar_knowledge_topics   FOR ALL TO service_role USING (true) WITH CHECK (true);
  CREATE POLICY acl_service_all      ON avatar_content_library    FOR ALL TO service_role USING (true) WITH CHECK (true);
  CREATE POLICY ass_service_all      ON avatar_streaming_sessions FOR ALL TO service_role USING (true) WITH CHECK (true);
  CREATE POLICY acr_service_all      ON avatar_comment_responses  FOR ALL TO service_role USING (true) WITH CHECK (true);
  CREATE POLICY bts_service_all      ON bidder_trust_scores       FOR ALL TO service_role USING (true) WITH CHECK (true);
  CREATE POLICY auc_service_all      ON auctions                  FOR ALL TO service_role USING (true) WITH CHECK (true);
  CREATE POLICY ab_service_all       ON auction_bids              FOR ALL TO service_role USING (true) WITH CHECK (true);
  CREATE POLICY aph_service_all      ON auction_payment_holds     FOR ALL TO service_role USING (true) WITH CHECK (true);
  CREATE POLICY mi_service_all       ON maxi_industries           FOR ALL TO service_role USING (true) WITH CHECK (true);
  CREATE POLICY mivp_service_all     ON maxi_industry_value_props FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- SEED — AVA, LUXI, MAXI (ready) + 4 placeholders
-- ─────────────────────────────────────────────────────────────────
-- All rows ship active=false per CLAUDE.md dormant-by-default.
-- Mary flips active=true per avatar when she's ready to launch.
-- ─────────────────────────────────────────────────────────────────

INSERT INTO avatars (
  avatar_name, business_vertical, display_name, tagline, catchphrase,
  personality_profile, visual_profile, branding, content_schedule,
  compliance_rules, default_outbound_channel, active
) VALUES
-- ─────────── AVA — Insurance Growth ───────────
('AVA', 'insurance',
 'AVA — Insurance Growth',
 'Protecting Canadian families. Growing the MGA without waiting for carriers.',
 'Protecting Canadian families',
 jsonb_build_object(
   'voice_tone',        'warm_authoritative',
   'formality_level',   'business_professional',
   'pace',              'measured',
   'humor',             'gentle',
   'age_band',          '35-42',
   'archetype',         'trusted_advisor'
 ),
 jsonb_build_object(
   'look',              'professional_blazer',
   'environment',       'modern_office_with_books',
   'wardrobe_palette',  ARRAY['navy','cream','charcoal'],
   'lighting',          'soft_natural'
 ),
 jsonb_build_object(
   'primary_color',     '#0f4c81',
   'accent_color',      '#c9a96e',
   'logo_strapline',    'Crystallux Insurance — AVA'
 ),
 jsonb_build_object(
   'timezone',          'America/Toronto',
   'broadcast_windows', jsonb_build_array(
     jsonb_build_object('days', ARRAY['mon','tue','wed','thu','fri'],
                        'start','09:00','end','17:00'),
     jsonb_build_object('days', ARRAY['sat'],'start','10:00','end','14:00')
   ),
   'cadence',           'daily',
   'channels',          ARRAY['linkedin','facebook','instagram','youtube','tiktok']
 ),
 jsonb_build_object(
   'regulatory_framework', ARRAY['FSRA','RIBO','provincial_insurance_acts'],
   'required_disclaimers', ARRAY[
     'Insurance products available through licensed advisors only.',
     'This is general education, not advice. Consult a licensed advisor for your specific needs.'
   ],
   'prohibited_topics', ARRAY[
     'specific_premium_quotes_without_application',
     'guaranteed_acceptance_claims',
     'comparing_carriers_negatively_by_name'
   ],
   'escalate_on',       ARRAY['claim_complaint','suspected_misrepresentation','vulnerable_disclosure']
 ),
 'email',
 false
),

-- ─────────── LUXI — Live Commerce ───────────
('LUXI', 'live_commerce',
 'LUXI — Live Auctions & Commerce',
 'Energetic, fast, fair. Live auctions across socials.',
 'Let''s make a deal!',
 jsonb_build_object(
   'voice_tone',        'energetic_fast_paced',
   'formality_level',   'casual',
   'pace',              'fast',
   'humor',             'playful',
   'age_band',          '28-32',
   'archetype',         'auctioneer_host'
 ),
 jsonb_build_object(
   'look',              'modern_bold_streetwear',
   'environment',       'bright_showroom',
   'wardrobe_palette',  ARRAY['hot_pink','black','white','gold_accents'],
   'lighting',          'high_key_bright'
 ),
 jsonb_build_object(
   'primary_color',     '#e91e63',
   'accent_color',      '#ffd700',
   'logo_strapline',    'LUXI · Live'
 ),
 jsonb_build_object(
   'timezone',          'America/Toronto',
   'broadcast_windows', jsonb_build_array(
     jsonb_build_object('days', ARRAY['mon','tue','wed','thu','fri','sat','sun'],
                        'start','09:00','end','21:00')
   ),
   'cadence',           'live_continuous',
   'channels',          ARRAY['tiktok_live','facebook_live','instagram_live','youtube_live']
 ),
 jsonb_build_object(
   'regulatory_framework', ARRAY['consumer_protection_act','provincial_auction_rules'],
   'required_disclaimers', ARRAY[
     'All bids are binding. Backup bidder cascade applies if winner forfeits.',
     'Refunds per posted return policy. Item descriptions are seller-provided.'
   ],
   'prohibited_topics', ARRAY[
     'guaranteed_outcomes_outside_listed_terms',
     'comparing_items_to_brand_names_without_proof'
   ],
   'escalate_on',       ARRAY['suspected_fraud','chargeback_threat','underage_bidder','intoxicated_bidder']
 ),
 'whatsapp',
 false
),

-- ─────────── MAXI — SMB Growth ───────────
('MAXI', 'smb_growth',
 'MAXI — Small Business Growth OS',
 'Let''s grow your business — across every industry.',
 'Let''s grow your business!',
 jsonb_build_object(
   'voice_tone',        'confident_motivational',
   'formality_level',   'business_casual',
   'pace',              'moderate',
   'humor',             'observational',
   'age_band',          '32-38',
   'archetype',         'entrepreneur_coach'
 ),
 jsonb_build_object(
   'look',              'modern_entrepreneur',
   'environment',       'open_plan_office_with_plants',
   'wardrobe_palette',  ARRAY['emerald','off_white','warm_grey'],
   'lighting',          'natural_with_warm_fill'
 ),
 jsonb_build_object(
   'primary_color',     '#10b981',
   'accent_color',      '#f59e0b',
   'logo_strapline',    'MAXI · Grow'
 ),
 jsonb_build_object(
   'timezone',          'America/Toronto',
   'broadcast_windows', jsonb_build_array(
     jsonb_build_object('days', ARRAY['mon','tue','wed','thu','fri'],
                        'start','09:00','end','17:00')
   ),
   'cadence',           'daily',
   'channels',          ARRAY['linkedin','facebook','instagram','youtube','tiktok']
 ),
 jsonb_build_object(
   'regulatory_framework', ARRAY['CASL','provincial_consumer_protection'],
   'required_disclaimers', ARRAY[
     'Industry examples are illustrative, not guarantees of results.',
     'Pricing varies by industry and feature set.'
   ],
   'prohibited_topics', ARRAY[
     'guaranteed_revenue_claims',
     'replacement_of_licensed_professional_advice'
   ],
   'escalate_on',       ARRAY['regulated_industry_outside_supported_list','enterprise_inquiry']
 ),
 'email',
 false
),

-- ─────────── Placeholders (Tranches 2-4) ───────────
('LUMI', 'wellness',     'LUMI — Wellness & Sleep',     NULL, 'Breathe with me...',         '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'email', false),
('LUMA', 'entertainment','LUMA — Entertainment Stage',  NULL, 'Welcome to Luma Stage!',     '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'email', false),
('LETY', 'education',    'LETY — Education & Tutoring', NULL, 'You got this!',              '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'email', false),
('EAZA', 'logistics',    'EAZA — Eazer Delivery Voice', NULL, 'Eazer delivers!',            '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'email', false)
ON CONFLICT (avatar_name) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- SEED — MAXI's 20+ industries + capability matrix
-- ─────────────────────────────────────────────────────────────────

INSERT INTO maxi_industries (industry_slug, industry_name, category, description, emoji, sort_order) VALUES
('construction',     'Construction & Trades',           'home_services',    'GCs, framers, drywallers, painters — anyone who quotes jobs.', '🛠️', 10),
('dental',           'Dental Practices',                'health_beauty',    'Independent + small-group dental practices.',                   '🦷', 20),
('beauty',           'Beauty & Salon',                  'health_beauty',    'Salons, barbers, brow bars, lash studios.',                     '💇', 30),
('restaurants',      'Restaurants & Cafes',             'food',             'Independent restaurants, cafes, food trucks.',                  '🍽️', 40),
('cleaning',         'Cleaning Services',               'home_services',    'Residential + commercial cleaning crews.',                      '🧹', 50),
('plumbers',         'Plumbing',                        'home_services',    'Independent plumbers + small-team plumbing shops.',             '🚿', 60),
('electricians',     'Electricians',                    'home_services',    'Licensed electricians — residential + light commercial.',       '💡', 70),
('hvac',             'HVAC',                            'home_services',    'Furnace, AC, ventilation — residential focus.',                 '🌡️', 80),
('real_estate',      'Real Estate Agents',              'professional',     'Solo agents + small teams; brokerages adjacent.',               '🏠', 90),
('mortgage',         'Mortgage Brokers',                'professional',     'Independent mortgage brokers + small brokerages.',              '🏦', 100),
('lawyers',          'Solo + Small-Firm Lawyers',       'professional',     'Family law, real-estate, immigration, criminal solo + duo.',    '⚖️', 110),
('accountants',      'Accountants & Bookkeepers',       'professional',     'CPA solo / boutique firms + bookkeeping shops.',                '📊', 120),
('fitness',          'Fitness Studios & Coaches',       'health_beauty',    'Yoga, pilates, CrossFit boxes, personal trainers.',             '💪', 130),
('photographers',    'Photographers',                   'professional',     'Wedding, portrait, brand photographers.',                       '📷', 140),
('coaches',          'Coaches & Consultants',           'professional',     'Business, life, executive coaches; solo consultants.',          '🎯', 150),
('home_services',    'Home Services (general)',         'home_services',    'Handymen, junk removal, lawn care, snow removal.',              '🏡', 160),
('therapists',       'Therapists & Counsellors',        'health_beauty',    'RP, RSW, MFT in private practice.',                             '🧠', 170),
('tutors',           'Tutors & Test Prep',              'professional',     'K-12, IELTS, LSAT, MCAT tutors.',                               '📚', 180),
('daycare',          'Daycare & Early Years',           'health_beauty',    'Licensed home daycares + boutique centres.',                    '🧸', 190),
('pets',             'Pet Services',                    'health_beauty',    'Groomers, walkers, sitters, trainers.',                         '🐾', 200),
('massage',          'Massage Therapy',                 'health_beauty',    'RMT solo + small practices.',                                   '💆', 210),
('your_industry',    'Your industry? Reach out.',       'other',            'If your business isn''t listed, MAXI may still fit — reach out.', '✨', 999)
ON CONFLICT (industry_slug) DO NOTHING;

-- MAXI value-prop matrix (8 capabilities × 21 industries = 168 rows;
-- seeded with the canonical 8 capability columns. Industry-specific
-- copy gets filled in by the content team per industry — for now,
-- rows exist with generic labels so the page renders out of the box.)

DO $$
DECLARE
  ind RECORD;
BEGIN
  FOR ind IN SELECT id, industry_slug FROM maxi_industries WHERE industry_slug != 'your_industry' LOOP
    INSERT INTO maxi_industry_value_props (industry_id, capability_slug, capability_label, sort_order) VALUES
      (ind.id, 'lead_gen',           'Automated lead generation',      10),
      (ind.id, 'booking',            'Booking systems',                20),
      (ind.id, 'follow_up',          'Follow-up automation',           30),
      (ind.id, 'reach_out',          'Customer reach-out',             40),
      (ind.id, 'ai_employees',       'AI employees',                   50),
      (ind.id, 'content_creation',   'Content creation',               60),
      (ind.id, 'payment_automation', 'Payment automation',             70),
      (ind.id, 'analytics',          'Analytics',                      80)
    ON CONFLICT (industry_id, capability_slug) DO NOTHING;
  END LOOP;
END $$;

-- ══════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ══════════════════════════════════════════════════════════════════
-- Rollback drops the new tables + the avatar_id FK additions.
-- Existing data in content_topics / content_videos / video_renders /
-- agent_personalities survives — the avatar_id column just goes away.
--
-- To roll back, execute the block below in a single transaction:
--
-- BEGIN;
--   ALTER TABLE agent_personalities  DROP COLUMN IF EXISTS avatar_id;
--   ALTER TABLE video_renders        DROP COLUMN IF EXISTS avatar_id;
--   ALTER TABLE content_videos       DROP COLUMN IF EXISTS avatar_id;
--   ALTER TABLE content_topics       DROP COLUMN IF EXISTS avatar_id;
--   DROP TABLE IF EXISTS maxi_industry_value_props;
--   DROP TABLE IF EXISTS maxi_industries;
--   DROP TABLE IF EXISTS auction_payment_holds;
--   DROP TABLE IF EXISTS auction_bids;
--   DROP TABLE IF EXISTS auctions;
--   DROP TABLE IF EXISTS bidder_trust_scores;
--   DROP TABLE IF EXISTS avatar_comment_responses;
--   DROP TABLE IF EXISTS avatar_streaming_sessions;
--   DROP TABLE IF EXISTS avatar_content_library;
--   DROP TABLE IF EXISTS avatar_knowledge_topics;
--   DROP TABLE IF EXISTS avatars;
-- COMMIT;
-- ══════════════════════════════════════════════════════════════════
