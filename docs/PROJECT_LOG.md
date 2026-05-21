# Project Log

Living journal of build progress. Updated at the end of every Claude Code session.

**How to use:**
- Session entries are reverse chronological — newest at the top of "Session log".
- Standing sections (Currently blocked / API signups / Mary's standing decisions) live at the bottom and update over time, not per-session.
- Git history is the authoritative commit record; this log is the higher-level narrative + decisions + blockers. Don't restate every commit subject — group related commits into a single bullet.

**Template for each session entry:**

```markdown
## YYYY-MM-DD — <one-line theme>

### What shipped
- <bullet per logical deliverable, with commit SHA(s)>

### What got unblocked / decided
- <Mary decisions, scope choices, tech picks>

### What got blocked or deferred
- <items that need external input — these also go in the Standing sections at the bottom>

### What Mary needs to do next
- <apply steps, env vars, signups, manual UI work>

### Open questions for next session
- <if any>
```

---

## Session log

## 2026-05-20 — Smart Quote + LUXI commerce + AVA scheduling + MGA public intake

### What shipped
- **Smart Quote — end-to-end production** (`8d7d922` → `cb4dffa`, `7c589f2`, `403abd0`, `d194cf1`, `d84360e`, `f2cc022`)
  - Schema: 6 tables (`quote_templates`, `quote_pricing_rules`, `quote_addons`, `quote_drafts`, `quote_completed`, `quote_follow_ups`)
  - 7 industry templates seeded (insurance_personal, construction, dental, cleaning, restaurants, moving, beauty)
  - Generic question-flow page `/pages/smart-quote/industry.html?industry=<slug>` (works for any template)
  - Admin Estimator index page with KPIs + Drafts/Completed tabs
  - Full server-side flow workflow `wfAdminSmartQuoteFlowV1`: load_template / start_draft / save_step / submit, with authoritative server-side pricing engine on submit
  - Postmark customer email on submit with branded breakdown
  - Public quote landing `crystallux.org/quote/<id>` (`site/quote.html` + 2 public workflows `clxPublicQuoteFetchV1` / `clxPublicQuoteRespondV1` + accept/decline)
  - Follow-up nurture cron `clxQuoteFollowupCronV1` — day 3 / 7 / 14 reminder sequence, auto-skips if quote already accepted/declined/expired
- **LUXI commerce loop closed** (`0bf7ee6`, `3ac648a`, `0f59289`)
  - SQL function `luxi_tick_anti_snipe_extension()` — wired into the existing 5-min auction tick
  - Stripe capture cron `clxLuxiStripeCaptureV1` — every minute, captures won-bid PaymentIntents + cancels outbid holds
  - Bid parser webhook `clxLuxiBidParserV1` (internal-secret gated, for future TikTok/IG/FB pollers)
  - Auction create / cancel from the LUXI dashboard via `wfAdminLuxiAuctionManageV1` + `+ New auction` and Cancel buttons
  - **Manual live-bid entry page** `/pages/avatars/luxi/live.html` — Mary watches a stream, enters bids by hand; `wfAdminLuxiPlaceBidV1` auto-registers tier_0 bidders on first sighting via SHA-256 identity hash
- **AVA broadcast scheduling** (`3d743d9`, `e7e7c25`)
  - Interactive AVA dashboard rendering 104 content topics grouped by stream with click-to-detail
  - Migration `avatar-content-library-topic-link.sql` adds `content_topic_id` FK
  - Scheduling workflow `wfAdminAvatarScheduleV1` (list / schedule / cancel actions)
  - Page `/pages/avatars/ava/schedule.html` with calendar-like queue, topic picker, platform multi-select
- **CIRO automation surface** (`aa463af`, `7059c9d`, `e9df074`)
  - Communications log viewer (unifies `messages_sent` + `outreach_log` + `email_log`)
  - Hot Lead Alert cron `clxCiroHotLeadAlertV1` — scores ≥80 + intent signals → writes to `sentinel_alerts`
  - Calendar Conflict Detector cron `clxCiroCalendarConflictV1` — overlap + tight-gap detection in upcoming `bookings`
  - Dedicated CIRO Alerts page `/pages/ciro/alerts.html` (filters `sentinel_alerts` to `module_name='ciro'`)
- **MGA public intake closes the booking loop** (`8e6d45e`)
  - `site/join-advisor.html` + `site/join-carrier.html` public landings
  - `clxPublicMgaApplyV1` workflow inserts into `leads` with the right `lead_type` + Postmark notification to Mary
  - Booking workflow's outgoing URLs updated to `crystallux.org/join-{advisor,carrier}` (previously 404'd)
