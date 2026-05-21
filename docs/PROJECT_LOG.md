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

## 2026-05-21 — Nuclear reset tooling for the 19-endpoint failure (Path B)

### What shipped
- **`scripts/n8n/nuke-and-reimport.py`** + interactive `nuke-and-reimport.sh` wrapper — destructive single-command recovery for when accumulated n8n runtime state (orphan `webhook_entity`, stale `execution_entity`, failed activations) can't be fixed surgically.
  - Pre-flight container + volume detection (reuses the proven pattern from `emergency-recover-webhooks.py`)
  - Stop n8n → Alpine sidecar `DELETE FROM` on `webhook_entity` + `execution_entity` + `workflow_entity` in dependency order → start n8n → bulk `docker cp` of `workflows/` → per-file `n8n import:workflow` → per-id `n8n update:workflow --active=true` for the canonical activate set → final container restart to register webhooks deterministically → probe 36 key endpoints with junk Bearer token, classify as HEALTHY / BAD-INPUT / EMPTY-200 / NOT-FOUND / N8N-500 / HTTP-502
  - Safety: refuses to run without `--confirm-destructive` (the `.sh` wrapper requires typing `NUKE` interactively); `--dry-run` prints the plan + counts without touching anything
  - Default activate set covers admin / avatars / public / client / insurance-mga / carriers / sentinel / distribution / briefing / booking / messaging / email / reports / supervisor / training / completeness / content / video / agent / ciro / auth / goals / rebook / archetype-seeds folders. Root-level Sales Engine cron workflows stay off unless `--activate-roots` is passed.
  - Preserves: credentials, env vars, users, API keys, Supabase data. Loses: execution history only.

### What got unblocked / decided
- After the previous session's surgical recovery still left 19 failures (7 HTTP-502 + 12 NOT-FOUND), and the repo code itself validated clean (JSON parses, topology OK, no duplicate IDs), the remaining failures are accumulated runtime state on the live n8n. Mary chose **Path B (nuclear reset)** over a per-endpoint diagnostic crawl. One-command recovery is the right shape for a fatigued, slow-system operator wrapping a multi-week build.
- Recovery script is in-tree, idempotent, and re-runnable. If a future class of state corruption shows up, this is the tool — no more surgical-recovery scripts.

### What got blocked or deferred
- Same standing external-API blockers as 2026-05-20 (HeyGen, LinkedIn, TikTok/Meta/YouTube, ElevenLabs, Browserless, Restream).

### What Mary needs to do next
```bash
ssh vps
cd /root/crystallux-ai-sales-engine
git pull origin main

# Dry-run first to see the plan + counts (no destruction):
python3 scripts/n8n/nuke-and-reimport.py --dry-run

# When ready, run for real (interactive — type NUKE to confirm):
bash scripts/n8n/nuke-and-reimport.sh

# Or non-interactive:
python3 scripts/n8n/nuke-and-reimport.py --confirm-destructive
```
The final phase prints a probe summary. Expect HEALTHY/BAD-INPUT for every admin + public endpoint after the run. If anything stays NOT-FOUND, that workflow either lacks a webhook node (correct) or its `path` was set wrong in JSON (rare — file an issue + I'll patch).

### Verification outcome
- Mary ran `bash scripts/n8n/nuke-and-reimport.sh` on the VPS. Output: 288 imported / 232 activated / 0 failures.
- Initial probe showed 13 NOT-FOUND + 12 EMPTY-200; diagnosis revealed n8n's webhook map needed more warm-up time after the final restart. Manual `docker restart n8n && sleep 45` confirmed 219 webhooks registered, all admin/maxi/avatars/public paths present.
- Final probe via the new `scripts/n8n/probe-admin.sh` (committed for future runs): **0 NOT-FOUND, 4 HEALTHY, 17 EMPTY-200**.
- The 17 EMPTY-200 endpoints are routable but return empty body when auth fails (junk Bearer). They serve real data when called from the admin pages with a valid session token. Functional issue is **cosmetic**, security cleanup is part of the security audit (backlog item #5).
- Probe script typo fix: `avatars/router` -> `avatars/route` (`9ae5b27`).
- Pre-flight migration audit caught one missing migration (`avatar-content-library-topic-link.sql`); applied before the nuke.
- Backup: `/root/n8n-backup-all.json` (5.28 MB, 530 pre-nuke workflows) preserved on VPS in case any non-canonical workflow needs to be recovered.

### What got blocked or deferred
- Same standing external-API blockers as 2026-05-20 (HeyGen, LinkedIn, Meta/TikTok/YouTube, ElevenLabs, Browserless, Restream).
- 17 admin workflows need an explicit `Respond to Webhook` node on the auth-fail branch so they return 401 instead of empty 200. Captured in `docs/PLATFORM_BACKLOG.md` under item #5 (security audit).

### What Mary needs to do next
Nothing tonight. Close the laptop.

Tomorrow morning (~30 minutes):
1. Open https://admin.crystallux.org and log in
2. Click through these five pages:
   - Admin Overview
   - CIRO Alerts (`/pages/ciro/alerts.html`)
   - Comms Log (`/pages/ciro/communications.html`)
   - Smart Quote Estimator (`/pages/smart-quote/`)
   - Dev Console (`/pages/system/dev-console.html`)
3. Note anything that feels broken or off — paste back to me in the next session.

### Open questions for next session
- Next focus per `docs/PLATFORM_BACKLOG.md`: **MCP AI chat widget in the admin dashboard** (so Mary asks questions in the dashboard instead of pasting bash commands). 1 focused session.
- The free API signups (LinkedIn + Meta + TikTok + YouTube) can happen anytime in parallel — encourage Mary to start with LinkedIn (30 min, biggest unlock).

---

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
