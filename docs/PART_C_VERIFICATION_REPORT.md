# Part C — End-to-End Verification Report

**Date:** 2026-04-23
**Branch:** `scale-sprint-v1`
**Covers:** Parts A, B, B.5, B.6, B.7, B.8, and the B.9 roadmap document.

---

## 0. Scope & method

This report documents a **static verification pass** of every pipeline
stage across the scaffolded sales engine. No live Supabase SQL was
executed, no n8n workflow was triggered, and no Gmail / Tavus / Apollo
/ Unipile / Twilio / Vapi API was called during this pass.

Instead, every workflow was re-read in its committed state; every
credential binding, TESTING MODE redirect, and placeholder credential
note was audited; every channel's expected skip / error / success path
was traced against the migration files that define the schema it
writes into.

The end-to-end **live** verification protocol Mary should run after
credentials land is in §9 below. It's the same 13-step sequence the
sprint brief listed, rewritten as a runnable checklist.

Why static: this Claude Code session has no Supabase connectivity, no
n8n instance, no provider API keys. Running the brief's SQL inserts
and workflow executions would require Mary to hand-execute everything
anyway; embedding the runbook directly in this report is the useful
form.

---

## 1. Pipeline snapshot at end of sprint

```
Intake → Research → Scoring → Signal Detection → Campaign Router ───┐
                                                                     ├─→ Outreach Generation
                                                                     │        ↓
                                                        ┌───── preferred_channel ─────┐
                                                        │                             │
                                                     email                         other
                                                        ↓                             ↓
                                               Outreach Sender v2          ┌─────────┴─────────┐
                                                (REAL SEND, TESTING       linkedin / whatsapp /
                                                 MODE inbox)              voice / video
                                                        ↓                  (all active=false —
                                               Follow-Up v2 (3-day)        dormant placeholders)
                                                        ↓
                                               Reply Ingestion → lead_status='Replied'
                                                        ↓
                                               Booking v2 (REAL SEND, TESTING MODE)
                                                 └── 48h branch ──→ Video Outreach (dormant)
                                                        ↓
                                               Video Ready ← (Tavus async callback)
                                                        ↓
                                               Embedded video email (dormant)
```

Error Monitor v1 polls `scan_errors` independently and fires Slack
warnings on threshold breaches — scaffolded and armed.

---

## 2. DO-NOT-BREAK final verification (static)

Output captured at `d5f3ae6` on branch `scale-sprint-v1`:

```
$ df -h /c | awk 'NR==2 {print "Disk free:", $4}'
Disk free: 17G                                            ✅ above 5G floor

$ grep -l 'adesholaakintunde+clxtest@gmail.com' workflows/*.json | wc -l
4                                                          ✅ senders only
  workflows/clx-booking-v2.json
  workflows/clx-follow-up-v2.json
  workflows/clx-outreach-sender-v2.json
  workflows/clx-video-ready-v1.json  (new in B.7)

$ grep -l '"name": "Gmail"' workflows/*.json | wc -l
6                                                          ✅ senders + monitors
  clx-booking-v2 / clx-error-monitor-v1 / clx-follow-up-v2 /
  clx-outreach-sender-v2 / clx-reply-ingestion-v1 /
  clx-video-ready-v1 (new)

$ grep -c 'Supabase Crystallux' workflows/*.json | awk -F: '{s+=$2} END {print s}'
109                                                        ✅ name-based bindings only

$ grep -l '"active": true' workflows/*.json
workflows/clx-lead-import.json                             ⚠ only active workflow
                                                             (pre-existing state;
                                                              unchanged by this sprint)

$ grep -n '"id":' workflows/*.json | grep -iE '"id": "[a-f0-9]{32}"'
(empty)                                                    ✅ no credential UUID IDs leaked

$ git log --oneline | head -6
d5f3ae6 Roadmap: B.9 Market Intelligence Engine full specification
2b7e5df Part B.7: video outreach scaffolding (Tavus, deferred activation)
fadd0ca Part B.6: multi-channel scaffolding (LinkedIn, WhatsApp, Voice — no live API calls yet)
1c64dc6 Part B.5: Apollo schema scaffolding (no live API calls yet)
ad0c3c8 Part B.8: dashboard polish - client context, intake URL, admin mode
6019676 Part B: scale to 10+ clients - schema, monitoring, intake, runbook
```

