# Mary's Activation Checklist

**Purpose:** single source of truth for what Mary does to bring the full
Crystallux sales engine live, end-to-end, after the `scale-sprint-v1`
branch is merged.

**Assumption:** you have Supabase, Gmail, Anthropic, and
`MARY_MASTER_TOKEN` already configured from earlier sprints. Every other
integration (Apollo, Stripe, Twilio, Vapi, Unipile, Tavus, Calendly) is
scaffolded but dormant. This document walks each one from zero to
production in the right order.

---

## Phase 1 — Migrations (one-time, apply in order)

Five migration files, all idempotent, all with rollback blocks at the
bottom. Apply via the Supabase SQL editor (Dashboard →
[Supabase project](https://supabase.com/dashboard/project/zqwatouqmqgkmaslydbr/sql)
→ **SQL Editor** → **New query**).

### 1a. Apollo schema

```bash
cat docs/architecture/migrations/2026-04-23-apollo-schema.sql
```

Paste the full file into the SQL editor and run. Then in a second
query tab, run the verification block (the trailing `SELECT` queries in
the migration). Expected: every check returns the expected count.

### 1b. Multi-channel schema

```bash
cat docs/architecture/migrations/2026-04-23-multi-channel.sql
```

Same drill. Expected: 5 leads channel-routing columns + 4 log tables +
4 RPCs + insurance_broker voice script seeded.

### 1c. Video schema

```bash
cat docs/architecture/migrations/2026-04-23-video-schema.sql
```

Expected: 5 leads video columns + video_generation_log table + 2
clients video columns + 1 RPC + insurance_broker video script seeded.

### 1d. B2B/B2C segmentation

```bash
cat docs/architecture/migrations/2026-04-23-b2b-b2c-segmentation.sql
```

Expected: niche_overlays.lead_target_type + lead_discovery_sources,
clients.focus_segments, leads.lead_segment, 2 check constraints,
2 indexes, insurance_broker overlay updated with lead_segments tree.

### 1e. Stripe billing

```bash
cat docs/architecture/migrations/2026-04-23-stripe-billing.sql
```

Expected: 8 clients stripe/subscription columns, stripe_events_log
table (RLS enabled), 5 indexes, 5 Stripe monitoring thresholds seeded.

---

## Phase 2 — API sign-ups (ordered by urgency)

Provider signup order is calibrated to the lead-time on verification.
Start the slowest ones first, in parallel.

### 2a. Tavus — DO FIRST (24h replica training delay)

- Sign up: https://tavus.io (starter plan ~$59/mo)
- Record 2-min replica training video (well-lit, stable camera)
- Wait up to 24h for training; Tavus emails you the `replica_id`
- Dashboard → Developer → API Keys → copy to `.env` as `TAVUS_API_KEY`

### 2b. Stripe — DO SECOND (2-5 day business verification)

- Sign up: https://stripe.com with `info@crystallux.org`
- Complete business verification (BN/HST number, address, business
  docs). Verification typically lands in 2-5 business days.
- Switch Dashboard to **Live mode** once verified (top-right toggle)
- Developers → API keys → copy Secret key as `STRIPE_SECRET_KEY`
- Developers → Webhooks → Add endpoint (see Phase 4)

### 2c. Twilio — DO THIRD (1-3 day WhatsApp sender approval)

- Sign up: https://twilio.com (usage-based ~$10-20/mo)
- Provision a phone number with WhatsApp capability
- Apply for WhatsApp sender approval (1-3 day Meta review)
- Account SID + Auth Token → `.env` as `TWILIO_ACCOUNT_SID` +
  `TWILIO_AUTH_TOKEN`; WhatsApp-enabled number → `TWILIO_WHATSAPP_NUMBER`

### 2d. Apollo — DO FOURTH (instant)

- Sign up: https://apollo.io ($49/mo starter)
- Settings → Integrations → API Keys → new key
- Copy to `.env` as `APOLLO_API_KEY`

### 2e. Vapi — DO FIFTH (instant)

- Sign up: https://vapi.ai (pay-as-you-go; ~$0.10/min voice)
- Phone Numbers → provision / import
- API Keys → Dashboard → copy to `.env` as `VAPI_API_KEY`
- Assistant creation happens at activation time; capture
  `VAPI_PHONE_NUMBER_ID` from the Phone Numbers page

### 2f. Unipile — DO SIXTH (instant)

- Sign up: https://unipile.com ($29/mo)
- Connect your LinkedIn account via their OAuth flow
- API Keys → copy to `.env` as `UNIPILE_API_KEY`
- Connected Accounts → copy the LinkedIn account ID to
  `UNIPILE_ACCOUNT_ID`

### 2g. Calendly — DO LAST (instant)

- Sign up: https://calendly.com (free plan works for MVP)
- Create a 20-minute "Crystallux Discovery" event
- Integrations → API & Webhooks → personal access token →
  `CALENDLY_API_TOKEN`
- Copy the event URL for storing per-client in `clients.calendly_link`

---

## Phase 3 — `.env` configuration

Final `.env` target. Everything lives in your n8n host's environment
(or `.env` file if using Docker compose).

```bash
# ── Already configured from earlier sprints ─────────────────────────
SUPABASE_URL=https://zqwatouqmqgkmaslydbr.supabase.co
SUPABASE_SERVICE_KEY=eyJ...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GOOGLE_REFRESH_TOKEN=...
MARY_MASTER_TOKEN=mmt_...

# ── Apollo (Part B.5) ───────────────────────────────────────────────
APOLLO_API_KEY=...

# ── LinkedIn via Unipile (Part B.6) ─────────────────────────────────
UNIPILE_API_KEY=...
UNIPILE_TENANT_HOST=api6.unipile.com:13619
UNIPILE_ACCOUNT_ID=...

# ── WhatsApp via Twilio (Part B.6) ──────────────────────────────────
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_WHATSAPP_NUMBER=whatsapp:+14155238886

# ── Voice via Vapi (Part B.6) ───────────────────────────────────────
VAPI_API_KEY=...
VAPI_PHONE_NUMBER_ID=...
VAPI_ASSISTANT_ID=...

# ── Video via Tavus (Part B.7) ──────────────────────────────────────
TAVUS_API_KEY=sk-tavus-...
TAVUS_REPLICA_ID=r1a2b3c4...
TAVUS_CALLBACK_URL=https://automation.crystallux.org/webhook/clx-video-ready-v1

# ── Calendly (Part B — booking) ─────────────────────────────────────
CALENDLY_API_TOKEN=...

# ── Stripe billing (Task 3) ─────────────────────────────────────────
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_FOUNDING_1997=price_...
STRIPE_PRICE_STANDARD_2497=price_...
STRIPE_PRICE_CONSTRUCTION_1497=price_...
STRIPE_PRICE_MOVING_997=price_...
STRIPE_PRICE_CLEANING_997=price_...
STRIPE_PRICE_SALON_997=price_...
STRIPE_PRICE_INTELLIGENCE_3997=price_...

# ── Error monitor (optional) ────────────────────────────────────────
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
```

After editing, **restart n8n** so the new env vars are picked up.

---

## Phase 4 — n8n credential creation

Per the `feedback_workflow_credentials.md` guardrail: credentials are
bound **by name only**, never by UUID. Create each credential in n8n
**with the exact name listed** so workflow bindings match.

| Credential name | Type | Header / field | Value | Bind to workflows |
|---|---|---|---|---|
| `Supabase Crystallux` | HTTP Header Auth | `apikey` + `Authorization: Bearer` | `$SUPABASE_SERVICE_KEY` | (already configured) |
| `Gmail` | Gmail OAuth2 | OAuth flow | via Google Cloud project | (already configured) |
| `Anthropic API` | HTTP Header Auth | `x-api-key` | `$ANTHROPIC_API_KEY` | clx-lead-research-v2, clx-lead-scoring-v2, clx-business-signal-detection-v2, clx-outreach-generation-v2, clx-booking-v2, clx-video-outreach-v1 |
| `Apollo` | HTTP Header Auth | `X-Api-Key` | `$APOLLO_API_KEY` | clx-apollo-enrichment-v1 |
| `Tavus` | HTTP Header Auth | `x-api-key` | `$TAVUS_API_KEY` | clx-video-outreach-v1 (Tavus Generate Video node) |
| `Twilio` | HTTP Basic Auth | Username / Password | `$TWILIO_ACCOUNT_SID` / `$TWILIO_AUTH_TOKEN` | clx-whatsapp-outreach-v1 (Twilio Send node) |
| `Vapi` | HTTP Header Auth | `Authorization` | `Bearer $VAPI_API_KEY` | clx-voice-outreach-v1 (Vapi Dial node) |
| `Unipile` | HTTP Header Auth | `X-API-KEY` | `$UNIPILE_API_KEY` | clx-linkedin-outreach-v1 (Unipile Send Invite node) |
| `Calendly` | HTTP Header Auth | `Authorization` | `Bearer $CALENDLY_API_TOKEN` | clx-booking-v2 (if you wire Calendly API; currently client's calendly_link is stored statically) |
| `Stripe` | HTTP Header Auth | `Authorization` | `Bearer $STRIPE_SECRET_KEY` | clx-stripe-provision-v1 (Create Customer, Create Subscription) |

After creating each, open the target workflow(s), click the HTTP node
with the TODO note, pick the new credential from the dropdown, and
save. No UUIDs — the workflow JSON only references the name.

---

## Phase 5 — Workflow re-import order

From `docs/PART_C_VERIFICATION_REPORT.md` §6, consolidated with
Tasks 2, 3, 4 additions.

### Phase 5a — New workflows (fresh imports, none exist in n8n)

Import in this order. Execute Workflow node references require earlier
workflows to exist:

1. `clx-form-intake-v1.json`                    *(Part A/B)*
2. `clx-error-monitor-v1.json`                  *(Part B)*
3. `clx-reply-ingestion-v1.json`                *(Part B)*
4. `clx-apollo-enrichment-v1.json`              *(Part B.5)*
5. `clx-linkedin-outreach-v1.json`              *(Part B.6)*
6. `clx-whatsapp-outreach-v1.json`              *(Part B.6)*
7. `clx-voice-outreach-v1.json`                 *(Part B.6)*
8. `clx-voice-result-webhook-v1.json`           *(Part B.6)*
9. `clx-video-outreach-v1.json`                 *(Part B.7)*  ← **before booking-v2**
10. `clx-video-ready-v1.json`                   *(Part B.7)*
11. `clx-stripe-webhook-v1.json`                *(Task 3)*
12. `clx-stripe-provision-v1.json`              *(Task 3)*

### Phase 5b — Modified workflows (re-import to overwrite existing)

Every workflow that was edited during this sprint. Re-import overwrites
the version in n8n. After re-import, confirm `active=false` on every
non-mcp workflow.

13. `clx-lead-research-v2.json`                *(modified: Task 2 Apollo skip gate)*
14. `clx-lead-scoring-v2.json`                 *(modified in B.5/B.6)*
15. `clx-business-signal-detection-v2.json`    *(modified in B.5/B.6)*
16. `clx-campaign-router-v2.json`              *(modified: B.6 + B.7 + Task 2 segment node)*
17. `clx-outreach-generation-v2.json`          *(modified: B.5/B.6 + Task 2 Merge Segment Overlay)*
18. `clx-outreach-sender-v2.json`              *(modified in B.5/B.6)*
19. `clx-follow-up-v2.json`                    *(modified in B.5/B.6)*
20. `clx-booking-v2.json`                      *(modified: Part B.7 48h video fallback)*

### TESTING MODE senders — do NOT remove the redirect

Five workflows have the hardcoded test alias
(`adesholaakintunde+clxtest@gmail.com`). They stay that way until Mary
deliberately flips each one to production per the per-channel runbook:

- `clx-outreach-sender-v2.json`
- `clx-follow-up-v2.json`
- `clx-booking-v2.json`
- `clx-video-ready-v1.json`
- `clx-stripe-provision-v1.json`

---

## Phase 6 — Per-channel activation (one at a time)

Order chosen to maximize learning with minimum risk: email is the
proven baseline, Apollo unlocks research depth, LinkedIn and WhatsApp
are lower unit cost than voice + video.

### 6a. Email (already configured — confirm)

- Gmail credential bound
- `clx-outreach-sender-v2` active=true
- `clx-follow-up-v2` active=true
- `clx-booking-v2` active=true
- Send test lead through pipeline; verify arrival in test inbox

### 6b. Apollo enrichment

- `APOLLO_API_KEY` in `.env`
- `Apollo` credential created + bound to `clx-apollo-enrichment-v1`
- `clx-apollo-enrichment-v1` activated
- `clx-lead-research-v2` has the Apollo skip gate from Task 2 — B2C
  leads (personal email, no LinkedIn/org signals) bypass Apollo
  automatically; B2B leads flow through enrichment
- Test: POST a B2B lead to the manual webhook; confirm
  `leads.apollo_enriched_at` populated and a row in
  `apollo_enrichment_log`

### 6c. LinkedIn

- Unipile account + LinkedIn connected
- `UNIPILE_API_KEY`, `UNIPILE_ACCOUNT_ID` in `.env`
- `Unipile` credential created + bound to
  `clx-linkedin-outreach-v1` (Unipile Send Invite node)
- Replace `TODO_UNIPILE_ACCOUNT_ID` token in the node body with your
  real account ID
- `clients.channels_enabled` includes `'linkedin'`
- Test on one high-score lead with `preferred_channel='linkedin'`
- Verify `linkedin_outreach_log` + `outreach_log` rows created

### 6d. WhatsApp

- Twilio WhatsApp sender approved
- `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_WHATSAPP_NUMBER`
  in `.env`
- `Twilio` credential (HTTP Basic Auth) created + bound to
  `clx-whatsapp-outreach-v1` (Twilio Send node)
- `clients.channels_enabled` includes `'whatsapp'`
- Test on one Canadian mobile lead
- Verify `whatsapp_outreach_log` + `outreach_log` rows created

### 6e. Voice — **BLOCKED until real CRTC DNCL lookup lands**

The `check_dncl_status` SQL function currently returns `true`
unconditionally. Activating voice before replacing that placeholder
with a real CRTC Do Not Call List lookup is non-compliant for Canadian
numbers. Do not activate this channel until that work is done.

Steps (for when the blocker is resolved):

- Replace `check_dncl_status` with a real DNCL check (separate work
  item not in this sprint)
- `VAPI_API_KEY`, `VAPI_PHONE_NUMBER_ID`, `VAPI_ASSISTANT_ID` in `.env`
- `Vapi` credential (Bearer) created + bound to
  `clx-voice-outreach-v1` (Vapi Dial node)
- Vapi assistant end-of-call webhook → `clx-voice-result-webhook-v1`
  URL
- `clients.channels_enabled` includes `'voice'`
- Activate both `clx-voice-outreach-v1` and
  `clx-voice-result-webhook-v1`

### 6f. Video (Tavus)

Per `OPERATIONS_HANDBOOK.md §15`:

- Tavus account + replica trained
- `TAVUS_API_KEY`, `TAVUS_REPLICA_ID`, `TAVUS_CALLBACK_URL` in `.env`
- `Tavus` credential + `Anthropic API` credential bound to the
  matching nodes
- Replace TODO tokens in `Tavus Generate Video` node
- Configure Tavus Dashboard callback → `TAVUS_CALLBACK_URL`
- Synthetic webhook test → expect `VIDEO_RESULT_NO_MATCH` in
  scan_errors
- `clients.video_enabled=true` for target client
- End-to-end dry-run on one test lead

### 6g. Stripe billing

Per `OPERATIONS_HANDBOOK.md §21`:

- Stripe account verified, Live mode active
- Products + Prices created; Price IDs in `.env`
- Webhook endpoint configured for 6 event types
- `STRIPE_WEBHOOK_SECRET` in `.env`
- `Stripe` credential created + bound to
  `clx-stripe-provision-v1` (Create Customer + Create Subscription
  nodes)
- `stripe listen --forward-to ...` smoke test passes
- Test subscription dry-run from Dashboard with Mary's card (refund
  after)
- Activate `clx-stripe-webhook-v1` and `clx-stripe-provision-v1`

---

## Phase 7 — First-client onboarding

1. **Create client row** in Supabase (or via `clx-form-intake-v1` if
   the client filled out the intake form):
   ```sql
   INSERT INTO clients (
     id, client_name, client_slug, vertical, dashboard_token,
     calendly_link, channels_enabled, focus_segments, video_enabled
   )
   VALUES (
     gen_random_uuid(),
     'Client Business Inc.',
     'client-business',
     'insurance_broker',
     'ctok_' || substr(md5(random()::text), 1, 16),
     'https://calendly.com/client-business/discovery',
     '["email","voice"]'::jsonb,   -- only channels the client opts into
     '["commercial"]'::jsonb,       -- or ["residential"] or both
     false                          -- flip to true when Tavus ready
   )
   RETURNING id, dashboard_token;
   ```
2. **Provision billing** via `clx-stripe-provision-v1`:
   ```bash
   curl -X POST https://automation.crystallux.org/webhook/clx-stripe-provision \
     -H "Content-Type: application/json" \
     -d '{
       "client_id": "<new-client-uuid>",
       "client_email": "owner@clientbusiness.com",
       "business_name": "Client Business Inc.",
       "selected_plan": "founding_1997"
     }'
   ```
   Welcome email lands in TESTING MODE inbox. Verify
   `clients.stripe_customer_id` + `subscription_status='trialing'`.
3. **Import client's existing leads** (if any) via
   `clx-lead-import` or direct SQL.
4. **First outreach run in TESTING MODE.** Every email still goes to
   Mary's test inbox. Review the copy with the client before flipping.
5. **Go live.** Client approves the messaging. Edit
   `clx-outreach-sender-v2` Build Gmail Raw Message node: replace
   `const to = 'adesholaakintunde+clxtest@gmail.com'` with
   `const to = data.email`. Re-import. Repeat for follow-up-v2,
   booking-v2, video-ready-v1 per the client's rollout preference.

---

## Phase 8 — Dashboard access URLs

Three access patterns:

- **Client mode** (per-client filtered view):
  ```
  https://crystallux.org/dashboard?client_id={CLIENT_UUID}&token={CLIENT_DASHBOARD_TOKEN}
  ```
  `CLIENT_DASHBOARD_TOKEN` is stored on `clients.dashboard_token`
  (generated at client-row insert time).

- **Admin mode** (multi-client aggregate):
  ```
  https://crystallux.org/dashboard?admin=true&token={MARY_MASTER_TOKEN}
  ```
  Shows the MRR summary strip, per-client billing table, and the
  channels-active panel for every client.

- **Public form intake** (per-client, client provides to their own
  prospects):
  ```
  https://crystallux.org/intake/{CLIENT_SLUG}
  ```

---

## Phase 9 — Ongoing maintenance

- **Daily:** quick pass on dashboard for spikes in scan_errors;
  verify TESTING MODE inbox hasn't filled with unexpected sends.
- **Weekly:** dashboard drill-down per client — pipeline health,
  response rates, any channel failing consistently.
- **Monthly:** Apollo credit usage report; Stripe Dashboard MRR vs
  dashboard MRR calc (should match within rounding); review the
  stripe_events_log.unprocessed tail for stuck events.
- **Quarterly:** review monitoring_thresholds tuning (were any alerts
  too noisy / too quiet?); API cost review (Tavus renders vs
  video_monthly_cap; Anthropic token spend vs outreach volume);
  vertical performance (which niches are converting well; should any
  be deprecated or added).

---

## Where each runbook lives

| Topic | File | Section |
|---|---|---|
| LinkedIn / WhatsApp / Voice | `docs/architecture/OPERATIONS_HANDBOOK.md` | §14 |
| Video (Tavus) | `docs/architecture/OPERATIONS_HANDBOOK.md` | §15 |
| B2B/B2C segmentation | `docs/architecture/OPERATIONS_HANDBOOK.md` | §20 |
| Stripe billing | `docs/architecture/OPERATIONS_HANDBOOK.md` | §21 |
| End-to-end verification | `docs/PART_C_VERIFICATION_REPORT.md` | entire file |
| Queued vertical seeding (batch 1) | `docs/architecture/QUEUED_VERTICAL_SEEDING_B2B.md` | entire file |
| Market Intelligence (future tier) | `docs/architecture/ROADMAP_B9_MARKET_INTELLIGENCE.md` | entire file |
| Beauty Marketplace (future product) | `docs/architecture/FUTURE_BEAUTY_MARKETPLACE_ROADMAP.md` | entire file |

---

**Done.** When every checkbox above is ticked, Crystallux is live
across all channels with billing, monitoring, segmentation, and
dashboard. New-vertical onboarding runs through the queued-seeding
batch; new channels get added using the same pattern as the existing
ones (credential by name, active=false import, runbook in
OPERATIONS_HANDBOOK, per-client flip).
