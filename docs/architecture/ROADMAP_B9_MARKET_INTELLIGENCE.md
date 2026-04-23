# Part B.9 — Market Intelligence Engine

**Status:** Roadmap / specification only. No executable code in this pass.
**Branch target when implemented:** a follow-up sprint branch (not `scale-sprint-v1`).
**Prerequisite tier:** B.5 Apollo enrichment + B.6 multi-channel + B.7 video must be validated in production.
**Revenue thesis:** external market signals drive dynamic campaign scaling. Premium pricing tier at +$2,000/mo over the Basic offering.

---

## 1. Executive summary

The Crystallux sales engine after Parts B.5, B.6, and B.7 knows everything that can be
learned from the lead record itself: Apollo firmographics, niche overlay, priority score,
preferred channel. What it does **not** know is the state of the world around the lead —
whether a wildfire just evacuated their market, whether interest rates shifted the
prospect's margin calculus yesterday, whether a CRTC ruling dropped that made their
current vendor noncompliant.

Part B.9 closes that gap. It ingests a curated set of free + premium market signal
sources, classifies each event for severity / geography / industry impact, and then
feeds those classifications back into the Campaign Router and the Outreach Generation
workflow. The result: a lead in BC receives outreach emphasizing property protection the
day after a wildfire, not a generic cold email. The *what* of outreach stays the same;
the *context* becomes situationally aware.

This intelligence layer is the foundation of a premium product tier. Basic ($1,997/mo)
delivers the existing scaffolded pipeline. Intelligence ($3,997/mo) adds B.9 and the
downstream dashboard surfaces that let clients see which signals are scaling their
campaigns this week, with revenue attribution back to the original trigger event.

Why now: the multi-channel scaffolding shipped in B.6/B.7 gives the router multiple
knobs to turn (channel choice, daily cap, video trigger). Without a signal layer, those
knobs are static. With one, they become market-responsive — which is the narrative that
justifies the premium tier and the +$10K MRR projected below.

---

## 2. Revenue impact

| Metric | Basic (B.5/B.6/B.7) | Intelligence (+ B.9) | Delta |
|---|---|---|---|
| Monthly price | $1,997 | $3,997 | +$2,000 |
| Setup fee | $2,500 | $3,500 | +$1,000 |
| Adoption on 10-client book (conservative 50%) | 10 | 5 | +5 Intelligence seats |
| MRR impact | — | — | **+$10,000** |
| ARR impact | — | — | **+$120,000** |

**Breakeven:** 1 adopter covers the full development cost (estimated 15-20 hours
at blended contractor rate) within the first month. Every adopter after that is net
margin against ~$500/mo in premium API costs for news and weather on the full
paid stack (scales to $0/mo on free tiers for the MVP pilot).

**Upgrade path:** existing Basic clients upgrade in place — same lead database, same
workflows, same dashboard, plus B.9 layer flipped on via `client_signal_preferences`.
No cutover risk, no data migration.

---

## 3. Four-layer architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 1 — Signal Ingestion                                          │
│  Scheduled pollers per source. One row per raw event.                │
│  Dedup by content hash. No classification at this layer.             │
└──────────────────┬──────────────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────────────┐
│  Layer 2 — Signal Processing                                         │
│  Claude Haiku classifies each raw event for:                         │
│    - signal_type (wildfire, rate-change, data-breach, seasonal...)   │
│    - severity (low / medium / high / critical)                       │
│    - geo_scope (country / province / city / national)                │
│    - industries[] (insurance, construction, moving, etc.)            │
│    - confidence score                                                │
│    - active_from / active_to timestamps                              │
│  Duplicate suppression across sources.                               │
└──────────────────┬──────────────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────────────┐
│  Layer 3 — Dynamic Routing                                           │
│  For each active signal, for each client, for each matching lead:    │
│    - scale_factor applied to daily caps (1.0-3.0x)                   │
│    - campaign_pain_point overlay swap (signal-specific messaging)    │
│    - channel preference boost (e.g., severe signal -> voice+video)   │
│  All decisions logged to signal_routing_log for revenue attribution. │
└──────────────────┬──────────────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────────────┐
│  Layer 4 — Client Heat Map Dashboard                                 │
│  Per-client visualization:                                            │
│    - Active signals mapped by geography and industry                  │
│    - Which campaigns are currently scaled and by how much             │
│    - Response-rate lift during active signals (proof of value)        │
│    - Revenue attribution back to originating signal                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Signal sources catalog

