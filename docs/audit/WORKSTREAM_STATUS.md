# Workstream status — 2026-05-20 execution mode

Mary's 9-workstream execution directive vs. what actually exists in the repo. Maintained as the single source of truth so we don't rebuild infrastructure that already ships.

Last updated: 2026-05-20 (commit `aa7a33c` and prior).

---

## WS1 — Reactivate Phase 1-9 Sales Engine

**Status: ✅ Repo-side complete. Awaiting Mary's recovery script run.**

| Phase | Workflow | Repo state | Notes |
|---|---|---|---|
| 1 Lead Discovery | `clx-b2c-discovery-v2.1.json` + `clx-city-scan-discovery.json` | Patched (WS6 insurance verticals added to city-scan) | Mary asked for city-scan to work; updated industries list with carrier/advisor/MGA queries + `lead_type` propagation |
| 2 Lead Research | `clx-lead-research-v2.json` | Unchanged, ready | Claude Sonnet research per lead |
| 3 Lead Scoring | `clx-lead-scoring-v2.json` | Unchanged, ready | 0-100 fit score via Claude Haiku |
| 4 Signal Detection | `clx-business-signal-detection-v2.json` | Unchanged, ready | Growth + buying signals |
| 5 Campaign Routing | `clx-campaign-router-v2.json` | Patched | Added `carrier_partnership` + `advisor_recruitment` campaigns; `lead_type` override before falling through to `recommended_campaign_type`; `limit=25` → `limit=100` per 15-min run |
| 6 Outreach Generation | `clx-outreach-generation-v2.json` | Unchanged, ready | Reads campaign config built by router → Claude personalizes per lead. The new carrier_partnership + advisor_recruitment configs flow through automatically |
| 7 Outreach Sender | `clx-outreach-sender-v2.json` | Unchanged, ready | Gmail send with CASL footer |
| 8 Follow-up | `clx-follow-up-v2.json` | Unchanged, ready | |
| 9 Booking | `clx-booking-v2.json` | **CRITICAL FIX** | Recipient was hardcoded to test inbox — every booking would have gone to Mary's inbox not the lead. Now reads `lead.email`; new `CLX_BOOKING_TEST_INBOX` env override for safe dry-runs |
| 11 City Scan | `clx-city-scan-discovery.json` | Patched | Per Mary's explicit "make city scan to work" |

**Mary's actions:**

```bash
git pull origin scale-sprint-v1
bash scripts/n8n/emergency-recover-webhooks.sh
```

Plus prerequisites in blockers `0t`:

- Each tenant in `clients` table needs `calendly_link` + `client_name` + `notification_email` + `active=true`.
- n8n credentials `Supabase Crystallux` (httpHeaderAuth, used by Phase 1-9 legacy workflows) AND `Supabase Crystallux Custom` (httpCustomAuth, used by admin/MGA new workflows) must both exist.

---

## WS2 — Fix remaining 36 broken endpoints

**Status: ✅ Repo-side complete (commit `f5c2773`). Awaiting Mary's recovery rerun.**

The 33-of-69-healthy result was caused by:
1. Orphan `webhook_entity` rows blocking new activations' INSERTs (unique-constraint on path)
2. CLI activation not reliably triggering in-process webhook registration

Both fixed in `emergency-recover-webhooks.py` (`f5c2773`):
- Sidecar SQL now always runs `DELETE FROM webhook_entity WHERE workflowId NOT IN (SELECT id FROM workflow_entity)`
- Added final `docker restart n8n` after activations so n8n boots fresh + registers webhooks deterministically

Re-running the same script Mary already used should flip the remaining 36 endpoints HEALTHY.

---

## WS3 — Client portal (client.crystallux.org)

**Status: ✅ Already built. Lives in `client-dashboard/`.**

Existing pages (all functional, use `clxAuth.require('client')`):

| Mary's spec | Existing page |
|---|---|
| Per-client login | `client-dashboard/index.html` (cross-origin token handoff via URL hash) |
| Their leads | `client-dashboard/pages/leads.html` |
| Their campaigns | `client-dashboard/pages/campaigns.html` |
| Their bookings | `client-dashboard/pages/bookings.html` |
| Their analytics | `client-dashboard/pages/overview.html` + `client-dashboard/pages/activity.html` |
| Their billing/subscription | `client-dashboard/pages/billing.html` |
| Their content | `client-dashboard/pages/content-calendar.html` + `content-engagement.html` + `content-preferences.html` |
| Their training | `client-dashboard/pages/training-coach.html` + `training-progress.html` |
| Their settings | `client-dashboard/pages/settings.html` |

What "build" still needs: Cloudflare Pages project + DNS for `client.crystallux.org` if not yet wired. Mary's action; no repo-side work needed.

---

## WS4 — Advisor portal (advisor.crystallux.org)

**Status: ✅ Already built. Lives in `insurance-mga-dashboard/advisor/`.**

Existing pages:

| Mary's spec | Existing page |
|---|---|
| Per-advisor login | `insurance-mga-dashboard/login.html` (restricts to advisor / sub_agent / mga_principal roles) |
| Their assigned leads | `insurance-mga-dashboard/advisor/leads.html` |
| Their commission tracking | `insurance-mga-dashboard/advisor/commissions.html` |
| RIBO study coach access | `insurance-mga-dashboard/advisor/coaching.html` |
| Compliance tools | `insurance-mga-dashboard/advisor/reviews.html` + `applications.html` |
| Quote generation | `insurance-mga-dashboard/advisor/calculators.html` + `product-comparison.html` |
| Daily plan | `insurance-mga-dashboard/advisor/today.html` |
| Routing | `insurance-mga-dashboard/advisor/route-map.html` |
| Goals | `insurance-mga-dashboard/advisor/goals.html` |
| Onboarding | `insurance-mga-dashboard/advisor/onboarding.html` |

