# QUEUED TASK — B2B Vertical Seeding (Construction, Moving, Cleaning)

**Status:** queued. **Do not execute** until Part C of the current sprint
completes AND Mary confirms the green light.

Execute after Part C of current sprint completes and Mary confirms
green light.

- Single migration file: `docs/architecture/migrations/2026-04-24-verticals-b2b-batch1.sql`
- Idempotent (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`)
- Rollback SQL as trailing comments
- Commit message: `Verticals seeded: construction, moving_services, cleaning_services`

## Schema pre-check

The following columns must exist on `niche_overlays` before running the
seed. If any are missing, add them via `ALTER TABLE ... ADD COLUMN IF
NOT EXISTS` at the top of the migration:

- `vertical text` (primary key / unique)
- `niche_display_name text`
- `claude_system_prompt text`
- `outreach_tone text`
- `pain_signals jsonb`
- `offer_mapping jsonb`
- `preferred_channels jsonb`
- `voice_script_template text`
- `apollo_title_keywords jsonb`
- `compliance_notes text`
- `is_active boolean default true`

**Note:** the current migrations (`2026-04-22-scale-sprint-v1.sql`,
`2026-04-23-multi-channel.sql`, `2026-04-23-video-schema.sql`) use
`niche_name` as the overlay key column, not `vertical`. Before
executing this batch, either (a) rename `niche_name` to `vertical`
(with an index) or (b) change every `vertical` in the INSERTs below to
`niche_name`. Mary to decide at execution time.

---

## Construction seed

```sql
INSERT INTO niche_overlays (
  vertical, niche_display_name, claude_system_prompt, outreach_tone,
  pain_signals, offer_mapping, preferred_channels,
  voice_script_template, apollo_title_keywords, compliance_notes,
  is_active
) VALUES (
  'construction',
  'Construction & General Contracting',
  'Peer-to-peer tone. Write as a fellow small business operator who understands job-site pressures, cash flow between projects, and the stress of inconsistent lead flow. Reference specific pain signals like: weeks between project handoffs, dependence on HomeStars/referrals, losing bids to larger firms, crews sitting idle between jobs, insurance premium creep. Offer framed as: "We find the homeowners planning renovations 30-60 days before they start calling contractors. You close 10 quality projects this quarter." Never sound like a tech vendor. Write in short direct sentences. No jargon. No bullet points or dashes.',
  'Confident peer, direct language, acknowledges job-site realities, respects operator busyness.',
  '["Weeks of downtime between projects","Paying Google Ads $40-80 per lead that never convert","Losing bids to bigger firms with marketing budgets","Relying on word-of-mouth and referrals with no system","Crew sitting idle while waiting for next project","HomeStars and Houzz fees eating into profit margins","Bidding against unlicensed contractors","Seasonal gaps winter slowdowns spring scramble","Spending evenings quoting instead of running the business","Missed callbacks because no one is in the office","Clients ghosting after the quote","Cannot compete with large firms on SEO"]'::jsonb,
  '{"primary_offer":{"founding_price":1497,"retail_price":2497,"target_outcome":"20 qualified homeowner leads per month actively planning renovations","guarantee":"10 qualified leads in first 30 days or month free"},"upsell_offer":{"name":"Construction Growth","price":3497,"includes":"Lead gen + automated follow-up + SMS reminders + booking pipeline + monthly pipeline report"}}'::jsonb,
  '["email","voice","whatsapp","linkedin"]'::jsonb,
  'Hi, is this {name}? This is Mary from Crystallux. I work with construction and renovation contractors in {city} like {company}. Most contractors I talk to are spending 3-4k a month on Google Ads and lead aggregators and getting homeowners who arent ready to pull the trigger. We find homeowners planning renovations 30 to 60 days before they start calling contractors, so you get in front of them first. My founding contractor clients are booking 20 quality quotes per month. I would love 15 minutes to show you how this works at {company}. Can I send you a Calendly link for this week or next?',
  '["Owner","Founder","President","Managing Partner","General Manager","Principal","Operations Manager","Estimator"]'::jsonb,
  'Canadian CASL compliance required. CRTC Do Not Call List check before voice outreach. Provincial contractor licensing — target licensed contractors only.',
  true
) ON CONFLICT (vertical) DO NOTHING;
```

---

## Moving_services seed

```sql
INSERT INTO niche_overlays (
  vertical, niche_display_name, claude_system_prompt, outreach_tone,
  pain_signals, offer_mapping, preferred_channels,
  voice_script_template, apollo_title_keywords, compliance_notes,
  is_active
) VALUES (
  'moving_services',
  'Moving & Relocation Services',
  'Peer-operator tone. Moving is a brutal business — seasonal, price-sensitive, high-competition. Write as someone who understands the daily grind: no-show customers, last-minute cancellations, fuel costs, insurance premiums, crew turnover. Reference signals like: Two Men and a Truck competitors, U-Haul DIY pressure, slow winter months, rate pressure from aggregators. Offer framed as: "We find homeowners planning moves 2-3 weeks before they start calling quotes, so you lock them in before your competitors do." Direct, confident, no fluff.',
  'Direct, fast-paced, respects operator time, acknowledges competitive pressure.',
  '["Losing jobs to last-minute cancellations","Competing with Two Men and a Truck on brand","U-Haul and PODS stealing DIY-price-sensitive customers","Moving aggregators capping rates","Seasonal income swings summer boom winter famine","Crew turnover during peak moving season","Customer ghosting after quote","No-show customers costing a truck plus crew half-day","Fuel prices eating into margins","Insurance premiums climbing each year","Review sites damaging reputation","Cannot predict lead flow month to month"]'::jsonb,
  '{"primary_offer":{"founding_price":997,"retail_price":1497,"target_outcome":"30 qualified move leads per month — homeowners planning moves 2-3 weeks out","guarantee":"15 quotes booked in first 30 days or month free"},"upsell_offer":{"name":"Moving Growth Pro","price":2497,"includes":"Lead gen + automated quote follow-up + SMS reminders + no-show recovery + seasonal demand forecasting"}}'::jsonb,
  '["sms","whatsapp","email","voice"]'::jsonb,
  'Hi, is this {name}? This is Mary from Crystallux. I work with moving companies in {city} like {company}. Most movers I talk to hit a wall during winter and lose summer jobs to last-minute cancellations. We find homeowners planning moves 2 to 3 weeks before they start calling for quotes, so you can lock them in before Two Men shows up. My founding moving clients are booking 30 quality quotes a month. I would love 15 minutes to show you how this works at {company}. Can I send you a Calendly link for tomorrow or the day after?',
  '["Owner","Founder","President","General Manager","Operations Manager","Dispatcher"]'::jsonb,
  'CASL compliance. CRTC DNCL check before voice. BBB accreditation recommended for client credibility.',
  true
) ON CONFLICT (vertical) DO NOTHING;
```

---

## Cleaning_services seed

```sql
INSERT INTO niche_overlays (
  vertical, niche_display_name, claude_system_prompt, outreach_tone,
  pain_signals, offer_mapping, preferred_channels,
  voice_script_template, apollo_title_keywords, compliance_notes,
  is_active
) VALUES (
  'cleaning_services',
  'Cleaning & Janitorial Services',
  'Peer-operator tone. Cleaning is a high-churn, high-competition business. Write as someone who understands: one-time jobs are a dead-end, recurring customers are the goal, retention matters more than acquisition. Reference signals like: Merry Maids, Molly Maid competitors, cleaner turnover, last-minute cancellations, residential vs commercial mix, scaling crew without quality drop. Offer framed as: "We find homeowners who want recurring cleaning — weekly or bi-weekly. Higher LTV than one-time cleans." Direct, practical, respects operational realities.',
  'Friendly but direct, acknowledges retention challenges, focuses on LTV over one-off revenue.',
  '["Customers booking one-time cleans and ghosting","Losing regulars to Merry Maids or Molly Maid marketing","Cleaner turnover training cost eating profit","Spending on Google Ads for one-time bookings","Last-minute cancellations wasting scheduled hours","Trying to build recurring contracts but competitors undercut","Cannot scale beyond what I can personally supervise","Commercial contracts stuck in bid wars on price","Customers comparing to 15 dollar per hour individual cleaners","Review management across platforms consumes time","Seasonal spikes spring cleaning rush then quiet","No retention system customers drift away silently"]'::jsonb,
  '{"primary_offer":{"founding_price":997,"retail_price":1497,"target_outcome":"25 qualified cleaning leads per month prioritizing recurring contracts","guarantee":"10 booked cleans in first 30 days or month free"},"upsell_offer":{"name":"Cleaning Retention Pro","price":1997,"includes":"Lead gen + automated rebooking + retention SMS sequence + review request automation + referral tracking"}}'::jsonb,
  '["sms","whatsapp","email","voice"]'::jsonb,
  'Hi, is this {name}? This is Mary from Crystallux. I work with cleaning and janitorial businesses in {city} like {company}. Most cleaning businesses I talk to hit a wall scaling past what the owner can supervise and lose regulars to big brands like Merry Maids. We find homeowners looking for weekly or bi-weekly recurring cleaning, so you get high-LTV customers not one-time jobs. My founding cleaning clients are booking 25 qualified recurring leads a month. I would love 15 minutes to show you how this works at {company}. Can I grab 15 minutes with you this week?',
  '["Owner","Founder","President","General Manager","Operations Manager","Sales Manager"]'::jsonb,
  'CASL compliance. WSIB recommended for client credibility. Commercial vs residential mix matters for messaging.',
  true
) ON CONFLICT (vertical) DO NOTHING;
```

---

## Verification queries

```sql
SELECT
  vertical,
  niche_display_name,
  is_active,
  jsonb_array_length(pain_signals) AS pain_count,
  offer_mapping->'primary_offer'->>'founding_price' AS founding_price
FROM niche_overlays
ORDER BY vertical;
```

Expected 4 rows total:

| vertical | niche_display_name | is_active | pain_count | founding_price |
|---|---|---|---|---|
| cleaning_services | Cleaning & Janitorial Services | true | 12 | 997 |
| construction | Construction & General Contracting | true | 12 | 1497 |
| insurance_broker | Insurance Brokers (Canada) | true | 13 | 1997 |
| moving_services | Moving & Relocation Services | true | 12 | 997 |

## DO-NOT-BREAK checks

- insurance_broker seed unchanged (`pain_count` stays 13,
  `founding_price` stays 1997)
- All other workflows untouched
- No changes outside `niche_overlays` seed

---

## Operations Handbook update (append §19)

Append to `docs/architecture/OPERATIONS_HANDBOOK.md`:

```markdown
## 19. B2B Vertical Catalog (Batch 1)

Seeded and ready for client onboarding:

| Vertical | Founding Price | Target Outcome | Primary Channels |
|----------|----------------|----------------|------------------|
| insurance_broker | $1,997 | 20 meetings/mo | email, voice, linkedin |
| construction | $1,497 | 20 project quotes/mo | email, voice, whatsapp, linkedin |
| moving_services | $997 | 30 move quotes/mo | sms, whatsapp, email, voice |
| cleaning_services | $997 | 25 recurring leads/mo | sms, whatsapp, email, voice |

First-client onboarding for each vertical:

1. Discovery call (use vertical-specific script from
   docs/client-outreach/)
2. Gather client info (service area, crew size, pricing tier, Calendly,
   etc.)
3. Insert client row with vertical assignment
4. Configure `channels_enabled` based on client plan
5. Test first 5 outreach sends in TESTING MODE
6. Activate when client approves messaging
```

---

## Client first-call scripts (create as part of the batch)

Create these three files alongside the migration:

- `docs/client-outreach/construction-first-call-script.md`
- `docs/client-outreach/moving-first-call-script.md`
- `docs/client-outreach/cleaning-first-call-script.md`

Each follows the structure:

- Opening (2 sentences)
- Pain diagnosis (5 questions specific to vertical)
- Offer presentation (price, outcome, guarantee)
- Common objection + answer
- Close to setup call

---

## Rollback (trailing comments in the migration)

```sql
-- -- Rollback this batch (uncomment sections to undo):
--
-- DELETE FROM niche_overlays
-- WHERE vertical IN ('construction','moving_services','cleaning_services');
--
-- -- Schema additions (only if this migration added them; skip if they
-- -- already existed from a prior migration):
-- -- ALTER TABLE niche_overlays
-- --   DROP COLUMN IF EXISTS compliance_notes,
-- --   DROP COLUMN IF EXISTS apollo_title_keywords,
-- --   DROP COLUMN IF EXISTS niche_display_name;
```