### Free tier (MVP — ~$0/mo)

| Source | Purpose | API | Cadence | Notes |
|---|---|---|---|---|
| **GDELT 2.0** | Global news events with CAMEO event codes + geo | HTTP GDELT DOC 2.0 | 15 min | Free. High volume, heavy filtering required |
| **OpenWeatherMap** | Weather + severe-weather alerts | Free tier 60 calls/min | 30 min | Active wildfires, snowstorms, floods |
| **Bank of Canada** | Interest rates + CAD/USD | Valet API (free) | Daily | Triggers mortgage broker + travel insurance signals |
| **Statistics Canada** | Monthly economic indicators | Open Data free | Weekly | Unemployment, housing starts, CPI |
| **Google Trends** | Search-interest deltas for niche keywords | pytrends / SerpApi free tier | Daily | Early-warning signal for seasonal shifts |
| **Regulatory RSS** | CRTC, OSFI, provincial insurance councils | RSS (free) | 1 h | Regulatory-change triggered outreach |
| **Seasonal calendar** | Tax season, back-to-school, moving peaks | Static JSON | Daily cron | Deterministic time-based signals |

### Premium tier (full paid stack — ~$500/mo)

| Source | Purpose | API | Cadence | Cost |
|---|---|---|---|---|
| **NewsAPI paid** | 5K requests/day, full-text, 1-month history | NewsAPI Pro | 15 min | $449/mo |
| **Apollo news enrichment** | Direct company-mentioned-in-news signal | Apollo API addon | Per-lead | ~$20/mo |
| **Dark web breach feeds** | Cyber insurance trigger | HaveIBeenPwned Enterprise | Daily | ~$40/mo |

MVP launches on the free tier. Premium sources are gated behind an upgrade within
the Intelligence tier (sub-tier at +$4,997/mo if Mary chooses to price the premium
news stack separately).

---

## 5. Database schema additions (pseudo-SQL)

