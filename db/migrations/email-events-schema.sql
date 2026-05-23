-- ══════════════════════════════════════════════════════════════════
-- email_events — live Postmark webhook event sink
-- ══════════════════════════════════════════════════════════════════
-- Receives Delivery / Bounce / SpamComplaint / Open / Click /
-- SubscriptionChange events from Postmark via the
-- clx-webhook-postmark-events-v1 workflow. Replaces the best-effort
-- email_log.status scan for spam tracking in the Sentinel Comms tab.
--
-- Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS email_events (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type           text NOT NULL,
  bounce_subtype       text,
  postmark_message_id  text,
  recipient            text,
  from_email           text,
  subject              text,
  tag                  text,
  message_stream       text,
  description          text,
  details              text,
  server_id            text,
  received_at          timestamptz,
  ingested_at          timestamptz DEFAULT now(),
  raw_payload          jsonb,
  metadata             jsonb DEFAULT '{}'::jsonb
);

DO $$ BEGIN
  ALTER TABLE email_events
    ADD CONSTRAINT email_events_type_check
    CHECK (event_type IN (
      'delivery','bounce','spam_complaint','open','click',
      'subscription_change','other'
    ));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Hot-path indexes: most queries are "events in the last N days" sorted
-- newest-first, filtered by type. The two partial indexes accelerate
-- the Sentinel Comms spam + bounce panels specifically.
CREATE INDEX IF NOT EXISTS idx_email_events_recent
  ON email_events(received_at DESC);

CREATE INDEX IF NOT EXISTS idx_email_events_type_recent
  ON email_events(event_type, received_at DESC);

CREATE INDEX IF NOT EXISTS idx_email_events_recipient
  ON email_events(recipient);

CREATE INDEX IF NOT EXISTS idx_email_events_postmark_message_id
  ON email_events(postmark_message_id);

CREATE INDEX IF NOT EXISTS idx_email_events_spam
  ON email_events(received_at DESC)
  WHERE event_type = 'spam_complaint';

CREATE INDEX IF NOT EXISTS idx_email_events_bounce
  ON email_events(received_at DESC)
  WHERE event_type = 'bounce';

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS email_events;
