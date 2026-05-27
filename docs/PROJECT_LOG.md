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

## 2026-05-26 — Signup funnel goes live + generate_video MCP wired end-to-end

Long session that closed three gaps blocking real customer signups: the public signup pages were in a redirect loop, the admin had no path for importing Mary's existing client list, and the video personalization stack existed but was never connected to MCP. All three landed; the platform is now ready for actual lead acquisition the moment external approvals (Postmark, Meta WhatsApp Business) clear.

### What shipped (8 commits — `3d1636a` → `72a8976`)

- **Public signup loop fix + customer-facing tech-leak cleanup** (`3d1636a`) — `/join-advisor` and `/join-carrier` were stuck in an infinite 308 redirect that gave ERR_TOO_MANY_REDIRECTS in Mary's browser. Root cause: explicit rewrite rules in `site/_redirects` fought CF Pages' built-in `.html` stripping (same trap the smart-quote comment in the file already warned about). Dropped the rules; CF Pages serves both paths natively now. Same commit replaced HeyGen / Postmark / Twilio / Vapi / Restream mentions across 5 customer-facing pages with plain-language equivalents ("AI video creation", "voice calls", etc.) — vendor names belong in PIPEDA subprocessor disclosures, not product pages.
- **Admin leads view cleaned up** (`1bd9313` → `765e27d`) — added a "Received" column showing `date_created` as an absolute timestamp; hid `advisor_candidate` + `carrier_prospect` lead types from the master admin by default (they belong to the MGA principal, not Crystallux master). Yellow banner shows count of hidden applications with a `?show=applications` reveal link. First commit assumed Postgres-convention column names (`created_at`, `lead_type`); follow-up fixed to actual API field names (`date_created`, `source`).
- **Bulk-import lane stood up** (`2f77813` + `c791ee0`) — new `workflows/api/admin/clx-admin-bulk-import-leads-v1.json` (admin-gated, 1000-lead cap, dedupes within batch by email, validates email + full_name, returns imported / skipped counts) + `admin-dashboard/pages/import-leads.html` (drag-drop CSV with PapaParse, auto-detects column mapping by header hints, preview of first 5 mapped rows, source / campaign_tag / lead_type / lead_score config, one-click dispatch). Sidebar nav link added between Leads and Workflows.
- **Super Visa landing page** (`af60837`) — dedicated `insurance-marketing/super-visa-insurance.html` for Mary's chosen highest-converting wedge (parents visiting Canada). Generic `/travel-insurance` page treats Super Visa as one dropdown option; this page is 100% focused: emotional hero ("Protect your parents before they travel to Canada"), pain anchor (uninsured ER costs), IRCC requirements ($100K, 1 year, Canadian insurer), 5-bracket sample-premium table for ages 55-80, pre-existing-condition honest disclosure, 5 FAQs answering actual Super Visa questions. Phone is required (not optional) — funnel relies on WhatsApp follow-up. Posts to existing `/mga/insurance/lead-capture` webhook with `product='super_visa'` hidden field. Footer + nav updated.
- **`generate_video` MCP pipeline wired end-to-end** (`23f2cdf` + `72a8976`) — the existing video stack (script-gen → HeyGen render → delivery) was orphaned: MCP's `Tool: Video` only called script-generate and never fired the render. Five-piece fix:
  - **New `workflows/api/mcp/clx-mcp-video-orchestrator-v1.json`** chains script-generate → heygen-render in one internal-call surface. POST `/webhook/mcp/video-orchestrate` with `{ internal_secret, lead_id, client_id, intent, override_script?, delivery_channel? }`. Intent allow-list covers 9 templates (general, welcome, birthday, anniversary, review_request, financial_tip, referral_request, quote_followup, booking_followup).
  - **Modified `workflows/api/mcp/clx-mcp-agent-tools-v1.json`** — `Tool: Video` URL retargeted from `/webhook/video/script-generate` to `/webhook/mcp/video-orchestrate`. One-line change.
  - **Modified `workflows/api/admin/clx-admin-chat-v3.json`** — added `generate_video` to Copilot's tool array with full input schema; added to WRITE_TOOLS so confirmation is required; added to system-prompt write-tools list. Mary can now chat "Send a birthday video to Jane Smith" and Copilot will describe + ask "Confirm? Reply yes to proceed."
  - **New `db/migrations/add-date-of-birth-to-leads.sql`** — adds `date_of_birth` (date) + `birthday_video_sent_year` (integer) columns to leads, plus a functional index on `(month, day)` of DOB filtered to NOT NULL. Idempotent.
  - **New `workflows/api/sentinel/clx-cron-birthday-videos-v1.json`** — daily cron at 12:00 UTC (~08:00 America/Toronto). Queries leads with DOB not null + sent_year stale, filters in JS to today's month+day, fires `generate_video` with `intent='birthday'` for each, PATCHes sent_year so no double-send.
  - Hotfix `72a8976` removed a stray `"..."+"..."` JavaScript string-concat in the orchestrator's JSON (broke `jq` parse; ship.sh blocked at step 2).
