# Crystallux Client Onboarding Framework
## Complete Setup, Configuration & Success Checklist

---

## Discovery Call — Questions to Ask Every Prospect

Run through these questions before presenting any package. The goal is to understand their current situation deeply enough to configure Crystallux correctly and position the value accurately.

### Current Customer Acquisition
- How do you get new clients today? Walk me through the exact process.
- What percentage of your new business comes from referrals vs. active outreach?
- How many new clients do you typically close per month?
- What does a new client relationship look like — one-time transaction or ongoing?
- What is your average client lifetime value?

### Target Client Profile
- Describe your ideal client in as much detail as possible.
- What industry or sector are they in?
- What size company (revenue, employee count, or geography)?
- What job title or role makes the buying decision?
- Where are they located — local, national, or international?
- What problem do they have that you solve better than anyone?

### Current Pain Points
- What is your biggest challenge in growing your client base right now?
- Have you tried cold outreach before? What happened?
- Do you have a CRM? What do you use?
- How much time per week does your team currently spend on lead generation and outreach?
- What would it mean for your business if you had a predictable flow of 50 qualified leads researched and ready every week?

### Technical Readiness
- Do you have a business email domain set up?
- Are you open to using WhatsApp for business outreach?
- Would you be comfortable with an AI video avatar representing you in outreach? (Enterprise only)
- Do you currently use any automation tools?

### Success Definition
- What does success look like at 90 days?
- How many new clients per month would make this obviously worth it?
- Who else is involved in this decision?

---

## Information Required to Configure Crystallux

Collect all of the following before beginning setup. Send a structured intake form after the discovery call.

### Business Information
- [ ] Business legal name and trading name
- [ ] Industry / sector (primary)
- [ ] Geographic target market (city, region, country)
- [ ] Product or service being sold
- [ ] Average deal size / transaction value
- [ ] Primary contact name, email, and phone

### Ideal Client Profile
- [ ] Target industry or industries (up to 3)
- [ ] Target company size (employee count or revenue range)
- [ ] Target job titles (who makes the buying decision)
- [ ] Geographic radius or specific cities/regions
- [ ] Signals that indicate a good prospect (e.g. "recently hired a sales team", "opened a new location", "posted a job for X role")
- [ ] Negative criteria — who NOT to target (competitors, wrong size, wrong geography)

### Outreach Configuration
- [ ] Sending email address (must be on business domain)
- [ ] Email signature content
- [ ] WhatsApp business number (if applicable)
- [ ] LinkedIn profile URL (if applicable)
- [ ] Calendly link for meeting booking
- [ ] Preferred meeting type (15-min intro, 30-min demo, etc.)
- [ ] Brand voice guidance (formal, conversational, direct, warm)

### CRM & Integrations (if applicable)
- [ ] CRM platform name (HubSpot, Salesforce, GoHighLevel, etc.)
- [ ] CRM API access or integration credentials
- [ ] Pipeline stage names they use
- [ ] Lead status terminology they prefer

### Video Avatar (Enterprise only)
- [ ] 2–5 minute video recording of the client speaking naturally
- [ ] Preferred backdrop or environment
- [ ] Any phrases or terminology to avoid
- [ ] Review and approval of first avatar test video before activation

---

## Setup Steps — Dedicated Client Workspace

Complete in this order. Estimated time: 2–4 hours per client.

### Step 1: Supabase Workspace
- [ ] Create new Supabase project for this client
- [ ] Run leads table schema migration
- [ ] Configure Row Level Security if multi-tenant
- [ ] Note project URL and service role key
- [ ] Test connection with a sample insert

### Step 2: n8n Workflow Configuration
- [ ] Duplicate base CLX workflows for this client
- [ ] Update lead import workflow with client's target criteria (industry, geography, job titles)
- [ ] Update Supabase credentials with client's project details
- [ ] Configure AI research prompts with client's product type and value proposition
- [ ] Test lead import — confirm leads are being discovered and stored
- [ ] Test lead research — confirm Claude output quality for their industry

