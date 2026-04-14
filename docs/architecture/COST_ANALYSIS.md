# Crystallux — Cost Analysis (v2.1 Smart Scanning)

_Updated 2026-04-13_

## TL;DR

| Metric | v2 (before) | v2.1 (after) |
|---|---|---|
| Google Maps calls / day | **215** | **~40** (steady state) |
| Google Maps spend / day | $6.88 | ~$1.28 |
| Google Maps spend / year | **$2,511** | **~$467** |
| Annual savings | — | **~$2,044** |
| Marginal cost of a new client (same industry + city already covered) | **~$0** | **~$0** |
| Marginal cost of a new client (new industry in existing city) | +$0.32/day (+$117/yr) | +$0.32/day (+$117/yr) |
| Marginal cost of a new client (new industry + new city) | +$0.64/day (+$234/yr) | +$0.64/day (+$234/yr) |

## Assumptions

- Google Maps Places API (New) **Text Search**: **$32 per 1,000 calls** ($0.032 each). Source: Google Maps Platform pricing, SKU "Text Search (New) - Essentials".
- Daily cron at 02:00 America/Toronto.
- 5 GTA cities: Toronto, Mississauga, Brampton, Vaughan, Markham.
- 43 query templates across 6 B2C industries (moving, insurance, dental, beauty, cleaning, construction).
- Current clients: 2 (Blonai Moving, Crystallux Insurance Network).

## v2 — The Baseline

```
43 queries × 5 cities = 215 API calls / day
215 × $0.032         = $6.88 / day
$6.88 × 365          = $2,511 / year
```

Every query runs every day, regardless of whether it ever produces a new lead. Most GTA B2C verticals are saturated after the first week — by day 10 the marginal benefit of scanning "dentist in Toronto Canada" for the 10th time is approximately zero, but we still pay $0.032 for it every 24 hours.

## v2.1 — Smart Scanning

Two levers reduce cost:

### Lever 1 — Auto-pause unproductive queries

The new `scan_query_tracker` table records every scan outcome. The `upsert_scan_tracker` RPC pauses a query when it returns zero new leads **three scans in a row**. Paused queries are re-tried once a week; if they stay dry, they stay paused.

**Expected steady state after ~10 days:**

| Phase | Queries active | Daily calls |
|---|---|---|
| Day 1 (cold start, first-time scan of everything) | 215 | 215 |
| Day 2–5 (saturated queries start triggering auto-pause) | ~120 | ~120 |
| Day 6–14 (most queries exhausted) | ~40 | ~40 |
| Day 15+ (steady state + weekly retries) | ~40–50 | ~40–50 |

Steady-state spend: **~40 calls/day × $0.032 = $1.28/day = ~$467/year**.

### Lever 2 — Client-driven query generation

v2.1's `Build B2C Scan List` node derives the active industry set from the `clients` table instead of a hardcoded list. If you only have clients in **moving** and **insurance**, the workflow will not scan **dental**, **beauty**, **cleaning**, or **construction** queries at all — a cold-start reduction before any auto-pause kicks in.

With the current 2 clients:

```
Active industries: moving services + insurance
Query templates:   moving (13) + insurance (8) = 21 queries × 5 cities = 105 calls
                   (vs. 215 for the full hardcoded set)
```

So on day 1, v2.1 already runs **~105 calls** instead of 215. After auto-pause converges, it settles at **~40**.

### Combined projection (2 clients)

| Day | v2 | v2.1 |
|---|---|---|
| 1 | 215 | ~105 |
| 7 | 215 | ~60 |
| 30 | 215 | ~40 |
| 365 | 215 | ~45 |

**Annual spend: $2,511 → ~$467. Savings: ~$2,044 / year.**

## Cost per additional tenant

This is the number that matters for scaling to 50+ clients.

| New client looks like… | Extra daily calls | Extra $/day | Extra $/year |
|---|---|---|---|
| **Same industry + city as existing client** (e.g. another Toronto mover) | 0 | $0.00 | $0 |
| Same industry, new city (e.g. Hamilton mover) | ~10–13 | ~$0.40 | ~$146 |
| New industry, existing city (e.g. Toronto dentist) | ~10 | ~$0.32 | ~$117 |
| New industry + new city (e.g. Ottawa dentist) | ~20 | ~$0.64 | ~$234 |
| **New industry + 5 cities** (worst case: expand to a whole new vertical) | ~50 | ~$1.60 | ~$584 |

After auto-pause kicks in (~10 days), these numbers typically drop by 70–80%.

### Scaling to 50 clients

Assume a pessimistic mix: 50 clients across 10 industries, 8 cities, no overlap.
- Cold start: 10 industries × 8 cities × ~10 templates = **800 calls/day = $25.60/day**
- After auto-pause: ~150–200 calls/day = **$4.80–$6.40/day** = **$1,750–$2,336/year**

That's **~$40–$50 per tenant per year** in scan costs at scale — well inside any reasonable SaaS margin.

## Break-even

If Crystallux charges **$200/month/client** ($2,400/year) and has 2 clients, annual revenue is **$4,800**.

| | Annual cost | Annual margin (2 clients) |
|---|---|---|
| v2 | $2,511 | $2,289 |
| **v2.1** | **$467** | **$4,333** |

v2.1 effectively **doubles** gross margin at current client count, and the per-tenant marginal cost of ~$40–$50/year means adding the 50th client still costs less in API fees than one month of that client's subscription.

## Not included in this analysis

- Supabase row/storage/egress (negligible at this volume — well inside the free tier)
- n8n self-hosted compute (fixed cost, not per-scan)
- Claude / LLM costs for downstream enrichment + outreach generation
- Gmail API (free for this volume)
- Google Maps _Place Details_ follow-up calls (not used by this workflow)

The "cost of a scan" in this doc is **only** the Google Maps Text Search call.

## How to verify the savings

After v2.1 has been live for ~2 weeks, run in Supabase SQL Editor:

```sql
-- How many queries are currently paused (cost savings)
SELECT paused, count(*) FROM scan_query_tracker GROUP BY paused;

-- Daily API spend (calls × $0.032)
SELECT
  date_trunc('day', scanned_at) AS day,
  count(*) AS scans,
  round(count(*) * 0.032::numeric, 2) AS usd_spent
FROM scan_log
WHERE workflow_name = 'CLX-B2C-Discovery'
GROUP BY 1
ORDER BY 1 DESC
LIMIT 14;
```

If the USD/day column stabilizes around $1.00–$1.60 after two weeks, v2.1 is working as designed.
