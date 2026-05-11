# Carrier Integration Architecture (Layer 2 — Insurance MGA)

> Foundation for moving the policy recommendation engine from a
> hardcoded 7-product static matrix to a real carriers + products
> catalog. Every table carries `vertical_id='insurance'`.

## Why

`clx-mga-insurance-policy-recommendation-engine-v1` shipped with a
static `products` object embedded in a Code node (Phase 5 MVP). That
worked to validate the Claude ranking pattern, but it cannot scale:
adding a carrier means editing a workflow. v2 swaps that matrix for
a Supabase query against `carrier_products`.

## Tables (db/migrations/carrier-integration-schema.sql)

| Table | Purpose |
|---|---|
| `insurance_carriers` | Per-MGA roster of carriers. Tracks province licensing, AI-readiness, digital-quote-readiness, API endpoint when applicable. |
| `carrier_products` | Catalog rows. Each product belongs to a carrier and has coverage range, base premium, underwriting age range, commission %, feature tags. `ai_compliance_ready` flag gates which products v2 ranks. |
| `carrier_integrations` | Per-MGA-client config: `integration_type` ∈ {manual, email, api, portal}. `credentials_encrypted` holds AES-256-GCM ciphertext for api/portal integrations. |
| `carrier_quotes` | Every quote, manual or API-sourced. Status lifecycle: pending → received → expired / bound / declined. |

All tables: `vertical_id text NOT NULL DEFAULT 'insurance'`.

## Workflows (workflows/api/insurance-mga/)

| Workflow | Webhook | Role |
|---|---|---|
| `clx-mga-insurance-carrier-create-v1` | POST `/webhook/mga/insurance/carrier-create` | mga_principal / admin |
| `clx-mga-insurance-carrier-product-create-v1` | POST `/webhook/mga/insurance/carrier-product-create` | mga_principal / admin |
| `clx-mga-insurance-carriers-list-v1` | POST `/webhook/mga/insurance/carriers-list` | any insurance role |
| `clx-mga-insurance-quote-engine-v1` | POST `/webhook/mga/insurance/quote-engine` | advisor or higher |
| `clx-mga-insurance-quote-manual-v1` | POST `/webhook/mga/insurance/quote-manual` | advisor or higher |
| `clx-mga-insurance-quote-api-v1` | POST `/webhook/mga/insurance/quote-api` | advisor or higher (STUB until per-carrier APIs land) |
| `clx-mga-insurance-product-compare-v1` | POST `/webhook/mga/insurance/product-compare` | any insurance role |
| `clx-mga-insurance-carrier-seed-digital-friendly-v1` | POST `/webhook/mga/insurance/carrier-seed` | INTERNAL_EMAIL_SECRET |
| `clx-mga-insurance-policy-recommendation-engine-v2` | POST `/webhook/mga/insurance/policy-recommend-v2` | INTERNAL_EMAIL_SECRET |

Pattern matches the rest of Layer 2: session-token auth, role allowlist, `vertical_id='insurance'` in queries, `regulatory_audit_log` write on principal-only mutations, `JSON.stringify` on responseBody. Seed workflow uses `INTERNAL_EMAIL_SECRET` + `Prefer: resolution=ignore-duplicates` for idempotency.

## v1 → v2 upgrade rationale

v1 stays in repo (DEACTIVATED) as fallback until v2 proves out in production. **The Claude prompt is identical between versions** — only the source of the `available_products` list changes:

- **v1 (lines 30-89):** hardcoded `products` object inline.
- **v2 (new node):** `GET /carrier_products?vertical_id=eq.insurance&product_type=eq.<t>&active=eq.true&ai_compliance_ready=eq.true` — bounds Claude context by pre-filtering to AI-ready products only.

If v2 returns `_no_products: true` (empty catalog for that product_type), responds 422 with a hint to seed first.

## quote-engine dispatch matrix

`carrier_integrations.integration_type` determines fan-out:

| Type | Behavior |
|---|---|
| `manual` | Principal manually enters quote via `quote-manual` once received by phone/email. |
| `email` | Flagged for ops queue (out of scope v1 — falls through to manual). |
| `api` | Routes through `quote-api` (stub returns 202 + logs pending row). |
| `portal` | Out of scope — falls through to manual. |

The engine **pre-seeds a pending `carrier_quotes` row per carrier_id** so the principal dashboard surfaces them immediately. Status flips to `received` once a real quote lands.

## Frontend wiring

- `principal/carriers.html` → `clxApi.mgaPost('carriers-list')`.
- `principal/products.html` → same call, flatten products.
- `advisor/product-comparison.html` → `clxApi.mgaPost('product-compare', { product_ids })`.
- Suitability interview (existing flow) → calls `policy-recommend-v2` once a client opts in to v2.

## Roadmap

- **Per-carrier API adapters:** `quote-api` is currently a stub. Phase 6+ adds dedicated workflows for the carriers with public APIs (PolicyMe, Walnut, Intact digital quote).
- **Email-parsed quotes:** ingest carrier email replies, parse PDF/HTML, populate `carrier_quotes` automatically.
- **Bind workflow:** quote → application → e-sign → bound flow with carrier_quotes.status = 'bound' atomic transition.
- **Multi-vertical reuse:** mortgage carriers, group benefits providers — same schema, different `vertical_id`. Workflows fork only if the dispatch matrix differs.