**Result:** all guardrails intact. TESTING MODE expanded from 3 to 4
files as planned (clx-video-ready-v1 is a new sender); Gmail bindings
grew by one (video-ready); Supabase name-only bindings added 15 new
references across the two video workflows (94 → 109). No credential
IDs, no unexpected active workflows, no disk pressure.

---

## 3. Stage-by-stage trace

For each of the 13 live-verification steps from the sprint brief,
documenting inputs, expected execution path, expected placeholder
behaviour, and success criteria.

### Stage 1 — Insert E2E test lead

**Input SQL (for Mary to run):**

```sql
INSERT INTO leads (
  id, client_id, full_name, email, company, industry, job_title,
  city, country, product_type, niche, phone, source, lead_status
)
VALUES (
  gen_random_uuid(),
  '6edc687d-07b0-4478-bb4b-820dc4eebf5d'::uuid,   -- target client
  'E2E Test Prospect',
  'adesholaakintunde+clxtest@gmail.com',          -- test alias
  'E2E Test Corp',
  'Insurance',
  'Owner',
  'Toronto',
  'CA',
  'insurance',
  'insurance_broker',
  '+14165550123',
  'e2e_test',
  'New'
)
RETURNING id;
```

Capture the returned UUID — every subsequent stage uses it.

**Expected:** one new row in `leads`, `lead_status='New'`, all other
fields populated. No other side effects.

### Stage 2 — Lead Research v2

**Trigger:** `clx-lead-research-v2` runs on schedule (or manual webhook
with `lead_id`).

**Expected path:**
1. Apollo People enrichment HTTP node fires. **Placeholder credential —
   returns 401/403 or is caught by `continueOnFail`.** Apollo skip path
   activates: `research_skip_reason='apollo_not_configured'`.
2. Claude research fallback runs: HTTP call to Anthropic API. If
   `Anthropic API` credential is bound, Claude returns summary. If not,
   this node also fails and the lead ends up with
   `research_skip_reason='claude_not_configured'`.
3. On Claude success: `research_summary`, `likely_business_need`,
   `research_angle` populated. `lead_status='Researched'`.

**Expected placeholder errors:** Apollo 401 → logged as
`APOLLO_NOT_CONFIGURED` to `scan_errors`. This is expected and safe; the
workflow continues via the Claude path.

**Success:** `leads.research_summary` is non-null;
`lead_status='Researched'`.

### Stage 3 — Lead Scoring v2

**Trigger:** `clx-lead-scoring-v2` picks up `lead_status='Researched'`.

**Expected:** Claude Haiku scores the lead based on
`research_summary` + firmographics. Writes `lead_score` (0-100),
`priority_level`, `scoring_rationale`. `lead_status='Scored'`.

**Expected placeholder errors:** none if `Anthropic API` credential is
bound. Otherwise the scoring Claude node fails and the lead stays at
`lead_status='Researched'`.

**Success:** `leads.lead_score` is a number between 0 and 100;
`lead_status='Scored'`.

### Stage 4 — Signal Detection v2

**Trigger:** `clx-business-signal-detection-v2` picks up
`lead_status='Scored'`.

**Expected:** Claude inspects the research summary for growth signals
(hiring, expansion, funding, acquisition). Writes `detected_signal`,
`signal_confidence`, `recommended_campaign_type`, `outreach_timing`,
`growth_stage`. `lead_status='Signal Detected'`.

**Success:** `leads.detected_signal` is non-null and
`lead_status='Signal Detected'`.

### Stage 5 — Campaign Router v2

**Trigger:** `clx-campaign-router-v2` picks up
`lead_status='Signal Detected'`.

**Expected execution path (after B.7 changes):**
1. `Get Signal Detected Leads` HTTP now includes
   `apollo_enriched_at`, `client_id`, `niche`, `clients(channels_enabled,video_enabled)`
   in the select.