```sql
-- Layer 1 raw storage. One row per polled event. No classification.
CREATE TABLE market_signals_raw (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source       text NOT NULL,              -- 'gdelt' | 'newsapi' | 'owm' | ...
  source_id    text,                       -- upstream event ID for dedup
  fetched_at   timestamptz DEFAULT now(),
  event_at     timestamptz,                -- when the event itself happened
  payload      jsonb NOT NULL,             -- raw upstream body
  dedup_hash   text,                       -- sha256 of (source, source_id) or content hash
  processed    boolean DEFAULT false,      -- Layer 2 has consumed this row
  created_at   timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX idx_msr_dedup ON market_signals_raw(source, dedup_hash);
CREATE INDEX idx_msr_unprocessed ON market_signals_raw(processed, fetched_at)
  WHERE processed = false;

-- Layer 2 classified signals. One row per distinct event, deduped
-- across sources. Active window defined by active_from/active_to.
CREATE TABLE market_signals_processed (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  raw_ids         uuid[] NOT NULL,          -- array of market_signals_raw IDs this merges
  signal_type     text NOT NULL,            -- 'wildfire' | 'rate_change' | 'data_breach' | ...
  severity        text NOT NULL,            -- 'low' | 'medium' | 'high' | 'critical'
  geo_country     text,
  geo_region      text,                     -- province / state
  geo_city        text,
  industries      jsonb DEFAULT '[]',       -- ['insurance','travel','moving']
  confidence      numeric(3,2),             -- 0.00-1.00
  title           text,
  summary         text,
  active_from     timestamptz NOT NULL,
  active_to       timestamptz,              -- null = indefinite
  classified_at   timestamptz DEFAULT now(),
  classifier      text DEFAULT 'claude-haiku-4-5',
  metadata        jsonb
);
CREATE INDEX idx_msp_active ON market_signals_processed(active_from, active_to)
  WHERE active_to IS NULL OR active_to > now();
CREATE INDEX idx_msp_industries_gin ON market_signals_processed USING gin (industries);

-- Layer 3 log — every routing decision Influenced by a signal.
-- Enables revenue attribution and post-hoc response-rate analysis.
CREATE TABLE signal_routing_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id       uuid REFERENCES market_signals_processed(id),
  lead_id         uuid REFERENCES leads(id) ON DELETE SET NULL,
  client_id       uuid REFERENCES clients(id) ON DELETE SET NULL,
  campaign_name   text,
  scale_factor    numeric(4,2),             -- 1.00 = no change, 2.00 = 2x daily cap
  decision_type   text,                     -- 'scale_up' | 'scale_down' | 'message_swap' | 'channel_boost'
  applied_at      timestamptz DEFAULT now(),
  outreach_id     uuid,                     -- FK into outreach_log when a send happens
  metadata        jsonb
);
CREATE INDEX idx_srl_signal ON signal_routing_log(signal_id);
CREATE INDEX idx_srl_client  ON signal_routing_log(client_id, applied_at);

-- Client preferences. Lets clients opt in/out of signal types
-- without touching global defaults.
CREATE TABLE client_signal_preferences (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       uuid REFERENCES clients(id) ON DELETE CASCADE,
  signal_type     text NOT NULL,
  enabled         boolean DEFAULT true,
  custom_scale_factor numeric(4,2),         -- override default scale for this client
  custom_message_overlay text,              -- client-authored signal-specific copy
  created_at      timestamptz DEFAULT now(),
  UNIQUE (client_id, signal_type)
);
```

All tables RLS-enabled; service_role ALL; same pattern as the B.5/B.6/B.7 tables.

---

## 6. Workflow specifications

### 6.1 `clx-signal-ingestion-v1` (new)

**Active:** true (scheduled). **Cadence:** 15 min.
**Purpose:** poll every configured source, write raw rows, dedup by hash.

```
Schedule Trigger (15min)
  → Branch per source (parallel):
    ├── GDELT poller          → HTTP GET GDELT DOC 2.0
    ├── OpenWeather poller    → HTTP GET /data/2.5/alerts
    ├── NewsAPI poller        → HTTP GET /v2/everything (premium only)
    ├── BoC poller            → HTTP GET Valet observations (daily)
    ├── Google Trends poller  → pytrends via Python node (daily)
    └── RSS poller            → RSS feed node per feed
  → Normalize (per source: extract source_id, event_at, payload)
  → Compute dedup_hash
  → Upsert into market_signals_raw (ON CONFLICT dedup_hash DO NOTHING)
  → Mark processed=false for Layer 2
```

Per-source credentials created by name (`NewsAPI`, `OpenWeatherMap`, `BankOfCanada`).

### 6.2 `clx-signal-intelligence-v1` (new)

**Active:** true (scheduled). **Cadence:** 15 min.
**Purpose:** consume unprocessed raw rows, classify, merge, write processed signals.

```
Schedule Trigger (15min)
  → SELECT * FROM market_signals_raw WHERE processed=false LIMIT 50
  → Split in batches of 5 (Claude Haiku batch classification)
  → Haiku: classify(payload) -> { signal_type, severity, geo_*, industries[], confidence, active_from, active_to }
  → Merge near-duplicates (same signal_type, overlapping geo, within 24h) into one market_signals_processed row
  → Write merged rows to market_signals_processed
  → UPDATE market_signals_raw SET processed=true
```

Confidence threshold for promotion: 0.70. Below that, raw rows stay in the backlog
for human review via the dashboard.

### 6.3 Modification to `clx-campaign-router-v2`

