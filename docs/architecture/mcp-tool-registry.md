# Crystallux MCP Tool Registry

Complete reference for all 10 MCP tools exposed by the CLX MCP Tool Gateway.

---

## Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/webhook/crystallux-mcp` | POST | Execute a tool call |
| `/webhook/crystallux-tools` | GET | List all available tools |

---

## Request Format

```json
{
  "tool_name": "research_lead",
  "tool_input": {
    "lead_id": "uuid-here",
    "company": "Toronto Insurance Group"
  }
}
```

## Response Format

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

## Tool 1: research_lead

Triggers AI research on a company via CLX Lead Research workflow.

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| lead_id | string | yes | UUID of the lead |
| company | string | yes | Company name to research |
| industry | string | no | Industry category |
| job_title | string | no | Contact job title |
| city | string | no | City location |
| product_type | string | no | Product/service type |

**Output:** Updated lead record with research_summary, likely_business_need, research_angle

---

## Tool 2: score_lead

Triggers AI scoring (0-100) via CLX Lead Scoring workflow.

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| lead_id | string | yes | UUID of the lead |
| company | string | yes | Company name |
| industry | string | no | Industry category |
| job_title | string | no | Contact job title |
| research_summary | string | no | Existing research |

**Output:** Updated lead with lead_score, priority_level, decision_maker_probability

---

## Tool 3: generate_outreach

Triggers personalized message generation via CLX Outreach Generation.

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| lead_id | string | yes | UUID of the lead |
| full_name | string | yes | Contact full name |
| company | string | yes | Company name |
| campaign_name | string | no | Campaign type (default: automation_campaign) |

**Output:** Updated lead with email_subject, email_body, linkedin_message, whatsapp_message

---

## Tool 4: send_outreach

Triggers email send via CLX Outreach Sender workflow.

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| lead_id | string | yes | UUID of the lead |
| email | string | yes | Email address to send to |
| full_name | string | no | Contact full name |

**Output:** Updated lead with outreach_sent_at, followup_scheduled_at, lead_status

---

## Tool 5: process_booking

Triggers interest detection and Calendly booking via CLX Booking.

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| lead_id | string | yes | UUID of the lead |
| full_name | string | yes | Contact full name |
| company | string | no | Company name |
| reply_text | string | yes | Prospect reply to analyze |

**Output:** Updated lead with interest_detected, booking_email_sent, lead_status

---

## Tool 6: get_pipeline_stats

Returns complete pipeline health metrics. No input required.

**Input:** none

**Output:** total_leads, status_counts object with count per status

---

## Tool 7: scan_city

Queues a Google Maps business discovery scan for a city + industry.

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| city | string | yes | City to scan (e.g. Toronto) |
| industry | string | yes | Industry to search (e.g. insurance broker) |
| product_type | string | no | Product category tag |

**Output:** Confirmation message with scan details

---

## Tool 8: get_lead

Retrieves a complete lead record from Supabase.

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| lead_id | string | no | UUID of the lead |
| email | string | no | Email address to look up |

At least one of lead_id or email should be provided.

**Output:** Complete lead object with all fields

---

## Tool 9: update_lead_status

Updates a lead's status in the pipeline.

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| lead_id | string | yes | UUID of the lead |
| lead_status | string | yes | New status value |
| notes | string | no | Optional notes |

**Output:** Updated lead object

---

## Tool 10: list_leads

Lists leads filtered by status, industry, or both.

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| lead_status | string | no | Filter by status |
| industry | string | no | Filter by industry |
| limit | number | no | Max results (default 20) |

**Output:** Array of lead objects

---

## Tool 11: check_system_health

Counts leads by status and returns overall system health.

**Input:** none

**Output:** total_leads, status_counts, active_conversations, health ("operational" or "empty")

---

## Tool 12: check_pipeline_health

Analyzes pipeline stages and flags stale leads based on age thresholds.

**Input:** none

**Output:** total_leads, stage_counts, stale_leads array, stale_count, health ("healthy" or "needs_attention")

---

## Tool 13: get_execution_stats

Returns MCP tool call stats from the last 24 hours.

**Input:** none

**Output:** Array of recent tool calls with tool_name, success, execution_time_ms, created_at

---

## Tool 14: get_clients

Lists all active Crystallux clients with their Calendly links and billing config.

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| industry | string | no | Filter by industry (e.g. moving_services) |

**Output:** Array of client objects with client_name, industry, calendly_link, notification_email, city, fee_per_booking, monthly_retainer

---

## Future Tools (Coming Soon)

| Tool | Description | Integration |
|------|-------------|-------------|
| ai_voice_call | AI voice call to prospect | Vapi.ai |
| send_whatsapp | WhatsApp message outreach | WhatsApp Business API |
| post_linkedin | LinkedIn content posting | LinkedIn API |
| generate_video | AI avatar video message | HeyGen |
| send_proposal | Send proposal for signature | DocuSign |
| process_payment | Process client payment | Stripe |
| onboard_client | Run client onboarding sequence | Internal |
