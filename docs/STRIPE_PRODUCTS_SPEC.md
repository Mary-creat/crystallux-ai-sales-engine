# Stripe Products Specification

**Purpose:** one-to-one mapping from vertical pricing (Phase 1 migration) to Stripe Products + Prices Mary must create in Live mode before day 7 of the 14-day sprint.

**Currency:** CAD (Canadian dollars).
**Tax:** GST/HST via Stripe Tax (auto-calculated per province).
**Billing period:** monthly, billed in advance.
**Trial:** 14 days default on every product (aligns with `clx-stripe-provision-v1` default).

---

## How to create in Stripe Dashboard

1. Go to **Products** → **Add product**.
2. Use the **Product name** and **Description** from the table below.
3. **Pricing:** Standard pricing → Recurring → Monthly → CAD → amount from the **Price (CAD)** column.
4. **Pricing tax behavior:** "Exclusive" (tax added on top, standard for B2B SaaS).
5. **Metadata:** add the key-value pairs from the **Metadata** column — the webhook router in `clx-stripe-webhook-v1` reads `selected_plan` + `vertical` to route events correctly.
6. After creating each Price, copy its **Price ID** (starts with `price_`) into `.env` under the matching variable name.

---

## Product catalog

### 1. Crystallux Consulting Founding
- **Price (CAD):** $1,997 / month
- **Billing:** Monthly, in advance
- **Tax behavior:** Exclusive (GST/HST added via Stripe Tax)
- **Trial:** 14 days
- **Metadata:**
  - `selected_plan` = `founding_1997`
  - `vertical` = `consulting`
  - `tier` = `founding`
  - `founding_lock_months` = `12`
- **Env var:** `STRIPE_PRICE_FOUNDING_1997`
- **Description (customer-facing):**
  > "Crystallux for consulting practices. 20 qualified discovery calls per month with decision-makers. 14-day trial. Guarantee: 10 qualified meetings in your first 30 days or month free. Founding pricing locked for 12 months."

### 2. Crystallux Consulting Standard (post-founding retail)
- **Price (CAD):** $2,497 / month
- **Metadata:**
  - `selected_plan` = `standard_2497`
  - `vertical` = `consulting`
  - `tier` = `standard`
- **Env var:** `STRIPE_PRICE_STANDARD_2497`
- **Description:**
  > "Crystallux for consulting practices — retail pricing after founding-client window. 20 qualified discovery calls per month."

### 3. Crystallux Consulting Growth Pro
- **Price (CAD):** $3,997 / month
- **Metadata:**
  - `selected_plan` = `consulting_growth_3997`
  - `vertical` = `consulting`
  - `tier` = `growth_pro`
- **Env var:** `STRIPE_PRICE_CONSULTING_GROWTH_3997`
- **Description:**
  > "Crystallux Consulting Growth Pro: lead gen + automated follow-up + proposal-request templates + monthly strategy review."

### 4. Crystallux Real Estate Founding
- **Price (CAD):** $1,497 / month
- **Metadata:**
  - `selected_plan` = `real_estate_founding_1497`
  - `vertical` = `real_estate`
  - `tier` = `founding`
  - `founding_lock_months` = `12`
- **Env var:** `STRIPE_PRICE_REAL_ESTATE_FOUNDING_1497`
- **Description:**
  > "Crystallux for real estate agents and brokers. 15 qualified seller listing appointments per month. Guarantee: 5 listing appointments in first 30 days or month free. Founding pricing locked for 12 months."

### 5. Crystallux Real Estate Growth Pro
- **Price (CAD):** $2,997 / month
- **Metadata:**
  - `selected_plan` = `real_estate_growth_2997`
  - `vertical` = `real_estate`
  - `tier` = `growth_pro`
- **Env var:** `STRIPE_PRICE_REAL_ESTATE_GROWTH_2997`
- **Description:**
  > "Crystallux Real Estate Growth Pro: lead gen + automated listing-appointment booking + buyer-lead nurture + monthly market heat map."

