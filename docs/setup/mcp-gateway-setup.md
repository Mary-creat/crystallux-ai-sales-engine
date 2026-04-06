# MCP Gateway Setup Guide

How to connect Claude AI agents to the Crystallux MCP Tool Gateway.

---

## Prerequisites

- All CLX workflows (Phases 1-11) imported and credentials assigned in n8n
- Supabase `mcp_tool_calls` table created (run migration first)
- n8n instance accessible at https://automation.crystallux.org

---

## Part 1 — Run the Migration

1. Open Supabase SQL Editor
2. Run `docs/architecture/migrations/add_mcp_tables.sql`
3. Verify the `mcp_tool_calls` table was created

---

## Part 2 — Import the Gateway Workflow

1. Import `workflows/clx-mcp-tool-gateway.json` into n8n
2. Re-assign **Supabase Crystallux** credential on all HTTP Request nodes
3. **Activate** the workflow (webhooks only work when active)

---

## Part 3 — Verify the Endpoints

**Test the tool registry:**
```bash
curl https://automation.crystallux.org/webhook/crystallux-tools
```
Should return a JSON object with 10 tools listed.

**Test a tool call:**
```bash
curl -X POST https://automation.crystallux.org/webhook/crystallux-mcp \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "get_pipeline_stats",
    "tool_input": {}
  }'
```
Should return pipeline statistics.

**Test with a lead:**
```bash
curl -X POST https://automation.crystallux.org/webhook/crystallux-mcp \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "list_leads",
    "tool_input": {
      "lead_status": "New Lead",
      "limit": 5
    }
  }'
```

---

## Part 4 — Connect a Claude AI Agent

To connect a Claude AI agent (via Claude Code, API, or MCP SDK) to Crystallux:

**Step 1:** The agent discovers available tools:
```
GET https://automation.crystallux.org/webhook/crystallux-tools
```

**Step 2:** The agent calls a tool:
```
POST https://automation.crystallux.org/webhook/crystallux-mcp
Content-Type: application/json

{
  "tool_name": "research_lead",
  "tool_input": {
    "lead_id": "abc-123",
    "company": "Toronto Insurance Group"
  }
}
```

**Step 3:** The agent receives structured response:
```json
{
  "success": true,
  "tool": "research_lead",
  "data": { ... },
  "timestamp": "2026-04-06T10:00:00Z",
  "execution_time_ms": 3421
}
```

---

## Part 5 — How Tool Routing Works

The gateway uses a status-based trigger architecture:

| Tool Call | Sets Lead Status To | Triggers Workflow |
|-----------|-------------------|-------------------|
| research_lead | New Lead | CLX Lead Research (Phase 2) |
| score_lead | Researched | CLX Lead Scoring (Phase 3) |
| generate_outreach | Campaign Assigned | CLX Outreach Generation (Phase 6) |
| send_outreach | Outreach Ready | CLX Outreach Sender (Phase 7) |
| process_booking | Replied | CLX Booking (Phase 9) |

The gateway sets the lead status, and the corresponding scheduled workflow picks it up on its next run. This is asynchronous by design.

For synchronous tools (get_lead, list_leads, update_lead_status, get_pipeline_stats), the gateway queries Supabase directly and returns results immediately.

---

## Part 6 — Monitoring Tool Calls

All tool calls are logged to the `mcp_tool_calls` table in Supabase. Query it to see:

```sql
SELECT tool_name, success, execution_time_ms, called_at
FROM mcp_tool_calls
ORDER BY called_at DESC
LIMIT 20;
```

---

## Security Notes

- The webhook URLs are public by default — consider adding API key validation
- All tool calls are logged with input and output for audit
- Supabase credentials are stored in n8n vault, never exposed
- The gateway validates all required inputs before processing
