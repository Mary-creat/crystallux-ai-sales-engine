# Crystallux platform backlog

Living list of everything in flight. Update as items complete.

**Last refreshed:** 2026-05-21 (after the nuke-and-reimport session)

---

## 0. In progress right now

- [ ] Verify the nuke fix (confirm 404s are gone, then close the session)

## 1. MCP AI chat widget in admin dashboard

- [ ] Chat widget bottom-right of admin (Intercom-style)
- [ ] Wired to `CLX - MCP Tool Gateway` workflow
- [ ] 10 starter tools (list leads, search clients, fetch client detail, send email to lead, send SMS to lead, create booking, fetch quote, run report, audit endpoint, schedule avatar broadcast)
- [ ] Conversation memory per session
- [ ] Action confirmation for destructive operations
- [ ] Audit log of every action taken
- [ ] Add more tools on demand as you identify them

**Why:** so you can give commands directly in the dashboard instead of running terminal commands.

## 2. DevOps Digital Employee

- [ ] Auto-restart failed workflows
- [ ] Quota watcher (Postmark daily limit, Twilio balance, OpenAI rate limits, Apollo credits)
- [ ] Credential rotation reminder (keys older than 90 days)
- [ ] Workflow drift detector (live n8n vs repo)
- [ ] Daily DevOps briefing (one paragraph every morning)
- [ ] Proactive code suggestions when fixable patterns detected
- [ ] Builds on existing Sentinel infrastructure

**Why:** so you stop carrying the system-health mental load.

## 3. Chief Operating Officer Digital Employee (expanded scope)

Combined COO + CMO duties. One report, one digital employee, covering business + content + brand + growth.

### Business operations
- [ ] Pipeline health (leads by stage, conversion rates, time-in-stage, what is stuck)
- [ ] Revenue forecast (booked + likely-close, rolling 30/60/90 day)
- [ ] Bottleneck detector (where leads die in the funnel)
- [ ] Capacity planning (your calendar load vs intake rate)
- [ ] Overdue task surveillance (clients not contacted in X days)

### Content quality + brand maintenance
- [ ] Pre-send content QA on every email, SMS, video script (tone, brand voice, broken links, PII leaks, em-dash check)
- [ ] Brand voice consistency across all channels
- [ ] Auto-flag off-brand content before it ships
- [ ] Watch for accidental data exposure in any outgoing message

### Multi-channel monitoring
- [ ] Mentions + engagement watcher (TikTok, Instagram, Facebook, LinkedIn, YouTube, Email replies)
- [ ] Brand-presence health (frequency, voice, visual consistency per platform)
- [ ] Flag inconsistencies (e.g. tone differs across channels, posting cadence dropped)
- [ ] Cross-platform comment monitoring

### Reports + growth recommendations
- [ ] Weekly business review (Monday morning) covering pipeline + content + brand + revenue
- [ ] Growth-experiment proposals (when conversion stalls, propose 2-3 specific experiments)
- [ ] Sales-increase recommendations (which channel to invest in, which segment is hot)
- [ ] Quarterly "what to publicize" memo

**Why:** so you receive summaries and decisions, not raw data to interpret.

## 4. Email + SMS + video content voice audit

- [ ] Strip all em-dashes from customer-facing templates
- [ ] Rewrite all generic openings (e.g. "Hope this finds you well")
- [ ] Remove duplicated footer blocks
- [ ] Kill triple-emoji headers and auto-generated patterns
- [ ] Standardize voice across all sequences (casual vs formal consistency)
- [ ] Document brand voice in `docs/handbook/BRAND_VOICE.md` so the COO has a spec to enforce

**Why:** emails should sound like you wrote them, not like AI.

## 5. Security audit (node-by-node)

- [ ] Auth gates on every admin/client workflow (Validate Session + Check Admin canonical pattern)
- [ ] Input validation on public endpoints
- [ ] Secrets hygiene (no API keys in code, no PII in logs)
- [ ] CORS configured correctly per endpoint
- [ ] Rate limiting on public endpoints
- [ ] Per-tenant data isolation (Client A cannot see Client B)
- [ ] Webhook signature validation (Stripe, HeyGen, Vapi)
- [ ] Error branches in every workflow (no silent fails)
- [ ] Duplicate execution guards (booking accept twice does not fire twice)
- [ ] Output: `docs/audit/SECURITY_SWEEP_2026-05-XX.md`

**Why:** wraps the platform tight before customers touch it.

## 6. End-to-end smoke test