2. `Route Campaign` code node assigns `campaign_name`,
   `campaign_value_proposition`, `campaign_pain_point`,
   `campaign_call_to_action`, `campaign_tone` from the niche table.
3. `Decide Channel` code node runs:
   - `lead.preferred_channel` is currently unset → `chosen='email'`.
   - Canadian + has mobile + `niche_preferred_channels` includes
     `whatsapp` → depends on niche overlay; for insurance_broker
     overlay, `preferred_channels=['email','voice','linkedin','whatsapp']`
     but the lead was not explicitly enriched → no whatsapp jump.
   - Video rule (B.7): `lead_score >= 90 AND apollo_enriched_at AND
     client.video_enabled` → **apollo_enriched_at is null** (Apollo was
     skipped in Stage 2) → rule does not fire.
   - Client allowlist guard: if `clients.channels_enabled=['email']`
     (default), `chosen='email'`. If video_enabled clients have other
     channels in their allowlist, those may be reached instead.
4. `Prep Update Campaign` writes `preferred_channel='email'` + campaign
   metadata via `rpc/update_lead`. `lead_status='Campaign Assigned'`.

**Expected placeholder behaviour:** with `apollo_enriched_at=null`, the
video rule correctly does not fire. This is the *expected* default
routing: the test lead falls through to email. To exercise the video
branch, Mary would need to set `apollo_enriched_at` manually after
Apollo is activated and re-run the router, plus flip
`clients.video_enabled=true` for the target client.

**Success:** `leads.preferred_channel='email'`;
`lead_status='Campaign Assigned'`; campaign_* fields populated.

### Stage 6 — Outreach Generation v2

**Trigger:** `clx-outreach-generation-v2` picks up
`lead_status='Campaign Assigned'`.

**Expected:** Claude Haiku generates `email_subject`, `email_body`,
`followup_message` using the niche overlay + campaign assignment.
`lead_status='Outreach Ready'`.

**Note on spec item 6:** the sprint brief mentions generating
linkedin / whatsapp / video_script content in this stage. The current
implementation of `clx-outreach-generation-v2` generates email +
followup only. The per-channel content is generated inside each
channel's sender workflow (LinkedIn invite_note in
`clx-linkedin-outreach-v1`'s Compose Message node; WhatsApp template
text in `clx-whatsapp-outreach-v1`; voice script in
`clx-voice-outreach-v1`; video script in `clx-video-outreach-v1`).
This is the correct architecture — each channel's copy constraints
(character limits, tone, etc.) are different enough that centralised
generation would have to generate 4-5 variants it might not use.

**Success:** `leads.email_subject` and `leads.email_body` populated.

### Stage 7 — Channel-specific sender execution

Branches on `preferred_channel`.

**7a — Email (`preferred_channel='email'`):** `clx-outreach-sender-v2`
picks up `lead_status='Outreach Ready'`. Gmail send fires against the
TESTING MODE inbox (`adesholaakintunde+clxtest@gmail.com`). One row in
`outreach_log`, `lead_status='Contacted'`,
`next_followup_scheduled_at=now+3d`.

**Expected:** Mary should see a real email in the test inbox with
subject + body from Stage 6. This is the primary "live" channel and
the sanity check for the whole pipeline.

**7b — LinkedIn (`preferred_channel='linkedin'`):**
`clx-linkedin-outreach-v1` is `active=false`. If activated, the
`Unipile Send Invite` node has no credential block → 401/NO_CREDENTIAL
→ `unipile_ok=false` → Log Send Failure fires
`LINKEDIN_SEND_FAILED` to scan_errors. Expected and dormant.

**7c — WhatsApp (`preferred_channel='whatsapp'`):**
`clx-whatsapp-outreach-v1` is `active=false`. If activated, Twilio
Send node has no credential → `whatsapp_ok=false` → `WHATSAPP_SEND_FAILED`.
Expected and dormant.

**7d — Voice (`preferred_channel='voice'`):**
`clx-voice-outreach-v1` is `active=false`. If activated:
`check_dncl_status` RPC returns true (placeholder), Vapi Dial has no
credential → `VOICE_CALL_FAILED`. Expected and dormant. **Critical:**
the DNCL placeholder returns true — must be replaced before any real
Canadian call.

