# Behavioral Intelligence — Phase 2 build plan

> **Status (post-this-session):** schema ready (`db/migrations/behavioral-intelligence-schema.sql`). Workflows + archetype seed library = **next session**.
> **Spec source:** [`docs/architecture/OPERATIONS_HANDBOOK.md`](../architecture/OPERATIONS_HANDBOOK.md) §35.
> **Universal multi-vertical:** the engine is built once and serves every Crystallux vertical. What's per-vertical is the seeded archetype library, not the schema or workflows.

## Phase 2 build inventory (5 workflows + seed)

### 5 workflows to build

1. **`workflows/api/behavioral/clx-behavioral-scanner-v1.json`** (~600 lines)
   - **Trigger:** Schedule, every 6h.
   - **Flow:** for each client where `clients.behavioral_intel_enabled=true`, fan out across leads, hit each enabled signal source (LinkedIn / NewsAPI / BoC / Crunchbase / etc.), call `record_behavioral_signal` RPC for hits.
   - **Cost-bound:** cap at N scans/day per client per category (configurable per `signal_subscriptions`).
   - **Sources tier-1 (free):** Bank of Canada Valet, Environment Canada, NewsAPI free, ESPN RSS, OpenCorporates, CRA filing calendar, LinkedIn public scrape.
   - **Sources tier-2 (paid):** Google News, Apollo, Crunchbase, Unipile.
   - **Sources tier-3 (consent-gated):** lead-supplied intake.

2. **`workflows/api/behavioral/clx-behavioral-classifier-v1.json`** (~300 lines)
   - **Trigger:** webhook + 6h schedule.
   - **Flow:** picks `behavioral_signals` rows where `relevance_score IS NULL`, batches 20 to Claude Haiku, scores relevance (0-100) + sensitivity (low/medium/high), PATCHes back.

3. **`workflows/api/behavioral/clx-behavioral-trigger-v1.json`** (~400 lines)
   - **Trigger:** webhook fired by classifier on every classified signal.
   - **Flow:** calls `match_signal_to_trigger` RPC. If match: composes outreach via §28 closing-intelligence script library using `archetype.message_template_id`. Auto-sends if `signal_subscriptions.sensitivity_ceiling` allows AND `archetype.sensitivity_floor` is met. Otherwise enqueues in dashboard "Suggested outreach today" panel for advisor approval.

4. **`workflows/api/behavioral/clx-behavioral-learning-loop-v1.json`** (~200 lines)
   - **Trigger:** Schedule, 02:00 daily.
   - **Flow:** uses `acted_on_at` + downstream `lead_status` changes to recompute `signal_archetypes.conversion_rate` over 90-day window. Mirrors §34 script-learning loop.

5. **`workflows/api/behavioral/clx-behavioral-consent-collector-v1.json`** (~150 lines)
   - **Trigger:** webhook fired by prospect's response landing page intake form.
   - **Flow:** writes signals as `signal_source = 'lead_supplied'` and flips `consent_status = 'explicit'` on the matching lead's existing signals.

### Seed archetype library — start with insurance vertical

Per §35.13 activation roadmap step 6. Insurance is Mary's home vertical → highest seed priority. Universal-engine principle: every vertical gets its own archetype seed seeded under the same schema.

#### Insurance broker — 12 starter archetypes