Add a pre-routing step:
1. For the lead's `(client_id, industry, city, country)`, look up active signals:
   ```sql
   SELECT * FROM market_signals_processed
   WHERE active_from <= now() AND (active_to IS NULL OR active_to > now())
     AND (geo_city = $lead.city OR geo_region = $lead.region OR geo_country = $lead.country)
     AND industries ?| ARRAY[$lead.industry]
   ORDER BY severity DESC, confidence DESC LIMIT 3;
   ```
2. For each matched signal, check `client_signal_preferences(client_id, signal_type)`:
   - If disabled → skip this signal.
   - If enabled → pull `scale_factor` (client override or global default).
3. Compose `effective_scale_factor` = product of all active signals (capped at 3.0).
4. Apply:
   - Daily cap multiplier (sends per day = base_cap × effective_scale_factor).
   - `campaign_pain_point` swap to the signal-specific overlay (pulled from niche_overlays where we extend each niche with a `signal_overlays` jsonb).
   - Channel boost for critical signals (severe signal + voice-enabled client → bump `preferred_channel` to `voice` even if score < 90).
5. Write one row per applied signal to `signal_routing_log`.

### 6.4 Modification to `clx-outreach-generation-v2`

Inject active-signal context into the Claude system prompt:

```
<active_market_context>
  Signal: Wildfire evacuation order, Kamloops BC
  Severity: critical
  Industries affected: insurance, property management
  Active since: 2 days ago
  Client pain hook: clients calling about property coverage confusion
</active_market_context>
```

Claude rewrites the outreach to reference the signal naturally without feeling
like a scripted tie-in. Fallback: if no active signals, the existing prompt runs
unchanged.

### 6.5 No changes required to sender workflows

All signal-awareness is upstream of `clx-outreach-sender-v2`,
`clx-follow-up-v2`, channel-specific senders, or `clx-booking-v2`. They all
consume a `leads` row that already carries the signal-influenced campaign
fields.

---

## 7. API cost estimates

| Scenario | Monthly API cost |
|---|---|
| Free-tier MVP (GDELT + OpenWeather + BoC + StatsCan + RSS + Google Trends + seasonal) | **$0** |
| + NewsAPI paid | **$449** |
| + Apollo news enrichment | +$20 |
| + Cyber breach feed | +$40 |
| **Full premium stack** | **~$510/mo** |

Anthropic token cost for Layer 2 classification (Claude Haiku, ~500 input tokens
per raw event, ~200 output tokens, ~3,000 events/day across sources):
3,000 × (500 input + 200 output) × $0.80/M input × $4/M output ≈ **$3-5/mo.**
Negligible.

Tavus-style per-render billing does not apply here (no video generation at this
layer). Signal-triggered videos are billed through the existing B.7 line.

---

## 8. Pricing tier structure

| Tier | Monthly | Setup | Inclusions |
|---|---|---|---|
| **Basic** | $1,997 | $2,500 | Parts B through B.7: Apollo enrichment + multi-channel outreach (email, LinkedIn, WhatsApp, voice, video) + error monitoring + dashboard |
| **Intelligence** | $3,997 | $3,500 | Basic + B.9 signal ingestion + processing + dynamic routing + heat map dashboard + client signal preferences UI |
| **Intelligence Premium** (optional) | $4,997 | $3,500 | Intelligence + NewsAPI paid + Apollo news enrichment + cyber breach feed |

Basic clients can upgrade to Intelligence via a single flag flip on their client row;
no reimport, no migration. Intelligence clients can opt any signal on/off via
`client_signal_preferences`.

---

## 9. Revenue projections

Assume the 10-client book at end-of-sprint (post-B.8). Adoption schedule:

| Quarter | Intelligence adopters | MRR contribution | Cumulative MRR |
|---|---|---|---|
| Q1 (first 90 days post-launch) | 3 | +$6,000 | $6,000 |
| Q2 | 5 | +$10,000 | $10,000 |
| Q3 | 6 | +$12,000 | $12,000 |
| Q4 | 7 | +$14,000 | $14,000 |

