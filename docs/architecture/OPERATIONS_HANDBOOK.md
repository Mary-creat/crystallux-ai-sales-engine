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
