# Crystallux — B2B vs B2C Industry Strategy & Enrichment Routing

## The Problem

Crystallux serves both B2B and B2C clients. Each type needs different lead
discovery and email enrichment strategies. Everything previously ran through one
pipeline, which is why Hunter.io (a B2B tool) failed on B2C leads — local
service businesses whose emails live on their own websites, not in Hunter's
domain database.

The fix is to classify leads by `lead_type` (`b2c`, `b2b`, `hybrid`) and route
discovery + enrichment accordingly.

---

## Industry Classification

### B2C Industries — Google Maps Discovery + Website Email Scraper

Local service businesses. Their customers are consumers. The *business itself*
is the lead — we find them and sell to them.

| Industry                   | Product Type       | Discovery   | Email Strategy              | Why                                        |
|----------------------------|--------------------|-------------|-----------------------------|--------------------------------------------|
| Moving services            | moving_services    | Google Maps | Website scraper             | `info@mover.ca` on their site              |
| Dental                     | dental             | Google Maps | Website scraper             | `clinic@dentist.ca` on website             |
| Hair and beauty            | beauty             | Google Maps | Website scraper             | `salon@beauty.ca` on website               |
| Cleaning services          | cleaning_services  | Google Maps | Website scraper             | `contact@cleaner.ca` on website            |
| Construction / Renovation  | construction       | Google Maps | Website scraper             | `info@contractor.ca` on website            |
| Plumbing / HVAC            | trades             | Google Maps | Website scraper             | `service@plumber.ca` on website            |
| Auto repair                | auto_services      | Google Maps | Website scraper             | `shop@autoshop.ca` on website              |
| Pet services               | pet_services       | Google Maps | Website scraper             | `info@petgrooming.ca` on website           |
| Fitness / Gym              | fitness            | Google Maps | Website scraper             | `info@gymname.ca` on website               |

### B2B Industries — Google Maps + Hunter.io + LinkedIn

Businesses that sell to *other* businesses. Leads are decision-makers at
companies — we find the person, not just the business.

| Industry              | Product Type  | Discovery              | Email Strategy        | Why                                   |
|-----------------------|---------------|------------------------|-----------------------|---------------------------------------|
| Financial advisors    | financial     | Google Maps + LinkedIn | Hunter.io             | `advisor@firmname.com` pattern        |
| Law firms             | legal         | Google Maps + LinkedIn | Hunter.io             | `lawyer@lawfirm.ca` pattern           |
| Accounting firms      | accounting    | Google Maps + LinkedIn | Hunter.io             | `cpa@firmname.ca` pattern             |
| Marketing agencies    | marketing     | Google Maps + LinkedIn | Hunter.io             | `name@agency.com` pattern             |
| SaaS companies        | saas          | LinkedIn + Web         | Hunter.io             | Standard B2B email patterns           |
| Consulting firms      | consulting    | LinkedIn + Web         | Hunter.io             | `consultant@firm.com` pattern         |
| Staffing / Recruiting | staffing      | Google Maps + LinkedIn | Hunter.io             | `recruiter@agency.ca` pattern         |
| Commercial real estate| commercial_re | Google Maps + LinkedIn | Hunter.io             | `broker@cre.ca` pattern               |
| Manufacturing         | manufacturing | Google Maps + LinkedIn | Hunter.io             | `manager@factory.ca` pattern          |

### Hybrid — use BOTH strategies

| Industry     | Product Type | Discovery   | Email Strategy         | Why                                                     |
|--------------|--------------|-------------|------------------------|---------------------------------------------------------|
| Real estate  | real_estate  | Google Maps | Website + Hunter.io    | Agents have personal emails AND generic `info@` boxes   |
| Insurance    | insurance    | Google Maps | Website + Hunter.io    | Brokers have personal emails AND generic office emails  |

---

## Crystallux Product Lines → Lead Types

Crystallux is an Ontario insurance broker operating a digital MGA platform.
Each product line targets a specific lead type.

### B2C products (sold to consumers directly or via referral partners)

| Product                       | Lead Source (who we contact first)          |
|-------------------------------|---------------------------------------------|
| Home / Condo / Tenant insurance | Real estate agents, movers (referral flow) |
| Auto insurance                | General public, new car buyers              |
| Travel insurance              | Travel agencies, immigration consultants    |
| Pet insurance                 | Vet clinics, pet stores                     |
| CHIP reverse mortgage         | Senior services, financial advisors         |
| Neo Financial                 | General public                              |
| Credit Lift                   | Financial advisors, mortgage brokers        |