- **Full automation deploy path used end-to-end** — all 5 workflows shipped via `scripts/n8n/ship.sh` (REST API PUT for existing, CLI import for new, REST activate, docker restart, webhook probe). No manual UI work needed for the workflow side this session.

### What got unblocked / decided

- **Founder rule saved as memory**: never default to manual workflows (Gmail BCC, personal DMs, hand-emailing) for business / customer-acquisition tasks. The platform exists specifically so Mary does not have to personally beg her network. Default is always: import → leads table → engine outreach → tracked campaigns. Manual is fallback only when automation is genuinely broken AND the customer is already in the pipeline.
- **Super Visa picked as the focus campaign vertical** (vs generic travel insurance). Reasoning: emotional + financial trigger ("hospital cost for visiting parents"), urgent ("trip in 2 weeks"), Mary's LLQP licence covers it, single-advisor + no carrier negotiation, immigrant communities = trust matters + Mary's natural network.
- **MCP/DevOps internal labels stay as-is.** Mary's call: "do not rename, I just want to maintain what is there and have the feature I need." The Copilot widget already shows as "Crystallux Copilot" to Mary (not "MCP"), and module='devops' labels in the Sentinel alerts table are operator-only, not customer-visible.
- **Postmark enhancements deferred** except CASL unsubscribe footer (legal requirement) and warm-up. Postmark dashboard already handles bounce management + open/click tracking natively; rebuilding those into the leads table is Phase 4 work. Warning surfaced: Postmark is transactional-only — cold outbound prospecting must use a different sender (Smartlead/Instantly/Mailgun) or accounts get suspended. Flagged for revisit when Mary hits volume.
- **`scale-sprint-v1` → `main` ff-merge cadence working well** — six pushes this session (`git push origin scale-sprint-v1:main`), each ~60s deploy via CF Pages. No PR overhead, no review bottleneck. Aligned with the standing decision in the bottom section.

### What got blocked or deferred