- [ ] Walk through Smart Quote customer journey on live system (quote, email, accept, booking, confirmation, calendar)
- [ ] Walk through MGA advisor application end-to-end
- [ ] Walk through carrier signup end-to-end
- [ ] Walk through LUXI auction creation, manual bid, winner notification
- [ ] Walk through AVA scheduled broadcast (once HeyGen is signed up)
- [ ] Document any breakage found

**Why:** you have not personally felt the customer journey yet.

## 7. Insurer marketing site audit

- [ ] Identify what info is currently public on `insurer-marketing/` that should not be
- [ ] Strip internal references, pricing logic, system internals
- [ ] Keep only what insurers need to plug in (API docs, integration guide, contact)
- [ ] Output: cleanup PR with before/after diff

**Why:** the concern about leaked internal info is valid and unaudited.

## 8. Standalone product pages (monetization layer)

- [ ] Public product page for Smart Quote (`/products/smart-quote`)
- [ ] Public product page for LUXI (`/products/luxi`)
- [ ] Public product page for AVA (`/products/ava`)
- [ ] Public product page for CIRO (`/products/ciro`)
- [ ] Public product page for MAXI (`/products/maxi`)
- [ ] Public product page for MGA (`/products/mga`)
- [ ] Public product page for Sales Engine (`/products/sales-engine`)
- [ ] Each page: features, pricing tier, demo video, signup CTA wired to Stripe checkout
- [ ] Per-tenant Stripe products + tier enforcement on signup
- [ ] Pricing decisions: you set the numbers, I wire them in

**Why:** the platform has the features but no place for customers to buy them.

## 9. API signup queue

### Free signups (do these first; biggest unlock per dollar)
- [ ] LinkedIn Developer API (free, 30 min) — unlocks CIRO auto-DM + comment
- [ ] Meta Business / Facebook + Instagram Graph (free, ~2 hours including verification) — unlocks LUXI auto-comment pull, AVA cross-posting
- [ ] TikTok Developer (free, 1-2 days approval) — same for TikTok
- [ ] YouTube Data API (free, 30 min) — content publishing + comment monitoring

### Paid signups (priority order)
- [ ] HeyGen (~$99-330/mo) — unlocks AVA video render, video outreach, video education
- [ ] ElevenLabs (~$22/mo) — premium voice for inbound + outbound calls
- [ ] Restream + HeyGen Interactive (~$19-83/mo) — live LUXI broadcast (camera-on)
- [ ] Browserless (~$10/mo) — Smart Quote server-side PDF

### Defer or skip
- [ ] Calendly OAuth confirm (already paid plan, verify two-way sync works)
- [ ] Stripe per-tenant product setup (defer until first paying customer)
- [ ] Apollo plan tier check (confirm matches actual lead volume)

**Why:** external dependencies only you can complete.

## 10. Content you write personally

- [ ] 130 LUXI content templates (auction opening, showcase, engagement, bid encouragement, winner, anti-fraud)
- [ ] Industry-specific Smart Quote tuning (refine questions and pricing per vertical)
- [ ] Brand voice document (so the COO has rules to enforce)

**Why:** only you can write these. Cannot be delegated.

## 11. Optional handbook activations (deferred unless needed)

- [ ] Apply `db/migrations/sentinel-foundation-schema.sql` if you want Sentinel cost monitoring live
- [ ] Apply `db/migrations/carrier-management-schema.sql` if you want carrier dashboard with seeded data
- [ ] Both are documented in `docs/handbook/SENTINEL_OPERATIONS_GUIDE.md` and `CARRIER_OPS_GUIDE.md` for when you activate

**Why:** features exist but are not on the core customer path. Activate if and when you need them.

---

## Suggested session order

Roughly 8 focused sessions total to land everything.

| # | Session | What gets done |
|---|---|---|
| 1 | Tonight (verify nuke) | Confirm 404s gone, sleep |
| 2 | Next | MCP AI chat widget + 10 starter tools |
| 3 | Then | DevOps Digital Employee |
| 4 | Then | COO Digital Employee (business ops core) |
| 5 | Then | COO content QA + multi-channel monitoring + brand watch |
| 6 | Then | Email + SMS voice audit + brand voice doc |
| 7 | Then | Security audit + end-to-end smoke test |
| 8 | Then | Standalone product pages + Stripe checkout wiring |

Each session is roughly 60-90 minutes of focused work. Not back-to-back. Sustainable pace.

---

## Standing rules (for any session)

- Repo is the source of truth. Do not edit workflows in the n8n UI.
- Dormant by default. New workflows ship inactive; activate per demo path.
- Migrations and workflow activations are Mary's manual actions.
- Branch model: `scale-sprint-v1` working, ff-merge to `main` at end of each commit cluster.
- Push frequently. Never sit on uncommitted work.
- Update this file as items complete or new ones surface.