- **LUXI + AVA interactive dashboards** (`3d743d9`) — same MAXI-template UX pattern
- **Dev console** at `/pages/system/dev-console.html` (`ee1bb8b`) — page directory + webhook probe + content edit GitHub links
- **Admin theme reverted to light**; MGA stays purple (`767872f`)
- **Security sweep — clean** (`767872f` includes `docs/audit/SECURITY_SWEEP_2026-05-20.md`)
- **Recovery tooling** (`e01668f`, `f38dadb`, `60aa124`, `f5c2773`) — apply-workflow-patch + emergency-recover-webhooks scripts, including the Alpine-sidecar SQL delete that doesn't require sqlite3 in the n8n container

### What got unblocked / decided
- Smart Quote tier-picking is now industry-agnostic (anchor-based, not advisor_count-specific)
- `bidder_identity_hash` = SHA-256(platform + ':' + lower(handle)) — shared convention across both bid-entry paths (manual admin + future external poller) so a bidder is one record regardless of entry mode
- Quote landing URL is `crystallux.org/quote/<id>` (the marketing site, via `_redirects` rewrite). NOT `insurance.crystallux.org/quote/<id>` (placeholder URL retired from email body)
- Advisor/carrier signup URLs: `crystallux.org/join-advisor`, `crystallux.org/join-carrier`, `/join` falls back to advisor form
- Workflow naming + auth conventions reaffirmed: top-level `id`, `neverError: true` on Validate Session, `(rows.user_id || rows.id)` unwrap-safe Check Admin, `allOf()` helper, CORS headers on public endpoints
- Branch model: ongoing work on `scale-sprint-v1`; ff-merge to `main` at the end of each commit cluster so CF Pages auto-deploys

### What got blocked or deferred
- AVA video render pipeline — gated on **HeyGen API signup**
- CIRO LinkedIn auto-DM/comment — gated on **LinkedIn Developer API signup**
- Server-side PDF for Smart Quote — gated on **PDF service pick** (Browserless ~$10/mo recommended); print-from-browser works as stop-gap
- Live LUXI broadcast (camera) — gated on **HeyGen Interactive + Restream**
- Auto-pull comments for LUXI bidding — gated on **TikTok / Facebook Graph / Instagram / YouTube Developer APIs**
- Avatar auto-reply to bidders — same blocker as above
- SaaS billing per-tenant (Stripe products + checkout + per-tenant tier) — multi-session scope, low priority
- 130 LUXI content templates — Mary writes the copy
- Real audio/voice for outreach — gated on **ElevenLabs signup**

### What Mary needs to do next
```bash
git pull origin main

# All new migrations:
psql -f db/migrations/smart-quote-schema.sql
psql -f db/migrations/smart-quote-additional-industries.sql
psql -f db/migrations/luxi-anti-snipe-function.sql
psql -f db/migrations/avatar-content-library-topic-link.sql

# All new workflows (import + activate):
bash scripts/n8n/apply-workflow-patch.sh workflows/api/admin/   --no-pull --activate=all
bash scripts/n8n/apply-workflow-patch.sh workflows/api/avatars/ --no-pull --activate=all
bash scripts/n8n/apply-workflow-patch.sh workflows/api/public/  --no-pull --activate=all
```

