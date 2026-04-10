# Crystallux Universal AI Sales Engine — API Requirements

This document lists every API used (or planned) by the Crystallux Universal AI Sales Engine, with cost, purpose, status, and onboarding instructions.

Statuses: **Connected** = live in production · **Pending** = account exists but blocked · **Not Started** = no account yet.

---

## CRITICAL — Already Connected

### 1. Anthropic Claude API
- **Purpose:** AI research, lead scoring, outreach generation, dashboard chat assistant
- **Cost:** Pay per token (~$0.003 / 1K tokens — Sonnet)
- **Priority:** Critical
- **Status:** Connected
- **How to get:** console.anthropic.com → create org → generate API key

### 2. Supabase
- **Purpose:** Postgres database for all leads, clients, campaigns, bookings
- **Cost:** Free tier up to 500MB storage, 2GB bandwidth
- **Priority:** Critical
- **Status:** Connected
- **How to get:** supabase.com → create project → copy URL + service role key

### 3. Google Maps Places API (New)
- **Purpose:** City scan business discovery — powers all city + B2C discovery workflows
- **Cost:** Free $200 credit/month (covers ~10K Place searches)
- **Priority:** Critical
- **Status:** Connected
- **How to get:** console.cloud.google.com → enable Places API (New) → create API key

### 4. Gmail OAuth2
- **Purpose:** Send all outreach emails and follow-ups
- **Cost:** Free
- **Priority:** Critical
- **Status:** Connected
- **How to get:** Google Cloud Console → OAuth consent → create OAuth2 client → connect to n8n credential

### 5. Hunter.io
- **Purpose:** Email enrichment — find decision-maker emails for company domains
- **Cost:** Free 25 searches/month, paid plans from $49/month
- **Priority:** Critical
- **Status:** Connected
- **How to get:** hunter.io → sign up → API key in dashboard settings

### 6. Calendly
- **Purpose:** Appointment booking automation — booking links inserted into outreach
- **Cost:** Free basic plan (1 event type)
- **Priority:** Critical
- **Status:** Connected
- **How to get:** calendly.com → sign up → create event type → personal access token under Integrations

---

## IMPORTANT — Needed Soon

### 7. Vapi.ai
- **Purpose:** AI voice calling for lead qualification and warm transfers
- **Cost:** $0.05–0.10 per minute
- **Priority:** High — multiplies booking rate 3–5x
- **Status:** Not Started
- **How to get:** vapi.ai → sign up → get API key → configure voice assistant

### 8. HeyGen
- **Purpose:** AI video avatar for personalised outreach (1:1 video emails)
- **Cost:** $29/month starter plan
- **Priority:** High — dramatically increases reply rates
- **Status:** Not Started
- **How to get:** heygen.com → sign up → create avatar → API key under developer settings

### 9. Stripe
- **Purpose:** Payment processing and recurring client billing
- **Cost:** 2.9% + $0.30 per transaction
- **Priority:** High — required before charging clients
- **Status:** Not Started
- **How to get:** stripe.com → create account → activate → API keys in dashboard

### 10. Twilio
- **Purpose:** WhatsApp and SMS outreach channel
- **Cost:** ~$0.005 per SMS, ~$0.005 per WhatsApp message
- **Priority:** Medium
- **Status:** Not Started
- **How to get:** twilio.com → sign up → buy a number → API SID/token in console

### 11. Apollo.io
- **Purpose:** B2B lead data and email enrichment (better quality than Hunter for B2B)
- **Cost:** $49/month basic (free plan blocks API access)
- **Priority:** Medium
- **Status:** Pending (free plan blocks API)
- **How to get:** apollo.io → upgrade to paid plan → API key in account settings

### 12. Buffer
- **Purpose:** Social media scheduling and posting (content engine)
- **Cost:** Free for 3 channels
- **Priority:** Medium — needed for content engine
- **Status:** Not Started
- **How to get:** buffer.com → sign up → connect channels → API access token