### 6. Crystallux Construction Founding
- **Price (CAD):** $1,497 / month
- **Metadata:**
  - `selected_plan` = `construction_1497`
  - `vertical` = `construction`
  - `tier` = `founding`
  - `founding_lock_months` = `12`
- **Env var:** `STRIPE_PRICE_CONSTRUCTION_1497`
- **Description:**
  > "Crystallux for construction and general contractors. 20 qualified reno leads per month. Guarantee: 10 leads in first 30 days or month free. Founding pricing locked for 12 months."

### 7. Crystallux Construction Growth
- **Price (CAD):** $3,497 / month
- **Metadata:**
  - `selected_plan` = `construction_growth_3497`
  - `vertical` = `construction`
  - `tier` = `growth`
- **Env var:** `STRIPE_PRICE_CONSTRUCTION_GROWTH_3497`
- **Description:**
  > "Crystallux Construction Growth: lead gen + automated follow-up + SMS reminders + booking pipeline + monthly pipeline report."

### 8. Crystallux Dental Founding
- **Price (CAD):** $1,497 / month
- **Metadata:**
  - `selected_plan` = `dental_founding_1497`
  - `vertical` = `dental`
  - `tier` = `founding`
  - `founding_lock_months` = `12`
- **Env var:** `STRIPE_PRICE_DENTAL_FOUNDING_1497`
- **Description:**
  > "Crystallux for dental practices. 30 qualified new-patient consults per month. Guarantee: 15 booked consults in first 30 days or month free. Compliance-reviewed templates per province. Founding pricing locked for 12 months."

### 9. Crystallux Dental Growth Pro
- **Price (CAD):** $2,997 / month
- **Metadata:**
  - `selected_plan` = `dental_growth_2997`
  - `vertical` = `dental`
  - `tier` = `growth_pro`
- **Env var:** `STRIPE_PRICE_DENTAL_GROWTH_2997`
- **Description:**
  > "Crystallux Dental Growth Pro: lead gen + recall automation + treatment-plan follow-up + Google review automation + monthly practice growth report."

### 10. Crystallux Insurance Broker Founding (existing, keep in sync)
- **Price (CAD):** $1,997 / month
- **Metadata:**
  - `selected_plan` = `insurance_broker_founding_1997`
  - `vertical` = `insurance_broker`
  - `tier` = `founding`
  - `founding_lock_months` = `12`
- **Env var:** `STRIPE_PRICE_INSURANCE_BROKER_FOUNDING_1997`
- **Description:**
  > "Crystallux for insurance brokers. 20 qualified renewal-season discovery calls per month. Canadian-compliant outreach. Founding pricing locked for 12 months."

### 11. Crystallux Intelligence Tier Upgrade (future B.9 — reserved)
- **Price (CAD):** $2,000 / month (add-on)
- **Metadata:**
  - `selected_plan` = `intelligence_3997`
  - `vertical` = `any`
  - `tier` = `intelligence_addon`
- **Env var:** `STRIPE_PRICE_INTELLIGENCE_3997`
- **Description:**
  > "Crystallux Market Intelligence tier. Signal-driven campaign scaling: wildfires, interest rates, regulatory changes, seasonal triggers. +$2,000/month on top of your existing plan. Available Q2 2026."

---

## Products NOT to create yet (inactive verticals)

Do not provision Stripe products for:
- **legal** (inactive until founder-client catalyst, compliance work required)
- **moving_services** (inactive until operating leverage proven)
- **cleaning_services** (inactive until operating leverage proven)

Create those products in Live mode only when the vertical is activated in `niche_overlays` (is_active=true).

---

## `.env` snippet to copy after creation