Confirm `POSTMARK_API_TOKEN`, `STRIPE_SECRET_KEY`, `INTERNAL_BID_PARSER_SECRET` env vars exist on n8n.

### Open questions for next session
- Which API does Mary want to sign up for first? (LinkedIn is free + unlocks CIRO Phase 4; HeyGen unlocks AVA video; Browserless unlocks Smart Quote PDF; Restream/HeyGen Interactive unlocks live LUXI)
- Does Mary want me to refine the seeded industry questions for any specific vertical, or wait for real customer feedback?
- Should the manual live-bid page poll a faster cadence (currently 8s)?

---

## 2026-05-19 — Sales Engine reactivation + Phase 1-9 fixes + nav/theme

### What shipped
- WS1 — Phase 1-9 reactivation patches (`aa7a33c`): city-scan WS6 insurance verticals (`carrier_prospect` / `advisor_candidate` / `smb`), campaign-router `lead_type` override, **critical booking send-bug fix** (booking emails were hardcoded to Mary's test inbox)
- WS3/4/5 portal audit (`fa4f3dd`): client-dashboard / mga advisor / insurer-dashboard ALL already exist in repo — only DNS work needed
- 23 admin workflows patched for autounwrap bug (`486831d`); 54 workflows patched for Validate Session halt (`6e44d0c`); audit + dedupe tooling shipped (`f5bc57a`, `877cfcc`, multiple scripts)
- Workflow recovery infrastructure: `apply-workflow-patch.sh` + `emergency-recover-webhooks.sh` (Alpine sidecar) + `dedupe-workflows.py`
- Sub-domain mapping clarity: `main` branch is what CF Pages serves; ongoing ff-merges from `scale-sprint-v1`

### What got unblocked / decided
- Repo branch model: working on `scale-sprint-v1`, ff-merge to `main` at end of each commit cluster (so CF Pages auto-deploys without a branch swap)
- Path mismatches were not the cause of 404s — workflows weren't activated. Activation surfaces in `apply-workflow-patch.sh --activate=all`
- `webhook_entity` orphan cleanup is required between import + activation cycles (encoded in `emergency-recover-webhooks.py` Alpine sidecar approach)

### What got blocked or deferred
- Live n8n still needs Mary to run `emergency-recover-webhooks.sh` to flip the remaining unhealthy endpoints
- 36 endpoints were still NOT-FOUND post-recovery; root cause was orphan `webhook_entity` rows blocking re-activation + a too-conservative `--activate=auto` default → fix shipped

### Decisions Mary made
- Confirmed Sales Engine WAS built in April with 12-phase pipeline; don't rebuild, extend
- "Don't gate, just build" — operating mode for the multi-week run
- Theme: admin = light, mga = purple (separate stylesheets, no cross-coupling)

---

## Earlier weeks (pre-2026-05-19) — see git log

Highlights from before this log was started:
- AVA / LUXI / MAXI avatar platform schema + initial dashboards
- MGA Layer 2 (insurance vertical): 73 workflows + insurer-dashboard + advisor portal + principal portal
- Sales Engine 12-phase pipeline (built April 2026, then partially reactivated this sprint)
- T1.7 LUXI auction tick (`feb7fc2`) — close-expired SQL function + 3-node cron
- Webhook inventory + comprehensive workflow audit tooling (`scripts/n8n/audit-webhook-endpoints.py`)
- `docs/audit/blockers.md` blocker numbering convention (entries 0a–0t cover historical issues)

For pre-log archaeology: `git log --oneline --since="2026-04-01" --until="2026-05-19" | wc -l` and group by week from there.

---

## Currently blocked (standing — update over time)

| Blocker | Severity | Action owner | Notes |
|---|---|---|---|
| HeyGen API key | Build | Mary signup | Unlocks AVA video render pipeline + outreach personalization |
| LinkedIn Developer API | Build | Mary signup | Unlocks CIRO Phase 4 auto-DM/comment |
| TikTok / Facebook Graph / Instagram / YouTube Developer APIs | Build | Mary signup | Unlocks LUXI auto-comment monitoring + avatar replies |
| Restream / HeyGen Interactive | Build | Mary signup | Unlocks live LUXI broadcast (camera-on) |
| ElevenLabs API | Build | Mary signup | Unlocks AI voice outreach + LUXI voice |
| Browserless or CF Worker PDF service | Polish | Mary pick | Smart Quote server-side PDF (print-from-browser works as stop-gap) |
| Stripe per-tenant product setup | Build | Mary | SaaS billing tier (multi-session work; deferred until first paying tenant) |
| Apollo paid plan integration tuning | Polish | Mary | Confirm plan tier matches actual lead enrichment volume |
| 130 LUXI content templates | Content | Mary writes | Auction opening / showcase / engagement / bid encouragement / winner / anti-fraud copy |
| Industry-specific Smart Quote tuning | Content | Mary writes | Default questions/pricing are MVP; refine per vertical based on real customer feedback |

## API signups needed (priority order)

1. **LinkedIn Developer API** — free, ~30 min to register, unlocks CIRO LinkedIn auto-DM (most-asked feature)
2. **TikTok Developer / Meta Business (Facebook + Instagram)** — free, unlocks LUXI auto-comment pull and bidder auto-registration without manual entry
3. **HeyGen** — ~$99–330/mo, unlocks AVA video render → starts visible AVA broadcasts
4. **ElevenLabs** — ~$22/mo, AI voice (Vapi already wired for inbound; this adds AI-voiced outbound)
5. **Browserless** — ~$10/mo, simplest HTML-to-PDF for Smart Quote
6. **Restream** — ~$19–83/mo, multi-platform live streaming for LUXI

## Mary's standing decisions (the rules I work to)

- **Don't break what's working** — pre-existing workflows + dashboards stay functional through any refactor
- **Dormant by default** — new workflows ship with `active: false`; Mary activates per demo path
- **Don't activate workflows or apply migrations from code** — those are Mary's manual VPS actions
- **Branch: `scale-sprint-v1` is the working branch; `main` is the deploy branch.** ff-merge to main at end of each commit cluster
- **Workflow conventions** (enforced by canonical patterns + `add-top-level-ids.py`):
  - Every workflow JSON has top-level `id` (camelCase: `wfXxx` for admin webhooks, `clxXxx` for everything else)
  - Validate Session httpRequest has `neverError: true`
  - Check Admin node uses `(rows.user_id || rows.id)` unwrap-safe pattern
  - Multi-row fetches use the canonical `allOf()` helper
  - Public endpoints include CORS headers (Access-Control-Allow-Origin: *)
- **Sustainable pace** — aim for 3–7 focused commits per session; quality over volume
- **Push frequently** — every commit; never sit on uncommitted work
- **Session handoff format** — 2-3 lines what shipped / 1 line blocker / 1 line next
- **`/shared/*` files cached at CF edge for 24h** — purge after any nav.html / components.js / layout.css change

## Glossary (quick reference)

| Term | Meaning |
|---|---|
| Sales Engine | The 12-phase lead-discovery → outreach → booking pipeline built April 2026 |
| Smart Quote (Estimator) | Multi-industry pricing tool shipped 2026-05-20 |
| LUXI | Live commerce avatar (auctions) |
| AVA | Insurance education avatar |
| MAXI | SMB growth avatar (21 industries) |
| CIRO | Operations avatar (comms log, alerts, briefings) |
| MGA | Mary's insurance Managing General Agency vertical |
| n8n | Workflow engine at `automation.crystallux.org` |
| `lead_type` | `carrier_prospect` / `advisor_candidate` / `smb` — drives routing in city-scan + campaign-router + booking |
| `bidder_identity_hash` | SHA-256(platform + ':' + lower(handle)) — stable bidder key across entry paths |