### B2B products (sold to businesses)

| Product                  | Target                                      |
|--------------------------|---------------------------------------------|
| Tax optimization         | Accounting firms, financial advisors        |
| Key person insurance     | Law firms, accounting firms, startups       |
| Buy-sell agreement       | Law firms, business brokers                 |
| Corporate life insurance | HR departments, consulting firms            |
| Group benefits           | Companies with 5+ employees                 |
| IFA wealth management    | High-net-worth individuals via advisors     |

---

## Implementation Plan

### 1. Schema changes

```sql
ALTER TABLE leads   ADD COLUMN IF NOT EXISTS lead_type text DEFAULT 'b2c';
ALTER TABLE clients ADD COLUMN IF NOT EXISTS lead_type text DEFAULT 'b2c';
CREATE INDEX IF NOT EXISTS idx_leads_lead_type ON leads(lead_type);
```

See `docs/architecture/migrations/v2.2_lead_type.sql`.

### 2. Industry → lead_type mapping (code)

```javascript
const INDUSTRY_TYPE_MAP = {
  'moving services':    'b2c',
  'dental':             'b2c',
  'hair and beauty':    'b2c',
  'cleaning services':  'b2c',
  'construction':       'b2c',
  'trades':             'b2c',
  'auto_services':      'b2c',
  'pet_services':       'b2c',
  'fitness':            'b2c',
  'financial':          'b2b',
  'legal':              'b2b',
  'accounting':         'b2b',
  'marketing':          'b2b',
  'saas':               'b2b',
  'consulting':         'b2b',
  'staffing':           'b2b',
  'commercial_re':      'b2b',
  'manufacturing':      'b2b',
  'real_estate':        'hybrid',
  'insurance':          'hybrid'
};
```

### 3. Enrichment routing logic

```
IF lead_type = 'b2c':
  → Run Website Email Scraper (only)

IF lead_type = 'hybrid':
  → Run Website Email Scraper first
  → If no email found → try Hunter.io as fallback

IF lead_type = 'b2b':
  → Run Hunter.io first (domain search)
  → If no email found → run Website Email Scraper as fallback
```

### 4. Discovery routing logic

```
IF client.lead_type = 'b2c':
  → Google Maps Discovery only (local service businesses)

IF client.lead_type = 'b2b':
  → Google Maps Discovery (for finding companies)
  → Future: LinkedIn Sales Navigator integration
  → Future: Business registries (Ontario Business Registry)

IF client.lead_type = 'hybrid':
  → Both strategies
```

---

## Rollout Priority

| Priority       | Action                                                         | Impact                        |
|----------------|----------------------------------------------------------------|-------------------------------|
| 1 (NOW)        | Deploy Email Scraper workflow (`clx-email-scraper-v1`)         | Unblocks 2,139 leads          |
| 2 (THIS WEEK)  | Add `lead_type` column to `leads` + `clients`                  | Enables routing               |
| 3 (THIS WEEK)  | Update B2C Discovery to set `lead_type = 'b2c'`                | Auto-classification           |
| 4 (NEXT WEEK)  | Update Email Scraper to route B2B leads to Hunter.io           | Dual enrichment               |
| 5 (LATER)      | Build B2B-specific discovery (LinkedIn, registries)            | New lead sources              |
| 6 (LATER)      | Different outreach templates per `lead_type`                   | Better conversion             |

---

## Cost Projection

| Service                        | B2C Cost            | B2B Cost           | Notes               |
|--------------------------------|---------------------|--------------------|---------------------|
| Google Maps Discovery          | ~$467/yr (smart scanning) | Same pool    | Shared              |
| Website Email Scraper          | $0                  | $0 (fallback)      | Free                |
| Hunter.io                      | $0 (not used)       | ~$50/mo (~$600/yr) | Only for B2B        |
| Claude AI (research / scoring) | ~$10/mo             | Same pool          | Shared              |
| Gmail sending                  | $0                  | $0                 | Free tier           |
| **Total**                      | **~$500/yr**        | **~$1,100/yr**     |                     |
