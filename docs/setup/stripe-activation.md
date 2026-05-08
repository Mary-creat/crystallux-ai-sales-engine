# Stripe activation — step by step

> **Goal:** flip Stripe billing from dormant to live. Both workflows are coded (commit `b5660d1` family). This doc is the human runbook for Mary.

> **Time budget:** 30-45 minutes once you have a Stripe account.

> **Universal multi-vertical note:** the products + prices below cover the platform's universal Pipeline tiers (Starter/Growth/Scale). Per-vertical founding rates (insurance broker $1,997/mo, real estate $1,497/mo, dental $1,497/mo, etc.) are documented separately in [`docs/STRIPE_PRODUCTS_SPEC.md`](../STRIPE_PRODUCTS_SPEC.md). Apply both — universal tiers cover most signups; vertical founding rates lock the founding-window cohort.

---

## Step 1 — Create Stripe account

1. Go to [stripe.com/register](https://stripe.com/register).
2. Sign up with `info@crystallux.org`.
3. Confirm the email; you'll land in **Test mode** by default. **Stay in Test mode for now** — you'll switch to Live after end-to-end smoke test.
4. Complete the business profile (Crystallux, Canada, B2B SaaS).

---

## Step 2 — Create products + prices

In Stripe Dashboard → **Products** → **Add product**. Repeat for each row below.

### Universal tiers

| Product name | Description (customer-facing) | Recurring | Amount (CAD) | Trial | Tax behavior |
|---|---|---|---|---|---|
| **Crystallux Starter** | "10-15 booked meetings/mo. AI lead discovery + email + LinkedIn outreach. Single vertical, single geography. 60-day commit." | monthly | $1,497 | 14 days | exclusive |
| **Crystallux Growth** | "20-30 booked meetings/mo. Adds WhatsApp + voice + video. Up to 3 cities or sub-verticals. Dedicated Slack support. 90-day commit." | monthly | $2,997 | 14 days | exclusive |
| **Crystallux Scale** | "50+ booked meetings/mo. Multi-vertical or national. Behavioral Intelligence add-on included. Weekly strategy calls. 6-month commit." | monthly | $5,997 | 14 days | exclusive |

For each product:
- **Pricing:** Standard pricing → Recurring → Monthly → CAD → amount above.
- **Tax behavior:** Exclusive (tax added on top — standard for B2B SaaS).
- **Trial:** 14 days.
- **Metadata** (under "Additional options"):
  - `selected_plan` = `starter_1497` / `growth_2997` / `scale_5997`
  - `tier` = `starter` / `growth` / `scale`
  - `vertical` = `universal`

After creating each price, **copy the Price ID** (starts with `price_`) — you'll paste them into env vars in Step 5.

### Vertical founding-rate prices (per `docs/STRIPE_PRODUCTS_SPEC.md`)

Same flow as above, with the names + amounts + metadata from the Stripe Products Spec doc. Create the founding rates for whichever verticals you're actively selling into:

- Insurance broker founding ($1,997/mo, 12-mo lock)
- Consulting founding ($1,997/mo, 12-mo lock)
- Real estate founding ($1,497/mo, 12-mo lock)
- Construction founding ($1,497/mo, 12-mo lock)
- Dental founding ($1,497/mo, 12-mo lock)

Skip legal / moving / cleaning until those verticals are activated (per the Spec).

---

## Step 3 — Configure Stripe Tax

Stripe handles GST/HST automatically once configured.

1. Dashboard → **Settings** → **Tax** → **Enable Stripe Tax**.
2. Add registered jurisdictions: minimum **Ontario + BC + Alberta + Quebec**.
3. Upload your **BN / HST registration**.
4. Verify the first test invoice shows GST/HST line correctly (5% federal + provincial portion).

---

## Step 4 — Configure Customer Portal

Lets customers manage their own subscription (update card, cancel, view invoices).

1. Dashboard → **Settings** → **Billing** → **Customer Portal** → **Configure**.
2. Enable:
   - ✓ Update payment method
   - ✓ Cancel subscription (with confirmation step — soft-land cancellations)
   - ✓ View invoice history
   - ✓ Update business address
3. Save. Copy the **Portal session URL** template — it lands in env in Step 5.

---

## Step 5 — Configure webhook endpoint

This is how Stripe events (subscription created/updated, payments succeeded/failed) reach n8n.

1. Dashboard → **Developers** → **Webhooks** → **Add endpoint**.
2. **Endpoint URL:** `https://automation.crystallux.org/webhook/stripe`
3. **Events to send** (subscribe to all 7):
   - `checkout.session.completed`
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `customer.subscription.trial_will_end`
   - `invoice.paid` (also fires `invoice.payment_succeeded`)
   - `invoice.payment_failed`
4. Click **Add endpoint**.
5. Click the new endpoint → reveal **Signing secret** (`whsec_...`) → copy. Goes into env as `STRIPE_WEBHOOK_SECRET`.

---

## Step 6 — Set environment variables on n8n VPS

SSH into the VPS, edit the n8n env (typically `/root/.n8n/.env` or wherever n8n loads from):

```bash
STRIPE_SECRET_KEY=sk_test_...           # from Dashboard → Developers → API keys
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...          # from Step 5
STRIPE_PORTAL_URL=https://billing.stripe.com/p/login/...   # from Step 4

# Universal tier price IDs (from Step 2)
STRIPE_PRICE_STARTER_1497=price_...
STRIPE_PRICE_GROWTH_2997=price_...
STRIPE_PRICE_SCALE_5997=price_...

# Vertical founding-rate prices (subset — only the ones you created)
STRIPE_PRICE_INSURANCE_BROKER_FOUNDING_1997=price_...
STRIPE_PRICE_CONSULTING_FOUNDING_1997=price_...
STRIPE_PRICE_REAL_ESTATE_FOUNDING_1497=price_...
STRIPE_PRICE_CONSTRUCTION_1497=price_...
STRIPE_PRICE_DENTAL_FOUNDING_1497=price_...
```

Restart n8n: `docker restart n8n` (or whatever your start command is).

---

## Step 7 — Re-import workflows

The two Stripe workflows already exist in the repo. They're dormant by default; import + activate:

```bash
# On VPS
cd /root/crystallux-workflows
git pull origin scale-sprint-v1
# If you have the bulk-import script:
bash /tmp/clx-import.sh   # imports + activates all changed workflows
# Or via n8n UI: import workflows/clx-stripe-provision-v1.json + clx-stripe-webhook-v1.json
# Then click "Activate" on each.
```

---

## Step 8 — End-to-end smoke test (Test mode)

1. Open `app.crystallux.org/onboarding/` in an incognito window.
2. Sign in as `testclient@crystallux.org` (per `docs/testing/test-accounts.md`).
3. Click "Choose your plan" → pick **Starter**.
4. You should be redirected to Stripe Checkout.
5. Use Stripe's test card: `4242 4242 4242 4242`, any future expiry, any 3-digit CVC, any postal.
6. Complete payment.
7. Confirm:
   - Stripe Dashboard → Customers shows the new test customer.
   - Stripe Dashboard → Subscriptions shows a trial subscription.
   - Supabase → `clients` row updated with `stripe_customer_id` + `subscription_status='trialing'`.
   - Supabase → `billing_events` row exists for `checkout.session.completed`.
   - The client returns to `/onboarding/` step 4 (welcome) within 5 seconds.
   - Welcome email lands at the test inbox (after Postmark activation — see [`postmark-activation.md`](postmark-activation.md)).

---

## Step 9 — Switch to Live mode

Only after Step 8 passes end-to-end:

1. Stripe Dashboard → top-right toggle → **Live mode**.
2. **Recreate the same products + prices in Live mode** (Stripe doesn't copy from Test). Use the same names + amounts + metadata.
3. Update env vars to use `sk_live_`, `pk_live_`, `whsec_` (live), and the live `price_` IDs.
4. Restart n8n.
5. Re-add the webhook endpoint in Live mode (with the `https://automation.crystallux.org/webhook/stripe` URL again — Stripe maintains separate Test and Live endpoint lists).
6. Smoke-test once with a real card on a $1 trial product (or use the per-vertical founding rate which has 14-day trial — no charge until day 15).

---

## Operational notes

- **Failed payment recovery** is handled by `clx-stripe-webhook-v1` on `invoice.payment_failed` — flips `subscription_status='past_due'` on the client row and triggers the Postmark dunning email.
- **Cancellation flow** — when a customer hits Cancel from the client billing page, `/webhook/billing/cancel` is called (placeholder workflow — build this when needed). Until built, route customers to the Customer Portal which handles cancel correctly.
- **Cancel-at-period-end vs. immediate cancel** — Stripe's default is at-period-end. The dashboard messages "Access continues until {next_billing_date}." That's the behavior we want.
- **Trial ending** — `customer.subscription.trial_will_end` fires 3 days before trial expiry. The webhook should send the Postmark "Trial ending" email; the existing Stripe webhook code already dispatches by event type, just needs the email template wired.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `clx-stripe-provision-v1` returns 401 | `STRIPE_SECRET_KEY` env var missing or wrong | Check Step 6 |
| Webhook returns 400 with "signature mismatch" | `STRIPE_WEBHOOK_SECRET` wrong, or events sent from a different endpoint | Re-copy from Step 5; confirm endpoint URL exactly |
| Customer charged but no subscription row in Supabase | `customer.subscription.created` event not subscribed | Step 5, re-check event list |
| Onboarding wizard step 3 shows "We couldn't start checkout" | Provision workflow not active in n8n, or env vars not set | n8n UI → activate `clx-stripe-provision-v1` + verify env |

## Cross-references

- Workflow source: [`workflows/clx-stripe-provision-v1.json`](../../workflows/clx-stripe-provision-v1.json), [`workflows/clx-stripe-webhook-v1.json`](../../workflows/clx-stripe-webhook-v1.json)
- Pricing canon: [`docs/STRIPE_PRODUCTS_SPEC.md`](../STRIPE_PRODUCTS_SPEC.md)
- Email templates: [`templates/emails/`](../../templates/emails/) (subscription-active, subscription-past-due, subscription-canceled, invoice-receipt)
- Operations runbook: [`docs/operations/PAYMENT_FOLLOW_UP.md`](../operations/PAYMENT_FOLLOW_UP.md)
