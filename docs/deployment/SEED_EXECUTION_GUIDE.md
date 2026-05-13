# Seed Workflow Execution Guide

> **Status:** documents the 4 critical Layer 2 seed workflows + the underlying n8n env-access gotcha that causes the "HTTP 200 with empty body, zero rows inserted" symptom seen during 2026-05-13 deployment.

## TL;DR — fix the empty-body-200 issue in one step

Add this line to `/root/crystallux/n8n/.env` on the VPS:

```
N8N_BLOCK_ENV_ACCESS_IN_NODE=false
```

Restart the n8n container:

```bash
cd /root/crystallux/n8n
docker compose -f docker-compose.prod.yml restart n8n
# (or: docker restart n8n)
```

That's it. Re-run the seed curls below. They should now return JSON bodies + actually insert rows.

---

## Root-cause diagnosis (why empty 200 happens)

All 5 INTERNAL_EMAIL_SECRET seeds use this pattern inside an n8n **Code node**:

```js
const body = $input.item.json.body || {};
const expected = process.env.INTERNAL_EMAIL_SECRET || '';
if (!body.internal_secret || body.internal_secret !== expected) {
  return { json: { _unauthorized: true, status: 401 } };
}
// …seed rows…
return { json: { _authorized: true, rows } };
```

In **n8n 1.0+**, `process.env` (and `$env`) access from **Code nodes** is blocked by default. The setting that controls it is `N8N_BLOCK_ENV_ACCESS_IN_NODE`, default `true`.

What happens when the env var is set in the container but `N8N_BLOCK_ENV_ACCESS_IN_NODE` is left at its default:

1. Webhook receives the POST → passes to Code node.
2. Code node tries to read `process.env.INTERNAL_EMAIL_SECRET` → **n8n throws** (`process.env.* is restricted…`).
3. The Code node fails. Workflow halts at that node.
4. With `responseMode: responseNode`, n8n waits for a `respondToWebhook` node to fire. None ever does (the auth node crashed before reaching the IF branch).
5. n8n's webhook returns **200 with empty body** (its default for halted-without-response executions).

Mary's symptoms exactly:

- `INTERNAL_EMAIL_SECRET` set in `/root/crystallux/n8n/.env` ✓
- Container loaded the env var ✓ (this is what container envsubst does)
- Workflow imported + activated ✓
- `curl` returns HTTP 200 ✓
- Response body empty ✓
- Database has zero rows ✓

The env var is **in the container** (so HTTP nodes can use `={{ $env.X }}` in their parameters), but the **Code-node sandbox** is gated by a separate setting.

**Confirm the fix took:** after restarting, the n8n executions log will show the Code node succeeding instead of throwing.

---

## The 4 critical seeds Mary needs to run

After the env-access fix above lands, run these in order. Each accepts an `internal_secret` in the JSON body and writes to a different Supabase table.

### 1. Carrier seed (digital-friendly carriers + starter products)

```bash
SECRET='<paste-INTERNAL_EMAIL_SECRET-here>'

curl -X POST \
  -H "Content-Type: application/json" \
  -d "{\"internal_secret\":\"$SECRET\"}" \
  https://automation.crystallux.org/webhook/mga/insurance/carrier-seed
```

**Expected response:**
```json
{ "ok": true, "carriers_seeded": 8, "products_seeded": 16 }
```

**Verification SQL** (run in Supabase Studio → SQL editor):
```sql
SELECT count(*) AS carriers FROM insurance_carriers WHERE vertical_id = 'insurance';
-- expect: 8

SELECT count(*) AS products FROM carrier_products WHERE vertical_id = 'insurance';
-- expect: ~16 (some carriers have 2 products, some 3)

SELECT carrier_name, carrier_type, ai_compliance_ready, digital_quote_ready
FROM insurance_carriers
WHERE vertical_id = 'insurance'
ORDER BY carrier_name;
-- expect: Aviva Canada, Canada Life, Intact, iA Financial, Manulife, PolicyMe, Sun Life, Walnut Insurance
```

