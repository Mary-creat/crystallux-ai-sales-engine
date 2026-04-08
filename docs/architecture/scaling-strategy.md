# Crystallux AI Sales Engine — Scaling Strategy
## Architecture Decisions and Growth Path (v1.0)

---

## Phase Architecture Overview — All 12 Phases Complete

| Phase | Workflow | Trigger | Volume Limit | Status |
|-------|----------|---------|-------------|--------|
| Phase 1 | CLX Lead Import | Manual / Webhook | 500 leads/run | Complete |
| Phase 2 | CLX Lead Research | Every 30 min | 50 leads/run | Complete |
| Phase 3 | CLX Lead Scoring | Every 30 min | 50 leads/run | Complete |
| Phase 4 | CLX Business Signal Detection | Every 60 min | 20 leads/run | Complete |
| Phase 5 | CLX Campaign Router | Every 60 min | 25 leads/run | Complete |
| Phase 6 | CLX Outreach Generation | On-demand | Variable | Complete |
| Phase 7 | CLX Outreach Sender | Every 60 min | 5 leads/run | Complete — Production Tested |
| Phase 8 | CLX Follow Up | Every 60 min | 5 leads/run | Complete — Production Tested |
| Phase 9 | CLX Booking | Every 30 min | 10 leads/run | Complete |
| Phase 10 | CLX Pipeline Update | Every 6 hours | All leads | Complete |
| Phase 11 | CLX City Scan Discovery | Nightly (midnight) | 35 queries/run | Complete — Production Tested |
| Phase 12 | CLX MCP Tool Gateway | Webhook (on-demand) | Unlimited | Complete |

---

## Lead Lifecycle Flow

```
Google Maps / Apollo → New Lead → Researched → Scored →
Signal Detected → Campaign Assigned → Outreach Ready →
Contacted → Replied → Booking Sent → Booked
```

---

## Phase-by-Phase Architecture

### Phase 1 — Lead Import (Apollo.io)
Imports leads from Apollo.io People Search API. Deduplicates by email against existing leads.

### Phase 2 — Lead Research (Claude AI)
Claude AI researches each company and produces research_summary, likely_business_need, and research_angle. 30-min schedule, batch 1, 2s wait.

### Phase 3 — Lead Scoring (Claude AI)
Claude AI scores leads 0-100 based on industry relevance, seniority, company size, and urgency. 30-min schedule, batch 1.

### Phase 4 — Business Signal Detection (Google Custom Search + Claude AI)
Searches Google for live business signals (hiring, expanding, funding) and uses Claude to classify growth_stage and recommend_campaign_type. 60-min schedule, 20 leads/run, 3s wait. Only processes leads with score >= 50.

### Phase 5 — Campaign Router
Routes scored leads to appropriate campaign types based on signal analysis. Sets recommended_campaign_type. 60-min schedule.

### Phase 6 — Outreach Generation (Claude AI)
Generates personalized email_subject, email_body, linkedin_message, and whatsapp_message using Claude AI. On-demand processing.

### Phase 7 — Outreach Sender (Gmail)
Sends outreach emails via Gmail OAuth. Includes safety guards: unsubscribed check, do_not_contact check, 5-email send limit. 60-min schedule, 60s wait between sends.

### Phase 8 — Follow Up (Gmail)
3-touch follow-up sequence at 3, 5, and 10 day intervals. Same safety guards as Phase 7. 60-min schedule.

### Phase 9 — Booking (Claude AI + Calendly)
Detects interest in prospect replies using Claude AI. Sends Calendly booking link for positive signals. 30-min schedule.

### Phase 10 — Pipeline Update
Runs every 6 hours. Counts leads at each status, calculates conversion rates, saves snapshots to pipeline_stats table, and flags stale leads.

### Phase 11 — City Scan Discovery (Google Maps Places API)
Nightly scan of 5 Canadian cities x 7 industries (35 queries) via Google Maps Places API (New). Discovers businesses, deduplicates by company name, inserts new leads.

### Phase 12 — MCP Tool Gateway
Webhook-based gateway exposing 10 MCP tools. Any AI agent can discover tools (GET /webhook/crystallux-tools) and execute them (POST /webhook/crystallux-mcp). Includes API key authentication, request validation, and tool call logging.