---

## OPTIONAL — Future Growth

### 13. DocuSign
- **Purpose:** Digital contract signing for client onboarding
- **Cost:** $25/month
- **Priority:** Low — needed at scale
- **Status:** Not Started
- **How to get:** docusign.com → developer account → integration key

### 14. SerpApi
- **Purpose:** Google search results for signal detection (Phase 4 enhancement)
- **Cost:** $50/month for 5,000 searches
- **Priority:** Low — Phase 4 enhancement
- **Status:** Not Started
- **How to get:** serpapi.com → sign up → API key in dashboard

### 15. LinkedIn API
- **Purpose:** LinkedIn outreach and content posting
- **Cost:** Varies by plan
- **Priority:** Low — complex approval process
- **Status:** Not Started
- **How to get:** developer.linkedin.com → create app → submit for partner approval

### 16. Realtor.ca API
- **Purpose:** Home listing data for B2C moving leads (sold listings = imminent move signal)
- **Cost:** Contact required
- **Priority:** Medium — B2C moving pipeline
- **Status:** Not Started
- **How to get:** Contact CREA business development directly

### 17. Ontario Business Registry API
- **Purpose:** New business registrations as insurance / commercial signals
- **Cost:** Free (government API)
- **Priority:** Medium — insurance signal detection
- **Status:** Not Started
- **How to get:** ontario.ca/page/ontario-business-registry → developer access

---

## Company Email Setup — info@crystallux.org

The official outbound address for all Crystallux outreach is **info@crystallux.org**. Steps to provision:

1. **Hostinger** → email settings → create mailbox `info@crystallux.org`
2. Set up forwarding from `info@crystallux.org` → `adesholaakintunde@gmail.com`
3. In Gmail, add `info@crystallux.org` as a "send mail as" alias (Settings → Accounts → Add another email)
4. Verify alias via confirmation email
5. Update n8n Gmail OAuth2 credential to use `info@crystallux.org` as the sender
6. Update all workflow notification emails (Gmail send nodes, internal alerts) to use this address
7. Update Calendly notification email to `info@crystallux.org`
8. Update Stripe account email to `info@crystallux.org` once Stripe is connected

**Future domain note:** when `crystallux.com` is acquired, repeat the above for `info@crystallux.com` and add it as a second send-as alias. Outbound campaigns should default to the `.org` address until both domains are warmed.

---

## Summary Table

| #  | API                       | Priority  | Status        | Cost                |
|----|---------------------------|-----------|---------------|---------------------|
| 1  | Anthropic Claude          | Critical  | Connected     | ~$0.003/1K tokens   |
| 2  | Supabase                  | Critical  | Connected     | Free (500MB)        |
| 3  | Google Maps Places        | Critical  | Connected     | Free $200/month     |
| 4  | Gmail OAuth2              | Critical  | Connected     | Free                |
| 5  | Hunter.io                 | Critical  | Connected     | Free 25/month       |
| 6  | Calendly                  | Critical  | Connected     | Free basic          |
| 7  | Vapi.ai                   | High      | Not Started   | $0.05–0.10/min      |
| 8  | HeyGen                    | High      | Not Started   | $29/month           |
| 9  | Stripe                    | High      | Not Started   | 2.9% + $0.30        |
| 10 | Twilio                    | Medium    | Not Started   | ~$0.005/msg         |
| 11 | Apollo.io                 | Medium    | Pending       | $49/month           |
| 12 | Buffer                    | Medium    | Not Started   | Free (3 channels)   |
| 13 | DocuSign                  | Low       | Not Started   | $25/month           |
| 14 | SerpApi                   | Low       | Not Started   | $50/month           |
| 15 | LinkedIn API              | Low       | Not Started   | Varies              |
| 16 | Realtor.ca API            | Medium    | Not Started   | Contact required    |
| 17 | Ontario Business Registry | Medium    | Not Started   | Free                |
