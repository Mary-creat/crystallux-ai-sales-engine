-- ══════════════════════════════════════════════════════════════════
-- AVA content seeds — insurance education + MGA revenue topics
-- ══════════════════════════════════════════════════════════════════
-- Companion to db/migrations/avatars-platform-schema.sql.
-- Seeds 25 content topics linked to AVA via avatar_knowledge_topics.
-- Topics span the six core insurance product lines, plus advisor
-- recruitment, AdvisorAssist subscription, and the RIBO Study Coach
-- product. Each topic ships status='approved' so the content
-- pipeline can pick them up immediately once activated.
--
-- IDs are deterministic UUIDs prefixed `ava0-…` so re-running the
-- migration is safe (ON CONFLICT DO NOTHING).
--
-- Apply order: this must run AFTER avatars-platform-schema.sql
-- (depends on avatars + content_topics + avatar_knowledge_topics).
--
-- Idempotent. No rollback necessary — content_topics rows are
-- harmless even if orphaned from AVA.
-- ══════════════════════════════════════════════════════════════════

-- Resolve AVA id once for the joins below.
DO $$
DECLARE
  ava_id uuid;
BEGIN
  SELECT id INTO ava_id FROM avatars WHERE avatar_name = 'AVA';
  IF ava_id IS NULL THEN
    RAISE EXCEPTION 'AVA avatar not found — run avatars-platform-schema.sql first.';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────
-- Content topics
-- ─────────────────────────────────────────────────────────────────