---

## Cost Scaling

| Phase | Cost Driver | Per Lead Cost (est.) |
|-------|------------|---------------------|
| Phase 1 | Apollo API | ~$0.01 |
| Phase 2 | Claude API (research) | ~$0.002 |
| Phase 3 | Claude API (scoring) | ~$0.001 |
| Phase 4 | Google API + Claude API | ~$0.007 |
| Phase 5 | None (routing logic) | ~$0.000 |
| Phase 6 | Claude API (generation) | ~$0.003 |
| Phase 7 | Gmail (free) | ~$0.000 |
| Phase 8 | Gmail (free) | ~$0.000 |
| Phase 9 | Claude API + Calendly | ~$0.003 |
| Phase 10 | None (Supabase queries) | ~$0.000 |
| Phase 11 | Google Maps Places API | ~$0.032/search |
| Phase 12 | None (routing) | ~$0.000 |

**Total per fully-processed lead:** ~$0.03
**City scan per night (35 queries):** ~$1.12

At 1,000 leads/month: ~$30 in API costs + ~$34 city scan = ~$64/month
At 10,000 leads/month: ~$300 in API costs + ~$34 city scan = ~$334/month

---

## General Scaling Principles

### Volume Scaling
Each workflow processes batch size 1 with wait nodes between API calls. To increase throughput:
- Increase the `limit` parameter in Supabase GET queries
- Reduce schedule intervals
- Add n8n worker processes for parallel execution

### Multi-Client Architecture (v0.9.4+)
The `clients` table in Supabase stores all client configurations:
- Each client has their own Calendly link, notification email, and billing config
- The Booking workflow dynamically looks up the correct client by matching `lead.product_type` to `client.industry`
- Adding a new client = one INSERT into the `clients` table — no workflow changes needed
- Deactivating a client = `UPDATE clients SET active = false` — leads fall back to defaults

```sql
-- Example: add a new client
INSERT INTO clients (client_name, industry, calendly_link, notification_email, city, active, fee_per_booking)
VALUES ('New Client', 'insurance', 'https://calendly.com/their-link', 'client@email.com', 'Vancouver', true, 200.00);
```

### Multi-Tenant Scaling (White Label)
Each client gets:
- Row in the `clients` table with their own Calendly link and billing config
- Leads matched by `product_type` → `industry` for automatic routing
- Dedicated Supabase project (or schema-level isolation with RLS) at scale
- Independent scheduling offset by 3 minutes per client at scale
- Separate Claude prompts configured for their industry

### Database Performance
Performance indexes covering all workflow queries are defined in `add_performance_indexes.sql`:
- `idx_leads_lead_status` — all phase queries
- `idx_leads_product_type` — campaign routing
- `idx_leads_updated_at` — stale detection
- `idx_leads_source` — analytics
- Composite indexes for common query patterns

### Error Recovery
Every workflow is re-runnable. Status-based filtering prevents double-processing. Failed leads remain at their current status and get picked up on the next scheduled run.

### n8n Infrastructure Scaling
Current: single Docker container + worker on Hostinger VPS.

| Threshold | Action |
|-----------|--------|
| >500 executions/day | Scale n8n-worker replicas to 2-3 |
| >5,000 leads/month | Upgrade VPS to 4 vCPU / 8GB RAM |
| >10 concurrent clients | Dedicated worker queue per client |
| >50 concurrent clients | n8n Cloud or Kubernetes deployment |

---

## Roadmap Beyond v1.0

| Future Phase | Capability | Integration |
|-------------|-----------|-------------|
| Phase 13 | WhatsApp outreach | WhatsApp Business API |
| Phase 14 | LinkedIn automation | LinkedIn API |
| Phase 15 | AI video messages | HeyGen API |
| Phase 16 | AI voice calls | Vapi.ai |
| Phase 17 | Client dashboard | Webflow + Supabase Auth |
| Phase 18 | Proposal and signing | DocuSign API |
| Phase 19 | Payment processing | Stripe API |
| Phase 20 | Referral engine | Internal automation |
