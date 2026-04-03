# Crystallux AI Sales Engine — Scaling Strategy
## Architecture Decisions and Growth Path

---

## Phase Architecture Overview

| Phase | Workflow | Trigger | Volume Limit | Status |
|-------|----------|---------|-------------|--------|
| Phase 1 | CLX Lead Import | Manual / Webhook | 500 leads/run | Complete |
| Phase 2 | CLX Lead Research | Every 30 min | 50 leads/run | Complete |
| Phase 3 | CLX Lead Scoring | Every 30 min | 50 leads/run | Complete |
| Phase 4 | CLX Business Signal Detection | Every 60 min | 20 leads/run | In Progress |
| Phase 5 | CLX Email Personalisation | Every 30 min | 25 leads/run | Planned |
| Phase 6 | CLX Outreach Sequencer | Every 60 min | 10 leads/run | Planned |

---

## Phase 4 — Business Signal Detection

### Purpose
Elevate the Crystallux engine from static research to live intelligence. Instead of only knowing what a company does, Phase 4 detects what a company is *currently doing* — hiring, expanding, funding, pivoting, or struggling — and uses that to determine the optimal outreach campaign type and timing.

### Architecture
```
Supabase (Scored leads)
  ↓
Google Custom Search API (live internet signal)
  ↓
Claude AI (signal analysis and classification)
  ↓
Supabase (Signal Detected leads with campaign recommendation)
```

### Key Design Decisions

**Why Google Custom Search over a scraping solution?**
Google's index is authoritative and current. Custom Search API results are structured, reliable, and within Google's terms of service. Scraping alternatives introduce fragility, IP blocking risk, and maintenance overhead. At $5/1,000 queries the cost is negligible at SMB scale.

**Why filter to lead_score >= 50?**
Signal detection costs money (Google API) and Claude API calls. Running it on every lead regardless of score would waste budget on low-quality leads. The 50-point threshold ensures only leads that passed research and scored above median receive the premium signal treatment.

**Why a 3-second Wait node?**
Google Custom Search API has rate limits. At batch size 1 with a 3-second wait, the maximum throughput is 20 requests/minute — well within Google's 100 queries per 100 seconds limit. This prevents rate limit errors without sacrificing meaningful throughput at current scale.

**Why 60-minute schedule instead of 30?**
Phase 4 is more expensive per operation than Phases 2 and 3 (requires an external API call to Google). Running hourly keeps costs predictable and gives the Google API rate limits room to breathe.

### Output Fields
| Field | Values | Purpose |
|-------|--------|---------|
| `detected_signal` | Free text | What the company is currently doing |
| `growth_stage` | Startup / Growing / Established / Declining / Pivoting | Lifecycle classification |
| `recommended_campaign_type` | automation_campaign / lead_generation_campaign / reputation_campaign / expansion_campaign / retention_campaign / general_outreach | Drives Phase 5 email template selection |
| `signal_confidence` | High / Medium / Low | How much evidence supports the signal |
| `outreach_timing` | Immediate / This Week / This Month | When to contact based on signal urgency |

### MCP Tool Interface
```
Tool name: detect_business_signal
Input:  lead_id, company, industry, city, research_summary
Output: detected_signal, growth_stage, recommended_campaign_type,
        signal_confidence, outreach_timing
```

---

## General Scaling Principles

### Volume Scaling
Each workflow is designed to process a limited batch per run and loop back for more. This prevents:
- Claude API rate limit errors
- Google API rate limit errors
- n8n execution timeouts
- Supabase connection pool exhaustion

To increase throughput, increase the `limit` parameter in the Supabase GET query and reduce the schedule interval — do not increase batch size beyond 1.

### Cost Scaling
| Phase | Cost Driver | Per Lead Cost (est.) |
|-------|------------|---------------------|
| Phase 1 | Apollo API (lead import) | ~$0.01 |
| Phase 2 | Claude API (research) | ~$0.002 |
| Phase 3 | Claude API (scoring) | ~$0.001 |
| Phase 4 | Google API + Claude API | ~$0.007 |
| Phase 5 | Claude API (email) | ~$0.002 |
| Phase 6 | Email/WhatsApp sending | ~$0.005 |

**Total estimated cost per fully-processed lead:** ~$0.03

At 1,000 leads/month: ~$30 in API costs.
At 10,000 leads/month: ~$300 in API costs.

### Multi-Tenant Scaling (White Label)
For the White Label package, each client gets:
- Dedicated Supabase project
- Separate n8n workflow instances with client-specific credentials
- Independent scheduling to prevent API rate limit collisions between clients
- Separate Claude prompts configured for their industry

At 10 white-label clients running simultaneously, offset each client's schedule by 3 minutes to distribute API load.

### Database Scaling
The current `leads` table is unindexed on `lead_status`. As volume grows, add:

```sql
CREATE INDEX IF NOT EXISTS idx_leads_status ON leads(lead_status);
CREATE INDEX IF NOT EXISTS idx_leads_score  ON leads(lead_score DESC);
```

These two indexes will keep workflow query times under 10ms even at 100,000+ rows.

### Error Recovery
Each workflow is designed to be re-runnable. If a workflow fails mid-batch:
- Leads already processed have an updated `lead_status` and will not be reprocessed
- Leads not yet processed remain at their previous status and will be picked up on the next run
- No deduplication logic is needed because status-based filtering is the deduplication mechanism

### n8n Infrastructure Scaling
Current setup: single Docker container on Hostinger VPS.

When to scale:
- >500 workflow executions/day → add n8n worker process
- >5,000 leads/month → upgrade VPS to 4 vCPU / 8GB RAM
- >10 concurrent clients → consider n8n Cloud or dedicated worker queue

---

## Roadmap Beyond Phase 6

| Future Phase | Capability |
|-------------|-----------|
| Phase 7 | WhatsApp outreach integration |
| Phase 8 | LinkedIn connection and message automation |
| Phase 9 | AI video personalisation (HeyGen or Synthesia API) |
| Phase 10 | Full MCP agent layer — all phases callable as tools |
| Phase 11 | Client-facing dashboard (Webflow + Supabase auth) |
| Phase 12 | Referral engine automation |