Assumptions: 50% conversion of Basic clients within 12 months, steady adoption
curve, no churn on the Intelligence tier (signal-driven results provide visible
lift). If the heat-map dashboard shows measurable response-rate lift during
active signals (>1.3× baseline), upgrade friction drops and these numbers climb.

**Risk-adjusted 12-month ARR delta:** +$120K to +$200K.

---

## 10. Development estimate

| Phase | Hours | Sessions |
|---|---|---|
| Schema migration + seed | 2h | 1 |
| Layer 1 ingestion workflow (single-source proof with GDELT) | 3h | 1 |
| Layer 2 classification workflow + dedup logic | 4h | 1 |
| Campaign Router integration + signal_routing_log | 3h | 1 |
| Outreach Generation prompt injection + niche overlay extension | 2h | 1 |
| Dashboard widgets (heat map + active-signal panel) | 4h | 1 |
| End-to-end QA with synthetic signal + real lead | 2h | 1 |
| **Total** | **20h** | **2-3 sessions** |

Multi-source fanout (NewsAPI, OpenWeather, etc.) is a repeatable extension of
the GDELT pattern and can ship incrementally, one source per subsequent session.

---

## 11. Prerequisites

Before starting B.9:

- B.5 Apollo enrichment validated in production on 3+ paying clients (real
  people and email fields populated from at least one real Apollo call).
- B.6 multi-channel scaffolding has seen at least one live LinkedIn,
  WhatsApp, or voice outreach (proves the activation runbooks work).
- B.7 video scaffolding has rendered and sent at least one real Tavus video to a
  real lead (proves the async callback flow end-to-end).
- 3+ clients on Basic tier generating revenue (signal layer has revenue to
  attribute against).
- Error monitor thresholds tuned and clean for ≥30 days (noisy pipeline = noisy
  signal routing logs).

If any prerequisite is unmet, B.9 ships speculative value on a shaky foundation.
Wait.

---

## 12. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Signal noise produces false positives that trigger irrelevant outreach | Medium | High (damages client trust) | Confidence threshold 0.70, human-in-loop dashboard review for first 30 days |
| Signals decay faster than `active_to` predicts, scaling stays on after relevance gone | Medium | Medium | Claude Haiku also sets `active_to` conservatively; dashboard has manual override |
| Over-scaling during low-quality signal spams prospects | Low | Critical | scale_factor cap at 3.0; per-client daily ceiling never exceeded regardless |
| Client objects to algorithmic campaign changes they didn't author | Medium | Medium | `client_signal_preferences` lets them disable any signal type; dashboard shows every decision |
| Premium API costs scale faster than revenue at low adoption | Low | Low | MVP runs on free tier; premium sources gated behind Intelligence Premium sub-tier |
| GDELT / NewsAPI rate limits under retry storms | Low | Medium | Dedup by hash prevents re-fetch storms; circuit breaker on repeated 429s |
| Signal processing backlog grows unbounded if Haiku fails | Low | Medium | scan_errors `SIGNAL_PROCESSING_FAILED` threshold, backlog size alert |

---

## 13. Success metrics

Measured in the heat-map dashboard (Layer 4):

- **Response rate lift during active signal window** — target ≥1.3× baseline for
  severity=high, ≥1.5× for critical.
- **Revenue attribution per signal type** — closed-won deals where the first
  outreach touch happened during an active signal, grouped by `signal_type`.
- **Signal → booking conversion** — of leads touched during active signal, what %
  reach `lead_status='Meeting Scheduled'`.
- **False positive rate** — % of active signals Mary (or client) marks irrelevant
  via dashboard override. Target ≤15%.
- **Intelligence tier retention** — 6-month retention on Intelligence clients vs
  Basic. Premium tier churn target ≤5%.
- **Processing backlog latency** — p95 time from raw signal ingest to processed
  classification. Target ≤10 min.

---

## 14. Concrete examples