**7e — Video (`preferred_channel='video'`):**
`clx-video-outreach-v1` is `active=false`. If activated: niche overlay
lookup succeeds, `get_monthly_video_count` returns 0, Tavus Generate
Video has no credential → `tavus_ok=false` → `VIDEO_GENERATION_FAILED`.
Expected and dormant.

### Stage 8 — Follow-up triggers 3 days later

**Live simulation:** Mary manually sets
`next_followup_scheduled_at` to a past timestamp to fast-forward.

```sql
UPDATE leads
SET next_followup_scheduled_at = now() - interval '1 minute'
WHERE company = 'E2E Test Corp';
```

`clx-follow-up-v2` picks up the row on its next scheduled run and
sends the `followup_message` via Gmail (TESTING MODE inbox).
`total_emails_sent=2`, `last_email_sent_at` updated.

**Success:** second email lands in test inbox with `followup_message`
body.

### Stage 9 — Simulate reply

```sql
UPDATE leads
SET lead_status='Replied', reply_text='Yes interested',
    replied_at=now()
WHERE company = 'E2E Test Corp';
```

`clx-reply-ingestion-v1` (if armed on a Gmail watch) or a direct DB
update both reach the same state. The workflow doesn't need to fire
for this simulated path.

**Success:** `leads.lead_status='Replied'`.

### Stage 10 — Booking v2

`clx-booking-v2` picks up `lead_status='Replied'`. Branch 1 (the
pre-existing one): Claude Detect Interest classifies the reply →
IF Interested → Get Client Config → Build Booking Email (inlines
Calendly link from `clients.calendly_link`) → Send Booking Email via
Gmail (TESTING MODE inbox). `lead_status='Booking Sent'`,
`booking_email_sent_at=now()`.

**Success:** third email lands in test inbox with a Calendly link.

### Stage 11 — 48h no-book → Video Outreach

**Live simulation:**

```sql
UPDATE leads
SET booking_email_sent_at = now() - interval '49 hours'
WHERE company = 'E2E Test Corp';
```

Next `clx-booking-v2` schedule tick: the new 48h-no-booking branch
(from B.7) fires.

- `Get 48h-No-Booking Leads` HTTP fetches the test lead (matches
  `lead_status='Booking Sent'`, `meeting_scheduled=false`,
  `booking_email_sent_at < now-48h`).
- `Filter Eligible For Video` checks `clients.video_enabled=true`.
  **If video not enabled for the target client, the branch
  short-circuits via the `_skip` → `No Eligible 48h Leads` noOp.
  Expected and dormant.**
- If `video_enabled=true`, Execute Workflow calls
  `clx-video-outreach-v1` which is active=false → the Execute
  Workflow node returns without triggering downstream nodes.

**Success:** no unintended Tavus API calls. No failure rows in
`scan_errors` (the workflow short-circuits cleanly on
`video_enabled=false` or on the target workflow being inactive).

### Stage 12 — Error Monitor spike test

```sql
INSERT INTO scan_errors (workflow_name, node_name, error_code,
                         error_message, created_at)
VALUES (
  'test-harness', 'test-spike', 'TEST_SPIKE',
  'Synthetic spike to exercise Error Monitor alert path', now()
);
```

Manual-execute `clx-error-monitor-v1` from the n8n UI. The workflow
polls `scan_errors` for the last 10 minutes, groups by `error_code`,
checks against `monitoring_thresholds`. `TEST_SPIKE` is not in the
threshold table, so it is ignored. To actually trigger an alert:

```sql
INSERT INTO monitoring_thresholds (error_code, window_minutes,
                                   count_threshold, severity)
VALUES ('TEST_SPIKE', 10, 1, 'warning')
ON CONFLICT (error_code) DO NOTHING;
```

Then run Error Monitor again. Expect a Slack warning (if
`SLACK_WEBHOOK_URL` is configured) or a `console.log` summary (if
not).

**Success:** Error Monitor logs the threshold breach. No false
positives on the real error codes. Clean up with:

```sql
DELETE FROM monitoring_thresholds WHERE error_code = 'TEST_SPIKE';
DELETE FROM scan_errors WHERE error_code = 'TEST_SPIKE';
```

