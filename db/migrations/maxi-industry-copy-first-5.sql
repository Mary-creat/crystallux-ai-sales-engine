-- ══════════════════════════════════════════════════════════════════
-- MAXI industry-specific copy — first 5 industries (T1.8.d)
-- ══════════════════════════════════════════════════════════════════
-- Companion to avatars-platform-schema.sql. The base schema seeded
-- 21 industries × 8 capabilities (160 rows) with generic capability
-- labels and NULL industry_specific_copy. This migration fills in
-- real per-industry copy for the first 5 industries — the spec's
-- "test with first 5 before scaling to 20" recommendation.
--
-- Industries: construction, dental, beauty, restaurants, cleaning.
-- Capabilities (all 8 per industry): lead_gen, booking, follow_up,
-- reach_out, ai_employees, content_creation, payment_automation,
-- analytics.
--
-- 40 UPDATEs total. Pure UPDATE statement — naturally idempotent
-- (re-running writes the same string to the same row). No rollback
-- needed; to revert, set industry_specific_copy = NULL for the
-- affected rows.
--
-- After applying, /pages/avatars/maxi/industry.html?slug=construction
-- (and the other four) renders concrete copy instead of italic
-- placeholders.
--
-- Order: must run AFTER avatars-platform-schema.sql. Independent
-- of avatar-content-seeds-ava.sql.
-- ══════════════════════════════════════════════════════════════════

