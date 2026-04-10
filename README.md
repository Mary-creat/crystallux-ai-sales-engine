# crystallux-ai-sales-engine

**Crystallux v1.0 — COMPLETE**

Crystallux Universal AI Sales Engine — A fully autonomous AI-powered sales system that operates as a digital sales employee. Built with n8n, Supabase, Apollo, Claude AI, and MCP. Self-hosted on Docker/Hostinger VPS.

## Build Phases

| Phase | Workflow | Status |
|-------|----------|--------|
| Phase 1 | CLX Lead Import (`clx-lead-import.json`) | Complete |
| Phase 2 | CLX Lead Research (`clx-lead-research.json`) | In Progress (v0.2.0) |
| Phase 3 | CLX Lead Scoring (`clx-lead-scoring.json`) | Complete (v0.3.0) |
| Phase 4 | CLX Business Signal Detection (`clx-business-signal-detection.json`) | In Progress (v0.4.0) |
| Phase 5 | CLX Campaign Router (`clx-campaign-router.json`) | In Progress (v0.5.0) |
| Phase 6 | CLX Outreach Generation (`clx-outreach-generation.json`) | Complete (v0.6.0) |
| Phase 7 | CLX Outreach Sender (`clx-outreach-sender.json`) | Complete — Production Tested (v0.7.0) |
| Phase 8 | CLX Follow Up (`clx-follow-up.json`) | Complete — Production Tested (v0.8.1) |
| Phase 9 | CLX Booking (`clx-booking.json`) | Complete (v0.9.0) |
| Phase 10 | CLX Pipeline Update (`clx-pipeline-update.json`) | Complete (v0.10.0) |
| Phase 11 | CLX City Scan Discovery (`clx-city-scan-discovery.json`) | Complete — Production Tested (v0.11.2) |
| Phase 12 | CLX MCP Tool Gateway (`clx-mcp-tool-gateway.json`) | Complete (v1.0.0) |
| Phase 14 | CLX B2C Discovery (`clx-b2c-discovery.json`) | Complete (v1.0.0) — 26 search queries across 6 B2C verticals |

## Credentials Required

The following credentials must be configured in n8n before activating workflows:

| n8n Credential Name | Type | Headers Set |
|---------------------|------|-------------|
| `Apollo API` | Header Auth | `X-Api-Key: <apollo_api_key>` |
| `Supabase Crystallux` | Header Auth | `apikey: <service_role_key>` |
| `Claude Anthropic` | Header Auth | `x-api-key: <anthropic_api_key>` |
| `Google Search` | Header Auth | `X-Goog-Api-Key: <google_api_key>` — see [setup guide](docs/setup/google-search-setup.md) |
| `Gmail` | Gmail OAuth2 | OAuth2 — see [setup guide](docs/setup/gmail-oauth-setup.md) |
| `Calendly` | Header Auth | `Authorization: Bearer <token>` — see [setup guide](docs/setup/calendly-setup.md) |
| `Google Maps` | Header Auth | `X-Goog-Api-Key: <google_maps_api_key>` — see [setup guide](docs/setup/google-maps-setup.md) |

> **Post-import steps for `clx-lead-research.json`:**
> 1. Re-assign credentials in n8n: open **Get New Leads**, **Update Lead in Supabase** → select `Supabase Crystallux` from the credential vault. Open **Claude Research Lead** → select `Claude Anthropic`.
> 2. The `Authorization` header in **Get New Leads** and **Update Lead in Supabase** is intentionally blank in the JSON (no keys are hardcoded). Set its value to `Bearer <your-supabase-service-role-key>` manually in the n8n UI after import. The `apikey` header is handled automatically by the `Supabase Crystallux` credential and is sufficient for most operations — the `Authorization` header is additive.
> 3. Activate the workflow once credentials are confirmed.

## Architecture Documentation

| Document | Description |
|----------|-------------|
| [Scaling Strategy](docs/architecture/scaling-strategy.md) | Phase architecture, volume limits, cost per lead, multi-tenant scaling, and roadmap |
| [Google Search Setup](docs/setup/google-search-setup.md) | How to get Google Custom Search API key and cx ID for Phase 4 |
| [Gmail OAuth2 Setup](docs/setup/gmail-oauth-setup.md) | Step-by-step Gmail OAuth2 credential setup for Phase 7 email sending |
| [Calendly Setup](docs/setup/calendly-setup.md) | Calendly API token setup for Phase 9 booking automation |
| [Google Maps Setup](docs/setup/google-maps-setup.md) | Google Maps Places API setup for Phase 11 city scan discovery |
| [MCP Tool Registry](docs/architecture/mcp-tool-registry.md) | Complete reference for all 10 MCP tools with input/output schemas |
| [MCP Gateway Setup](docs/setup/mcp-gateway-setup.md) | How to connect Claude AI agents to the Crystallux MCP gateway |
| [Redis Security](docs/setup/redis-security.md) | Redis password authentication setup with zero-downtime guide |
| [Supabase RLS](docs/setup/supabase-rls-setup.md) | Row Level Security policies for production data protection |
| [Infrastructure Audit](docs/architecture/infrastructure-audit.md) | Full system audit report with health scores and fix tracking |
| [API Requirements](docs/setup/api-requirements.md) | Master list of every API used (or planned) by Crystallux — cost, status, onboarding |
| [Web Dashboard](docs/dashboard/index.html) | Crystallux operations dashboard — pipeline stats, recent leads, quick actions, Claude chat, API status |

## Business Documentation

| Document | Description |
|----------|-------------|
| [Monetization Strategy](docs/business/monetization-strategy.md) | Business philosophy, service packages, pricing psychology, path to first 10 clients, and competitive advantage |
| [Service Packages](docs/business/service-packages.md) | Client-facing one-page overview of all four packages with comparison table and value propositions |
| [Competitive Positioning](docs/business/competitive-positioning.md) | Market differentiation analysis — what competitors offer, what Crystallux offers, and why the combination is defensible |
| [Client Onboarding](docs/business/client-onboarding.md) | Complete onboarding framework — discovery call questions, configuration checklist, setup steps, training outline, and 30-day success metrics |
## MCP Gateway

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `POST /webhook/crystallux-mcp` | POST | Execute any tool call |
| `GET /webhook/crystallux-tools` | GET | Discover all available tools |

10 tools available: `research_lead`, `score_lead`, `generate_outreach`, `send_outreach`, `process_booking`, `get_pipeline_stats`, `scan_city`, `get_lead`, `update_lead_status`, `list_leads`

See [MCP Tool Registry](docs/architecture/mcp-tool-registry.md) for complete documentation.

# Auto-deploy enabled Sun Apr  5 15:02:52 EDT 2026