### Stage 13 — Dashboard load

Open (replace host and token):

```
https://your-dashboard-host/?client_id=6edc687d-07b0-4478-bb4b-820dc4eebf5d&token=<MARY_MASTER_TOKEN>
```

**Expected rendering:**
- Client context banner: the target client's name + logo (if
  configured).
- Lead table: E2E Test Corp row visible with
  `lead_status='Booking Sent'` (or later if Mary advanced through the
  stages).
- Pipeline stats tiles updated.
- Recent outreach panel: the email + follow-up + booking emails
  listed.
- Per-channel tiles (B.6/B.7): LinkedIn / WhatsApp / Voice / Video
  all show "0 active today" since none actually sent.

**Success:** dashboard loads without 400 / 500 errors, client-scoped
data visible, E2E Test Corp row present.

---

## 4. Final expected `leads` table state for E2E Test Corp

Assuming Mary runs stages 1-13 in sequence after credentials land for
Gmail only (no Apollo, LinkedIn, WhatsApp, Voice, Video activation):

| Column | Expected value |
|---|---|
| `full_name` | 'E2E Test Prospect' |
| `email` | `adesholaakintunde+clxtest@gmail.com` |
| `company` | 'E2E Test Corp' |
| `lead_status` | 'Booking Sent' (Stage 10 terminal) |
| `lead_score` | 40-80 (Claude's judgement on a minimal profile) |
| `research_summary` | non-null (Claude fallback path) |
| `detected_signal` | non-null (Stage 4) |
| `preferred_channel` | 'email' |
| `channels_attempted` | `[]` (no channels beyond email populate this) |
| `campaign_name` | Insurance broker niche campaign name |
| `total_emails_sent` | 3 (initial + follow-up + booking) |
| `interest_detected` | true (Stage 10) |
| `calendly_link` | from client row |
| `booking_email_sent` | true |
| `booking_email_sent_at` | artificially backdated in Stage 11 |
| `video_status` | null (video never activated) |
| `apollo_enriched_at` | null (Apollo skipped) |
| `do_not_contact` | false initially; flipped to true in cleanup |

---

## 5. Cleanup (after E2E test)

Do **not** delete the test lead — audit trail preserved. Just muzzle it:

```sql
UPDATE leads
SET do_not_contact = true,
    do_not_contact_reason = 'e2e_test_complete'
WHERE company = 'E2E Test Corp';
```

All subsequent workflow runs skip the row via the
`do_not_contact=false` WHERE clause present in every sender query.

---

## 6. Complete re-import list for Mary (order matters)

Import order matters because Campaign Router v2 references
`clx-video-outreach-v1` via Execute Workflow. Import the dependent
workflow first.

### 6.1 New workflows to import (fresh in n8n — never imported before)

Import in this order:

1. `workflows/clx-form-intake-v1.json`                       *(Part A/B)*
2. `workflows/clx-error-monitor-v1.json`                     *(Part B)*
3. `workflows/clx-reply-ingestion-v1.json`                   *(Part B)*
4. `workflows/clx-apollo-enrichment-v1.json`                 *(Part B.5)*
5. `workflows/clx-linkedin-outreach-v1.json`                 *(Part B.6)*
6. `workflows/clx-whatsapp-outreach-v1.json`                 *(Part B.6)*
7. `workflows/clx-voice-outreach-v1.json`                    *(Part B.6)*
8. `workflows/clx-voice-result-webhook-v1.json`              *(Part B.6)*
9. `workflows/clx-video-outreach-v1.json`                    *(Part B.7)*  ← import before booking-v2
10. `workflows/clx-video-ready-v1.json`                      *(Part B.7)*

### 6.2 Modified workflows to re-import (replace existing)

11. `workflows/clx-lead-research-v2.json`                    *(modified in B.5/B.6)*
12. `workflows/clx-lead-scoring-v2.json`                     *(modified in B.5/B.6)*
13. `workflows/clx-business-signal-detection-v2.json`        *(modified in B.5/B.6)*
14. `workflows/clx-campaign-router-v2.json`                  *(modified in B.6 + B.7)*
15. `workflows/clx-outreach-generation-v2.json`              *(modified in B.5/B.6)*
16. `workflows/clx-outreach-sender-v2.json`                  *(modified in B.5/B.6)*
17. `workflows/clx-follow-up-v2.json`                        *(modified in B.5/B.6)*
18. `workflows/clx-booking-v2.json`                          *(modified in B.7)*

Every workflow except `clx-lead-import` is `active=false`. After
import, leave them deactivated. Activation only happens per the
per-channel runbooks.

---

## 7. Migration apply order (pending Supabase)

Run in Supabase SQL editor in this order. Each is idempotent (safe to
re-run) and has a rollback block commented at the bottom.

1. `docs/architecture/migrations/2026-04-23-apollo-schema.sql` *(Part B.5)*
2. `docs/architecture/migrations/2026-04-23-multi-channel.sql` *(Part B.6)*
3. `docs/architecture/migrations/2026-04-23-video-schema.sql` *(Part B.7)*

After each run, execute the verification queries at the bottom of the
migration file to confirm every column / table / RPC / seed landed
correctly.

---

## 8. `.env` template

Add these keys to `.env` as Mary brings each channel online. No key
is required for the scaffolded workflows to import or parse — these
only become load-bearing at activation time per channel.

```bash
# ── Existing (already in your .env before this sprint) ──────────────
SUPABASE_URL=https://zqwatouqmqgkmaslydbr.supabase.co
SUPABASE_SERVICE_KEY=...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GOOGLE_REFRESH_TOKEN=...
MARY_MASTER_TOKEN=...

# ── Apollo (Part B.5 — activate when ready) ─────────────────────────
APOLLO_API_KEY=...                 # apollo.io → Settings → Integrations

# ── LinkedIn via Unipile (Part B.6) ─────────────────────────────────
UNIPILE_API_KEY=...                # unipile.com → API keys
UNIPILE_TENANT_HOST=api6.unipile.com:13619
UNIPILE_ACCOUNT_ID=...             # Unipile dashboard → connected LinkedIn account

# ── WhatsApp via Twilio (Part B.6) ──────────────────────────────────
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_WHATSAPP_FROM=whatsapp:+14155238886   # your sandbox or WA-enabled number

# ── Voice via Vapi (Part B.6) ───────────────────────────────────────
VAPI_API_KEY=...
VAPI_PHONE_NUMBER_ID=...           # Vapi dashboard → Phone Numbers
VAPI_ASSISTANT_ID=...              # configure once, shared across calls

# ── Video via Tavus (Part B.7) ──────────────────────────────────────
TAVUS_API_KEY=sk-tavus-...
TAVUS_REPLICA_ID=r1a2b3c4...       # from training-ready email, ~24h after upload
TAVUS_CALLBACK_URL=https://your-n8n-host/webhook/clx-video-ready-v1

# ── Error monitor (optional, already in .env) ───────────────────────
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
```

Per `feedback_workflow_credentials.md`: the workflow JSON references
credentials by **name only** (e.g., `"Supabase Crystallux"`, `"Gmail"`,
`"Tavus"`). Mary creates the n8n credentials with those exact names;
no UUID IDs are baked into the workflow files.

---

## 9. Master activation checklist per channel

### 9.1 Apollo enrichment (Part B.5)

- [ ] `APOLLO_API_KEY` in `.env`
- [ ] n8n credential `Apollo` created (HTTP Header Auth, `X-Api-Key`)
- [ ] Bind `Apollo` credential to HTTP nodes in
      `clx-apollo-enrichment-v1`: Apollo People Enrich, Apollo
      Organizations Enrich
- [ ] Replace placeholder tokens in request bodies
- [ ] Activate Schedule Trigger in `clx-apollo-enrichment-v1`
- [ ] Run manual webhook test on one lead; confirm
      `leads.apollo_enriched_at` populated
- [ ] Lead Research v2 stops skipping Apollo path

### 9.2 LinkedIn (Part B.6)

- [ ] Unipile account + LinkedIn connection
- [ ] `UNIPILE_API_KEY`, `UNIPILE_TENANT_HOST`, `UNIPILE_ACCOUNT_ID`
      in `.env`
- [ ] n8n credential `Unipile` (HTTP Header Auth, `X-API-KEY`)
- [ ] Bind to `Unipile Send Invite` in `clx-linkedin-outreach-v1`
- [ ] Replace `TODO_UNIPILE_ACCOUNT_ID` in the node's body
- [ ] `clients.channels_enabled` includes `'linkedin'` for target client
- [ ] Manual webhook test for one lead
- [ ] Confirm `linkedin_outreach_log` row + `outreach_log`
      (channel='linkedin')
- [ ] Activate Schedule Trigger in workflow

### 9.3 WhatsApp (Part B.6)

- [ ] Twilio WhatsApp number provisioned
- [ ] `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_WHATSAPP_FROM`
      in `.env`
- [ ] n8n credential `Twilio` (HTTP Basic Auth)
- [ ] Bind to `Twilio Send` in `clx-whatsapp-outreach-v1`
- [ ] `clients.channels_enabled` includes `'whatsapp'`
- [ ] Manual test on one Canadian mobile lead
- [ ] Confirm `whatsapp_outreach_log` + `outreach_log` rows
- [ ] Activate Schedule Trigger

### 9.4 Voice (Part B.6 — **DNCL BLOCKER**)

- [ ] **Replace `check_dncl_status` SQL function with real CRTC DNCL
      lookup.** Placeholder returns true unconditionally — activating
      voice without this change is non-compliant for Canadian numbers.
- [ ] `VAPI_API_KEY`, `VAPI_PHONE_NUMBER_ID`, `VAPI_ASSISTANT_ID`
      in `.env`
- [ ] n8n credential `Vapi` (HTTP Header Auth, `Authorization: Bearer`)
- [ ] Bind to `Vapi Dial` in `clx-voice-outreach-v1`
- [ ] Configure Vapi assistant → end-of-call webhook →
      `clx-voice-result-webhook-v1` URL
- [ ] `clients.channels_enabled` includes `'voice'`
- [ ] Activate both `clx-voice-outreach-v1` and
      `clx-voice-result-webhook-v1`

### 9.5 Video (Part B.7)

See `docs/architecture/OPERATIONS_HANDBOOK.md` §15 for the full
runbook. Summary:

- [ ] Tavus account + 2-min replica training (24h wait)
- [ ] `TAVUS_API_KEY`, `TAVUS_REPLICA_ID`, `TAVUS_CALLBACK_URL` in `.env`
- [ ] n8n credential `Tavus` (HTTP Header Auth, `x-api-key`)
- [ ] Bind `Tavus` to `Tavus Generate Video` node
- [ ] Bind `Anthropic API` to `Compose Video Script (Claude)` node
- [ ] Replace `TODO_TAVUS_REPLICA_ID` + `TODO_TAVUS_CALLBACK_URL` tokens
- [ ] Configure Tavus dashboard callback → `TAVUS_CALLBACK_URL`
- [ ] Synthetic webhook test → expect `VIDEO_RESULT_NO_MATCH` in scan_errors
- [ ] `clients.video_enabled=true` for target client
- [ ] Dry-run single lead; confirm `leads.video_status='delivered'`
- [ ] (Optional go-live) Remove TESTING MODE redirect in
      `clx-video-ready-v1` Build Gmail Raw Message node

---

## 10. E2E test protocol for Mary (after keys added)

Run in order; any stage can be paused and resumed the next day.

1. Insert E2E test lead (SQL from §3 Stage 1). Capture UUID.
2. Trigger `clx-lead-research-v2` via manual webhook:
   `POST /webhook/clx-lead-research-v2 {"lead_id":"<uuid>"}`.
   Verify `research_summary` populated.
3. Let `clx-lead-scoring-v2` run on next schedule tick (or manual).
   Verify `lead_score` populated.
4. Let `clx-business-signal-detection-v2` tick. Verify
   `detected_signal` populated.
5. Let `clx-campaign-router-v2` tick. Verify
   `preferred_channel='email'` (unless Apollo + high-score + video
   path active). Verify campaign metadata populated.
6. Let `clx-outreach-generation-v2` tick. Verify `email_subject` and
   `email_body` populated.
7. Let `clx-outreach-sender-v2` tick. **Check TESTING MODE inbox for
   first email.** Verify `total_emails_sent=1`,
   `lead_status='Contacted'`.
8. Backdate `next_followup_scheduled_at`:
   `UPDATE leads SET next_followup_scheduled_at = now() - interval '1 minute' WHERE company = 'E2E Test Corp';`
   Let `clx-follow-up-v2` tick. **Check inbox for follow-up email.**
9. Simulate reply:
   `UPDATE leads SET lead_status='Replied', reply_text='Yes interested' WHERE company = 'E2E Test Corp';`
10. Let `clx-booking-v2` tick. **Check inbox for Calendly link email.**
11. Backdate `booking_email_sent_at`:
    `UPDATE leads SET booking_email_sent_at = now() - interval '49 hours' WHERE company = 'E2E Test Corp';`
    Let `clx-booking-v2` tick again. **If** video is activated and
    `clients.video_enabled=true` for the target client → Tavus render
    initiated; expect `leads.video_status='delivered'` after the
    callback (~2 min).
12. Error Monitor spike test (SQL in §3 Stage 12). Verify threshold
    breach logged / Slack alert fired.
13. Load dashboard:
    `https://your-host/?client_id=<id>&token=<MARY_MASTER_TOKEN>`.
    Verify E2E Test Corp row present with terminal state.

Cleanup: `UPDATE leads SET do_not_contact = true WHERE company = 'E2E Test Corp';`

---

## 11. Suggestions / manual fixes if anything unexpected breaks

**If Apollo fails with 429:** you've hit Apollo's per-credit-batch rate
limit. Reduce batch size in `clx-apollo-enrichment-v1` (Split in
Batches node) from default 10 to 5. Re-run.

**If LinkedIn invite returns 400 "Provider ID not found":** the
`linkedin_url` on the lead is malformed. Ensure it's the full
`https://www.linkedin.com/in/<slug>` URL, not just the slug.

**If Twilio WhatsApp returns 63016:** the target number hasn't opted
into Twilio's WhatsApp sandbox. For production, you need a WABA-approved
number; Twilio's sandbox only sends to opted-in numbers.

**If Vapi "phone_number.id invalid":** the `VAPI_PHONE_NUMBER_ID` is
the UUID from Vapi's Phone Numbers page, not the E.164 number itself.

**If Tavus returns 402 "insufficient credits":** starter plan is out of
renders. Either top up, or set `video_enabled=false` on all clients to
drop the outreach pipeline to email-only temporarily.

**If the dashboard shows no data:** verify `clients.id` in the URL matches
the target client, `MARY_MASTER_TOKEN` env matches the dashboard's
configured token, and the client_id column has no RLS filter that
excludes service_role.

**If `preferred_channel='email'` persists when you expected video:**
confirm `apollo_enriched_at IS NOT NULL` *and* `lead_score >= 90` *and*
`clients.video_enabled=true`. All three conditions must hold for the
video rule to fire (by design — video is a premium channel).

**If a channel workflow runs but writes nothing:** check the preflight
skip reasons in `scan_errors` — each workflow logs why it bypassed a
lead (`*_PREFLIGHT_SKIP` codes are informational, not alerting).

---

## 12. Summary

Every pipeline stage is scaffolded. Every channel has a migration, a
dormant workflow, activation documentation, and monitoring thresholds.
Only the email channel is live-capable today; the others activate on
Mary's cadence once credentials land.

Three sprint-level deliverables are complete:
- **Part B.7** (video outreach scaffolding) — committed `2b7e5df`
- **Part B.9** (market intelligence roadmap) — committed `d5f3ae6`
- **Part C** (this verification report) — pending commit

The scale-sprint-v1 branch is ready for Mary's first round of
credential-by-credential activation, starting with Apollo (highest
leverage for enrichment quality) and ending with Video (highest dollar
cost per unit). Each channel's runbook is self-contained in the
OPERATIONS_HANDBOOK; this report is the cross-channel narrative that
ties them together.
