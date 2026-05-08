# External dependencies checklist

> **Format:** by phase, with signup URL + credentials needed + setup time + whether it blocks subsequent phases or runs in parallel. Tick items as you complete them.

---

## Phase 1 — TONIGHT (~3-4 hours total)

### Stripe (billing)

- [ ] Sign up at [stripe.com/register](https://stripe.com/register) — `info@crystallux.org`
- [ ] Create products + prices per [STRIPE_PRODUCTS_SPEC.md](../STRIPE_PRODUCTS_SPEC.md) (universal tiers + per-vertical founding rates)
- [ ] Configure Stripe Tax for ON, BC, AB, QC
- [ ] Configure Customer Portal
- [ ] Set up webhook to `https://automation.crystallux.org/webhook/stripe` with the 7 events listed in [stripe-activation.md](stripe-activation.md)
- [ ] Copy these secrets into n8n VPS env:
  - [ ] `STRIPE_SECRET_KEY`
  - [ ] `STRIPE_PUBLISHABLE_KEY`
  - [ ] `STRIPE_WEBHOOK_SECRET`
  - [ ] `STRIPE_PORTAL_URL`
  - [ ] `STRIPE_PRICE_*` for each created price
- [ ] Activate `clx-stripe-provision-v1` and `clx-stripe-webhook-v1` in n8n UI
- [ ] Smoke test with card `4242 4242 4242 4242`

**Setup time:** 30-45 min once you have a Stripe account.
**Blocks:** monetisation. Without this, no real customers pay.
**Parallel?** Yes — can run in parallel with Postmark below.

### Postmark (transactional email)

- [ ] Sign up at [postmarkapp.com](https://postmarkapp.com) — `info@crystallux.org`
- [ ] Verify sender domain `crystallux.org` (DKIM + Return-Path + SPF — 10-30 min DNS propagation)
- [ ] Get Server API token
- [ ] Create the 9 templates in Postmark dashboard (aliases match `templates/emails/*.html` files)
- [ ] Generate `INTERNAL_EMAIL_SECRET`: `openssl rand -base64 24`
- [ ] Set env vars on n8n VPS:
  - [ ] `POSTMARK_API_TOKEN`
  - [ ] `INTERNAL_EMAIL_SECRET`
  - [ ] `N8N_INTERNAL_BASE` (typically `http://localhost:5678`)
- [ ] Apply migration: `email_log` table + `clients.welcome_email_sent_at` column (in `postmark-activation.md` step 9)
- [ ] Activate `clx-email-send` and `clx-auth-welcome` in n8n UI
- [ ] Update existing magic-link + password-reset workflows to call `/webhook/email/send` (per step 7 in `postmark-activation.md`)
- [ ] Smoke test: send a magic link, confirm email lands

**Setup time:** 30-45 min including DNS propagation.
**Blocks:** real auth emails (magic link, password reset, welcome, billing notices).
**Parallel?** Yes.

---

## Phase 2 — Behavioral Intelligence (NO new external deps)

Phase 2 only requires existing Anthropic + OpenAI keys (already in env for Copilot). Tier 1 sources are all free public APIs.

Optional Tier 2 paid sources (sequence as needed):

- [ ] **Google News API** — sign up at [news.google.com](https://news.google.com); ~$0.005 per query at scale. **Setup:** 30 min. **Blocks:** nothing — degrades gracefully without.
- [ ] **Crunchbase Starter plan** — $49/mo at [crunchbase.com](https://crunchbase.com). **Setup:** 15 min. **Blocks:** nothing.
- [ ] **Apollo signal feed** — already paid for Pipeline; just enable the signal-monitor endpoint. **Setup:** in product, 10 min.

---

## Phase 3a — Voice agent (5-7 day build, 30-min external setup)

Senior recommendation: **Vapi** (see [`docs/agent/build-phases.md`](../agent/build-phases.md) Phase 3a for reasoning — better existing wiring + lower per-minute cost vs Retell).

- [ ] Sign up at [vapi.ai](https://vapi.ai). Free tier covers initial testing.
- [ ] Create an Assistant in Vapi dashboard. Use OpenAI / Claude as the LLM (Claude works via Vapi's BYO LLM feature).
- [ ] Configure voice (start with stock voice, swap to ElevenLabs clone later if Mary records — 30-60 min recording session).
- [ ] Set webhook URLs:
  - [ ] inbound → `https://automation.crystallux.org/webhook/clx-agent-voice-inbound`
  - [ ] end-of-call → `https://automation.crystallux.org/webhook/clx-agent-voice-finalized`
  - [ ] transcript stream (already wired) → `https://automation.crystallux.org/webhook/vapi/transcript-stream`
- [ ] Copy API key + webhook secret into n8n env:
  - [ ] `VAPI_API_KEY`
  - [ ] `VAPI_WEBHOOK_SECRET`
- [ ] Buy a phone number through Vapi (or BYO Twilio number)
- [ ] Test outbound call to your own phone

**Setup time:** 30 min once account exists.
**Blocks:** voice agent.
**Parallel?** Yes.

---

## Phase 3b — WhatsApp + SMS (1-2 weeks external approval, 30 min config after)

### Twilio (SMS + WhatsApp Business)

- [ ] Sign up at [twilio.com](https://twilio.com)
- [ ] Buy a Canadian SMS-enabled phone number (~$1.15/mo)
- [ ] Apply for WhatsApp Business API access via Twilio's WA onboarding (this triggers the Meta verification below)
- [ ] Copy credentials to env:
  - [ ] `TWILIO_ACCOUNT_SID`
  - [ ] `TWILIO_AUTH_TOKEN`
  - [ ] `TWILIO_SMS_NUMBER`
  - [ ] `TWILIO_WHATSAPP_NUMBER`
- [ ] Configure inbound webhook on the Twilio number → `https://automation.crystallux.org/webhook/twilio/sms-inbound`

**Setup time:** 30 min for Twilio account; 1-2 weeks for WhatsApp Business approval.
**Blocks:** WhatsApp + SMS agent (3b).
**Parallel?** Twilio account setup is parallel; WA approval is the critical-path long pole.

### Meta WhatsApp Business

- [ ] Apply at [developers.facebook.com](https://developers.facebook.com) → WhatsApp Business Platform
- [ ] Submit Crystallux business verification (Mary uploads incorporation docs, address proof)
- [ ] Approve display name "Crystallux"
- [ ] Wait for Meta approval (1-2 weeks; faster if business is well-established)

**Setup time:** 1-2 weeks (external).
**Blocks:** WhatsApp inbound + outbound.
**Parallel?** Yes — submit early, build other phases in parallel.

---

## Phase 3c — Email agent (no new external)

Already-existing Postmark + Gmail/Outlook IMAP for inbound parsing.

---

## Phase 3d — Social media (1-2 weeks per platform approval)

### Meta (Instagram + Facebook)

- [ ] [developers.facebook.com](https://developers.facebook.com) → create Meta App
- [ ] Add **Instagram Graph API** + **Facebook Pages API** products
- [ ] App review for `pages_messaging` + `instagram_manage_messages` (1-2 weeks)
- [ ] Configure webhook → `https://automation.crystallux.org/webhook/clx-agent-meta-inbound`
- [ ] Per-tenant: tenant connects their FB page + IG account via OAuth flow

**Setup time:** Meta app setup 30 min; review 1-2 weeks.

### LinkedIn

- [ ] Already integrated via Unipile for outreach. Extend Unipile usage to inbound DM + comment monitoring.
- [ ] No new approval needed — Unipile abstracts LinkedIn auth.

### X (Twitter)

- [ ] [developer.twitter.com](https://developer.twitter.com) → Apply for Basic tier (~$100/mo)
- [ ] Generate API keys + bearer token
- [ ] Configure webhook for DMs + mentions
- [ ] Apply for elevated access if hitting rate limits at scale

**Setup time:** 1 week approval + 30 min config.

---

## Video pipeline — HeyGen (30-60 min recording session after activation)

- [ ] Sign up for HeyGen Creator plan ($29/mo) at [heygen.com](https://heygen.com)
- [ ] Mary records a 2-3 minute training video — multiple expressions, varied energy, clear audio
- [ ] HeyGen trains avatar (~24h)
- [ ] Get API key + avatar id; copy to n8n env:
  - [ ] `HEYGEN_API_KEY`
  - [ ] `HEYGEN_AVATAR_ID`
- [ ] Test video generation through `clx-video-outreach-v1` (currently dormant; activate per client)

**Setup time:** 1h Mary's time + 24h training wait.
**Blocks:** AI video outreach.
**Parallel?** Yes — fully independent from other phases.

---

## Booking — Cal.com (alternative to Calendly)

Currently using Calendly. Cal.com is a future migration option.

- [ ] [cal.com](https://cal.com) — free tier covers small teams
- [ ] Get API key
- [ ] Configure team scheduling per tenant
- [ ] Per tenant: connect Google Calendar / Outlook calendar
- [ ] Webhook → `https://automation.crystallux.org/webhook/calcom/booking-created` (workflow not yet built; see [api-surface-audit.md](../audit/api-surface-audit.md) Bucket 4)

**Setup time:** 30 min per tenant.
**Blocks:** nothing — Calendly continues to work.
**Parallel?** Yes — defer until tenant volume justifies the migration.

---

## Anthropic + OpenAI (already in env)

- [x] `ANTHROPIC_API_KEY` — Claude Sonnet for decisions / Haiku for classifications. Confirmed in env per existing Copilot workflows.
- [x] `OPENAI_API_KEY` — Whisper for transcription, embeddings for `agent_memory`. Confirmed in env.

If either is rate-limited at scale, request higher tier from the respective vendor. Both vendors approve quickly for verified business accounts.

---

## Critical-path summary

If you want to ship the most value fastest, the critical-path order is:

1. **Stripe + Postmark** (tonight, ~3-4 hours total) — unlocks monetisation + email
2. **Apply 3 SQL migrations** (10 min) — foundation for Phase 2 + 3
3. **Vapi** + **HeyGen** (parallel, can do later this week) — voice + video unlock the demo magic
4. **Twilio + Meta WA** (start the 1-2 week approval clock NOW) — these are the long-pole external dependencies
5. **Build Phase 2** (5-7 days) — Behavioral Intelligence
6. **Build Phase 3a-3f** (parallel as external deps land) — AI Sales Agent

The non-blocking parallel plan: while Meta WA approval is pending (1-2 weeks), Mary builds Phase 2 (Behavioral Intel) which has zero external dependencies beyond keys already in env.