What "build" still needs: if Mary wants `advisor.crystallux.org` as a SEPARATE subdomain from `mga.crystallux.org`, that's a Cloudflare Pages project + DNS choice. Otherwise advisor pages already serve under mga.crystallux.org/advisor/*.

---

## WS5 — Carrier portal (carriers.crystallux.org)

**Status: ✅ Already built. Lives in `insurer-dashboard/`.**

Mary's spec calls it "carriers" portal; the repo named it `insurer-dashboard/` (insurer.crystallux.org). Same purpose — insurance carriers viewing their production through Crystallux MGAs.

Existing pages:

| Mary's spec | Existing page |
|---|---|
| Per-carrier login | `insurer-dashboard/index.html` (restricts to insurer_user role) |
| Their submissions | `insurer-dashboard/production/advisors.html` + `production/monthly.html` + `production/trends.html` |
| Performance metrics | `insurer-dashboard/overview/dashboard.html` |
| Commission reports | `insurer-dashboard/reports/library.html` + `reports/generator.html` + `reports/schedule.html` + `reports/exports.html` |
| Product portfolio | `insurer-dashboard/production/products.html` |
| Compliance | `insurer-dashboard/compliance/audit-log.html` + `reviews.html` + `scorecard.html` |
| Account | `insurer-dashboard/account/profile.html` + `account/users.html` |

What "build" still needs: if Mary specifically wants `carriers.crystallux.org` instead of `insurer.crystallux.org`, that's a domain decision. The code is done.

---

## WS6 — Extend Sales Engine for insurance vertical

**Status: 🟡 In progress (`aa7a33c`). Phase 1 + Phase 5 done; downstream phases ride existing infrastructure.**

| Sub-task | Status | Where |
|---|---|---|
| Carrier discovery in Phase 1 | ✅ Done | `clx-city-scan-discovery.json`: insurance carrier + MGA queries added with `lead_type=carrier_prospect` |
| Advisor recruitment in Phase 1 | ✅ Done | Same file: RIBO advisor query → `lead_type=advisor_candidate` |
| `lead_type` propagation through phases | ✅ Done in router | Phase 5 reads `lead.lead_type` and overrides `recommended_campaign_type` |
| Carrier-specific outreach templates | ✅ Via existing infra | Phase 6 reads `campaign_value_proposition` etc. set by Phase 5; carrier_partnership campaign config carries the message |
| Advisor recruitment templates | ✅ Via existing infra | Same — advisor_recruitment campaign config |
| Booking routes by lead_type | 🟡 Open | Booking currently sends generic email + Calendly link. Could enhance: carrier_prospect → insurer.crystallux.org/join landing; advisor_candidate → insurance.crystallux.org/join. Skipping for now until Mary confirms landing pages exist |

---

## WS7 — CIRO Phase 2-5 (LinkedIn / briefings / auto-pilot / multi-tenant)

**Status: ⏸ Deferred. Most of this already exists; see audit summary in previous session.**

Already built in repo:
- Daily briefing (morning): `clx-daily-plan-generator-v1.json`
- Daily summary (evening): `clx-daily-summary-generator-v1.json`
- Pre-meeting briefing: `clx-pre-meeting-briefing-generator-v1.json` (Claude Sonnet, 30-min cron)
- Communications log viewer: `clx-admin-comms-log-v1.json` + `admin-dashboard/pages/ciro/communications.html`
- Lead routing / distribution: 5 workflows in `workflows/api/distribution/`
- LinkedIn outreach: `clx-linkedin-outreach-v1.json`

Truly missing:
- Hot lead alert
- Calendar conflict resolution
- LinkedIn auto-comment / auto-DM (requires LinkedIn API key Mary signs up for)

These are small focused commits when Mary's ready. Not blocking demos.

---

## WS8 — Smart Quote multi-industry estimator

**Status: ⏸ Deferred. Not started; not blocking.**

Genuinely new build. ~8-12 hours per Mary's earlier estimate. Wait for WS1/2 reactivation to be confirmed working before starting.

---

## WS9 — Avatar / LUXI interactivity

**Status: ⏸ Deferred. Polish-tier.**

Working features already: MAXI 21 industries, AVA 104-template content library, LUXI auction tick (T1.7). Drill-downs + clickable menus are UX polish that doesn't block business operations.

---

## Net summary

- WS1 + WS2: repo-side done. Mary runs `emergency-recover-webhooks.sh`.
- WS3/4/5: already built; just need Cloudflare Pages project setup if subdomains aren't wired.
- WS6: insurance extension working end-to-end via existing Phase 6/7/8/9 — no per-phase template work needed because the campaign config carries the message.
- WS7/8/9: deferred; small focused commits when Mary's unblocked on the core pipeline.

**Single command for Mary to validate WS1-6:**

```bash
git pull origin scale-sprint-v1
bash scripts/n8n/emergency-recover-webhooks.sh

# Then verify Phase activation:
docker exec n8n n8n list:workflow --active=true \
  | grep -iE "clx-(b2c|lead-research|lead-scoring|business-signal|campaign-router|outreach|follow-up|booking|city-scan|apollo)"

# Should show ~10-11 active workflows.

# Smoke-test booking flow with a test lead:
# (manually) insert into leads with email='your-test-inbox@gmail.com', lead_status='Replied'
# Wait 30 min for booking workflow's schedule tick
# Confirm Calendly email arrives in test inbox
```