**Schema written:** `insurance_carriers`, `carrier_products`.

**Workflow path:** `workflows/api/insurance-mga/clx-mga-insurance-carrier-seed-digital-friendly-v1.json`
**Webhook:** `POST /webhook/mga/insurance/carrier-seed`
**Auth:** `internal_secret` in JSON body, matched against `INTERNAL_EMAIL_SECRET` env var.

---

### 2. Content library seed (20 insurance content topic templates)

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{\"internal_secret\":\"$SECRET\"}" \
  https://automation.crystallux.org/webhook/mga/insurance/content-library-seed
```

**Expected response:**
```json
{ "ok": true, "vertical_id": "insurance", "templates_seeded": 20 }
```

**Verification SQL:**
```sql
SELECT count(*) AS templates FROM insurance_content_templates WHERE vertical_id = 'insurance';
-- expect: 20

SELECT topic_category, count(*)
FROM insurance_content_templates
WHERE vertical_id = 'insurance'
GROUP BY topic_category
ORDER BY topic_category;
-- expect rows across: life_insurance_basics, critical_illness, disability,
-- estate_planning, business_insurance, mortgage_protection, retirement, health_benefits
```

**Schema written:** `insurance_content_templates`.

**Workflow path:** `workflows/api/insurance-mga/clx-mga-insurance-content-library-seed-v1.json`
**Webhook:** `POST /webhook/mga/insurance/content-library-seed`
**Auth:** `internal_secret` in JSON body.

---

### 3. Training topics seed (12 insurance-specific training topics)

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{\"internal_secret\":\"$SECRET\"}" \
  https://automation.crystallux.org/webhook/mga/insurance/training-topics-seed
```

**Expected response:**
```json
{ "ok": true, "vertical_id": "insurance", "topics_seeded": 12 }
```

**Verification SQL:**
```sql
SELECT count(*) AS topics FROM training_topics WHERE vertical_id = 'insurance';
-- expect: 12

SELECT topic_category, count(*)
FROM training_topics
WHERE vertical_id = 'insurance'
GROUP BY topic_category
ORDER BY topic_category;
-- expect: compliance (4-5), product_knowledge (2), objection_handling (1),
-- discovery (1), follow_up (1), closing (1), sales_psychology (1)
```

**Schema written:** `training_topics` (Layer 1 table with `vertical_id='insurance'` rows).

**Workflow path:** `workflows/api/insurance-mga/clx-mga-insurance-training-topics-seed-v1.json`
**Webhook:** `POST /webhook/mga/insurance/training-topics-seed`
**Auth:** `internal_secret` in JSON body.

---

### 4. Onboarding curriculum seed (30-day advisor curriculum)

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{\"internal_secret\":\"$SECRET\"}" \
  https://automation.crystallux.org/webhook/mga/insurance/onboarding-curriculum-seed
```

**Expected response:**
```json
{ "ok": true, "vertical_id": "insurance", "days_seeded": 30 }
```

**Verification SQL:**
```sql
SELECT count(*) AS days FROM insurance_onboarding_curriculum WHERE vertical_id = 'insurance';
-- expect: 30

SELECT day_number, module_title, estimated_minutes
FROM insurance_onboarding_curriculum
WHERE vertical_id = 'insurance'
ORDER BY day_number;
-- expect 30 rows: Days 1-3 licensing/E&O/MGA agreement, Days 4-7 compliance,
-- Days 8-14 product training, Days 15-21 sales conversations,
-- Days 22-28 application process, Days 29-30 first client + signoff
```

**Schema written:** `insurance_onboarding_curriculum`.

**Workflow path:** `workflows/api/insurance-mga/clx-mga-insurance-onboarding-curriculum-seed-v1.json`
**Webhook:** `POST /webhook/mga/insurance/onboarding-curriculum-seed`
**Auth:** `internal_secret` in JSON body.

---

## Bonus seed — report templates (Session 3 Layer 2)

The 5th seed mentioned in Session 3's deployment notes, also affected by the same `process.env` gotcha:

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{\"internal_secret\":\"$SECRET\"}" \
  https://automation.crystallux.org/webhook/mga/insurance/report-template-seed
```

**Expected:** `{ "ok": true, "vertical_id": "insurance", "templates_seeded": 6 }`

**Verification:** `SELECT count(*) FROM production_report_templates WHERE vertical_id = 'insurance';` → 6.

---

## Common failure modes — pattern → cause → fix

### Symptom: HTTP 200, empty body, zero rows inserted

**Most likely cause:** the `N8N_BLOCK_ENV_ACCESS_IN_NODE` issue documented above.

**Verify:** open n8n UI → Executions → click the most-recent execution for the seed workflow. If the **Build Seeds** (or **Build Seed Data**) node shows a red error icon with a message like `process.env.* is restricted` or similar, this is the cause.

**Fix:** add `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` to `/root/crystallux/n8n/.env`, restart the container.

---

### Symptom: HTTP 401, `{"ok":false,"error":"Unauthorized"}`

**Cause:** the `internal_secret` you sent doesn't match the `INTERNAL_EMAIL_SECRET` env var inside the container.

**Verify:**
```bash
# On the VPS, confirm the var is loaded inside the running container:
docker exec n8n printenv INTERNAL_EMAIL_SECRET
```

If the output is empty → the env var isn't being passed through. Check `docker-compose.prod.yml` has `env_file: .env` or `environment: { INTERNAL_EMAIL_SECRET: "${INTERNAL_EMAIL_SECRET}" }`. Recreate the container after fixing.

If the output matches what you're sending in curl → check for trailing whitespace, hidden characters, or quote mismatches.

---

### Symptom: HTTP 404, "Webhook not found"

**Cause:** the workflow is imported but **not activated**.

**Fix:** open n8n UI → find the workflow by name → toggle Active in the top-right. The webhook path only registers when the workflow is active.

---

### Symptom: HTTP 500 or n8n error in execution log

**Likely cause:** the workflow's Supabase credential (`Supabase Crystallux Custom`) is not configured, or its API key / URL is wrong.

**Verify:** n8n UI → Credentials → confirm `Supabase Crystallux Custom` exists with:
- Type: `httpCustomAuth`
- Header name: `apikey`
- Header value: the Supabase **service-role** key (NOT anon key — service role is required to bypass RLS for seed writes).

The same credential must also send the `Authorization: Bearer <service-role-key>` header. The fastest setup:
- Credential name: `Supabase Crystallux Custom`
- Headers JSON:
```json
{
  "apikey": "<SUPABASE_SERVICE_ROLE_KEY>",
  "Authorization": "Bearer <SUPABASE_SERVICE_ROLE_KEY>"
}
```

---

### Symptom: HTTP 200 with body `{ "ok": true, "carriers_seeded": 0 }` (returns OK but zero rows)

**Cause:** the Code node ran, but the downstream Supabase INSERT silently failed. This usually means RLS is blocking the insert (you're using anon key instead of service-role key) or the table doesn't exist.

**Verify:**
```sql
-- In Supabase Studio SQL editor:
\d+ insurance_carriers
-- If "relation does not exist", the carrier-integration-schema.sql migration didn't run.

SELECT count(*) FROM insurance_carriers;
-- If this fails with permission error, RLS is on but service-role isn't bypassing it
-- (i.e., you're using anon key in the n8n credential).
```

**Fix:** confirm `db/migrations/carrier-integration-schema.sql` (and similar for the other 3) is applied. Use service-role key in the n8n credential, not anon key.

---

### Symptom: Workflow runs successfully on first call, but second call returns 200 with `carriers_seeded: 0`

**That's correct behavior, not a bug.** The seed workflows use `Prefer: resolution=ignore-duplicates` plus `UNIQUE` constraints. On re-run, all rows are skipped because they already exist. The `carriers_seeded` counter reads from the original `carriers` array length in the Code node, so it reports 8 even on re-runs (it counts what was *attempted*, not what was *newly inserted*). To verify what actually exists, always run the verification SQL.

---

## Verification — full deployment check after all 4 seeds

After running all 4 seeds, this single query confirms everything landed:

```sql
SELECT
  (SELECT count(*) FROM insurance_carriers           WHERE vertical_id = 'insurance')                 AS carriers,
  (SELECT count(*) FROM carrier_products             WHERE vertical_id = 'insurance')                 AS products,
  (SELECT count(*) FROM insurance_content_templates  WHERE vertical_id = 'insurance')                 AS content_templates,
  (SELECT count(*) FROM training_topics              WHERE vertical_id = 'insurance')                 AS training_topics,
  (SELECT count(*) FROM insurance_onboarding_curriculum WHERE vertical_id = 'insurance')              AS curriculum_days;
```

**Expected result:**
| carriers | products | content_templates | training_topics | curriculum_days |
|---|---|---|---|---|
| 8 | ~16 | 20 | 12 | 30 |

If any column is 0, jump back to the "Common failure modes" section above.

---

## Longer-term fix (next session — not needed for deployment)

The cleanest fix is to refactor each seed so the secret is read from `{{ $env.INTERNAL_EMAIL_SECRET }}` in an **n8n expression** (which is always allowed) inside an **HTTP Request node parameter** or an **IF node condition**, instead of inside a Code node body. Expression-based env access doesn't go through the Code-node sandbox.

A next-session task can refactor the 6 affected workflows to remove the dependency on `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`. Until then, the one-line env-file change above is the working fix.

Affected workflows that would need refactoring later:

- `clx-mga-insurance-carrier-seed-digital-friendly-v1`
- `clx-mga-insurance-content-library-seed-v1`
- `clx-mga-insurance-training-topics-seed-v1`
- `clx-mga-insurance-onboarding-curriculum-seed-v1`
- `clx-mga-insurance-report-template-seed-v1`
- `clx-mga-insurance-video-review-templates-seed-v1`
- `clx-mga-insurance-demo-data-seed-v1` (uses `$env.MARY_MASTER_TOKEN` — same issue, same fix)

The HTTP nodes that already use `={{ $env.ANTHROPIC_API_KEY }}` (e.g., compliance-engine, policy-recommendation, behavioral-classifier) work today because n8n expressions are evaluated outside the Code-node sandbox. The seeds got caught because the auth check happens inside the Code node, not in the HTTP node.

---

## Quick reference — one-shot deploy script

After the env-file fix + container restart, run all 4 seeds in sequence:

```bash
#!/bin/bash
# Run from the VPS or any host with curl + the SECRET handy.

SECRET='<paste-INTERNAL_EMAIL_SECRET>'
BASE='https://automation.crystallux.org/webhook/mga/insurance'

echo "--- Carrier seed ---"
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"internal_secret\":\"$SECRET\"}" \
  "$BASE/carrier-seed"
echo

echo "--- Content library seed ---"
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"internal_secret\":\"$SECRET\"}" \
  "$BASE/content-library-seed"
echo

echo "--- Training topics seed ---"
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"internal_secret\":\"$SECRET\"}" \
  "$BASE/training-topics-seed"
echo

echo "--- Onboarding curriculum seed ---"
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"internal_secret\":\"$SECRET\"}" \
  "$BASE/onboarding-curriculum-seed"
echo

echo "--- (bonus) Report templates ---"
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"internal_secret\":\"$SECRET\"}" \
  "$BASE/report-template-seed"
echo

echo "Done. Run the verification SQL in docs/deployment/SEED_EXECUTION_GUIDE.md."
```

Save as `seed-all.sh`, `chmod +x seed-all.sh`, run once. Should complete in under 30 seconds.
