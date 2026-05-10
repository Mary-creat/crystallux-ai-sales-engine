# Multi-Vertical Layer 2 Architecture (vertical_id strategy)

> **Audience:** any engineer building a future Layer 2 vertical module on top of this foundation.

## Why vertical_id everywhere

Crystallux is a multi-vertical platform. Layer 1 (the AI Sales Agent + behavioral intelligence + video pipeline) is universal — same engine serves insurance, mortgage, real estate, dental, construction, consulting, etc.

Layer 2 (regulated operations: MGA / brokerage / agency hierarchy / commissions / compliance) is **vertical-specific** because each vertical has its own regulator, its own KYC requirements, its own suitability surface, its own disclosure obligations.

We chose **column-level vertical tagging** (every Layer 2 table carries `vertical_id text NOT NULL DEFAULT 'insurance'`) over **per-vertical schema duplication** for one decisive reason:

> **Cross-vertical reporting and observability without schema joins across N parallel-shape tables.** Mary will run `SELECT count(*) FROM compliance_reviews WHERE status='human_review_required'` to see compliance backlog across ALL verticals — insurance, mortgage, real estate — in a single query. Without column-level tagging this becomes a UNION across N tables that diverge over time.

## Valid vertical_id values

| Value | Phase | Regulator(s) | Status |
|---|---|---|---|
| `insurance` | 5 (this build) | FSRA Ontario, PIPEDA, CASL, FINTRAC | **active in this commit** |
| `mortgage` | 7 (future) | FSRA mortgage broker rules, FINTRAC | reserved |
| `real_estate` | 8 (future) | RECO (Ontario), provincial equivalents | reserved |
| `investment` | 9 (future) | MFDA, IIROC | reserved (separate licensing tier) |
| `group_benefits` | 10 (future) | provincial insurance regulators | reserved |
| `commercial_insurance` | 11 (future) | FSRA Ontario commercial line | reserved (distinct from personal insurance) |

This list is the canonical enumeration. Adding a new vertical = adding a row here + the corresponding workflow + template module. **No schema migration required.**

## Required tagging on every new Layer 2 table

```sql
CREATE TABLE IF NOT EXISTS <table_name> (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id text NOT NULL DEFAULT '<your_vertical>',
  -- ... rest of schema
);

CREATE INDEX IF NOT EXISTS idx_<table_name>_vertical
  ON <table_name>(vertical_id);
```

The `_vertical` index is mandatory — every Layer 2 query filters by `vertical_id` and the partition is the most-selective predicate in production once multiple verticals are live.

## Required tagging on every new Layer 2 workflow

1. **Webhook URL includes vertical:** `/webhook/mga/<vertical>/<action>` (e.g. `/webhook/mga/insurance/compliance-review`, `/webhook/mga/mortgage/kyc-start`)
2. **All `INSERT` statements explicitly set `vertical_id`:** never rely on the column DEFAULT — make the value explicit in the JSON body so it's grep-able and can't drift if the DEFAULT changes later
3. **All `SELECT` queries filter `WHERE vertical_id='<vertical>'`:** even if a workflow is single-vertical today, the filter prevents cross-vertical bleed when verticals share tables
4. **All `UPDATE` / `PATCH` statements include the `vertical_id` filter:** `WHERE id=$1 AND vertical_id='<vertical>'` — defence in depth

The full pattern is enforced in code review by greppable conventions:

```bash
# Every Layer 2 workflow JSON should match:
grep -l "/mga/insurance/" workflows/api/insurance-mga/*.json    # webhook tagging
grep -l "vertical_id" workflows/api/insurance-mga/*.json        # query/insert tagging
```

## How a new vertical plugs in (Layer 2 Part 7 example: mortgage MGA)

1. **Reserve `vertical_id = 'mortgage'` in this doc** (already done — see table above).
2. **Create `db/migrations/mortgage-mga-schema.sql`** that adds *only mortgage-specific tables* (e.g. `mortgage_credit_pulls`, `mortgage_lender_recommendations`). Reuse the universal Layer 2 tables created in this build by inserting rows with `vertical_id='mortgage'` — no schema duplication.
3. **Create workflows in `workflows/api/mortgage-mga/`** following the same naming pattern (`clx-mga-mortgage-<action>-v1.json`) and tagging conventions.
4. **Create disclosure templates in `documents/templates/mortgage/`** — same template-id pattern as insurance.
5. **Add mortgage archetype seed workflow** mirroring `clx-archetype-seed-insurance-v1.json` from commit 25c0886.
6. **Document mortgage-specific regulatory framework** in `docs/mortgage-mga/REGULATORY_FRAMEWORK.md` (FSRA mortgage broker rules + FINTRAC).
7. **Add mortgage clients via `auth_users.user_role='advisor'` + `clients.niche_name='mortgage'`** — existing role schema (commit 6bd51c7) handles this without changes.

