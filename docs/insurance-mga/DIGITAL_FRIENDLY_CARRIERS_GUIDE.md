# Digital-Friendly Canadian Carriers Guide

> Reference for which carriers `clx-mga-insurance-carrier-seed-digital-friendly-v1`
> seeds, and how the `ai_compliance_ready` + `digital_quote_ready` flags map to
> business reality. **Verify business relationships before making production
> marketing claims based on this list.**

## Qualification criteria

- **`ai_compliance_ready=true`** — carrier accepts AI-pre-screened applications
  (eg PolicyMe, Walnut, Intact for personal auto/home). Means the underwriter
  is comfortable with answers gathered via the Crystallux suitability flow
  rather than a human advisor-recorded transcript.
- **`digital_quote_ready=true`** — carrier publishes a quote API or operates a
  partner portal sufficient to retrieve a real-time premium. Tier-1 mutuals
  (Manulife, Sun Life, Canada Life) are generally NOT digital_quote_ready
  even though they have advisor portals — those require a human MGA login.

## Seed roster (8 carriers)

Run `POST /webhook/mga/insurance/carrier-seed` with the `INTERNAL_EMAIL_SECRET`
once after applying `db/migrations/carrier-integration-schema.sql`.

| # | Carrier | Type | AI-ready | Digital quote | Notes |
|---|---|---|---|---|---|
| 1 | **PolicyMe** | life | ✓ | ✓ | Fully-underwritten online term. 2 starter products (Term 10, Term 20). |
| 2 | **Walnut Insurance** | life | ✓ | ✓ | Group term, employer-distribution channel. |
| 3 | **Manulife** | life | — | — | Tier-1 mutual. 3 products: Family Term, Manulife Par (whole), Lifecheque (CI). |
| 4 | **Sun Life** | life | — | — | Tier-1 mutual. 3 products: SunTerm, Sun Par Protector II, Sun CII. |
| 5 | **Canada Life** | life | — | — | Tier-1 mutual. 3 products: My Term, Wealth Achiever Plus, LifeAdvance CI. |
| 6 | **iA Financial** | life | — | ✓ | 2 products: Pick-A-Term, Genesis IUL. |
| 7 | **Intact** | p_and_c | ✓ | ✓ | Personal lines. 3 products: Auto, Homeowners, Tenant. |
| 8 | **Aviva Canada** | p_and_c | — | ✓ | 2 products: Auto, Ovation Home. |

## Province licensing (seed defaults)

All carriers seeded with province coverage matching their public licensing as of
2026-Q1. Update via the `carrier-create` workflow if a carrier expands or
withdraws from a province.

## Adding a non-seed carrier

```bash
curl -X POST https://automation.crystallux.org/webhook/mga/insurance/carrier-create \
  -H "Authorization: Bearer <mga_principal_session_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "carrier_name": "Empire Life",
    "carrier_code": "EMPIRE",
    "carrier_type": "life",
    "province_licensed": ["ON","BC","AB","QC","MB","SK","NS","NB"],
    "ai_compliance_ready": false,
    "digital_quote_ready": false,
    "contact_email": "broker.support@empire.ca"
  }'
```

Then add products via `/webhook/mga/insurance/carrier-product-create`.

## Re-seeding

Safe — the seed workflow uses `Prefer: resolution=ignore-duplicates` and a
`UNIQUE(vertical_id, carrier_name)` constraint. Running it twice does not
create duplicate carriers or products.

## What the recommendation engine v2 sees

By default, `clx-mga-insurance-policy-recommendation-engine-v2` filters with
`WHERE active=true AND ai_compliance_ready=true`. From the seed roster that
narrows ranking candidates to **PolicyMe, Walnut, and Intact**. To include
tier-1 mutuals in the ranking pool, set their `ai_compliance_ready=true` only
after confirming the underwriter accepts AI-pre-screened applications.

This is the right default: v2 prevents an advisor from recommending a tier-1
mutual's product through an AI-only flow when the carrier requires a human
advisor in the underwriting loop.