| Archetype | Required signals | Optional | Action | Sensitivity |
|---|---|---|---|---|
| `birthday_with_pending_renewal` | `personal.birthday` + `vertical_specific.policy_renewal_60d` | sports.local_team_event | send_email | low |
| `expansion_signals_group_benefits` | `business.headcount_expansion` + `business.new_office` | business.funding_round | send_linkedin | low |
| `new_parent_term_life` | `personal.new_baby` | — | queue_for_review | high |
| `bereavement_pause` | `personal.bereavement` | — | wait | high |
| `business_anniversary_renewal_walkthrough` | `business.anniversary` + `vertical_specific.policy_renewal_window` | — | send_email | low |
| `industry_regulatory_change_review` | `industry.regulatory_change` (with prospect's vertical match) | — | send_email | low |
| `policy_lapse_recovery` | `vertical_specific.policy_lapsed` | personal.life_event | phone_call | medium |
| `claim_filed_check_in` | `vertical_specific.claim_filed` | — | phone_call | medium |
| `cross_sell_critical_illness` | `personal.new_parent` + `vertical_specific.has_life_no_ci` | financial.income_increase | send_email | medium |
| `mortgage_renewal_cross_sell` | `financial.mortgage_renewal_window` + `vertical_specific.has_no_mortgage_insurance` | — | send_email | low |
| `news_mention_positive` | `news.positive_press` | — | send_email_warm | low |
| `funding_round_group_health` | `business.funding_round` (>$2M) | business.headcount_expansion | send_linkedin | low |

#### Real estate — 10 starter archetypes (Phase 2 follow-on)

`anniversary_in_home_5yr_listing_pitch`, `neighbourhood_comp_sold_above_asking`, `school_age_milestone_suburb_relocation`, `divorce_news_relocation_listing`, `permit_filed_block_market_pulse`, etc.

#### Mortgage broker — 8 starter archetypes

`boc_rate_drop_refi_window`, `mortgage_renewal_60d_quote_war`, `promotion_upsizing_pre_approval`, `new_baby_first_home_pre_approval`, etc.

#### Dental — 6 starter archetypes

`recall_due_no_booking`, `treatment_plan_idle_30d`, `insurance_year_end_use_or_lose`, `cosmetic_inquiry_consult`, etc.

#### Construction — 6 starter archetypes

`permit_filed_in_zone`, `home_25yr_mark_reno_pitch`, `storm_event_in_region`, `seasonal_demand_pre_book`, etc.

#### Consulting — 6 starter archetypes

`target_company_press_release`, `competitor_named_in_market`, `target_exec_hire`, `target_funding_round`, etc.

## Activation roadmap (sequenced, dormant-by-default)

Each gate is independently shippable. Per §35.13:

1. **Pre-req per vertical:** vertical-specific data feeds (e.g., insurance `policies` table; real estate MLS-comp; dental recall calendar; construction permit feed). Without these, the `vertical_specific` signal category is hollow for that vertical — the other 9 categories still work universally.
2. **MVP universal launch:** 4 categories live (`personal.birthday`, `business.headcount_expansion`, `vertical_specific.<one>`, `calendar.<internal>`). Tier 1 (free) sources only. `auto_send=false` everywhere — queue mode only.
3. **Tier 2 sources:** Google News + Crunchbase. Adds `news.*` + `social.*` categories.
4. **Sensitive personal category:** `personal.new_baby / marriage / bereavement / illness`. High-sensitivity gating tested. Default OFF per client; admin opt-in.
5. **Full 10 categories:** add `industry.*`, `sports.*`, `financial.*`, `geographic.*`.
6. **Per-vertical archetype seeding:** import seed library (insurance first, then real estate, mortgage, dental, consulting, construction).
7. **Auto-send mode:** flip `auto_send=true` per client/category once trigger archetypes have ≥ 50 acted-on rows of feedback (data to ground sensitivity defaults).
8. **Learning loop activation:** activate `clx-behavioral-learning-loop-v1` 02:00 schedule.

## What's done after this session (foundation only)

- ✓ Schema migration (`db/migrations/behavioral-intelligence-schema.sql`)
- ✓ 4 RPCs (record/match/mark-acted-on/enable)
- ✓ RLS service-role-only on all 4 tables
- ✓ Per-client tier flag on `clients` (`behavioral_intel_enabled`)

## Estimated build time for Phase 2

- 5 workflows: 5-7 days senior-engineer
- Seed archetype library (insurance starter set, 12 archetypes, ~3 days research + writing)
- Vertical-specific data feed pre-reqs: vary; insurance `policies` table is ~1 day, others vary
- Total to insurance MVP launch: **5-7 days** of focused engineering after this foundation lands

## Cost ceiling at scale

Per §35.15 — at 30 clients × 100 monitored leads each (3,000 prospects):
- Tier 1 sources: free
- Tier 2 (Google News + Crunchbase): ~$200/mo
- Claude Haiku classifier: ~$90/mo
- Claude Sonnet trigger compose: ~$225/mo
- **~$515/mo platform cost to deliver $30K-$60K MRR.** Margin is the headline.

## Cross-references

- Spec: [OPERATIONS_HANDBOOK.md §35](../architecture/OPERATIONS_HANDBOOK.md)
- Schema migration: [db/migrations/behavioral-intelligence-schema.sql](../../db/migrations/behavioral-intelligence-schema.sql)
- Archetype use cases: §35.7 (4 worked examples in handbook)
- Vision context: [PRODUCT_VISION.md](../architecture/PRODUCT_VISION.md)
- Insurance vertical scope: [docs/audit/insurance-features-extracted.md §2.13](../audit/insurance-features-extracted.md)