UPDATE maxi_industry_value_props mivp
SET industry_specific_copy = v.copy
FROM (VALUES
  -- ─── Construction ───
  ('construction', 'lead_gen',           'Inbound site-survey requests routed by postal code; auto-replied within 2 minutes with a calendar link + first-photo intake.'),
  ('construction', 'booking',            'Calendar block per crew per day; lockout when a crew is at-capacity; weather buffer baked in for outdoor work.'),
  ('construction', 'follow_up',          'After a no-decision quote, three automated touches over 14 days: spec clarification, neighbour-comparison example, deposit-waiver offer.'),
  ('construction', 'reach_out',          'Maintenance-season reminders (roofing pre-fall, drainage pre-spring) to the past-job book. Opt-out tracked per address.'),
  ('construction', 'ai_employees',       'AI estimator drafts a line-item quote from photo + scope text; the foreman reviews + sends in under 5 minutes.'),
  ('construction', 'content_creation',   'Weekly before/after reels from your job-site photo dump, captioned with Ontario building-code talking points where relevant.'),
  ('construction', 'payment_automation', 'Deposit on signature, progress payment on inspection, balance on completion — Stripe links, no chase calls.'),
  ('construction', 'analytics',          'Win-rate by lead source + crew utilisation by week; auto-flag jobs where time-on-site exceeds estimate by 20%.'),

  -- ─── Dental ───
  ('dental',       'lead_gen',           'Local-search lead capture with insurance-network pre-filter — only patients in your accepted networks see the booking link.'),
  ('dental',       'booking',            'New-patient slots reserved for high-value exams (cleaning + x-rays + consult); recall slots auto-released 30 days out.'),
  ('dental',       'follow_up',          'After a treatment-plan review, three touches over 21 days addressing the three most common rejection reasons: cost, time, anxiety.'),
  ('dental',       'reach_out',          '6-month recall reminders by SMS + email; missed-recall escalation at month 9; reactivation campaign at month 18.'),
  ('dental',       'ai_employees',       'AI front-desk handles after-hours appointment requests, insurance-coverage questions, and prescription-refill triage.'),
  ('dental',       'content_creation',   'Monthly patient-education shorts on each procedure your practice offers, in a tone that respects Ontario professional-advertising rules.'),
  ('dental',       'payment_automation', 'Estimate at booking, copay collection at check-in, balance-due payment plans via Stripe — never chase a missed cheque.'),
  ('dental',       'analytics',          'Production per chair per hour, recall compliance %, treatment-plan acceptance rate by hygienist.'),

  -- ─── Beauty ───
  ('beauty',       'lead_gen',           'Instagram + TikTok comment-to-DM conversion; service-specific landing pages auto-tailored from the comment intent.'),
  ('beauty',       'booking',            'Online booking with stylist-preference memory, colour-history follow-up prompts, and 24-hour deposit hold for new clients.'),
  ('beauty',       'follow_up',          'After a colour service, automated 6-week maintenance reminder; after a cut, 4-week trim reminder — both bookable in one tap.'),
  ('beauty',       'reach_out',          'Birthday + anniversary perk SMS; lapsed-client reactivation (60 days no-visit) with a personalised stylist greeting.'),
  ('beauty',       'ai_employees',       'AI booking concierge handles consultations, service-explainer questions, and reschedules — frees the front desk for in-salon clients.'),
  ('beauty',       'content_creation',   'Weekly transformation reels from your portfolio, styled per the lash/colour/cut trends your demographic actually searches for.'),
  ('beauty',       'payment_automation', 'Deposit on booking (non-refundable inside 24h), tip integration, packages with auto-renewing pre-paid credits.'),
  ('beauty',       'analytics',          'Stylist rebooking rate, average ticket trend, product-attach rate per service — colour-coded to surface coaching opportunities.'),

  -- ─── Restaurants ───
  ('restaurants',  'lead_gen',           'Maps + delivery-app review-driven traffic captured into a CRM; new-customer first-order discount tracked end-to-end to LTV.'),
  ('restaurants',  'booking',            'Reservation system tuned to your covers + average-turn-time; party-size-aware section assignment; deposits on parties of 6+.'),
  ('restaurants',  'follow_up',          'Day-after-meal review prompt; sentiment-segmented so the team responds to negatives within hours, not days.'),
  ('restaurants',  'reach_out',          'Birthday + special-occasion email/SMS; seasonal menu launch announcements; loyalty-tier reactivation flows.'),
  ('restaurants',  'ai_employees',       'AI host handles after-hours reservations, dietary-restriction confirmations, and standard FAQ — kitchen never sees the noise.'),
  ('restaurants',  'content_creation',   'Daily-specials reels and weekly behind-the-line shorts captioned for the local-foodie hashtags your market actually follows.'),
  ('restaurants',  'payment_automation', 'Pre-pay deposits for prix-fixe nights, QR-code split-bill at the table, automatic gratuity routing per shift roster.'),
  ('restaurants',  'analytics',          'Cover-by-cover labour cost vs revenue, menu-item profitability ranking, no-show rate by booking source.'),

  -- ─── Cleaning ───
  ('cleaning',     'lead_gen',           'Quote-on-the-call: AI scopes the job (sq ft, frequency, pain points) and produces a price range before the call ends.'),
  ('cleaning',     'booking',            'Recurring-booking management; cancellations auto-rebook within 48 hours from the standby crew calendar.'),
  ('cleaning',     'follow_up',          'Post-service satisfaction check at 24 hours; missed-area resolution path; review prompt only after a 5/5 reply.'),
  ('cleaning',     'reach_out',          'Quarterly deep-clean upsell; seasonal-service prompts (gutters, exterior windows); referral incentive at 6-month tenure.'),
  ('cleaning',     'ai_employees',       'AI dispatcher routes the crew when a cancellation hits — minimises drive time and keeps payroll productive.'),
  ('cleaning',     'content_creation',   'Before/after job reels with the day''s chemistry callout; safety-tip carousels per residential vs commercial.'),
  ('cleaning',     'payment_automation', 'Auto-charge on completion via stored card; missed-payment SMS at +24h, then suspend service at +7d.'),
  ('cleaning',     'analytics',          'Hours-per-job vs quoted, churn by service tier, crew utilisation against weather + holiday seasonality.')
) AS v(industry_slug, capability_slug, copy),
  maxi_industries mi
WHERE mi.industry_slug = v.industry_slug
  AND mivp.industry_id = mi.id
  AND mivp.capability_slug = v.capability_slug;

-- ─────────────────────────────────────────────────────────────────
-- Verify
-- ─────────────────────────────────────────────────────────────────
-- After running, this should return 40:
--
--   SELECT count(*) FROM maxi_industry_value_props mivp
--   JOIN maxi_industries mi ON mi.id = mivp.industry_id
--   WHERE mi.industry_slug IN ('construction','dental','beauty','restaurants','cleaning')
--     AND mivp.industry_specific_copy IS NOT NULL;
--
-- And per-industry-detail page at /pages/avatars/maxi/industry.html?slug=construction
-- (and the other four) should show concrete copy instead of italic placeholders.
-- ═══════════════════════════════════════════════════════════════════