These are the signals that would fire in the MVP, with their routing behaviour:

- **Wildfire evacuation order, BC** (GDELT + OpenWeather)
  → Scale UP property insurance broker daily cap 2× for 14 days; scale DOWN travel
  insurance outreach to BC leads 0.5× (travellers are not the audience right now).
  Campaign message overlay: "property coverage during evacuation" pain hook.
- **Bank of Canada overnight rate drops >25bps**
  → Scale UP mortgage broker outreach 2× for 21 days. Campaign overlay: "refinance
  window opening, help your past clients lock in." Pairs naturally with high-score
  video outreach (B.7).
- **CAD/USD drops >3% in 7 days**
  → Scale UP travel insurance hedging outreach to outbound-travel niches 1.5×.
  Cross-sell to clients with both travel insurance and mortgage broker lines.
- **New CRTC regulation published** (regulatory RSS)
  → Scale UP compliance consulting outreach to affected industries 3× for 30 days.
  Critical severity auto-bumps `preferred_channel` to voice for clients with voice
  enabled. Overlay: "new compliance requirement, our audit framework covers it."
- **Major data breach disclosed** (NewsAPI + HIBP Enterprise)
  → Scale UP cyber insurance outreach 2.5× for 30 days, targeted geographically if
  the breach disclosure names specific markets. Overlay: "recent breach in
  [industry] — here's how our coverage line covers this exact scenario."
- **Major snowstorm forecast** (OpenWeatherMap severe weather alert)
  → Scale UP moving services outreach in the affected region 1.8× for the week
  before the storm (people panic-book winter moves). Overlay: "beat the storm,
  book your move this week."
- **Tax season** (seasonal calendar, Feb 1 - Apr 30 Canada)
  → Scale UP accountant outreach 2× for 90 days. Overlay: "tax season lead
  capture, let us book your discovery calls before April 30." Deterministic; no
  classification needed.
- **Back-to-school season** (seasonal calendar, mid-Aug - mid-Sep)
  → Scale UP student insurance + kids' dental outreach 1.5× for 45 days. Overlay:
  "back-to-school coverage gaps, help parents lock in before first-aid claims
  start rolling in."

Each example has a one-liner Claude-Haiku-classifiable payload, a clear
downstream action, and a revenue tie-back. They're the first 8 taxonomies to
build; the dashboard learns more from operator feedback.

---

## 15. Next steps after B.9

- **B.10 Predictive ML** — train a per-signal / per-niche / per-client response
  model on the `signal_routing_log` × `outreach_log` × closed-won join. Outcome:
  scale_factor becomes learned rather than configured. 3-4 sessions once B.9 has
  ≥90 days of routing logs.
- **B.11 Client-specific signal training** — each client accrues their own
  response curve. "Client X responds best to wildfire signals at severity=high
  with a 1.8× scale; Client Y responds best only to severity=critical." Stored
  in `client_signal_preferences.custom_scale_factor`, set by B.10's model.
- **B.12 Signal-driven content generation** — Claude generates the signal-specific
  overlay copy from the raw signal payload on the fly rather than pulling from
  `niche_overlays.signal_overlays`. Lets Intelligence clients handle signal types
  the platform hasn't seen before without a migration.
- **B.13 External signal subscriptions** — let clients POST their own signals
  into the platform (e.g., "internal: competitor raised prices, scale our
  outreach 2× for 7 days"). Closes the loop between external market data and
  private business intelligence.

---

## Appendix A — Out of scope for B.9

- Real-time streaming (sub-minute latency). Signals are time-scaled in hours to
  days; 15-min cadence is sufficient.
- Multi-tenant signal isolation. All clients see the same processed signal pool;
  opt-in/out is the only granularity. If a client demands their signal decisions
  remain private, that's a B.10+ discussion.
- Multi-lingual signal sources. MVP is English + Canadian French RSS only.
- Stock market signals (equity / crypto). High noise, low relevance to SMB
  outreach. Consider for a vertical-specific Wall Street tier later.
