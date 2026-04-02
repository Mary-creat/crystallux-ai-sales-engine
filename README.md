# crystallux-ai-sales-engine
Crystallux Universal AI Sales Engine — A fully autonomous AI-powered sales system that operates as a digital sales employee. Built with n8n, Supabase, Apollo, Claude AI, and MCP. Self-hosted on Docker/Hostinger VPS.

## Build Phases

| Phase | Workflow | Status |
|-------|----------|--------|
| Phase 1 | CLX Lead Import (`clx-lead-import.json`) | Complete |
| Phase 2 | CLX Lead Research (`clx-lead-research.json`) | In Progress (v0.2.0) |
| Phase 3 | CLX Email Personalisation | Planned |
| Phase 4 | CLX Outreach Sequencer | Planned |

## Credentials Required

The following credentials must be configured in n8n before activating workflows:

| n8n Credential Name | Type | Headers Set |
|---------------------|------|-------------|
| `Supabase Crystallux` | Header Auth | `apikey: <service_role_key>` |
| `Claude Anthropic` | Header Auth | `x-api-key: <anthropic_api_key>` |

> **Post-import steps for `clx-lead-research.json`:**
> 1. Re-assign credentials in n8n: open **Get New Leads**, **Update Lead in Supabase** → select `Supabase Crystallux` from the credential vault. Open **Claude Research Lead** → select `Claude Anthropic`.
> 2. The `Authorization` header in **Get New Leads** and **Update Lead in Supabase** is intentionally blank in the JSON (no keys are hardcoded). Set its value to `Bearer <your-supabase-service-role-key>` manually in the n8n UI after import. The `apikey` header is handled automatically by the `Supabase Crystallux` credential and is sufficient for most operations — the `Authorization` header is additive.
> 3. Activate the workflow once credentials are confirmed.
