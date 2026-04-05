# crystallux-ai-sales-engine
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

## Credentials Required

The following credentials must be configured in n8n before activating workflows:

| n8n Credential Name | Type | Headers Set |
|---------------------|------|-------------|
| `Supabase Crystallux` | Header Auth | `apikey: <service_role_key>` |
| `Claude Anthropic` | Header Auth | `x-api-key: <anthropic_api_key>` |
| `Google Search` | Header Auth | `X-Goog-Api-Key: <google_api_key>` — see [setup guide](docs/setup/google-search-setup.md) |
| `Gmail` | Gmail OAuth2 | OAuth2 — see [setup guide](docs/setup/gmail-oauth-setup.md) |

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

## Business Documentation

| Document | Description |
|----------|-------------|
| [Monetization Strategy](docs/business/monetization-strategy.md) | Business philosophy, service packages, pricing psychology, path to first 10 clients, and competitive advantage |
| [Service Packages](docs/business/service-packages.md) | Client-facing one-page overview of all four packages with comparison table and value propositions |
| [Competitive Positioning](docs/business/competitive-positioning.md) | Market differentiation analysis — what competitors offer, what Crystallux offers, and why the combination is defensible |
| [Client Onboarding](docs/business/client-onboarding.md) | Complete onboarding framework — discovery call questions, configuration checklist, setup steps, training outline, and 30-day success metrics |
# Auto-deploy enabled Sun Apr  5 15:02:52 EDT 2026