**No schema migration required for the universal Layer 2 tables** (compliance_reviews, kyc_verifications, suitability_assessments, policy_recommendations, compliance_disclosures, regulatory_audit_log, policy_applications). The `vertical_id` tag does the partition.

## Tables shared across all Layer 2 verticals

These tables created in `insurance-mga-schema.sql` are **universal Layer 2 infrastructure** — every future vertical writes to them with its own `vertical_id`:

- `compliance_reviews`
- `kyc_verifications`
- `suitability_assessments`
- `policy_recommendations` *(name is insurance-flavored but the structure works for mortgage product recommendations, group benefit selections, etc. — Phase 7 may add per-vertical view aliases for ergonomics)*
- `compliance_disclosures`
- `regulatory_audit_log`
- `policy_applications` *(same naming caveat as policy_recommendations)*

Tables that are PER-VERTICAL (only insurance-specific data, no other vertical needs them):

- *None in this build.* All seven tables above are designed to be vertical-agnostic via the `vertical_id` partition + jsonb fields for vertical-specific shape (e.g. `application_data jsonb` holds different field shapes per carrier per vertical without schema change).

If a future vertical genuinely cannot fit into the universal tables — e.g. real estate brokerage requires an `mls_listings` table that has no analog in insurance — that table goes into `db/migrations/real-estate-mga-schema.sql` as vertical-specific. The default position is to extend the universal tables via jsonb; the exception is when the data model genuinely diverges.

## Reporting patterns enabled

```sql
-- Cross-vertical compliance backlog
SELECT vertical_id, count(*) AS pending
  FROM compliance_reviews
  WHERE status = 'human_review_required'
  GROUP BY vertical_id
  ORDER BY pending DESC;

-- Per-vertical KYC pass rate
SELECT vertical_id,
       count(*) FILTER (WHERE status = 'verified') * 100.0 / count(*) AS pass_rate_pct
  FROM kyc_verifications
  WHERE created_at > now() - interval '30 days'
  GROUP BY vertical_id;

-- Single-client cross-vertical audit
SELECT vertical_id, event_type, performed_by_role, occurred_at
  FROM regulatory_audit_log
  WHERE client_id = $1
  ORDER BY occurred_at DESC;
```

These queries become impossible without column-level vertical tagging. The architecture pays dividends the day Mary onboards her first mortgage client.

## Anti-patterns to avoid

- ❌ **Adding a new top-level table per vertical** that mirrors compliance_reviews / kyc_verifications etc. The whole point of vertical_id is one universal table set.
- ❌ **Forgetting the `vertical_id` filter in a SELECT.** Cross-vertical bleed is silent and hard to detect. Code review should reject any Layer 2 query without the filter.
- ❌ **Defaulting `vertical_id` to `NULL` or `'unknown'`.** The DEFAULT is `'insurance'` for the current generation of tables; future modules override the DEFAULT in their migration. Never NULL.
- ❌ **Using a table partition (PostgreSQL native partitioning) instead of vertical_id column.** Native partitioning would block cross-vertical reporting and complicate FK relationships. Column-level tagging is the right tool here.

## Cross-references

- This build's vertical (insurance): [`docs/insurance-mga/AI_COMPLIANCE_VISION.md`](../insurance-mga/AI_COMPLIANCE_VISION.md), [`docs/insurance-mga/REGULATORY_FRAMEWORK.md`](../insurance-mga/REGULATORY_FRAMEWORK.md)
- Schema: [`db/migrations/insurance-mga-schema.sql`](../../db/migrations/insurance-mga-schema.sql)
- Roles infrastructure (universal — supports all verticals): [`ROLES.md`](ROLES.md)
- Universal AI Sales Agent (Layer 1, vertical-agnostic): [`docs/agent/AGENT_VISION.md`](../agent/AGENT_VISION.md)