INSERT INTO content_topics (id, vertical, avatar_id, topic_title, topic_description, generated_by, status, priority_score)
SELECT * FROM (VALUES
  -- ─── Life insurance (5) ───
  ('00000000-ava0-0000-0001-000000000001'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Term life vs whole life: which actually protects your family?',
    'Plain-language breakdown of term vs permanent, with three real-life scenarios — new parent, mid-career, near-retiree.',
    'admin', 'approved', 85),
  ('00000000-ava0-0000-0001-000000000002'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'How much life insurance do you actually need?',
    'The 10x-income rule + DIME method explained. Walk through a needs analysis live.',
    'admin', 'approved', 90),
  ('00000000-ava0-0000-0001-000000000003'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'No-medical life insurance: who is it actually for?',
    'When simplified-issue products make sense (and when they don''t). Honest pricing comparison.',
    'admin', 'approved', 75),
  ('00000000-ava0-0000-0001-000000000004'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Universal life vs whole life: the difference in plain English',
    'Two permanent products that look similar but aren''t. Who each one fits.',
    'admin', 'approved', 70),
  ('00000000-ava0-0000-0001-000000000005'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Why your group life through work is probably not enough',
    'Coverage ends when employment ends. Conversion options + portability gaps explained.',
    'admin', 'approved', 80),

  -- ─── Auto insurance (3) ───
  ('00000000-ava0-0000-0002-000000000001'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Ontario auto-insurance: the four coverages everyone needs to understand',
    'Third-party liability, accident benefits, DCPD, uninsured-motorist — what each one actually pays for.',
    'admin', 'approved', 80),
  ('00000000-ava0-0000-0002-000000000002'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Optional auto coverages: which are worth it, which aren''t',
    'OPCF 20, OPCF 27, OPCF 44R — practical guidance per driver type.',
    'admin', 'approved', 65),
  ('00000000-ava0-0000-0002-000000000003'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'High-risk auto: why your rate spiked and what to do about it',
    'Tickets, claims, lapses — how each affects rates and the realistic recovery path.',
    'admin', 'approved', 70),

  -- ─── Home insurance (3) ───
  ('00000000-ava0-0000-0003-000000000001'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Home insurance: what most policies actually exclude',
    'Sewer backup, overland water, earthquake — what''s standard and what costs extra.',
    'admin', 'approved', 80),
  ('00000000-ava0-0000-0003-000000000002'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Replacement cost vs actual cash value: the one number that matters at claim time',
    'The 30-second difference that decides whether you can rebuild your home.',
    'admin', 'approved', 75),
  ('00000000-ava0-0000-0003-000000000003'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Tenant insurance: $20/month decisions that protect $50,000',
    'For renters: liability, contents, and additional-living-expense — why each matters.',
    'admin', 'approved', 60),

  -- ─── Travel insurance (2) ───
  ('00000000-ava0-0000-0004-000000000001'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Travel insurance: the pre-existing-condition trap',
    'Stability periods, voluntary cancellation, and the most common claim denial reasons.',
    'admin', 'approved', 70),
  ('00000000-ava0-0000-0004-000000000002'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Snowbird coverage: what your provincial health card actually pays in Florida',
    'OHIP / RAMQ out-of-province reimbursement reality + recommended top-up.',
    'admin', 'approved', 65),

  -- ─── Critical illness (3) ───
  ('00000000-ava0-0000-0005-000000000001'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Critical illness insurance: a lump sum vs your savings account',
    'Why a $50k cheque on diagnosis can keep your house and your sanity intact.',
    'admin', 'approved', 80),
  ('00000000-ava0-0000-0005-000000000002'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Return-of-premium critical illness: what you actually get back',
    'The 15-year break-even math, with a real policy example.',
    'admin', 'approved', 65),
  ('00000000-ava0-0000-0005-000000000003'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Critical illness vs disability: not the same product, not the same problem',
    'Lump sum on diagnosis vs monthly income while you can''t work. Most families need both.',
    'admin', 'approved', 75),

  -- ─── Disability (2) ───
  ('00000000-ava0-0000-0006-000000000001'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Disability insurance: the statistic that should scare every breadwinner',
    '1 in 3 Canadians off work 90+ days before age 65. What individual coverage looks like.',
    'admin', 'approved', 85),
  ('00000000-ava0-0000-0006-000000000002'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Own-occupation vs any-occupation: a single word that changes everything',
    'Two definitions of "disabled" — and why doctors / dentists / lawyers buy own-occupation.',
    'admin', 'approved', 75),

  -- ─── Advisor recruitment (3) ───
  ('00000000-ava0-0000-0007-000000000001'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'New to LLQP: the realistic first 90 days as a Canadian life advisor',
    'Licensing, E&O, MGA selection, first-month income reality — no sugar coating.',
    'admin', 'approved', 75),
  ('00000000-ava0-0000-0007-000000000002'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Why advisors leave their MGA — and what to ask before signing',
    'The five questions Mary wishes she''d asked her first MGA principal. Honest checklist.',
    'admin', 'approved', 80),
  ('00000000-ava0-0000-0007-000000000003'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'Switching MGAs without losing your book: the 30-day playbook',
    'Carrier reassignment timing, client notification, commission flow during the transition.',
    'admin', 'approved', 70),

  -- ─── AdvisorAssist + RIBO Study Coach (3) ───
  ('00000000-ava0-0000-0008-000000000001'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'AdvisorAssist: the $49/mo tool that saves 6 hours of admin a week',
    'What''s in the Starter tier — needs-analysis templates, client renewal alerts, FSRA-aware scripts.',
    'admin', 'approved', 70),
  ('00000000-ava0-0000-0008-000000000002'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'AdvisorAssist Pro: when the $149/mo tier actually pays for itself',
    'For advisors at 20+ active clients — automation thresholds and ROI math.',
    'admin', 'approved', 65),
  ('00000000-ava0-0000-0008-000000000003'::uuid, 'insurance', (SELECT id FROM avatars WHERE avatar_name='AVA'),
    'RIBO Study Coach: pass your licensing on the first try',
    'Spaced-repetition study plan + sample questions + the three exam-day mistakes.',
    'admin', 'approved', 70)
) AS t(id, vertical, avatar_id, topic_title, topic_description, generated_by, status, priority_score)
ON CONFLICT (id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- Avatar ↔ knowledge-topic joins (weighted)
-- ─────────────────────────────────────────────────────────────────
-- Weights bias the topic-rotation order in the script writer:
--   90 — flagship topics (life / disability / home need-to-know)
--   70 — strong evergreen
--   50 — default
--   30 — niche / supplementary

INSERT INTO avatar_knowledge_topics (avatar_id, content_topic_id, weight)
SELECT
  (SELECT id FROM avatars WHERE avatar_name = 'AVA'),
  ct.id,
  CASE
    WHEN ct.priority_score >= 85 THEN 90
    WHEN ct.priority_score >= 75 THEN 70
    WHEN ct.priority_score >= 65 THEN 50
    ELSE 30
  END
FROM content_topics ct
WHERE ct.id::text LIKE '00000000-ava0-%'
ON CONFLICT (avatar_id, content_topic_id) DO NOTHING;