### Step 3: Outreach Setup (Growth and above)
- [ ] Configure sending email address in outreach workflow
- [ ] Set up email warm-up if new domain (minimum 2 weeks before volume sends)
- [ ] Configure WhatsApp business integration
- [ ] Set up follow-up sequence timing (Day 1, Day 3, Day 7 recommended)
- [ ] Test end-to-end — lead discovered → researched → outreach sent → reply handling

### Step 4: Dashboard & Reporting
- [ ] Set up client-facing pipeline view in Supabase or dashboard tool
- [ ] Configure weekly email report workflow
- [ ] Test report generation and delivery
- [ ] Confirm client can view their dashboard

### Step 5: CRM Integration (if purchased)
- [ ] Connect Crystallux pipeline to client's CRM
- [ ] Map Crystallux lead fields to CRM fields
- [ ] Test lead sync — confirm researched leads appear in CRM
- [ ] Confirm meeting bookings from Calendly sync to CRM

### Step 6: Go-Live Check
- [ ] All workflows active and scheduled
- [ ] Client has received first test batch of leads
- [ ] Client has reviewed and approved sample outreach messages
- [ ] Calendly link tested — meeting booking confirmed working
- [ ] Client onboarding call completed (see Training Outline below)

---

## Training Outline — Client Onboarding Call

**Duration:** 60 minutes
**Format:** Zoom or Google Meet with screen share
**Attendees:** Client + any staff who will manage the pipeline

### Agenda

**0:00–0:10 — Welcome and orientation**
- Overview of what Crystallux is doing in the background every day
- Walk through the workflow: discovery → research → outreach → booking
- Explain the 30-minute schedule trigger and what triggers each phase

**0:10–0:25 — Live dashboard walkthrough**
- Show the leads table in Supabase (or their dashboard)
- Explain each field: research_summary, likely_business_need, research_angle
- Show how to read a researched lead and understand the AI's recommendation
- Explain lead_status progression: New Lead → Researched → Outreach Sent → Replied → Meeting Booked

**0:25–0:40 — Outreach review**
- Show a sample outreach message generated for one of their leads
- Explain how the AI uses the research to personalize the message
- Walk through the follow-up sequence timing
- Explain reply handling — what happens when someone responds

**0:40–0:50 — What to do when a lead responds**
- Handoff protocol — how Crystallux flags hot leads for human follow-up
- Best practices for taking over after AI has booked interest
- What information from the research_summary to reference in the conversation

**0:50–0:60 — Q&A and success planning**
- Review 30-day success metrics (see below)
- Confirm they know how to contact support
- Set date for 30-day review call

---

## 30-Day Success Metrics

Review these with the client on a scheduled 30-day check-in call.

### Volume Metrics
| Metric | Target (Starter) | Target (Growth) | Target (Enterprise) |
|--------|-----------------|-----------------|---------------------|
| Leads discovered | 200+ | 200+ | 500+ |
| Leads researched | 200+ | 200+ | 500+ |
| Outreach messages sent | — | 150+ | 400+ |
| Follow-ups sent | — | 300+ | 800+ |

### Quality Metrics
| Metric | Benchmark |
|--------|-----------|
| Email open rate | 35–50% (personalized outreach) |
| Reply rate | 8–15% |
| Positive reply rate | 3–6% |
| Meetings booked | 3–10 depending on package and industry |

### Business Impact Questions for 30-Day Call
- How many leads in the pipeline have responded positively?
- How many meetings have been booked?
- Have any meetings converted to clients?
- Are the research summaries accurate and useful for your industry?
- Are the outreach messages matching your brand voice?
- What adjustments would improve lead quality or message relevance?

### Optimisation Actions Based on 30-Day Data
- If open rate < 25%: Review subject lines, check deliverability, verify sending domain setup
- If reply rate < 5%: Review personalization quality, check if research angle is resonating, adjust prompt engineering
- If lead quality is off: Refine targeting criteria, adjust industry filters, tighten job title targeting
- If meetings are booked but not converting: Review handoff protocol, ensure client is following up promptly, refine qualification criteria

---

## Ongoing Client Success Protocol

**Monthly:** Automated performance report delivered to client email
**Quarterly:** Strategy review call — assess results, expand targeting, add new channels
**Annually:** Full package review — upsell evaluation, new vertical setup, contract renewal

---

*Last updated: April 2026 | Crystallux Universal AI Sales Engine*