- **Postmark Production approval pending** — server provisioned with Crystallux/info@crystallux.org sender (DKIM verified, Return-Path not verified). Approval is a 1-24 hour manual review by Postmark. All notification emails (form submissions, application acknowledgements, video delivery email channel) are wired but dormant until approval lands. Once approved, Mary needs to copy the server API token into `POSTMARK_API_TOKEN` env var on the VPS (both `/root/crystallux/n8n/.env` AND `docker-compose.prod.yml`'s environment block per [[crystallux-n8n-env-var-propagation]]; force-recreate to pick up).
- **Meta WhatsApp Business via Twilio pending** — `clx-whatsapp-send-v1.json` is built + activated but its notes mark it "DORMANT until Meta WhatsApp Business approval clears for the client's Twilio WA sender." Meta approval is typically 1-4 weeks, no way to speed up. Once cleared: Twilio sender provisioned → workflow already routes correctly.
- **HeyGen API key + credit not verified this session.** generate_video pipeline is wired but actual render-to-MP4 depends on `HEYGEN_API_KEY` + sufficient credit. Need to confirm via a test fire (Copilot chat → "Send welcome video to lead X" → check `video_renders` table for `status='rendering'` + check HeyGen dashboard for the render job).
- **Return-Path Not Verified in Postmark** — deliverability concern, not a send-blocker. Add the CNAME Postmark shows in Sender Signatures → DNS Settings to Cloudflare DNS. ~5 min + propagation. Improves Gmail/Outlook deliverability significantly. Not tonight.
- **Bulk-import dedupe across batches** — workflow dedupes within a single batch by email but does not deduplicate against leads already in the table. If Mary re-imports the same CSV, she gets duplicate rows. Acceptable for the first import; add `ON CONFLICT (email) DO UPDATE` + `UNIQUE(email)` constraint when this becomes a real problem.
- **Birthday video script template** — script-generator currently uses generic `intent` flavoring; it does NOT yet have explicit "birthday" template logic. The cron will fire and Claude will write *something* on `intent='birthday'`, but it may not always lead with "Happy birthday". Add explicit intent-template handling in script-generator's Build Claude Prompt node when there's a real birthday lead to test on.

### What Mary needs to do next

1. **Watch the Postmark inbox** for approval (subject usually contains "Crystallux Production"). On approval: Settings → API Tokens → copy Server API Token → update VPS env per [[crystallux-n8n-env-var-propagation]] → force-recreate n8n.
2. **Verify HeyGen account state** — log in to HeyGen, confirm API key matches `HEYGEN_API_KEY` env var on VPS, confirm there is credit available. Even with Postmark + WhatsApp blocked, the render itself can be tested + the rendered MP4 can be downloaded from the HeyGen dashboard.
3. **Drive Super Visa traffic** — paid ads OR FB groups OR LinkedIn organic OR existing-client CSV import. Form is live + capturing into leads table. Leads land regardless of downstream channel approvals.
4. **Bulk-import existing-client CSV** when ready — go to `/admin/pages/import-leads.html`, drag CSV in, set source / campaign tag (e.g. `travel_insurance_2026q2`), import. The leads are then targetable by any campaign workflow filtering on `source='existing_client_import'`.
5. **First test of Copilot generate_video** — open Copilot widget on any admin page, type "Send a welcome video to lead `<id>` for client `6edc687d-07b0-4478-bb4b-820dc4eebf5d`". Reply `yes` to the confirmation prompt. Check `video_renders` table for a new row + check HeyGen dashboard for the render job.

### Open questions for next session

- **Dedicated MGA principal workflows missing** — `dashboard-home.html` originally called `mga/insurance/principal/compliance-queue` + `mga/insurance/principal/applications` which were never built (HTTP 404). Tonight tactical fix re-routed those 2 cards to existing workflows (advisors-and-compliance for compliance alerts; advisor/applications for recent apps). Proper build: dedicated cross-advisor workflows that aggregate compliance reviews + applications across the whole MGA. ~60 min.
- **LUXI outright-sale mode** — extend the auction-only platform to support fixed-price live commerce. Catalog table + "buy now" comment trigger + FCFS inventory locking + optional "skip auction at price X" hybrid. Reuses existing Stripe integration + multi-platform broadcast + comment parser. ~2 sessions. Unlocks the larger TikTok-Shop / Whatnot-fixed-price market. Real-world precedent: Whatnot, TikTok Shop Live, Instagram Live Shopping all blend auction + fixed-price; auction-only is the rarer pattern. Today LUXI is auction-only — zero outright-sale references in product page or workflows.
- **Standalone DevOps Employee product page** — Mary asked at session-end whether the internal DevOps Digital Employee (daily-briefing cron + Sentinel + drift detector + workflow restart automation) can be packaged as a standalone product page. Monetization strategy already names this as Phase 7 ("Sentinel Operations standalone-izes the internal DevOps capability"). Distinct from CIRO (CIRO = sales ops). Next session: build `/products/sentinel.html` or `/products/devops-employee.html` modeled on existing product-page pattern. 45-60 min.
- After the first real Super Visa lead arrives, does the existing `/mga/insurance/lead-capture` workflow auto-trigger anything (orchestrator? video? Postmark?), or is it pure capture-and-store? Need to verify whether the engine fires outreach automatically on insert or whether Mary still has to manually click "Run campaign on this segment" somewhere.
- Should the bulk-import workflow get cross-batch email dedupe via a `UNIQUE(email)` constraint + `ON CONFLICT` handling? Depends on whether Mary expects to re-import the same CSV (e.g. monthly client list refreshes).
- Is the WhatsApp-greeting branch on the lead-capture workflow worth building NOW (so it auto-fires the moment Meta approves) or wait until approval lands (so the test is real, not theoretical)? Trade-off: build-now = readiness, build-later = no wasted work if pipeline shape changes.

---

## 2026-05-25 — Launch-readiness wrap-up: audit, sync, no duplication

Pre-launch sweep across the repo. Two Explore agents read the handbook + audit + dedupe + blockers corpus to surface what's shipped, what's left, what's duplicated, and what conflicts between docs. Then five focused commits to fix everything in-session that didn't need VPS access. The picture is now clean for Mary to run the VPS launch runbook against accurate docs.

### What shipped (5 commits — `95b159a` → `b3ecc68`)

- **Avatars registry move finished** (`95b159a`) — half-done refactor in the working tree had moved `pages/avatars.html` → `pages/system/avatars.html` but left 9 references pointing at the deleted path (nav.html, components.js, `_redirects`, 5 subpage breadcrumbs, dev-console). All 9 updated; `_redirects` got a 301 from the old path so external bookmarks don't 404.
- **`.gitignore` hardening** (`f1300af`) — `__pycache__/` + `*.pyc` added (drift detector was leaving cache files in working tree).
- **Handbook refresh to 2026-05-25** (`a9ec9e5`) — was stamped 2026-05-11; missed every capability shipped since. §5.1 phase table gained 11 new rows (self-healing layer, Postmark webhook, market intelligence, DevOps + COO digital employees, polish v2, workflow drift detector, MCP chat v3, avatars Tranche 1, Smart Quote, brand-voice scrub, product pages). §5.3 (Next 30 days) rewritten as a launch-blocking ordered list (§0s → §0v → §0t → §0i → dedupe → TESTING MODE removal → Stripe Live → legal docs).
- **Cross-doc conflict reconciliation** (`19b09ec`) — insurer-portal subdomain naming canonicalized to `portal.crystallux.org` (app, auth-gated) vs `insurers.crystallux.org` (marketing, public) across WORKSTREAM_STATUS + PAGE_STATUS_REPORT; Stripe Products status in PLATFORM_BACKLOG item #8 fixed (header said "DONE" but checkboxes unchecked — pages are done, Stripe wiring is explicitly DEFERRED until Live mode lands); `Last refreshed` bumped 2026-05-21 → 2026-05-25.
- **Dedupe doc cross-references** (`b3ecc68`) — two overlapping dedupe docs (`DUPLICATE_CLEANUP_PLAN.md` 2026-05-16 + `WORKFLOW_DEDUPE_PLAN.md` 2026-05-19) had no relationship spelled out, so a reader couldn't tell which to execute. Added headers on each naming role + pointing at companion + flagging which parts of each are still load-bearing. No content removed.

### What got blocked or deferred

- Mary's VPS launch runbook (`§0s` webhook re-registration → `§0v` Postmark deploy → `§0t` WS1 reactivation → `§0i` Cloudflare cache purge → workflow dedupe → TESTING MODE removal per channel) is now the single ordered path to actual launch. Each step is documented; execution requires VPS access. See refreshed handbook §5.3.
- Stripe Live mode (2-5 business days for verification) and legal docs (1-2 week lawyer SLA) are the two external dependencies that gate first revenue. Neither is unblockable from inside the repo.

### What Mary needs to do next

1. Run the VPS launch runbook in order (handbook §5.3). Each step's full instructions live in `docs/audit/blockers.md` at the cited §number.
2. Send legal docs to lawyer (today if not done — 1-2 week SLA).
3. LinkedIn Developer signup (~30 min, free) — unlocks CIRO Phase 4 auto-DM.
4. Once Stripe Live verification lands: create Products + Prices per `docs/STRIPE_PRODUCTS_SPEC.md` (3 tiers) and copy Price IDs into n8n env.

### Open questions for next session

- After §0s/0v/0t run on the VPS, was the WEBHOOK_INVENTORY EMPTY-200 count fixed? Should drop from 12 (or 17, depending on snapshot) → 0 after the workflow re-import.
- Carrier portal vanity domain — does Mary want `carriers.crystallux.org` added alongside `portal.crystallux.org`, or stay single-domain? (5-min CF custom-domain add either way.)

---

## 2026-05-23 (pt 4) — Polish v2: SaaS-feel primitives within the existing stack

Mary forwarded a generic template prompt asking for a Next.js + React + Tailwind + shadcn + Framer Motion rewrite. Doctrine conflict (CLAUDE.md: "the repo is intentionally plain HTML + plain JS"). Offered three scoped options; Mary picked Polish v2 — additive within the current stack.

### What shipped (three commits — `19bed4b` + `4c55b64` + this)
- **Primitives in `components.js`** (admin + client mirrored): `toast`, `dialog`, `confirm`, `dropdown`, `tabs`. Pure vanilla, no framework. ~400 LoC + matching CSS in both `layout.css`.
- **Cmd+K command palette** — auto-wired globally, parses `CLX_FALLBACK_NAV` for entries, fuzzy substring match, arrow-key nav. Pages extend via `window.CLX_PALETTE_ACTIONS`; disable with `window.CLX_AUTO_PALETTE = false`.
- **CSS polish** — page-load fade + 40ms-stagger stat-card reveal (pure `@keyframes` + nth-child), brand-purple `:focus-visible` ring on every interactive element, soft brand box-shadow on focused inputs. `prefers-reduced-motion` honored.
- **Demo wirings** — `sentinel.html` swapped both `window.confirm` sites for `clxComp.confirm` + added toast feedback on save/error.
- **`docs/handbook/DESIGN_SYSTEM.md`** — single-source-of-truth doc covering tokens, every helper, the polish v2 primitives, common patterns, the rules.

### What got blocked or deferred
- Zero pages migrated wholesale — additive only. Other pages can opt into `clxComp.confirm` / `clxComp.toast` / `clxComp.tabs` incrementally as they get touched.

### What Mary needs to do next
- Pull on the VPS clone — no migrations, no env vars, no Postmark config required for this set (pure frontend, Cloudflare Pages auto-deploy on next push).
- Hit Cmd+K on any admin page after the next CF deploy to feel the palette.

---

## 2026-05-23 (pt 3) — ship.sh --branch flag (kill the manual checkout)

Tiny ergonomics commit. ship.sh hardcoded `git pull origin main`, so the existing pattern required merging `scale-sprint-v1` → `main` (or manually checking out the feature branch in `/tmp/clx-latest`) before shipping anything. Added `--branch <name>` (and `CLX_BRANCH` env equivalent) so the standard flow becomes:

```bash
bash scripts/n8n/ship.sh --branch scale-sprint-v1 clx-foo-v1.json
```

ship.sh now does `git fetch + git checkout + git pull` of the requested branch. Default stays `main` so every existing caller still works. ship-today.sh passes `--branch` straight through to every ship.sh invocation; argument-array expansion guarded with `${arr[@]+...}` so it stays compatible with older bash on the VPS.

Updated blockers §0v to use `--branch scale-sprint-v1` in the Postmark deploy steps — Mary no longer needs to merge before shipping.

---

## 2026-05-23 (pt 2) — Postmark webhook ingestion: spam + bounces go live

Closed the placeholder on the Comms tab — spam tracking has been "best-effort scan of email_log.status" since the Comms tab shipped. Now it's a live Postmark webhook stream.

### What shipped
- `db/migrations/email-events-schema.sql` — `email_events` table with type/subtype/recipient/subject/tag/stream/raw_payload + 6 indexes (incl. partial indexes on spam_complaint + bounce for the hot path).
- `workflows/api/webhooks/clx-webhook-postmark-events-v1.json` — receiver workflow. Validates `X-Postmark-Webhook-Token` against `$env.POSTMARK_WEBHOOK_TOKEN`, normalizes Postmark RecordType → our event_type enum (Delivery/Bounce/SpamComplaint/Open/Click/SubscriptionChange/other), inserts into `email_events`, always acks 200 so Postmark doesn't retry on transient Supabase blips.
- `clx-admin-sentinel-comms-health-v1.json` — two new fetches (`Spam Events 30d` + `Bounce Events 30d`) wired through the fan-out. Shape Response now prefers email_events when present and falls back to the old email_log scan so the panel keeps rendering before the webhook is configured. New `bounces` block in the payload (total + by_subtype + recent).
- `admin-dashboard/pages/sentinel.html` — new Bounces card with subtype breakdown; Spam card sub-note now flips between `live` (pill-up) and `not live` (pill-info) pills depending on data source.

### What got blocked or deferred
- Live data depends on Mary doing the Postmark UI config + setting the env var + restarting n8n. Until then the cards keep working off the email_log scan (no regression).

### What Mary needs to do next
- Apply migration, set env var, import + activate workflow, configure Postmark webhook URL + custom header, re-import comms-health workflow. Step-by-step in `docs/audit/blockers.md` §0v.

---

## 2026-05-23 — Vendor-health wired into the Sentinel Communications tab

Short follow-up session on top of yesterday's self-healing layer (4 commits ending `69e6119`). The vendor-health monitor was writing snapshots every 15 min but the data was only surfaced via the alert it raised at the 30%/10-call threshold. Wired the latest snapshot into the existing Comms tab so the live vendor circuit shows alongside the trailing 30-day delivery rate.

### What shipped
- `clx-admin-sentinel-comms-health-v1.json` — added `Vendor Health Latest` fetch (most recent `sentinel_vendor_health` row per vendor over the last 30 min) + extended Shape Response to emit `data.vendor_health.by_channel` (severity-ranked dedupe when multiple vendors hit the same channel).
- `admin-dashboard/pages/sentinel.html` — `renderCommsChannels` gained Vendor + Circuit (60 min) columns; circuit pill uses existing `pill-up` / `pill-degraded` / `pill-critical` classes; last error becomes a `title=` tooltip on the cell. Card sub-note now cites the snapshot age via `fmtAgo()`. Page still renders cleanly when the monitor hasn't produced a snapshot yet (cells fall back to `—`).
- No schema migration — `sentinel_vendor_health` already exists from `vendor-health-schema.sql`.

### What got blocked or deferred
- The vendor-health monitor (`clx-sentinel-vendor-health-monitor-v1`) is still `active: false` until Mary activates. Until then the new columns will read `—`.

### What Mary needs to do next
- Re-import `clx-admin-sentinel-comms-health-v1.json` via the n8n UI (Import-Replace — CLI `import:workflow` won't update an existing row per `[[n8n-workflow-update-gotcha]]`).
- Purge Cloudflare cache for `admin.crystallux.org/pages/sentinel.html` after the Pages deploy.
- Activate the vendor-health monitor when ready (or leave it dormant — Comms tab degrades gracefully).
- See `docs/audit/blockers.md` §0u.

---

## 2026-05-22 — Build wrap-up: digital employees + MCP chat with tools + market intelligence + product pages + dashboard polish

The longest single session of the build. Pivoted from "more new builds" to "wrap up everything in flight" so we can shift to page-by-page audit next.

### What shipped
- **Sales Engine page wake-up** (`1688ec6`) — `wfAdminSalesEngineActivityV1` + Today's-activity grid + Recent-activity feed (color-coded events from leads / bookings / outreach / email). Replaced the 3 dead placeholder cards with one honest "Voice operations" status panel. Fix for "unknown 200" pipeline display (`51f2af8`) — page was reading `status` instead of `lead_status` plus a migration that backfilled NULL/empty/"New" → "New Lead" across the leads table.
- **Sentinel Communications tab** (`406b939`) — 7th tab with delivery rate by channel (color-coded bars, green ≥95% / amber ≥85% / red below), recent failures, opt-out posture with unsubscribe-rate red-flag, spam complaints (with Postmark-webhook-needed note), 14-day per-channel volume sparklines. `wfAdminSentinelCommsHealthV1` aggregates email_log + messages_sent + outreach_log + leads opt-out flags.
- **MCP AI chat widget — three iterations** (`dd6b876` → `7ad0a7e` → `7c13fb0` → `3476ddc`) — floating bottom-right chat panel on every admin page. v1 = Q&A only, v2 = persistence in `admin_chat_sessions` + `admin_chat_messages`, v3 = full tool execution via the MCP Tool Gateway with 10 tools (check_system_health, list_leads, scan_city, etc.). v3 also added the **write-action confirmation gate**: tools are classified READ vs WRITE; write tools (research_lead, score_lead, update_lead_status, scan_city) require Claude to describe the action and ask "Confirm? Reply yes to proceed" before invoking, with a server-side guard that refuses execution unless the most recent user message contains an affirmative token.
- **Market Intelligence (Part B.9)** (`1c70467` → `6698237` → `074fe69`) — schema migration with 4 tables (raw + processed + routing log + per-client preferences) + `v_active_market_signals` view + admin endpoint `admin/market-intelligence/summary` aggregating signals by type / vertical / region / source + 7d ingestion + routing stats. Heat-map dashboard at `/pages/market-intelligence.html`. Critically, the existing `clx-campaign-router-v2` + `clx-outreach-generation-v2` workflows already had signal-aware nodes wired in production — they were just waiting on the schema. So Layers 3 + 4 of the B.9 spec activate the moment the schema lands.
- **Email + SMS voice audit** (`d59ef62` + `ccd3644`) — `docs/handbook/BRAND_VOICE.md` documents the hard rules (no em-dashes, no generic openers, no stilted sign-offs). `scripts/audit/lint-message-templates.py` scans every workflow JSON + HTML page for violations with severity + auto-fix for em-dashes. **127 em-dashes scrubbed** from 26 customer-facing files: every outbound channel (email, SMS, WhatsApp, LinkedIn, voice, video), every public site page, every insurer-marketing page, every booking confirmation, every Smart Quote email.
- **All 7 standalone product pages live** (`4e7bba7` → `1e1ac53` → `47de20a`) — site/products/{index, smart-quote, luxi, ava, maxi, ciro, mga, sales-engine}.html with shared product-page.css. Each: dark gradient hero, 6-card feature grid, vertical-specific "who buys this", numbered how-it-works, "Talk to me" pricing card, closing CTA. Insurer-marketing pages also got AI-native-era + solo-founder positioning stripped earlier (`7d946b6`, `8d36040`).
- **Dashboard polish two rounds** (`a3b12dc` + `1d5cbb1`) — slate neutral ramp (replaces zinc), emerald accent ramp, shadow + motion tokens, global transition baseline. Chart.js wired in via `/shared/charts.js` with line / bar / donut / sparkline helpers. Overview page uses real Chart.js now. Sidebar active state has gradient + 3px brand edge. Stat cards have variant-aware top-edge gradients (leads/activity/bookings/errors/revenue each get their own). Tables polished, buttons with linear-gradient + shadow, skeleton shimmer. Browser-style back/forward arrows auto-inject in the topbar via `clxComp.injectNavArrows()`.
- **DevOps Digital Employee** (`30462e6`) — `wfDevopsDailyBriefingV1` cron at 11:00 UTC. Aggregates Sentinel alerts (24h) + cost tracking (7d vs budgets) + paused workflows + lead/booking activity, Claude writes a one-paragraph senior-on-call-engineer briefing, Postmark emails Mary + persists to `sentinel_alerts` (module='devops').
- **COO Digital Employee** (`66cfe5b`) — `wfCooWeeklyReviewV1` cron at 23:00 UTC Sunday so Monday morning lands the review. Aggregates pipeline (this week vs prior 3w avg, trend %, status/source/industry mixes), conversion (bookings, quotes sent + accepted + acceptance %), revenue (MRR + closed this week), comms (volume per channel + failure rate %), overdue work (>14d silent + high-score subset). Claude writes a 6-section summary (verdict / pipeline / conversion / bottleneck / overdue / one growth recommendation) with a sectioned HTML email + stats footer + sentinel_alerts row module='coo'.
- **Workflow drift detector** (`19e0bfb` → `4cda91c` → `653da5d` → `fc4546b`) — `scripts/drift/detect-workflow-drift.py` runs on VPS via cron, hashes every repo workflow + every n8n workflow (REST API with docker exec CLI fallback when API key lacks listing permission), classifies divergence as `repo_only` / `n8n_only` / `content_diff` / `active_diff`. CLAUDE.md "Dormant by default" rule encoded: only flags active_diff when repo expects active=true but n8n has it off. Migration `workflow-drift-schema.sql` defines `workflow_drift` + `workflow_drift_runs` tables. Daily cron added on Mary's VPS at 08:00. Current state: 0 repo_only, 1 n8n_only (old chat-v2 to deactivate), 0 active_diff, 60 content_diff (mix of historic UI edits + n8n adding default fields the hash can't strip yet — known limitation, operationally fine).
- **ship.sh evolution** (`9742679` → `3ee001e` → `f0585bc` → `f417d55` → `ce97502`) — one command that handles import OR update via REST API PUT. SQL fallback when API key fails. `ship-em-dash-fixes.sh` + `ship-today.sh` bulk wrappers for batch deploys.
- **Cleanup** — superseded `clx-admin-chat-v1.json` and `clx-admin-chat-v2.json` removed from repo (`1e1ac53`); only v3 is canonical now.

### What got unblocked / decided
- Mary picked the launch-priority order: DevOps employee → COO employee → drift detector, then audit. Build wrap then page-by-page review.
- ship.sh upgraded to REST API PUT semantics means future commits update workflows in place — no more deactivate-then-reship dance.
- Drift detector accepted at "operationally useful but content_diff is noisy" level. Refining the hash is a 1-2h rabbit hole with diminishing returns; the action Mary would take with 5 findings is the same as with 60 (audit or bulk-reship).
- The drift detector lives on the VPS cron, NOT in n8n, because:
  1. The repo isn't mounted into the n8n container
  2. The pattern keeps drift detection independent of n8n's own health

### What got blocked or deferred
- Live spam tracking via Postmark webhook — needs the webhook + an `email_events` table. Follow-up.
- Multi-channel monitoring (LinkedIn / Meta / TikTok / YouTube mentions + engagement) — gated on the free API signups.
- Content QA pre-send hook — needs to hook into every sender workflow; 1-2 sessions.
- Workflow drift admin page + DevOps briefing integration — low-priority polish.

### What Mary needs to do next

```bash
ssh vps
cd /tmp/clx-latest && git pull origin main
```

Migrations to verify applied (run each in Supabase SQL Editor; idempotent):
- `db/migrations/lead-status-backfill.sql` — fixes "unknown 200" Sales Engine display
- `db/migrations/market-intelligence-schema.sql` — Part B.9 schema
- `db/migrations/chat-history-schema.sql` — chat persistence
- `db/migrations/workflow-drift-schema.sql` — drift tracking

Workflow ships to apply:
- `bash scripts/n8n/ship-today.sh` — bulk-ship the 7 new/modified workflows from today
- Deactivate orphan `CLX - Admin Chat v2` in n8n UI (clears the 1 n8n_only drift finding)

API signups to pursue in parallel (priority order):
1. LinkedIn Developer (free, ~30 min) — unlocks CIRO auto-DM
2. Meta Business / Facebook + Instagram Graph (free, ~2h with verification) — unlocks LUXI auto-comment + AVA cross-posting
3. TikTok Developer (free, 1-2d approval) — same for TikTok
4. YouTube Data API (free, ~30 min) — content publishing + comment monitoring
5. HeyGen (~$99-330/mo) — AVA video render
6. ElevenLabs (~$22/mo) — premium voice
7. NewsAPI + OpenWeatherMap (both free) — activate market intelligence ingestion

### Open questions for next session
- Start the page-by-page audit (you proposed; suggested order: overview → sales-engine → sentinel → market-intelligence → smart-quote → luxi → ava → carriers → ciro → public products → marketing) — or ship one more build item first (Postmark webhook, Content QA pre-send)?
- Pricing decision for the product pages — current placeholders say "Talk to me"; you have the ballpark tier structure proposal from earlier today (Smart Quote $97-397, MGA $1,997-6,997, etc.).
- Anything in the chat widget you want adjusted before launch (placement, default greeting, tool list)?

---

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
| **Postmark Production approval** | **Launch** | **Postmark (waiting)** | **Provisioned 2026-05-26; 1-24h review. Gates ALL transactional email — form notifications, application acks, video delivery email channel. Once approved: copy Server API Token to VPS `POSTMARK_API_TOKEN` per [[crystallux-n8n-env-var-propagation]].** |
| **Meta WhatsApp Business via Twilio** | **Launch** | **Meta (waiting)** | **`clx-whatsapp-send-v1` is built + activated but dormant. 1-4 week Meta review. Gates WhatsApp greeting auto-send on new lead + WhatsApp delivery channel for personalized videos.** |
| HeyGen API key | Build | Mary signup | Unlocks AVA video render pipeline + outreach personalization. Pipeline now end-to-end wired via `clx-mcp-video-orchestrator-v1` — needs API key + credit verified in n8n env. |
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
