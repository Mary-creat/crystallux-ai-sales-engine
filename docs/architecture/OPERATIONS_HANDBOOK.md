# Crystallux Operations Handbook

> **What this is:** A working reference for understanding, operating, and debugging the Crystallux AI Sales Engine. Written for the system owner. Updated as the system evolves.
>
> **Who this is for:** You (the owner), when pitching clients, debugging problems, managing developers, or onboarding anyone new to the system.
>
> **How to use it:** Skim the Table of Contents. Jump to the section you need. Every section is written to stand alone so you don't have to read top-to-bottom.

---

## Table of Contents

1. [What Crystallux Is, In Plain Language](#1-what-crystallux-is-in-plain-language)
2. [The Pipeline: What Happens When a Lead Enters the System](#2-the-pipeline-what-happens-when-a-lead-enters-the-system)
3. [The Technology Stack](#3-the-technology-stack)
4. [Key Concepts You Need to Know](#4-key-concepts-you-need-to-know)
5. [The 14 Workflows: What Each One Does](#5-the-14-workflows-what-each-one-does)
6. [The Database: Tables, Columns, Functions](#6-the-database-tables-columns-functions)
7. [Common SQL Queries You'll Actually Use](#7-common-sql-queries-youll-actually-use)
8. [When Things Break: Troubleshooting Guide](#8-when-things-break-troubleshooting-guide)
9. [Security and Access](#9-security-and-access)
10. [For the Pitch: Talking Points](#10-for-the-pitch-talking-points)
11. [Glossary](#11-glossary)

---

## 1. What Crystallux Is, In Plain Language

### The one-sentence version
Crystallux is an AI-powered sales engine that finds potential customers, researches them, writes personalized outreach, sends it, and books meetings on a client's calendar — automatically, at scale.

### The paragraph version
Crystallux is software that runs 24/7 to grow businesses. It discovers prospects on Google Maps and other sources, researches each one using AI, scores how likely they are to buy, writes them a personal email (not spam), sends it from a real inbox, handles replies, and books qualified leads directly into the client's Calendly. It replaces what would normally take a team of 3-5 SDRs (sales development reps) at roughly 1/10th the cost.

### What makes it different
Most "AI sales tools" on the market are either: (1) mail merge with AI-generated templates (still feels like spam), or (2) expensive enterprise platforms that require sales teams and months of setup. Crystallux is different because:

- **It researches each lead individually before writing anything.** Every email references something specific about that business — not a "[Company Name]" merge field.
- **It's signal-driven.** It watches for buying signals (growth stage, seasonal triggers, pain points from their website) and only reaches out when timing is right.
- **It's multi-channel.** Email today, with WhatsApp, SMS, and voice coming. Same prospect, same context, across every channel they use.
- **It's transparent.** Clients see live dashboards showing exactly what's happening with their pipeline.
- **It's built for specific industries first.** Currently specialized for insurance brokers and moving companies, not "everyone everywhere."

### Who the customers are
Two types:

**Clients** — businesses who pay Crystallux to fill their calendars. Currently Blonai Moving Company and Crystallux Insurance Network. Pricing: ~$500/month per client (scaling tier depending on volume).

**Leads** — the clients' prospective customers. Small to medium businesses in specific industries (insurance, moving, dental, contracting, etc.) who might want what the client sells.

### Business model
- **Recurring monthly subscription** from each client
- Currently 2 clients
- Target: 20-50 clients in first year, $10K-25K MRR (monthly recurring revenue)

---

## 2. The Pipeline: What Happens When a Lead Enters the System

Think of the pipeline as a conveyor belt with 9 stations. A new business goes in at station 1, moves through each station, and comes out the other side as either a booked meeting or a disqualified lead.

### The 9 stations

```
1. DISCOVERY          → Find businesses on Google Maps
2. ENRICHMENT         → Get their email address from their website
3. RESEARCH           → Look up what the business does, who runs it
4. SCORING            → Rate 0-100 how likely they are to buy
5. SIGNAL DETECTION   → Look for buying signals (growth, pain points)
6. CAMPAIGN ROUTING   → Decide which message angle to use
7. OUTREACH GENERATION → AI writes a personalized email
8. SENDING            → Email goes out from a real inbox
9. FOLLOW-UP / BOOKING → Handle replies, send Calendly link
```

Each station has one or more n8n workflows that handle it. The lead's `lead_status` field in the database tracks where it currently is in the pipeline.

### What each status means

| Status | Meaning |
|--------|---------|
| New | Just discovered, nothing done yet |
| Researched | Claude AI has pulled info about the company |
| Scored | Lead has a 0-100 score based on fit |
| Signal Detected | Buying signal identified (or no signal found) |
| Campaign Assigned | Decided what kind of pitch to make |
| Outreach Ready | Email body generated, waiting to send |
| Contacted | Email sent, waiting for reply |
| Replied | Prospect replied to email |
| Booking Sent | Calendly link sent to interested prospect |
| Meeting Scheduled | They booked a slot |
| Not Interested | Said no |
| Closed Lost | No response after follow-ups |

### How long does it take?
A lead typically moves from "New" to "Outreach Ready" in a few hours (depending on workflow schedules). Sending and reply cycles take days to weeks. A typical lead-to-booked-meeting cycle is 3-21 days.

---

## 3. The Technology Stack

Every piece of the system, and what it does:

### Database & Backend
- **Supabase** — PostgreSQL database with built-in REST API, authentication, and row-level security. This is where ALL lead data lives. Project ID: `zqwatouqmqgkmaslydbr`.
- **PostgreSQL** — The actual database engine under Supabase. You write SQL against it.

### Automation Engine
- **n8n** — Workflow automation platform. All 14 workflows run here. Self-hosted at `https://automation.crystallux.org`. Think of it as "Zapier on steroids, but owned by you."

### AI
- **Claude (Anthropic)** — The AI that does research, scoring, signal detection, and email writing. Accessed via Anthropic API with API key.

### External Data Sources
- **Google Maps / Google Places API** — Where new leads come from (business discovery).
- **Apollo.io** — Planned addition for B2B email enrichment (not yet integrated).

### Email
- **Gmail (personal)** — Current sending inbox (`adesholaakintunde@gmail.com`).
- **Google Workspace (info@crystallux.org)** — In progress, pending domain verification.

### Hosting
- **Hostinger VPS** — Virtual server where n8n runs. IP: `187.77.20.222`.
- **Cloudflare (likely)** — DNS and SSL for the domain.

### Dev Tools
- **GitHub** — Code repository (`Mary-creat/crystallux-ai-sales-engine`). All workflow JSONs, SQL migrations, and docs live here.
- **Claude Code** — AI coding assistant running on the VPS. Used to edit workflows, run SQL, and debug.
- **Claude (chat)** — This conversation. Used for planning, strategy, and reviewing work.

### Client-Facing
- **Dashboard** — Web app at `localhost:3000` (dev) / TBD (production) showing live pipeline stats.
- **Calendly** — Where prospects book meetings. Each client has their own Calendly link.

### The Big Picture

```
┌────────────────────────────────────────────────────────┐
│                       CLIENT                            │
│               (e.g. Blonai Moving Company)              │
└─────────────────────┬──────────────────────────────────┘
                      │ pays monthly subscription
                      ▼
┌────────────────────────────────────────────────────────┐
│                   CRYSTALLUX                            │
│                                                         │
│  ┌────────┐   ┌───────┐   ┌────────┐   ┌──────────┐    │
│  │ n8n    │◄─►│Supa-  │◄─►│ Claude │   │ Dashboard│    │
│  │workflow│   │ base  │   │  AI    │   │  (stats) │    │
│  └────┬───┘   └───────┘   └────────┘   └──────────┘    │
│       │                                                 │
│       ├────► Google Maps (discover leads)              │
│       ├────► Scraper (find emails)                     │
│       ├────► Gmail (send outreach)                     │
│       └────► Calendly (book meetings)                  │
└─────────────────────┬──────────────────────────────────┘
                      │ delivers booked meetings
                      ▼
┌────────────────────────────────────────────────────────┐
│           CLIENT'S CALENDAR (Calendly)                  │
└────────────────────────────────────────────────────────┘
```

---

## 4. Key Concepts You Need to Know

### 4.1 What is a database?

A database is a structured way to store information. Think of it as a collection of spreadsheets (called **tables**) where:

- Each **row** is one item (like one lead)
- Each **column** is a property of that item (like email, company name, status)
- **Columns have types** — text, integer, boolean (true/false), timestamp, etc.

When you run a query like `SELECT email FROM leads WHERE company = 'Acme'`, you're asking the database "give me the email column from the leads table for any row where company equals Acme."

### 4.2 NULL vs empty string — a gotcha you've already hit

- `NULL` means "no value exists" (literally nothing is there)
- `''` (empty string) means "there's a value, and it's zero characters long"

In SQL, these are **different**. `WHERE email IS NULL` will NOT match a row where email is `''`. To catch both, use: `WHERE email IS NULL OR email = ''`.

We hit this exact bug today when filtering "personal emails" — 76 leads matched a filter that was supposed to exclude them, because they had empty string emails, not NULL emails.

### 4.3 What is SQL?

SQL (Structured Query Language) is how you talk to databases. The five commands you'll use 99% of the time:

- `SELECT` — read data
- `INSERT` — add new data
- `UPDATE` — change existing data
- `DELETE` — remove data
- `ALTER TABLE` — change the structure (add columns, etc.)

See [Section 7](#7-common-sql-queries-youll-actually-use) for actual queries you'll use.

### 4.4 What is an API?

An API (Application Programming Interface) is how one piece of software talks to another over the internet. When your workflow sends a lead to Claude for research, it's making an API call.

Every API call has:
- A **URL** — where to send it
- A **method** — GET (read), POST (create/act), PUT (replace), PATCH (update), DELETE (remove)
- **Headers** — metadata, often including auth keys
- A **body** — the actual data being sent (for POST, PUT, PATCH)

### 4.5 What is RPC (and why we use it everywhere)?

**RPC = Remote Procedure Call.** It means "call a function on a server as if it were local code."

In Crystallux, **RPC refers to calling custom PostgreSQL functions via Supabase's REST API.**

Your database has functions like `update_lead()` defined inside it. Instead of writing SQL in every workflow, the workflow sends an HTTP POST to a URL like `/rest/v1/rpc/update_lead` with the function's arguments. Supabase runs the function and returns the result.

**Why Crystallux uses RPC for all writes (not direct table updates):**

1. **Auth limitation.** Supabase direct PATCH requires two auth headers (`apikey` + `Authorization`). Your credential only sends `apikey`. RPC POST only needs `apikey`, so it works.
2. **Bypasses RLS.** RPC functions are marked `SECURITY DEFINER`, meaning they run with database-owner permissions. This lets them write to tables where Row-Level Security would normally block them.
3. **Atomic operations.** Functions like `insert_lead_if_not_exists` do multiple things in one transaction (check for duplicate + insert), which is safer than two separate HTTP calls.
4. **Type safety.** Functions explicitly cast field types, preventing silent coercion bugs.

### 4.6 What is RLS (Row-Level Security)?

RLS is a database feature that decides "who can see or change which rows." In Crystallux, RLS policies ensure:

- A client can only see their own leads, not other clients' leads
- The anonymous API key has limited read access
- Write operations go through `SECURITY DEFINER` functions that enforce proper auth

If RLS is misconfigured, either: (a) nobody can read/write anything (too strict) or (b) anyone can read/write everything (too loose). Both are bad.

### 4.7 What is n8n?

n8n is a workflow automation tool. A workflow is a series of **nodes** connected like a flowchart:

- **Trigger nodes** start a workflow (webhook, schedule, manual)
- **Code nodes** run JavaScript on the data
- **HTTP Request nodes** call external APIs
- **IF nodes** branch based on conditions
- **Split In Batches (SIB) nodes** loop over many items

Data flows from one node to the next. Each node can see the output of the previous node(s).

### 4.8 Why `$input.item.json` instead of `$('NodeName').item.json`

In n8n Code nodes, you can reference data two ways:

- `$input.item.json` — the data from the node directly before this one, for THIS iteration of the loop
- `$('NodeName').item.json` — data from a named node by reference

In a loop (Split In Batches), `$('NodeName')` can return **stale data** from a previous iteration or the wrong item. `$input.item.json` always reflects the current item being processed. **Always use `$input.item.json` in loops.** This is a bug Crystallux has already hit and fixed.

### 4.9 "Run Once for Each Item" vs "Run Once for All Items"

n8n Code nodes have a mode setting:

- **Run Once for Each Item** — the code runs separately for each item in the input, one at a time. Use this for per-lead operations like formatting, prep, API body building.
- **Run Once for All Items** — the code runs once with ALL items available together. Use this for aggregations like counting, statistics, batch summaries.

Using the wrong mode silently breaks things. If you're updating leads in a loop and it's set to "Run Once for All Items," you'll only update one lead and not know why.

### 4.10 continueOnFail — when it helps and when it hurts

Setting `continueOnFail: true` on an HTTP node means "if this call fails, don't halt the workflow — keep going with the other items."

**Good use:** An external API times out on one lead. You don't want that to stop processing of the other 49 leads in the batch.

**Bad use:** A database write fails. Now you've lost data AND the workflow keeps going as if everything is fine. Silent failure.

Rule of thumb: `continueOnFail: true` is okay for read operations or idempotent external calls. For write operations, you want it OFF, or you want explicit error logging to catch failures.

### 4.11 The Split In Batches (SIB) wiring swap bug

This is a recurring n8n bug that affects Crystallux. When you export a workflow JSON and re-import it, the Split In Batches node's two outputs can **get swapped**:

- `done` output (should go to summary node) ends up wired to the loop
- `loop` output (should go back to processing) ends up wired to done

If this happens, the workflow either runs once and stops, or loops forever, depending on which way it swapped. **Always visually inspect SIB wiring after every import.**

---

## 5. The 14 Workflows: What Each One Does

### Production workflows (hardened v2/v3)

**1. CLX - B2C Discovery v2.1**
Scans Google Maps for businesses matching target industries and cities. Uses smart scanning to avoid re-scanning recently-scanned queries. Saves each new business as a lead.
- Trigger: schedule
- Writes to: `leads`, `scan_log`, `scan_query_tracker`
- Status: Active

**2. CLX - Email Scraper v3**
Visits each lead's website, scrapes contact emails, saves to the lead record. Currently being fixed to read from the new `website` column.
- Trigger: schedule (every 2 hours, changing to 1 hour)
- Reads: `leads` where `email IS NULL` and `website IS NOT NULL`
- Writes to: `leads.email`, `leads.email_enriched`
- Status: Active but under revision

**3. CLX - Lead Research v2**
For each new lead, uses Claude Haiku to research the company and generate a summary. Populates `research_summary`, `likely_business_need`, `research_angle`.
- Trigger: schedule or trigger from new lead
- Status: Active

**4. CLX - Lead Scoring v2**
Scores each researched lead 0-100 using Claude Haiku based on fit, size, industry, signals.
- Writes to: `leads.lead_score`, `leads.scoring_reason`
- Status: Active

**5. CLX - Business Signal Detection v2**
Looks for buying signals: growth indicators, hiring, pain points, seasonal triggers.
- Writes to: `leads.detected_signal`, `leads.signal_confidence`
- Status: Active

**6. CLX - Campaign Router v2**
Based on industry, signal, and score, decides what campaign angle to use (pain point focus, growth focus, savings focus, etc.).
- Writes to: `leads.campaign_type`, `leads.campaign_message_angle`
- Status: Active, but only processing ~1 in 30 leads — needs investigation

**7. CLX - Outreach Generation v2**
Writes a personalized email (subject + body) for each lead using Claude.
- Writes to: `leads.email_subject`, `leads.email_body`, `leads.followup_message`
- Status: Active, but wastes Claude credits generating emails for leads with no email address

**8. CLX - Outreach Sender v2**
Sends generated emails via Gmail with CASL (Canadian anti-spam) compliance footer.
- Writes to: `leads.outreach_sent_at`, `leads.lead_status = Contacted`
- Status: Active

**9. CLX - Follow Up v2**
Sends follow-up emails to leads who haven't replied after a set time.
- Status: Active

**10. CLX - Booking v2**
Detects interest in replies. Sends Calendly link to interested prospects.
- Writes to: `leads.booking_email_sent`, `leads.calendly_link`
- Status: Active but Calendly integration needs verification

**11. CLX - Pipeline Update v2**
Calculates pipeline statistics every 6 hours, saves snapshot to `pipeline_stats`.
- Status: Active, Calculate Statistics node mode needs to be verified as "Run Once for All Items"

### Non-hardened workflows (older, should be reviewed or retired)

**12. CLX - City Scan Discovery** — older discovery workflow, likely superseded by B2C Discovery v2.1
**13. CLX - Lead Import** — manual bulk import tool
**14. CLX - MCP Tool Gateway** — webhook API layer for dashboard actions, not yet hardened

---

## 6. The Database: Tables, Columns, Functions

### Main tables

**`leads`** — 2,282 rows. The core table. Every prospect in the system. ~75 columns covering everything from basic info (company, email, phone) to workflow state (lead_status, scores, research, outreach content, timestamps, flags).

Key columns you'll reference often:
- `id` — UUID, primary key
- `company` — business name
- `email` — contact email (NULL or empty string for most right now)
- `website` — business website URL (newly added, backfilled from notes)
- `place_id` — Google Places ID for re-querying
- `industry`, `city` — targeting fields
- `lead_status` — where it is in pipeline (see Section 2)
- `lead_score` — 0-100 fit score
- `lead_type` — `NULL` for real leads, `'test'` for test records
- `client_id` — which client owns this lead
- `research_summary`, `likely_business_need`, `research_angle` — AI research outputs
- `email_subject`, `email_body`, `followup_message` — AI-generated outreach content
- `do_not_contact`, `unsubscribed` — suppression flags
- `email_enriched`, `email_enriched_at` — scraper status flags

**`clients`** — 2 rows. Who pays for Crystallux. Has name, industry, monthly fee, etc.

**`scan_log`** — every scan attempt, for debugging

**`scan_errors`** — errors from workflow runs, for debugging silent failures

**`scan_query_tracker`** — smart-scan frequency controller (which queries have been run recently)

**`pipeline_stats`** — snapshots for dashboard

**`mcp_tool_calls`** — logs for the MCP Tool Gateway

**`leads_backup_20260416`** — point-in-time backup from the enrichment schema fix

### RPC Functions (the ones your workflows call)

- `update_lead(uuid, jsonb)` — universal lead updater. Takes a lead ID and a JSON of fields to update. Handles type casting.
- `insert_lead_if_not_exists(...)` — safely inserts a new lead, or does nothing if a duplicate exists. Atomic.
- `upsert_scan_tracker(...)` — marks a query as scanned to enable smart frequency control
- `update_lead_after_send(uuid, ...)` — called by Outreach Sender after a successful email send
- `mark_lead_send_failed(uuid, text)` — called when an email send fails
- `get_daily_send_count()` — returns how many emails have been sent today (for Gmail limit protection)

### Views

- `dashboard_scan_summary` — pre-joined data for the dashboard

---

## 7. Common SQL Queries You'll Actually Use

### Quick health check — what's the pipeline look like right now?

```sql
SELECT
  lead_status,
  COUNT(*) AS count
FROM leads
WHERE lead_type != 'test' OR lead_type IS NULL
GROUP BY lead_status
ORDER BY count DESC;
```

### How many leads have contactable emails?

```sql
SELECT
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE email IS NOT NULL AND email != '') AS has_email,
  COUNT(*) FILTER (WHERE website IS NOT NULL AND website != '') AS has_website
FROM leads
WHERE lead_type != 'test' OR lead_type IS NULL;
```

### Find leads stuck in a status for too long

```sql
SELECT id, company, lead_status, updated_at
FROM leads
WHERE lead_status = 'Researched'  -- change to whichever status
  AND updated_at < NOW() - INTERVAL '7 days'
  AND (lead_type != 'test' OR lead_type IS NULL)
ORDER BY updated_at ASC
LIMIT 20;
```

### How many emails sent today?

```sql
SELECT COUNT(*)
FROM leads
WHERE outreach_sent_at::date = CURRENT_DATE;
```

### What's today's reply rate?

```sql
SELECT
  COUNT(*) FILTER (WHERE outreach_sent_at::date = CURRENT_DATE) AS sent_today,
  COUNT(*) FILTER (WHERE reply_detected = true AND outreach_sent_at::date = CURRENT_DATE) AS replied_today;
```

### Show me a specific lead's full record

```sql
SELECT * FROM leads WHERE company ILIKE '%acme%';
-- ILIKE is case-insensitive LIKE
```

### Show me all columns in the leads table (when you forget a column name)

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'leads'
ORDER BY ordinal_position;
```

### Recent errors (for debugging)

```sql
SELECT * FROM scan_errors
ORDER BY created_at DESC
LIMIT 20;
```

### Create a safety backup before big changes

```sql
CREATE TABLE leads_backup_YYYYMMDD AS SELECT * FROM leads;
```

### Undo a bad UPDATE from a backup

```sql
UPDATE leads
SET email = (SELECT email FROM leads_backup_YYYYMMDD WHERE id = leads.id)
WHERE id IN (SELECT id FROM leads_backup_YYYYMMDD);
```

### Counts that matter for a client pitch

```sql
SELECT
  (SELECT COUNT(*) FROM leads WHERE lead_type != 'test' OR lead_type IS NULL) AS total_leads_discovered,
  (SELECT COUNT(*) FROM leads WHERE email IS NOT NULL AND email != '') AS leads_with_contact_info,
  (SELECT COUNT(*) FROM leads WHERE outreach_sent_at IS NOT NULL) AS outreach_sent,
  (SELECT COUNT(*) FROM leads WHERE reply_detected = true) AS replies_received,
  (SELECT COUNT(*) FROM leads WHERE meeting_scheduled = true) AS meetings_booked;
```

---

## 8. When Things Break: Troubleshooting Guide

### "Nothing is happening in the pipeline"

Check in this order:
1. Is n8n running? (SSH to VPS, check the n8n service)
2. Are the workflows active? (n8n UI, look for green toggle on each workflow)
3. When did the last execution run? (n8n "Executions" tab)
4. Are there errors? (`SELECT * FROM scan_errors ORDER BY created_at DESC LIMIT 10;`)

### "A workflow ran but the data didn't change"

Check in this order:
1. Did the workflow actually complete successfully? (n8n Executions view, look for green vs red nodes)
2. Did the write happen? (query the table and check the updated_at timestamp)
3. If a Code node is involved: is it in "Run Once for Each Item" mode?
4. If using `$('NodeName').item.json`: switch to `$input.item.json`
5. If SIB loop involved: check that wiring didn't swap (done output → summary, loop output → processing)
6. If an HTTP node has `continueOnFail: true`: silent failures hide errors — temporarily turn it off to see what's failing

### "Emails aren't getting sent"

1. Check Gmail credential in n8n — re-auth if OAuth token expired
2. Check daily send count: `SELECT get_daily_send_count();` — Gmail limits apply
3. Check do_not_contact flag: `SELECT * FROM leads WHERE email_body IS NOT NULL AND do_not_contact = true;`
4. Check for rate limiting in n8n execution logs

### "Claude API calls are failing"

1. Check API key is valid and has credits (Anthropic console)
2. Check rate limits (Anthropic can throttle on burst)
3. Check n8n credential name matches what workflows reference

### "Supabase writes are failing"

1. Check Supabase is up (dashboard.supabase.com)
2. Confirm you're using RPC POST, not direct PATCH
3. Check RLS policies — `SECURITY DEFINER` on functions is critical
4. Check the RPC body JSON structure — `{p_lead_id, p_fields}` format

### "Dashboard is showing wrong numbers"

1. Default row limit on Supabase is 1000 — add `limit=5000` and `Prefer: count=exact` header
2. Filter for `lead_type != 'test'` — test records shouldn't count
3. Force refresh the dashboard cache

### Emergency SSH commands to the VPS

```bash
# Check n8n is running
ps aux | grep n8n

# Tail n8n logs
tail -f /path/to/n8n/logs/*.log

# Restart n8n (adjust for your setup)
systemctl restart n8n
# or
pm2 restart n8n
# or
docker restart n8n
```

---

## 9. Security and Access

### Who has access to what

- **Database (Supabase):** Owner account only, plus service role key (in n8n) and anon key (for dashboard reads)
- **n8n:** Owner account, admin UI at automation.crystallux.org
- **VPS:** SSH access via key, root password
- **GitHub:** Owner + collaborators
- **API keys (Claude, Google Maps, etc.):** Stored in n8n credentials, never in git

### Secrets rotation — when and why

Rotate immediately if:
- A key is exposed in git history (Hunter.io was — already rotated)
- A developer leaves
- A suspicious access pattern is noticed
- It's been more than 6 months

### Backup strategy

- Supabase has automated daily backups on paid tiers
- Manual `leads_backup_YYYYMMDD` tables before risky migrations
- GitHub holds all workflow JSONs and SQL migrations (code backup)

### CASL compliance (Canadian anti-spam law)

Every email sent must include:
- Identification of the sender
- An unsubscribe mechanism
- A physical mailing address

The Outreach Sender v2 workflow includes a CASL footer. Do not remove it.

---

## 10. For the Pitch: Talking Points

### When a client asks "what does this do?"

"It's an AI sales engine. It finds your ideal customers, researches each one, writes them a personal email, sends it, handles replies, and books qualified meetings on your calendar — automatically, 24/7. It does the work of 3-5 sales development reps for about 1/10th the cost."

### When a client asks "how is this different from other tools?"

"Three ways. First, every email is individually researched and personalized — not a template with merge fields. Second, we only reach out when there's a buying signal, so your prospects don't feel spammed. Third, we're built specifically for [their industry] — we know the seasonal patterns, the pain points, the triggers that matter."

### When a client asks "how do you find leads?"

"We scan Google Maps for businesses matching your ideal customer profile — by industry, location, size. We deduplicate, enrich with contact info, research each one individually using AI, and score them for fit. Only the best-fit leads get reached out to."

### When a client asks "how do you know it'll work?"

"We're currently showing [X% reply rate, Y bookings per 100 sends] on live data. [When you have real numbers, quote them.] We start every client with a pilot phase to validate targeting before scaling up."

### When a client asks "what if the AI writes a bad email?"

"Every email template goes through a review cycle before going live. You see a sample of 10-20 generated emails before we send anything. We iterate on the messaging until you're comfortable with the tone and positioning."

### When a client asks "is this going to spam my domain reputation?"

"No. We send in small batches, from a dedicated sending domain (not your primary), with proper SPF/DKIM/DMARC setup. We respect CASL, CAN-SPAM, and GDPR. Every email has a working unsubscribe. We monitor for bounces and blacklist any problem addresses."

### When a client asks "how long before I see results?"

"First sends within 1 week of onboarding. First replies typically within 2 weeks. First booked meetings within 3-4 weeks. Meaningful pipeline within 6-8 weeks."

### When a client asks about pricing

"$500/month for base tier — covers up to [X] leads/month and [Y] sends/month. Scaling tiers available for higher volume. No long-term contracts — month to month."

---

## 11. Glossary

- **API** — Application Programming Interface; how software talks to software
- **Atomic operation** — something that either fully completes or fully fails; no half-states
- **Backfill** — populating a column with values derived from existing data (like extracting website from notes)
- **CASL** — Canada's Anti-Spam Legislation
- **Credential** — stored auth info for an external service (API key, OAuth token)
- **CI/CD** — Continuous Integration / Continuous Deployment; automated testing and releasing of code
- **Claude Haiku** — Anthropic's fastest/cheapest AI model, used for high-volume research and scoring
- **DNS** — Domain Name System; maps domain names to IP addresses
- **End-to-end test** — testing the full pipeline from start to finish on real data
- **Enrichment** — adding missing data to a lead (email, phone, contact name)
- **HTTP methods** — GET (read), POST (create/act), PUT (replace), PATCH (modify), DELETE (remove)
- **JSON** — data format used by most modern APIs; looks like `{"key": "value"}`
- **JWT** — JSON Web Token; a way to prove identity to an API
- **Lead** — a prospective customer (the businesses we're trying to reach on behalf of our clients)
- **MCP** — Model Context Protocol; how Claude interacts with external tools in some setups
- **MGA** — Managing General Agency (insurance industry term)
- **MRR** — Monthly Recurring Revenue
- **n8n** — Self-hosted workflow automation platform where all 14 Crystallux workflows run. Think "Zapier you own."
- **PostgreSQL** — The open-source SQL database engine running under Supabase. The actual engine executing your queries.
- **RLS (Row-Level Security)** — Postgres feature controlling which rows a given user can read or write. Enforces per-client data isolation.
- **RPC (Remote Procedure Call)** — Calling a server-side database function over HTTP. Crystallux uses RPC POST for all writes to bypass RLS and avoid direct PATCH auth issues (see 4.5).
- **SDR (Sales Development Representative)** — A human sales prospector. Crystallux replaces the output of 3-5 SDRs per client at roughly 1/10th the cost.
- **SIB (Split In Batches)** — n8n node that loops over items in chunks. Has a known wiring-swap bug on workflow re-import — always inspect after import (see 4.11).
- **SQL** — Structured Query Language; how you talk to the database. Five commands cover 99% of daily use: SELECT, INSERT, UPDATE, DELETE, ALTER TABLE.
- **Supabase** — Hosted Postgres with built-in REST API, auth, and RLS. Where all Crystallux lead data lives. Project ID `zqwatouqmqgkmaslydbr`.
- **VPS (Virtual Private Server)** — Rented cloud server. Crystallux runs n8n on a Hostinger VPS at `187.77.20.222`.

---

## 12. Backup / Restore

Crystallux runs on a single Hostinger VPS. Two databases carry state:

1. **Supabase Postgres** (primary) — all lead data, clients, niche_overlays, scan_errors. Supabase provides daily automated backups with 7-day retention on the free tier. Dashboard → Database → Backups.
2. **n8n internal Postgres** — workflow definitions, credentials (encrypted), execution history. **This is the at-risk surface.** If the VPS dies, restoring n8n's DB is how you bring everything back without re-importing + re-authorizing.

### 12.1 Verification script

`scripts/test-restore.sh` dumps the live Supabase DB, restores it into a scratch database on the same host, runs sanity checks (leads, clients, niche_overlays counts > 0), and drops the scratch DB.

```bash
# Dry run (print commands, don't execute)
./scripts/test-restore.sh --dry-run

# Real run
./scripts/test-restore.sh
```

**Expected output on success:**
```
[1/5] Dumping ... Dump size: 4823610 bytes
[2/5] Creating scratch database ...
[3/5] Restoring dump ...
[4/5] Running sanity checks ...
    leads: 62, clients: 1, niche_overlays: 1
[5/5] Dropping scratch database ...
✓ PASS: restore verified end-to-end.
```

### 12.2 When to run

- **Weekly** (Sunday night, low traffic)
- **Before any schema migration** (including sprint migrations like `2026-04-22-scale-sprint-v1.sql`)
- **Before onboarding each new-client wave**
- **After any significant n8n version change**

### 12.3 What it does NOT cover

- n8n internal DB (credentials, executions) — add a second script pointed at the n8n postgres container in a follow-up sprint
- Off-site backups — if the VPS itself dies, Supabase's own backups cover Crystallux data but n8n workflow state is lost. Git is the safety net for workflow JSON; credentials must be re-entered manually.
- Restore timing — this script does not measure restore duration under load. Time a full restore once per quarter.


## 13. Apollo Integration — Activation Steps

Apollo enrichment scaffolding (Part B.5) ships dormant. The schema migration
`docs/architecture/migrations/2026-04-23-apollo-schema.sql` is idempotent and
safe to apply ahead of time; the workflow `clx-apollo-enrichment-v1.json`
imports with its Schedule Trigger turned off and no live API calls until you
complete these six steps:

1. **Sign up for Apollo** at https://apollo.io — pick the Basic plan (~$49/mo,
   ~1,200 credits/month). Email-and-phone reveal is the minimum tier the
   enrichment flow needs.
2. **Add the key to `.env`** on the n8n host: set `APOLLO_API_KEY=<your key>`.
   The placeholder is already scaffolded under the "Apollo Enrichment
   (Part B.5)" block in `.env.example` (line 89).
3. **Create the n8n credential** — n8n UI → **Credentials → New → HTTP Header
   Auth**. Name it exactly `Apollo`. Header name `X-Api-Key`, header value
   `{{ $env.APOLLO_API_KEY }}` (preferred) or the literal key. Save.
4. **Bind the credential** to the three Apollo HTTP nodes in
   `clx-apollo-enrichment-v1`: **Apollo People Search**,
   **Apollo Contact Enrichment**, **Apollo Organization Enrichment**. Open
   each node → Credentials dropdown → pick `Apollo`. The nodes ship with no
   credentials block attached so this step is unmissable.
5. **Test with a single lead** via the manual webhook (no need to activate
   the scheduler yet):
   ```bash
   curl -X POST https://<your-n8n-host>/webhook/clx-apollo-enrichment-v1 \
        -H "Content-Type: application/json" \
        -d '{"lead_id":"<some-lead-uuid>"}'
   ```
   Verify: the `leads` row has non-null `apollo_enriched_at`, and a row
   appears in `apollo_credits_log` for that lead.
6. **Activate the Schedule Trigger** once the single-lead test passes. The
   trigger is set to 30-minute intervals by default; dial it down if you're
   approaching the 1,150/month guard threshold.

### Quota guard and error handling

- Before each Apollo call, the workflow hits
  `get_monthly_apollo_credits_used()` and skips with `apollo_quota_exceeded`
  → `scan_errors` when usage > 1,150. The buffer below Apollo's 1,200 Basic
  cap leaves room for in-flight retries.
- RPC write failures are caught and logged to `scan_errors` with
  `error_code = 'APOLLO_ENRICHMENT_FAILED'`. `clx-error-monitor-v1` already
  has a matching threshold row (5 failures in 10min → warning), seeded in the
  prior migration.

### Lead-Research v2 integration

`clx-lead-research-v2` now calls `clx-apollo-enrichment-v1` as an Execute
Workflow step *before* the Claude Research Lead node. The step has
`continueOnFail: true`, so:

- **Before** you configure the Apollo credential, the sub-workflow fails auth
  on its Apollo HTTP nodes and execution falls through to Claude — the
  research flow continues uninterrupted.
- **After** activation, Apollo enriches the lead first, Claude reasons over
  both scraped and Apollo-verified data, and the downstream scoring flow
  picks up the Apollo bonus automatically.

### Lead-Scoring v2 Apollo bonus

`clx-lead-scoring-v2`'s Parse Scoring Response node layers on top of Claude's
0–100 score:

- `+10` if `apollo_enriched_at IS NOT NULL` (any Apollo data at all)
- `+15` if `job_title_verified` matches any of the insurance_broker
  decision-maker keywords (`Broker of Record`, `Principal`, `Owner`,
  `Managing Partner`, `President`, `Founder`)

Final score is clamped to 100. The bonus is appended to `scoring_reason` as
`[Apollo bonus +N]` so the audit trail is obvious in the dashboard.

---

## 14. Multi-Channel Activation — LinkedIn, WhatsApp, Voice

Multi-channel outreach scaffolding (Part B.6) ships dormant. The schema
migration (`docs/architecture/migrations/2026-04-23-multi-channel.sql`) is
safe to run immediately — it adds channel routing columns to `leads`, a
central `outreach_log`, three per-channel provider tables, the daily-count
RPCs, and a **placeholder `check_dncl_status(phone)` that always returns
true**. The four new workflows (`clx-linkedin-outreach-v1`,
`clx-whatsapp-outreach-v1`, `clx-voice-outreach-v1`,
`clx-voice-result-webhook-v1`) ship with their triggers deactivated and
their provider HTTP nodes bound to no credential. Activation is per-channel
and deliberate; do not enable all three at once.

The Campaign Router (v2) already sets `leads.preferred_channel` on every
lead it assigns. Default is `'email'`, so the router is safe to leave
active even before any channel workflow is enabled — nothing will route
out-of-band until you set `clients.channels_enabled` to include the new
channel AND activate the corresponding sender workflow.

### 14.1 LinkedIn (Unipile)

1. **Sign up for Unipile** at https://unipile.com — Basic plan is ~€79/mo
   and includes the LinkedIn connector. Connect at least one LinkedIn
   account through the Unipile dashboard; note the `account_id` and the
   per-tenant API host (looks like `apiNN.unipile.com:PORT`).
2. **Add to `.env`**: `UNIPILE_API_KEY=...`.
3. **Create n8n credential**. In n8n: Credentials → New → **HTTP Header
   Auth**. Name it exactly `Unipile`. Header name `X-API-KEY`, header value
   the key from step 2.
4. **Bind + configure the workflow**. Open `clx-linkedin-outreach-v1` →
   **Unipile Send Invite** node. In the URL, replace the
   `api6.unipile.com:13619` host with the host Unipile issued for your
   tenant. In the JSON body, replace `TODO_UNIPILE_ACCOUNT_ID` with the
   real `account_id`. Open the Credentials dropdown and pick `Unipile`.
5. **Enable the channel for one client.** In Supabase:
   `UPDATE clients SET channels_enabled = channels_enabled || '["linkedin"]'::jsonb WHERE id = '...';`
6. **Dry-run via the Manual Webhook.** POST `{ "lead_id": "..." }` to the
   workflow's webhook URL with a test lead whose `preferred_channel` is
   `linkedin` and whose `linkedin_url` is populated. Confirm one row lands
   in `linkedin_outreach_log` and `outreach_log`.
7. **Activate the Schedule Trigger** only after the dry-run succeeds.
8. **Platform/compliance notes.** LinkedIn tolerates ~20 connection
   invites/day/account; the workflow caps at **18** per client to keep a
   retry buffer. `LINKEDIN_SEND_FAILED` in `monitoring_thresholds` fires a
   `warning` after 5 failures in 10 minutes.

### 14.2 WhatsApp (Twilio)

1. **Provision Twilio WhatsApp Business API.** Buy a WhatsApp sender
   number in the Twilio Console. Register at least one outreach **message
   template** — opening messages on WhatsApp must use an approved template
   until a 24-hour session window has been opened by the recipient's reply.
2. **Add to `.env`**: `TWILIO_ACCOUNT_SID=...`, `TWILIO_AUTH_TOKEN=...`,
   `TWILIO_WA_NUMBER=...` (E.164, e.g. `15551234567`).
3. **Create n8n credential**. Credentials → New → **Basic Auth**. Name it
   exactly `Twilio WhatsApp`. Username = Account SID, Password = Auth
   Token.
4. **Bind + configure the workflow.** Open `clx-whatsapp-outreach-v1` →
   **Twilio Send** node. Replace `TWILIO_ACCOUNT_SID_PLACEHOLDER` in the
   URL. Replace `TWILIO_WA_NUMBER_PLACEHOLDER` in the `From` body
   parameter. Open the Credentials dropdown and pick `Twilio WhatsApp`.
5. **Enable the channel for one client.** In Supabase:
   `UPDATE clients SET channels_enabled = channels_enabled || '["whatsapp"]'::jsonb WHERE id = '...';`
6. **Dry-run via the Manual Webhook** against Mary's personal WhatsApp
   number — post a single lead with `preferred_channel='whatsapp'` and a
   mobile phone populated. Confirm one row lands in `whatsapp_outreach_log`
   and `outreach_log`.
7. **Activate the Schedule Trigger** only after the dry-run.
8. **Locale/compliance notes.** For non-Canadian leads, keep
   `preferred_channel != whatsapp` unless your template is approved in the
   target locale. Workflow caps at **90/day/client** (buffer under Twilio's
   default 100 template-pacing cap). `WHATSAPP_SEND_FAILED` fires a
   `warning` after 5 failures in 10 minutes.

### 14.3 Voice (Vapi + DNCL)

Voice has one extra gate beyond LinkedIn/WhatsApp — the **DNCL
compliance check** for Canadian leads. It is mandatory and blocking.

1. **Sign up for Vapi** at https://vapi.ai. Connect a Twilio phone number
   via the Twilio → Vapi SIP trunk bridge. Note the `phoneNumberId` Vapi
   issues (UUID-shaped).
2. **Create a Vapi Assistant.** In the Vapi dashboard, build an assistant
   using the seeded `voice_script_template` from `niche_overlays` as the
   opening line. Pick a voice provider (11labs `rachel` is a reasonable
   default and is what the workflow requests).
3. **Add to `.env`**: `VAPI_API_KEY=...`.
4. **Create n8n credential**. Credentials → New → **HTTP Header Auth**.
   Name it exactly `Vapi`. Header name `Authorization`, header value
   `Bearer {your key}`.
5. **Bind + configure the workflow.** Open `clx-voice-outreach-v1` →
   **Vapi Dial** node. Replace `VAPI_PHONE_NUMBER_ID_PLACEHOLDER` with the
   `phoneNumberId` from step 1. Open Credentials and pick `Vapi`.
6. **Wire the result webhook.** Open `clx-voice-result-webhook-v1` —
   activate the workflow and copy its production webhook URL. In the Vapi
   dashboard, set the assistant's **end-of-call webhook URL** to this
   address so Vapi posts call outcomes back (transcript, duration, cost,
   recording).
7. **DNCL compliance — MANDATORY before the first live Canadian call.**
   The `check_dncl_status(phone)` function shipped in the migration is a
   PLACEHOLDER that always returns `true`. Before activating the Schedule
   Trigger, replace its body with one of:
   - (a) A nightly sync of the CRTC National DNCL into a local
     `dncl_registry` table, plus a real `SELECT NOT EXISTS(...)` lookup
     from `check_dncl_status`. Requires a paid CRTC subscription.
   - (b) A live API-based check against a compliant DNCL lookup provider
     (e.g. DNCScrub, Gryphon). Reconfigure the function to call an edge
     function or Supabase HTTP extension that hits the provider.
   Until (a) or (b) is in place, do NOT enable the voice Schedule Trigger
   for Canadian leads. The workflow logs `VOICE_DNCL_BLOCKED` to
   `scan_errors` when the function returns `false`; the monitoring
   threshold for that code is `critical` at 1 event per 60 minutes.
8. **Enable the channel for one client.** In Supabase:
   `UPDATE clients SET channels_enabled = channels_enabled || '["voice"]'::jsonb WHERE id = '...';`
9. **Dry-run via the Manual Webhook** against Mary's personal phone — post
   a single lead with `preferred_channel='voice'` and a callable number.
   Confirm one row in `voice_call_log` and `outreach_log`, and confirm the
   result webhook is updating the `voice_call_log` row end-to-end with
   transcript/duration/cost after the call ends.
10. **Activate the Schedule Trigger** only after DNCL is real, the dry-run
    succeeds, and the end-of-call webhook has been verified against at
    least one full call. Workflow caps at **45 calls/day/client** (buffer
    under the 50/day design limit). `VOICE_CALL_FAILED` fires a `critical`
    alert after 3 failures in 10 minutes.

### 14.4 Activation checklist (per-channel, before going live)

- [ ] Provider account provisioned and credentials in `.env`
- [ ] n8n credential created with the exact name listed above
- [ ] Placeholder tokens inside the workflow JSON replaced (account IDs,
      phone IDs, tenant hosts)
- [ ] Credentials dropdown in the provider HTTP node bound
- [ ] `clients.channels_enabled` updated to include the channel
- [ ] For **voice only**: `check_dncl_status` replaced with a real lookup
- [ ] Manual webhook dry-run succeeds for one test lead
- [ ] Provider log table and `outreach_log` both show the dry-run entry
- [ ] Schedule Trigger activated
- [ ] One real outbound observed in production against a non-Mitch
      Insurance lead (Mitch remains `do_not_contact=true` at all times)

### 14.5 Decommission / rollback

To silence any one channel without editing workflow JSON:

- Set `clients.channels_enabled` to exclude the channel: the Campaign
  Router falls back to `email` for any lead in that client. Leads already
  in `preferred_channel=<channel>` remain in that state until a future
  router pass rewrites them.
- Or, deactivate the Schedule Trigger in the channel workflow directly —
  in-flight batches finish; no new batches start.

Full schema rollback is at the bottom of
`2026-04-23-multi-channel.sql`, commented out. Test on a staging schema
first; the migration drops table data when uncommented.

---

## 15. Video Outreach Activation — Tavus

Part B.7 ships video-outreach scaffolding dormant: migration, two
workflows (`clx-video-outreach-v1`, `clx-video-ready-v1`), a 48h
no-booking fallback branch in `clx-booking-v2`, and a score-gated
routing rule in `clx-campaign-router-v2`. Nothing sends a live Tavus
request until the steps below are completed, per-client.

The flow end-to-end once activated:

1. Campaign Router (or Booking v2 48h fallback, or a direct webhook POST)
   sets `preferred_channel='video'` on a lead and triggers
   `clx-video-outreach-v1`.
2. That workflow pulls the niche's `video_script_template`, interpolates
   lead tokens, hands the draft to Claude Haiku for a rewrite, then POSTs
   the final script to Tavus.
3. Tavus renders the video asynchronously (~60-120s) and POSTs the result
   to `clx-video-ready-v1`'s webhook URL.
4. `clx-video-ready-v1` builds an embedded-thumbnail email with a
   Calendly CTA and sends it via Gmail (TESTING MODE still points to
   `adesholaakintunde+clxtest@gmail.com` until Mary removes the override).

### 15.1 Tavus account + replica

- Sign up at **tavus.io** on the starter plan (~$59/mo — includes
  one personal replica + enough render credits for initial pilots).
- Record a 2-minute replica training video per Tavus's guidance
  (well-lit, stable camera, clear diction, neutral background). Upload
  via the Tavus dashboard.
- Wait up to 24h for Tavus to finish training. You'll receive an email
  with the `replica_id` once ready.
- Capture the API key from Tavus dashboard → Developer → API Keys.

### 15.2 .env keys

```
TAVUS_API_KEY=sk-tavus-...           # from Tavus dashboard
TAVUS_REPLICA_ID=r1a2b3c4...         # from the training-ready email
TAVUS_CALLBACK_URL=https://your-n8n-host/webhook/clx-video-ready-v1
```

`TAVUS_CALLBACK_URL` is the production webhook URL exposed by the
`Tavus Callback Webhook (DEACTIVATED)` node in `clx-video-ready-v1` —
copy it from n8n after the workflow is imported (and before it's
activated).

If you plan to run multiple replicas (e.g., separate video branding per
client), you can set per-client overrides in `clients.metadata->>
tavus_replica_id` and extend `clx-video-outreach-v1` to read it. Not
required for launch.

### 15.3 n8n credential

Create one HTTP Header Auth credential in n8n named **`Tavus`**:

- Name: `Tavus` (exact string — credential bindings are name-based per
  the workflow-credential convention)
- Header Name: `x-api-key`
- Header Value: `$TAVUS_API_KEY`

### 15.4 Per-node credential binding

In `clx-video-outreach-v1`, bind the `Tavus` credential to:

- `Tavus Generate Video` (HTTP node, URL `https://tavusapi.com/v2/videos`)

Replace the placeholder tokens inside the same node's JSON body:

- `TODO_TAVUS_REPLICA_ID` → your `$TAVUS_REPLICA_ID`
- `TODO_TAVUS_CALLBACK_URL` → your `$TAVUS_CALLBACK_URL`

The `Compose Video Script (Claude)` node also needs the existing
`Anthropic API` credential bound — if Mary hasn't set it up yet, create
an HTTP Header Auth credential named `Anthropic API` with header name
`x-api-key` and value `$ANTHROPIC_API_KEY`. The script workflow has a
fallback path (deterministic interpolation) so this is strictly an
uplift, not a blocker — but attach it before the first dry-run for
cleaner video scripts.

All Supabase HTTP nodes in both workflows already bind by name to
`Supabase Crystallux` — no action needed for those.

### 15.5 Tavus → Callback webhook

Configure the Tavus dashboard to POST completion events to
`$TAVUS_CALLBACK_URL` (which points at `clx-video-ready-v1`). Tavus
supports this per-video (via the `callback_url` field in the generate
call) *and* as a global setting in the dashboard. Setting both is
belt-and-suspenders safe; duplicates are deduped by `video_request_id`
correlation in the Normalize Payload node.

Sanity-check by POSTing a synthetic payload into the webhook:

```json
{ "video_id": "test_video_id", "status": "ready",
  "hosted_url": "https://example.com/test.mp4",
  "thumbnail_url": "https://example.com/test.jpg",
  "duration": 60, "total_cost": 1.00 }
```

Expect: correlation miss logged to `scan_errors` as
`VIDEO_RESULT_NO_MATCH`. That's the correct response — no lead has
`video_request_id='test_video_id'`.

### 15.6 Flip a client on

Per client, in Supabase:

```sql
UPDATE clients
SET video_enabled    = true,
    video_monthly_cap = 50     -- adjust per budget
WHERE id = '<client-uuid>';
```

Confirm: `Campaign Router v2` will start routing that client's
high-score Apollo-enriched leads to `preferred_channel='video'`. The
48h-no-booking fallback in `clx-booking-v2` also activates for that
client only.

Leave `video_enabled=false` on all other clients until each has been
individually validated.

### 15.7 Dry-run — single lead end-to-end

1. Pick a test lead whose client has `video_enabled=true`, with a valid
   `email`, reasonable `full_name` / `company` / `city` / `industry`.
2. POST to the `Manual Trigger (Webhook)` in `clx-video-outreach-v1`:
   ```bash
   curl -X POST https://your-n8n-host/webhook/clx-video-outreach-v1 \
     -H "Content-Type: application/json" \
     -d '{"lead_id":"<test-lead-uuid>"}'
   ```
3. Verify in Supabase:
   - `video_generation_log` gained one row, `status='generating'`,
     `request_id` populated.
   - `leads.video_request_id`, `video_script`, and `video_status='generating'`
     are set on the lead.
4. Wait 60-120s for Tavus to finish rendering.
5. Verify Tavus posted the ready event to `clx-video-ready-v1`. Check:
   - `video_generation_log.status='ready'`, `video_url` populated,
     `cost_usd` set.
   - `leads.video_url` + `video_status='delivered'`, `lead_status='Video Sent'`.
   - `outreach_log` has a `channel='video'` row for the lead.
6. Check the TESTING MODE inbox (`adesholaakintunde+clxtest@gmail.com`)
   for the video email. Click the thumbnail — should open Tavus's hosted
   URL in a browser.

### 15.8 Go-live (remove TESTING MODE redirect)

Once Mary is satisfied the embedded email renders correctly on Gmail
desktop + mobile + Outlook, edit `clx-video-ready-v1` node
`Build Gmail Raw Message`:

```javascript
// BEFORE:
const to = 'adesholaakintunde+clxtest@gmail.com'; // TESTING MODE — remove before production

// AFTER:
const to = data.email;
```

Then re-import the workflow. Same pattern as the other sender workflows
(`clx-outreach-sender-v2`, `clx-follow-up-v2`, `clx-booking-v2`), which
Mary may choose to flip at her own cadence.

### 15.9 Activation checklist

- [ ] Tavus account provisioned; replica trained (≤24h wait)
- [ ] `TAVUS_API_KEY` and `TAVUS_REPLICA_ID` in `.env`
- [ ] n8n credential `Tavus` created (HTTP Header Auth, `x-api-key`)
- [ ] `Anthropic API` credential bound to Compose Video Script node
      (uplift; deterministic fallback exists)
- [ ] `Tavus` credential bound to `Tavus Generate Video` node
- [ ] `TODO_TAVUS_REPLICA_ID` + `TODO_TAVUS_CALLBACK_URL` tokens replaced
- [ ] `clx-video-ready-v1` webhook URL configured in Tavus dashboard
- [ ] Synthetic webhook test logs `VIDEO_RESULT_NO_MATCH` to scan_errors
- [ ] `clients.video_enabled=true` flipped for the target client
- [ ] Dry-run succeeds end-to-end for one test lead
- [ ] `leads.video_status='delivered'` observed on the test lead
- [ ] Video email received and renders correctly in TESTING MODE inbox
- [ ] (Optional go-live) TESTING MODE redirect removed from
      `clx-video-ready-v1` Build Gmail Raw Message node

### 15.10 Decommission / rollback

- Quick mute (per client): `UPDATE clients SET video_enabled=false WHERE id=...`.
  Campaign Router stops routing that client's leads to video; the
  48h-no-booking Execute Workflow node in booking-v2 short-circuits at
  the Filter Eligible step.
- Full schema rollback: uncomment the trailing block of
  `2026-04-23-video-schema.sql`. This drops `video_generation_log`,
  removes the `leads.video_*` columns, and removes the monitoring
  thresholds. Test on staging first.
- No Schedule Trigger to deactivate — `clx-video-outreach-v1` runs only
  on Manual Webhook or Execute Workflow from `clx-booking-v2`. Disabling
  the workflow entirely (`active=false`, already the default) is
  sufficient.

### 15.11 Cost guardrails

- Tavus charges per render (~$1/video on the starter plan).
- `video_monthly_cap` (default 50) is the per-client ceiling. The
  preflight check (`Monthly Cap Gate` in `clx-video-outreach-v1`) uses
  `get_monthly_video_count` RPC and leaves a 2-render buffer below the
  cap to absorb in-flight callbacks.
- High-score gate (`lead_score >= 90` in Campaign Router) keeps video
  reserved for Apollo-enriched leads where the unit economics justify it.
- A failed Tavus call is captured in `scan_errors` as
  `VIDEO_GENERATION_FAILED`; 5 within 10 minutes triggers a warning via
  `clx-error-monitor-v1` per the threshold seeded in the migration.

---

## 20. B2B / B2C Segmentation

Scaffolded in Task 2 of the final scale-sprint pass. Adds a segment
classification step to Campaign Router v2 and a cost-saving Apollo
skip gate to Lead Research v2. Segment-aware outreach copy is wired
into Outreach Generation v2. All dormant until the migration runs and
a real client's `focus_segments` is set; default behavior is
indistinguishable from pre-segmentation for any lead that classifies
as `unknown`.

### 20.1 Classification heuristics

`clx-campaign-router-v2` node **Decide Segment** classifies each lead
(first match wins) into `residential` / `commercial` / `unknown`:

1. **`company_size > 1`** → `commercial`
2. **`linkedin_url` AND `apollo_org_id` both set** → `commercial`
3. **Personal email domain** (gmail, yahoo, hotmail, outlook, icloud,
   live, aol, proton, me) → `residential`
4. Fallback → `unknown`

The classification is written to `leads.lead_segment` via the existing
`rpc/update_lead` call — no separate write.

### 20.2 Client focus_segments filter

`clients.focus_segments` is a jsonb array. Default
`["residential","commercial"]` accepts all leads. A client who wants
commercial-only sets `["commercial"]`; the router then marks any
residential-classified lead as `lead_status='Out of Focus'` and skips
the campaign assignment. Unknown-segment leads pass through — they get
normal campaign routing regardless of the client's focus preferences.

```sql
-- Example: insurance broker client, commercial-only
UPDATE clients SET focus_segments = '["commercial"]'::jsonb
WHERE id = '<client-uuid>';
```

### 20.3 Apollo skip gate (Lead Research v2)

`clx-lead-research-v2` now has a **Decide Apollo Gate** code node
before the Apollo Enrichment sub-workflow call. The gate sets
`_skip_apollo=true` when:

- The lead's email is on a personal domain, **AND**
- No business signals are present (no `linkedin_url`, no
  `apollo_org_id`, `company_size <= 1`).

When true, the workflow routes directly to Claude Research, saving an
Apollo credit on a lead that would return empty firmographics anyway.
When false (B2B indicators present or business email), Apollo runs as
before.

### 20.4 Segment-aware outreach prompt (Outreach Generation v2)

`clx-outreach-generation-v2` has a new **Merge Segment Overlay** code
node between Fetch Niche Overlay and Build Outreach Prompt. When the
niche's `offer_mapping.lead_segments[<segment>]` branch exists, the
merge node:

- Appends the segment's `pain_angles` to the overlay's `pain_signals`.
- Appends a SEGMENT CONTEXT stanza to the overlay's
  `claude_system_prompt` with a tone preamble: "business formal,
  consultative, peer-advisor" for commercial vs "friendly, local,
  neighborly" for residential.

Build Outreach Prompt then reads the enriched overlay as normal, so no
other changes are needed downstream.

### 20.5 Channel preference per segment

Decide Channel in Campaign Router reads
`overlay.offer_mapping.lead_segments[<segment>].channels` when
`preferred_channel` isn't already set by an upstream signal. For
insurance_broker the residential branch is `["sms","email","voice"]`
and the commercial branch is `["email","linkedin","voice"]`. The
client's `channels_enabled` allowlist still applies — if the first
segment channel isn't in the allowlist, the router falls back to the
existing channel-selection flow.

### 20.6 Onboarding checklist addition

When onboarding a new client, ask:

> "Do you want residential leads only, commercial leads only, or
> both?"

Record the answer and set:

```sql
UPDATE clients
SET focus_segments = '[<selected segments>]'::jsonb
WHERE id = '<client-uuid>';
```

Explain to the client that the platform will now only route leads
matching their segment focus — residential-only clients never see
commercial leads and vice versa.

### 20.7 Decommission / rollback

Remove segmentation entirely:

```sql
-- Revert any segment classifications
UPDATE leads SET lead_segment = 'unknown';

-- Reset every client's focus to the default
UPDATE clients SET focus_segments = '["residential","commercial"]'::jsonb;

-- Full schema rollback (uncomments at the bottom of
-- 2026-04-23-b2b-b2c-segmentation.sql) drops the new columns and
-- check constraints. Test on staging first.
```

All three workflow hooks (Decide Segment, Decide Apollo Gate, Merge
Segment Overlay) are safe no-ops when `lead_segment='unknown'` and the
overlay has no `lead_segments` branch — reverting the schema does not
break the workflows.

---

## 21. Stripe Billing Activation

Task 3 ships dormant billing scaffolding: migration
(`2026-04-23-stripe-billing.sql`), two workflows
(`clx-stripe-webhook-v1`, `clx-stripe-provision-v1`), and the Stripe
credential slot. No live Stripe calls happen until the steps below are
complete. Until activation, client rows carry NULL Stripe fields and
the dashboard billing panel shows "Not yet provisioned" for every
client.

### 21.1 Stripe account provisioning

- Sign up at **stripe.com** using `info@crystallux.org`.
- Complete business verification: Canadian business registration docs,
  business address, BN/HST number. Stripe typically verifies in 2-5
  business days.
- Once verified, switch the Dashboard to **Live mode** (top-right
  toggle) before copying keys — Test mode keys start with `sk_test_`,
  Live mode with `sk_live_`.

### 21.2 Create Stripe Products + Prices

In the Stripe Dashboard → Products, create:

| Product | Price (CAD/mo) | Interval | Internal plan key |
|---|---|---|---|
| Crystallux Insurance Broker Founding | $1,997 | monthly | `founding_1997` |
| Crystallux Insurance Broker Standard | $2,497 | monthly | `standard_2497` |
| Crystallux Construction Founding | $1,497 | monthly | `construction_1497` |
| Crystallux Moving Founding | $997 | monthly | `moving_997` |
| Crystallux Cleaning Founding | $997 | monthly | `cleaning_997` |
| Crystallux Salon Founding | $997 | monthly | `salon_997` |
| Crystallux Intelligence Upgrade | +$2,000 | monthly | `intelligence_3997` |

Copy each Price ID (starts with `price_...`) into `.env` under the
variable names expected by `clx-stripe-provision-v1`:

```
STRIPE_PRICE_FOUNDING_1997=price_...
STRIPE_PRICE_STANDARD_2497=price_...
STRIPE_PRICE_CONSTRUCTION_1497=price_...
STRIPE_PRICE_MOVING_997=price_...
STRIPE_PRICE_CLEANING_997=price_...
STRIPE_PRICE_SALON_997=price_...
STRIPE_PRICE_INTELLIGENCE_3997=price_...
```

### 21.3 .env keys

```
STRIPE_SECRET_KEY=sk_live_...                          # Dashboard → Developers → API keys
STRIPE_WEBHOOK_SECRET=whsec_...                        # Dashboard → Developers → Webhooks → signing secret
```

### 21.4 Configure the webhook endpoint

- In Stripe Dashboard → Developers → Webhooks → **Add endpoint**.
- Endpoint URL: `https://automation.crystallux.org/webhook/stripe`
  (the webhook path defined by `clx-stripe-webhook-v1`; confirm the
  host in your n8n deployment).
- Events to listen for (minimum set):
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
  - `invoice.paid`
  - `invoice.payment_succeeded`
  - `invoice.payment_failed`
- Copy the **Signing secret** (starts with `whsec_`) into
  `STRIPE_WEBHOOK_SECRET` in `.env`.

### 21.5 n8n credential

Create **one** HTTP Header Auth credential in n8n named **`Stripe`**:

- Name: `Stripe`
- Header Name: `Authorization`
- Header Value: `Bearer $STRIPE_SECRET_KEY`

Bind to the following nodes:

- `clx-stripe-provision-v1` → `Create Stripe Customer`
- `clx-stripe-provision-v1` → `Create Stripe Subscription`

Both nodes currently ship without a `credentials` block; binding the
`Stripe` credential to each one after creation is the activation step.

### 21.6 Local test with Stripe CLI

Before flipping the webhook active:

```bash
stripe listen --forward-to https://automation.crystallux.org/webhook/stripe
```

Leave this running and trigger a test event:

```bash
stripe trigger customer.subscription.created
```

Verify:

- A row appears in `stripe_events_log` with
  `event_type='customer.subscription.created'` and `processed=true`.
- No `STRIPE_WEBHOOK_UNVERIFIED` rows in `scan_errors`.

### 21.7 First real subscription (smoke test)

1. In the Stripe Dashboard (Live mode), create a test customer with
   Mary's personal card.
2. Attach the customer to the `founding_1997` price with a 14-day
   trial.
3. Verify webhooks fired: `stripe_events_log` has 1-2 rows with
   `processed=true`; the `clients` row (matched by
   `stripe_customer_id`) has `subscription_status='trialing'`,
   `subscription_plan='founding_1997'`, `trial_ends_at` populated.
4. Issue a refund from Stripe Dashboard to clean up.

### 21.8 Provisioning via clx-stripe-provision-v1

Once the Stripe credential is bound and smoke test passes, activate
`clx-stripe-provision-v1` for onboarding automation. POST to the
manual webhook:

```bash
curl -X POST https://automation.crystallux.org/webhook/clx-stripe-provision \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "<uuid-of-existing-client-row>",
    "client_email": "owner@clientbusiness.com",
    "business_name": "Client Business Inc.",
    "selected_plan": "founding_1997"
  }'
```

The workflow: creates the Stripe Customer, creates the Subscription
(14-day trial), updates the `clients` row, and sends a welcome email
via Gmail (TESTING MODE inbox until Mary removes the redirect).

### 21.9 Activation checklist

- [ ] Stripe account verified and in Live mode
- [ ] All Products + Prices created; Price IDs in `.env`
- [ ] `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET` in `.env`
- [ ] Webhook endpoint configured in Stripe Dashboard for the 6 events
- [ ] n8n credential `Stripe` created (HTTP Header Auth, `Authorization`)
- [ ] `Stripe` credential bound to the two Create Stripe * nodes in
      `clx-stripe-provision-v1`
- [ ] `stripe listen --forward-to ...` smoke test passes
- [ ] First Stripe Dashboard-triggered test subscription flows cleanly
      through the webhook and lands on the correct `clients` row
- [ ] `clx-stripe-webhook-v1` activated (set `active=true`)
- [ ] `clx-stripe-provision-v1` activated (set `active=true`)
- [ ] (Optional go-live) TESTING MODE redirect removed from
      `clx-stripe-provision-v1` Build Welcome Email node

### 21.10 Decommission / rollback

- Quick mute: set both Stripe workflows `active=false`. In-flight
  events already in `stripe_events_log` will retry via Stripe's
  automatic retry cadence once reactivated.
- Disable the webhook endpoint in Stripe Dashboard (Developers →
  Webhooks → Disable). Stripe will stop delivering; `stripe_events_log`
  entries frozen at their current `processed` state.
- Full schema rollback: uncomment the trailing block of
  `2026-04-23-stripe-billing.sql`. Drops `stripe_events_log`, removes
  all `clients.stripe_*` / `subscription_*` / `trial_ends_at` columns,
  removes monitoring thresholds. Test on staging first.

### 21.11 Cost notes

- Stripe: **2.9% + $0.30 per transaction** (Canadian card standard).
  On a $1,997/mo subscription: ~$58/mo in fees per client, absorbed
  into pricing.
- No per-webhook or per-API-call fee — unlimited reads/writes at no
  cost.
- Stripe Customer Portal is **free** for every subscription; the URL
  in the welcome email template is a placeholder until Mary creates
  the portal config in Stripe Dashboard → Settings → Billing.

---

## 22. Admin Copilot

Persistent conversational AI layer embedded in the admin dashboard.
Opens via the ✦ FAB (bottom-right) or `Ctrl+K` / `Cmd+K` from any
panel. Available **only** to role=admin — hidden for client and ops
sessions.

### Capabilities

1. **Database query.** Type/speak a question → Claude generates a
   safe PostgreSQL SELECT → server executes via
   `admin_execute_select` RPC → table/scalar/chart result renders in
   the panel.
2. **Troubleshoot error.** Supply an `error_id` or free-text
   description → Claude diagnoses root cause from recent
   `scan_errors` → proposes severity, fix summary, and (optionally)
   a safe SQL action. Only `mark_error_resolved` RPC calls are
   auto-executable; anything else is suggest-only.
3. **Platform Q&A.** Ask what a feature does, which tables hold what
   data, what's on the roadmap → Claude answers grounded in
   OPERATIONS_HANDBOOK, ROADMAP_*.md, and workflow source. Never
   invents capabilities — references existing roadmaps before
   proposing new ideas.
4. **Voice input.** Click the microphone icon → MediaRecorder captures
   audio (max 60 seconds) → uploads to Whisper workflow →
   transcription auto-populates the input box for review.

### Activation

1. Apply migration `2026-04-24-admin-copilot.sql`. Creates
   `admin_action_log`, adds resolved-tracking columns to
   `scan_errors`, creates `admin_execute_select` + `mark_error_resolved`
   RPCs.
2. Sign up OpenAI API for Whisper → add `OPENAI_API_KEY` to `.env`.
3. Confirm `ANTHROPIC_API_KEY` in `.env`.
4. Create n8n credentials:
   - **Anthropic API** — HTTP Header Auth, `x-api-key` = `$ANTHROPIC_API_KEY`
   - **OpenAI** — HTTP Header Auth, `Authorization` = `Bearer $OPENAI_API_KEY`
5. Import the 4 Copilot workflows:
   - `clx-copilot-query-v1.json`
   - `clx-copilot-troubleshoot-v1.json`
   - `clx-copilot-platform-v1.json`
   - `clx-copilot-whisper-v1.json`
6. Bind credentials to the Claude/OpenAI HTTP nodes in each workflow.
7. Activate all 4 workflows (`active=true`).
8. Open the admin dashboard with `?token=<MARY_MASTER_TOKEN>`. The ✦
   FAB appears bottom-right. Press `Ctrl+K` to open.

### Cost

- Claude Sonnet per query: **~$0.003-$0.015** depending on output
  length
- Whisper per minute of audio: **~$0.006 USD**
- Typical month at normal use (30-60 queries/day): **$20-$50**

### Safety

- **Admin token required** on every webhook call. Token validated
  against `MARY_MASTER_TOKEN` env var before Claude is invoked.
- **SELECT-only** enforced at two layers: workflow validates with a
  regex blacklist + LIMIT requirement; `admin_execute_select` RPC
  re-validates before executing (defence in depth).
- **Rate limit**: in-flight cap of 100 queries/day expected
  (Anthropic soft limit). Adjust per cost observed.
- **All actions logged** to `admin_action_log` with admin_user,
  action_type, input, generated content, result summary,
  success/error, timestamp.
- **No secrets leaked** in responses — system prompts instruct
  Claude to never return credential values or raw API keys.
- **Client isolation preserved** — Copilot is admin-only; client
  dashboards have no copilot UI injection.

### Decommission

- Deactivate the 4 workflows (`active=false`). Copilot FAB remains
  in admin UI but every call returns a network error.
- Roll back the migration via trailing rollback block in
  `2026-04-24-admin-copilot.sql`.
- Remove `OPENAI_API_KEY` from `.env` (Whisper no-ops).

### Future work (scaffolded, not yet built)

- Streaming responses via Server-Sent Events for incremental render
- "Execute fix" button on troubleshoot results that calls
  mark_error_resolved via a dedicated workflow
- Query result → chart rendering (Chart.js) for `result_type='chart'`
- Context awareness: automatic inclusion of the current panel's
  data in the Claude prompt (e.g., viewing #alerts → queries get
  current unresolved error count as context)

---

## 26. Dashboard Role Model

The dashboard shell at `dashboard/index.html` supports four
roles with distinct access levels:

### Roles

- **admin** — Mary, full platform visibility. Authenticated via
  `?token=<MARY_MASTER_TOKEN>`. Sees all 11 admin panels plus
  Copilot FAB plus legacy panels.
- **client** — end customers. Authenticated via
  `?client_id=<UUID>&token=<DASHBOARD_TOKEN>`. Sees 8 client panels,
  data scoped to their own client_id via `clxScopeUrl` wrapper + RLS.
  No Copilot. No admin panels. No other clients' data.
- **ops** — future VA / support staff. Authenticated via
  `?token=<OPS_TOKEN_OR_MASTER>&ops=1`. Sees 4 ops panels (dormant
  until activated). Read-only access to clients panel. No billing
  admin surface. No Copilot.
- **guest** — no credentials. Shown access-denied landing with
  prompt to use proper URL format.

### URL patterns

```
Admin:   https://crystallux.org/dashboard?token=<MASTER>
         https://crystallux.org/dashboard?token=<MASTER>#clients
Client:  https://crystallux.org/dashboard?client_id=<UUID>&token=<DT>
         https://crystallux.org/dashboard?client_id=<UUID>&token=<DT>#my-leads
Ops:     https://crystallux.org/dashboard?token=<OPS>&ops=1
Status:  https://crystallux.org/dashboard/status.html (public, no auth)
```

### Role detection

Happens client-side in the IIFE added during Phase 1. Populates
`window.CLX_ROLE`, `window.CLX_CLIENT_ID`, `window.CLX_TOKEN`.
Precedence: `ops=1&token` → ops · `token` alone → admin · `token +
client_id` → client · else → guest.

### Server-side verification (dormant)

`clx-verify-dashboard-access-v1` workflow provides authoritative
role resolution with rate limiting (60 req/min per IP) and audit
logging. Activated when the dashboard calls it before rendering —
pending front-end wiring.

### Client isolation

Every new data query from Phase 3 onward uses `clxFetch(url)` or
`clxScopeUrl(url)` which forcibly append `&client_id=eq.<CLX_CLIENT_ID>`
when role=client. Legacy pre-Phase-2 queries rely on Supabase RLS
only; the hardening migration (`2026-04-24-dashboard-rls-hardening.sql`)
enforces `service_role`-only direct-table access and revokes anon
SELECT/INSERT/UPDATE/DELETE from client-scoped tables.

### Mobile responsiveness

- Sidebar collapses below 820px, replaced by a hamburger toggle
- Panel scaffolds pad down to 18px at small screens
- Copilot panel becomes full-width on small screens
- Breadcrumb adapts padding to accommodate hamburger position

### Panel catalogue

- **Admin (11):** Overview, Clients, Leads, Campaigns, Outreach,
  Replies & Bookings, Vertical Overlays, Credentials, Billing,
  Alerts/Errors, Settings (+ Onboarding, System Health, Legacy)
- **Client (8):** Dashboard, My Leads, Campaigns, Replies,
  Bookings, Reports, Billing, Settings (+ Onboarding)
- **Ops (4):** Support Queue, Onboarding Tasks, Clients
  (read-only), Alerts (all dormant)
- **Legacy:** 16 pre-existing sections preserved as a single
  "Legacy Panels" route — every pre-Phase-3 query and panel
  continues to function identically

Each new panel is a scaffold with placeholder cards until data
wiring ships in a future pass.

### Audit + decommission

- All access attempts through `clx-verify-dashboard-access-v1` log
  to `admin_action_log`.
- All Copilot actions log to `admin_action_log`.
- To decommission the multi-role layer: revert to the pre-Phase-3
  state by removing the CSS `.clx-shell`, `.clx-sidebar`,
  `.clx-panel` rules and the IIFE role-detection block; the
  original 16 sections render as before. Client-side rollback
  only; RLS migration stays for security regardless.

---

## 27. Market Intelligence Activation (Phase B.9)

The Market Intelligence Engine ingests external market signals
(news, weather, economic indicators, regulatory feeds), classifies
them via Claude Sonnet 4.5, and dynamically scales outreach volume +
messaging per vertical for clients on the Intelligence tier. Ships
dormant: migration + 3 new workflows + additive edits to Campaign
Router v2 and Outreach Generation v2.

Pricing: +$2,000/month CAD on top of the base tier.

### 27.1 Free signal sources (recommended starting point, $0/mo)

1. **GDELT** — free, unlimited, no signup. Global news events
   filtered to Canada + Crystallux verticals via query string.
2. **Bank of Canada Valet** — free, no signup. FX rates + overnight
   interest rate observations.
3. **Statistics Canada** — free, no signup. Monthly indicators (not
   yet wired in v1 ingestion; placeholder in source list).
4. **FSRA RSS** — free, no signup. Regulatory feed for Ontario
   insurance + pension + financial services regulation.
5. **OpenWeatherMap** — free 1000 calls/day dev tier covers
   top-5 Canadian cities severe-weather alerts.
   - Sign up at openweathermap.org
   - Copy API key → `OPENWEATHER_KEY` in `.env`
6. **NewsAPI** — free 100 requests/day dev tier covers basic
   Canadian business news.
   - Sign up at newsapi.org
   - Copy API key → `NEWSAPI_KEY` in `.env`

### 27.2 Premium tier (scale past 20 Intelligence clients)

- NewsAPI Business: $449/mo unlimited
- Google Trends via pytrends server or SerpAPI ($50-200/mo)
- Consider: Bloomberg, Reuters, Financial Post premium feeds later

### 27.3 Anthropic API

- Already required for other features (outreach gen, copilot)
- B.9 cost estimate: ~$30-50/mo at 50 Intelligence clients
- Per signal processed: ~$0.005 (Sonnet 4.5 at 1500 tokens)

### 27.4 n8n credentials

Create with name-only binding (no UUIDs):

- **OpenWeatherMap** — HTTP Query Auth, `appid` param. Bind to the
  Fetch Source node in `clx-signal-ingestion-v1` when targeting
  that source (requires editing the URL template; current v1 sends
  URLs as-is).
- **NewsAPI** — HTTP Query Auth, `apiKey` param. Same binding
  pattern.
- **Anthropic API** — already exists if Copilot workflows are
  active. Bind to Claude Analyze Signal node in
  `clx-signal-intelligence-v1`.

### 27.5 Activation order

1. Apply migration `2026-04-24-market-intelligence.sql`
2. Import 3 new workflows:
   - `clx-signal-ingestion-v1` (dormant, hourly)
   - `clx-signal-intelligence-v1` (dormant, every 6h)
   - `clx-intelligence-upsell-detector-v1` (dormant, weekly Sun 9am)
3. Re-import modified workflows:
   - `clx-campaign-router-v2` (B.9c additive: Fetch Active Signals
     For Lead + Fetch Client Signal Preferences + Apply Signal
     Multiplier + Log Signal Routing Decision nodes)
   - `clx-outreach-generation-v2` (B.9c additive: Fetch Signal For
     Outreach + Merge Signal Context nodes)
4. Configure API keys in `.env`
5. Create n8n credentials per §27.4
6. Manually fire `clx-signal-ingestion-v1` once with GDELT-only to
   test (remove other sources from Prep Ingestion Targets before
   first run)
7. Verify `market_signals_raw` populating
8. Manually fire `clx-signal-intelligence-v1` once
9. Verify `market_signals_processed` populating with quality output
10. Spot-check 5 random processed signals — is Claude's analysis
    accurate? If hallucinations detected, refine system prompt in
    Build Claude Prompt node
11. Activate Schedule Trigger on ingestion workflow
12. Activate Schedule Trigger on intelligence workflow
13. Monitor for 7 days before enabling on any real clients
14. Enable Intelligence tier on beta client:
    `SELECT enable_intelligence_tier('<client-uuid>'::uuid, 2000.00);`
15. Monitor that client's outreach for 14 days — does multiplier
    behaviour match expectation?
16. Expand to more clients gradually; activate upsell detector only
    after 3+ Intelligence clients are live

### 27.6 Per-client controls

```sql
-- Enable tier (auto-creates preferences for all active verticals)
SELECT enable_intelligence_tier('client-uuid', 2000.00);

-- Disable tier
SELECT disable_intelligence_tier('client-uuid');

-- Adjust specific preferences
UPDATE client_signal_preferences
SET auto_scale_enabled = false
WHERE client_id = 'client-uuid' AND vertical = 'insurance_broker';

-- Manual multiplier override
UPDATE client_signal_preferences
SET manual_multiplier_override = 1.5
WHERE client_id = 'client-uuid' AND vertical = 'consulting';

-- Exclude signal types
UPDATE client_signal_preferences
SET excluded_signal_types = '["seasonal","political"]'::jsonb
WHERE client_id = 'client-uuid' AND vertical = 'real_estate';

-- Raise the cap (default 3.0)
UPDATE client_signal_preferences
SET max_multiplier_cap = 4.0
WHERE client_id = 'client-uuid' AND vertical = 'dental';
```

### 27.7 Monitoring thresholds

Seeded in the migration:

- `SIGNAL_INGESTION_FAILED` (warning, 3 in 60min)
- `SIGNAL_PROCESSING_FAILED` (warning, 3 in 60min)
- `SIGNAL_API_QUOTA_EXCEEDED` (critical, 1 in 60min)
- `SIGNAL_HALLUCINATION_DETECTED` (warning, 2 in 1440min / 24h)
- `HIGH_IMPACT_SIGNAL_DETECTED` (warning, 1 in 60min — triggers
  Mary's alert email via Error Monitor workflow)

### 27.8 Decommission

```sql
-- Quick mute per client
SELECT disable_intelligence_tier('client-uuid');

-- Full decommission: deactivate the 3 new workflows in n8n, then
-- roll back the migration via the trailing rollback block in
-- 2026-04-24-market-intelligence.sql. Router + Outreach Gen
-- fall back gracefully — signal_context becomes null for every
-- lead and the workflows route as pre-B.9.
```

### 27.9 Safety defaults

- Max multiplier hard-capped at 5.0 (workflow layer)
- Per-client cap default 3.0 (client_signal_preferences)
- Low-confidence + no-impact signals are stored as `active=false`
  (won't route)
- Signal prompts explicitly instruct Claude not to hallucinate
- Messaging angles are guidance, not content — Claude is told never
  to quote the headline verbatim
- Client isolation preserved: a signal that affects one client's
  vertical does not leak to other clients' data. RLS unchanged.



## 28. Closing Intelligence Activation (Phase B.12a-1)

Client-facing closing scripts dashboard + Claude-ranked script matching per
lead. Built dormant; activate per-client as they start booking calls.

### 28.1 What is Closing Intelligence?

A vertical-specific library of sales scripts (discovery frameworks, objection
handlers, closing scripts, follow-up sequences, competitor comparisons) that
Mary and her clients use when running calls. The library ships seeded for
7 verticals (construction, moving_services, cleaning_services, real_estate,
dental, legal, consulting), with usage tracking on every render so the top
performers surface over time. Admin role sees the full library; client role
is confined to their own vertical by RLS + niche filter.

### 28.2 Schema

Migration: `docs/architecture/migrations/2026-04-24-closing-intelligence-client-facing.sql`

Additive columns:
- `closing_scripts.times_used / conversion_rate / last_used_at`
- `objection_handlers.times_used / conversion_rate`
- `discovery_frameworks.times_used`

New table: `script_usage_log` (agent_id, lead_id, script_id, script_type,
context, outcome, logged_at). RLS on; service_role policy only.

RPCs (SECURITY DEFINER, search_path = public):
- `record_script_usage(p_agent_id, p_lead_id, p_script_id, p_script_type, p_context, p_outcome)`
  — called by dashboard when an agent picks a script.
- `get_scripts_for_lead(p_lead_id, p_stage)` — returns ranked candidate
  scripts across all categories for a given lead, joining on niche_name.
- `get_agent_script_performance(p_agent_id, p_period_days)` — per-agent
  30-day stats (uses_count, conversion_rate) grouped by script_category.

### 28.3 Workflow

`workflows/clx-script-matcher-v1.json` (dormant).
- POST `/webhook/clx-script-matcher` body:
  `{ lead_id, stage_hint (optional), situation_hint (optional), token, client_id (optional) }`
- Pipeline: validate → fetch lead+client → call `get_scripts_for_lead`
  RPC → pass candidates to Claude Sonnet 4.5 for ranking → fallback to RPC
  order if Claude is unbound. Top 3 per category returned.
- All Supabase nodes already bind "Supabase Crystallux" credential by name.
- Anthropic node has a TODO on credential binding — ship unbound; the
  fallback branch keeps the workflow functional.

### 28.4 Dashboard panel

Section `#closingIntelligenceSection` in `dashboard/index.html` is visible
only for admin and client roles. Five tabs (Discovery / Objections / Closing
/ Follow-up / Competitor). Niche + lead_id inputs; load button calls the
RPC or the table directly. Per-agent 30-day performance strip appears when
`window.CLX_AGENT_ID` is set (reserved for per-agent auth post-Phase 10).

### 28.5 Activation steps

1. Apply `2026-04-24-closing-intelligence-client-facing.sql` in Supabase SQL
   editor (after prior migrations in the order documented in Phase 1).
2. Run verification query (at bottom of the migration file) to confirm seed
   counts: 7 discovery frameworks, 28 objection handlers, 14 closing scripts,
   7 follow-up sequences.
3. Re-import `clx-script-matcher-v1.json` into n8n. Leave `active: false`.
4. Optionally bind Anthropic API credential on the "Claude Rank Scripts"
   node (HTTP Header Auth, header `x-api-key` = `Bearer $ANTHROPIC_API_KEY`).
   Until bound, the workflow still returns ranked scripts via RPC fallback.
5. Deploy dashboard. Admin URL loads the full library; client URLs filter
   by `vertical` via RLS.
6. Per-client enablement: no flag required — the panel auto-renders for
   admin + client roles. To hide it for a specific client, add a feature
   flag on the `clients` row in a future migration.

### 28.6 Expansion

- Add more scripts by inserting into `closing_scripts`, `objection_handlers`,
  etc. — the dashboard will pick them up on next load.
- To extend to a new vertical: seed all 5 category tables with
  `niche_name = '<new-vertical>'`. Minimum viable seed: 1 discovery
  framework, 4 objection handlers (price/timing/trust/competitor),
  2 closing scripts, 1 follow-up sequence.

### 28.7 Privacy

`script_usage_log` stores agent + lead linkage only. No PII on lead beyond
`lead_id` FK. RLS + service_role-only policy means the log is invisible
to client role and requires service_role to read.

### 28.8 Decommission

`UPDATE closing_scripts SET archived=true WHERE niche_name='<vertical>';`
(schema does not currently include `archived`; add the column if Mary
decommissions a vertical). Workflow stays dormant by default; no Schedule
Trigger to deactivate.


## 29. Calendar Restructuring + No-Show Recovery (Phase B.12a-2)

Structured no-show detection, SMS recovery, and reshuffle suggestions
when a slot vacates. Built dormant; activate once Twilio SMS is live
and each client's Calendly link is populated on the `clients` row.

### 29.1 Schema

Migration: `docs/architecture/migrations/2026-04-24-calendar-restructuring.sql`

- Creates `appointment_log` with `IF NOT EXISTS` (safe — preserves the
  manually-created production table). Adds no-show / reshuffle /
  recovery columns via idempotent `ADD COLUMN IF NOT EXISTS`.
- New `calendar_reshuffle_log` table tracks every vacated slot + its
  suggested-vs-selected lead.
- New `agent_calendar_prefs` table holds per-agent timezone + working
  hours + SMS template overrides (reserved; Component 3 extends it).
- RPCs (SECURITY DEFINER, service_role only):
  `mark_appointment_no_show(appointment_id)`,
  `get_daily_appointments(client_id, date)`,
  `get_reshuffle_candidates(client_id, slot_start, slot_end, limit)`,
  `record_reshuffle(client_id, vacated_id, reason, slot_start, slot_end, suggested, source)`.

### 29.2 Workflows

Three dormant workflows (`active: false`):

- **`clx-no-show-detector-v1`** — every 30 min scans
  `appointment_log` for `scheduled_end < now - 15min` with
  `outcome IS NULL`. Marks `no_show_flag=true`, logs
  `NO_SHOW_DETECTED`, then fires the SMS recovery sub-workflow.
- **`clx-no-show-sms-recovery-v1`** — webhook-triggered. Preflight
  checks lead.phone + client.calendly_link; composes a short
  first-name rebook SMS via Twilio SMS credential (`Twilio SMS`,
  Basic Auth). TESTING MODE hardcodes a test phone until Mary
  deletes the override.
- **`clx-reshuffle-suggester-v1`** — webhook-triggered. Runs
  `get_reshuffle_candidates` RPC, records the suggestion set via
  `record_reshuffle`, returns JSON to the caller (dashboard or
  booking workflow).

### 29.3 Dashboard panel

Section `#yourDaySection` in `dashboard/index.html` (admin + client
roles). Date picker + client id input (client role is auto-filled +
readonly). Calls `get_daily_appointments` RPC. Renders grouped summary
strip + per-appointment timeline with status chips (completed / no-show
/ cancelled / rebooked / upcoming). Join-meeting link shown when
`meeting_url` is populated.

### 29.4 Activation steps

1. Apply `2026-04-24-calendar-restructuring.sql` in Supabase SQL editor
   (after prior migrations per Phase 1 order).
2. Verify via the queries at the bottom of the migration (column
   presence, empty reshuffle log, 4 RPCs present).
3. Provision Twilio SMS (standard SMS-enabled number; distinct from
   the WhatsApp Business number).
4. Create n8n credential named exactly `Twilio SMS` (Basic Auth:
   username = Account SID, password = Auth Token).
5. Re-import all 3 calendar workflows. Bind the Twilio node in
   `clx-no-show-sms-recovery-v1` to the `Twilio SMS` credential.
6. Replace `TWILIO_ACCOUNT_SID_PLACEHOLDER` in the URL + the `From`
   number placeholder with real values (or expression-inject from
   env).
7. Pre-production testing: keep the `TESTING_PHONE` override in
   `Compose SMS` node. Fire a manual run with a seeded appointment;
   confirm SMS lands on the test phone.
8. Go-live per client: remove the `TESTING_PHONE` override line, set
   `agent_calendar_prefs.no_show_sms_enabled=true` for that client,
   activate `clx-no-show-detector-v1` on a Schedule Trigger.

### 29.5 Decommission

`UPDATE agent_calendar_prefs SET no_show_sms_enabled=false WHERE
client_id=...;` Detector continues to mark no-shows; recovery SMS
simply won't fire. Alternatively, deactivate
`clx-no-show-detector-v1` to stop detection too.

### 29.6 Privacy + compliance

- SMS recovery message includes "Reply STOP to opt out." (CASL).
- `lead.phone` is only read when `do_not_contact=false` (DNCL
  alignment per §14.4).
- `calendar_reshuffle_log.suggested_lead_ids` stores lead ids only;
  no PII beyond what already exists in `leads`.
- RLS service_role-only on all three new tables keeps client-role
  anon-key queries from reading them.


## 30. Morning Priority Task Ordering (Phase B.12a-3)

Every agent opens the dashboard and gets an ordered task list: replies
first, then hot leads, then no-show rebooks, upcoming calls, stale
follow-ups. The ordering is heuristic-first (`compute_daily_tasks`
RPC) with optional Claude re-rank on top.

### 30.1 Schema

Migration: `docs/architecture/migrations/2026-04-24-morning-priority-ordering.sql`

- Extends `agent_calendar_prefs` (originally created in the calendar
  migration) with 9 task-ordering fields including
  `morning_focus_block`, `daily_task_cap`, `reply_sla_hours`,
  `hot_lead_threshold`, `custom_order` jsonb, and
  `notification_email`.
- New `daily_task_plan` table — one row per agent per client per day,
  unique constraint on `(agent_id, client_id, plan_date)`. Stores
  the ranked `tasks` jsonb array + a one-sentence `summary_line`.
- New `task_completion_log` — append-only log of agent check-offs.
- RPCs: `compute_daily_tasks(client_id, limit)`,
  `upsert_daily_plan(...)`, `record_task_completion(...)`. All
  SECURITY DEFINER, service_role-only EXECUTE.

### 30.2 Workflows

- **`clx-daily-plan-generator-v1`** — Schedule Trigger at 07:00 (once
  activated) fans out across `clients.active=true`, calls
  `compute_daily_tasks`, prompts Claude Haiku to re-rank with a
  `summary_line`, upserts `daily_task_plan`. Manual webhook path lets
  the dashboard regenerate on demand.
- **`clx-task-classifier-v1`** — ad-hoc webhook to re-classify a single
  lead into one of six categories when something changes mid-day. The
  morning generator does bulk classification via the RPC; this exists
  for surgical updates only.

Both are dormant. Claude nodes have TODO bind the "Anthropic API"
credential; fallback branches return deterministic output if the
Claude call errors or is unbound.

### 30.3 Dashboard panel

Section `#todaysPlanSection`. Admin + client roles. Shows:
`summary_line` in the header, then a ranked task list. Each task
renders the category chip, due-by time, SLA badge when breached, and
a "Done" button that writes to `task_completion_log`. "Regenerate"
button POSTs to the generator webhook; requires
`window.CLX_N8N_BASE` to point at the n8n origin.

### 30.4 Activation

1. Apply `2026-04-24-morning-priority-ordering.sql`.
2. Re-import `clx-daily-plan-generator-v1.json` and
   `clx-task-classifier-v1.json`.
3. Walk every agent through `docs/operations/AGENT_PREFERENCE_ONBOARDING.md`
   (5-question Q&A, ~5 min each). Insert their row in
   `agent_calendar_prefs`; hand over the generated `agent_id`.
4. Set `window.CLX_N8N_BASE` in the dashboard (one-line injection in
   the Cloudflare Pages HTML or a browser env shim).
5. (Optional) Activate `clx-daily-plan-generator-v1`'s Schedule Trigger
   at 07:00 local. Leave it off during testing; the webhook path still
   works for manual regenerate.
6. Dashboard check: panel renders today's plan; "Done" button ticks
   items off without errors.

### 30.5 Decommission

- Deactivate the Schedule Trigger on
  `clx-daily-plan-generator-v1` if Mary wants the generator fully off.
- The dashboard panel keeps reading whatever rows exist in
  `daily_task_plan` — to blank it per client, UPDATE tasks='[]'.

### 30.6 Privacy + performance

- `agent_calendar_prefs` is service_role-only RLS; `notification_email`
  and `agent_email` never leave the backend.
- Plan generation is O(clients · leads) per run; the RPC is indexed
  on `leads.client_id`. At 10 clients × 500 active leads the RPC
  returns in <200 ms per client on the Supabase free tier.
- Claude Haiku costs ~$0.002 per plan (1 client). At 10 clients × 250
  working days = ~$5/yr on the Haiku re-rank.