```bash
# Founding tier prices (month-1 client acquisition)
STRIPE_PRICE_CONSULTING_FOUNDING_1997=price_...
STRIPE_PRICE_REAL_ESTATE_FOUNDING_1497=price_...
STRIPE_PRICE_CONSTRUCTION_1497=price_...
STRIPE_PRICE_DENTAL_FOUNDING_1497=price_...
STRIPE_PRICE_INSURANCE_BROKER_FOUNDING_1997=price_...

# Standard / retail (post-founding-window)
STRIPE_PRICE_STANDARD_2497=price_...

# Growth tier upsells
STRIPE_PRICE_CONSULTING_GROWTH_3997=price_...
STRIPE_PRICE_REAL_ESTATE_GROWTH_2997=price_...
STRIPE_PRICE_CONSTRUCTION_GROWTH_3497=price_...
STRIPE_PRICE_DENTAL_GROWTH_2997=price_...

# Intelligence tier addon (reserved — Q2 2026)
STRIPE_PRICE_INTELLIGENCE_3997=price_...
```

**Note:** env var names have diverged slightly from the earlier `MARY_ACTIVATION_CHECKLIST.md` draft (which used generic plan keys like `STRIPE_PRICE_FOUNDING_1997`). Harmonise the checklist or the `clx-stripe-provision-v1` PLAN_ENV_MAP at the point of activation — whichever Mary prefers. The canonical naming is the per-vertical form above.

---

## Stripe Tax setup (critical, one-time)

1. **Dashboard → Settings → Tax → Enable Stripe Tax** for your registered jurisdictions (minimum: all provinces where Crystallux clients operate, initially Ontario + BC + Alberta + Quebec).
2. Upload your BN / HST registration.
3. Set **tax behavior** on every price as "Exclusive" — tax is added on top of the listed price, standard for B2B SaaS in Canada.
4. Verify first test invoice shows GST/HST line correctly (5% federal + provincial).

---

## Stripe Customer Portal setup (for the welcome email link)

1. **Dashboard → Settings → Billing → Customer Portal → Configure**.
2. Enable:
   - Update payment method
   - Cancel subscription (with confirmation step — soft-land cancellations)
   - View invoice history
   - Update business address
3. Copy the portal base URL and update the placeholder in `clx-stripe-provision-v1` Build Welcome Email node:
   ```js
   // BEFORE
   const portalUrl = 'https://billing.stripe.com/p/login/PLACEHOLDER_PORTAL_URL';
   // AFTER (use actual URL from Stripe Dashboard → Customer Portal)
   const portalUrl = 'https://billing.stripe.com/p/login/YOUR_ACTUAL_PORTAL_SESSION_URL';
   ```
4. Same placeholder exists in `docs/dashboard/index.html` — search for `PLACEHOLDER_PORTAL_URL` and replace.

---

## Webhook endpoint configuration (day 7 of sprint)

1. **Dashboard → Developers → Webhooks → Add endpoint**.
2. **Endpoint URL:** `https://automation.crystallux.org/webhook/stripe`
3. **Events to send:**
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.paid`
   - `invoice.payment_succeeded`
   - `invoice.payment_failed`
4. Copy the **Signing secret** (whsec_...) to `.env` as `STRIPE_WEBHOOK_SECRET`.

---

## Verification after product creation

In Stripe Dashboard → Products, confirm:
- 10 products visible (excluding Intelligence which is reserved)
- Each with a recurring monthly CAD price
- Each with correct metadata: `selected_plan`, `vertical`, `tier`
- 14-day trial set on each
- Tax behavior "Exclusive"

Run this curl against `clx-stripe-provision-v1` after setup to confirm end-to-end:

```bash
curl -X POST https://automation.crystallux.org/webhook/clx-stripe-provision \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "<existing-test-client-uuid>",
    "client_email": "test@crystallux.org",
    "business_name": "Test Business",
    "selected_plan": "founding_1997"
  }'
```

Expect: new Stripe Customer + Subscription visible in Dashboard, `clients` row updated with stripe_customer_id + subscription_status='trialing', welcome email in TESTING MODE inbox.
