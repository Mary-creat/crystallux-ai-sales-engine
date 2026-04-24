# Dashboard Audit — State of docs/dashboard/index.html

**Scope:** complete snapshot of the existing dashboard (2,000 lines) before Phase 3+ role-based extensions.
**Performed:** Phase 1 of multi-role architecture spec.
**File:** `docs/dashboard/index.html`

---

## 1. Current panel inventory (16 sections)

All sections render in one viewport; visibility toggled by URL params, not role.

| # | Section ID | Line | Purpose | Default visible |
|---:|---|---:|---|:---:|
| 1 | `clientContextBanner` | 412 | Client welcome + vertical/slug display | hidden (shown when `client_id` in URL) |
| 2 | `adminBanner` | 427 | Admin-mode banner | hidden (shown when `admin=true` in URL) |
| 3 | `intakeUrlSection` | 434 | Public intake URL for client | hidden (shown when `client_id` in URL) |
| 4 | `dashboard` | 446 | Pipeline Stats — Live | ✅ |
| 5 | `scanMonitor` | 454 | Scan Monitor — Today | ✅ |
| 6 | `enrichment` | 478 | Email Enrichment Progress | ✅ |
| 7 | `funnel` | 486 | Lead Pipeline Funnel | ✅ |
| 8 | `leads` | 499 | Recent Leads | ✅ |
| 9 | `emails` | 520 | Recent Emails Sent | ✅ |
| 10 | `activity` | 541 | Recent Activity Timeline | ✅ |
| 11 | `clientPerf` | 555 | Client Performance (admin-only content, but visible to all) | ✅ |
| 12 | `crm` | 563 | CRM Quick Access | ✅ |
| 13 | `actions` | 572 | Quick Actions | ✅ |
| 14 | `apiStatus` | 578 | API Status | ✅ |
| 15 | `billingSection` | 584 | Billing & Subscription (Task 4 Stripe panel) | hidden (shown when `client_id` or `admin=true`) |
| 16 | `channelsActiveSection` | 594 | Channels Active | hidden (shown when `client_id` or `admin=true`) |
| 17 | `chat` | ~600 | Crystallux Assistant chat | ✅ |

---

## 2. Current data queries (by Supabase table)

Fetch calls enumerated from `index.html` lines 800-1950:

### `leads` table
- Line 811 — `select=lead_status&limit=5000` (funnel stats — **no client filter**)
- Line 977 — `select=email` (enrichment — **no client filter**)
- Line 1033 — `select=...&order=updated_at.desc&limit=20` (Recent Leads — **no client filter**)
- Line 1096 — `select=...&outreach_sent_at=not.is.null&order=outreach_sent_at.desc&limit=20` (Recent Emails — **no client filter**)
- Line 1159 — `select=...&order=updated_at.desc&limit=20` (Activity timeline — **no client filter**)
- Line 1222 — `select=client_id,lead_status,total_emails_sent` (Client Performance — admin-only purpose but unfiltered)
- Line 1318 — `select=...&product_type=eq.<type>` (niche-filtered leads)
- Line 1338 — `select=...&lead_score=gte.70&order=lead_score.desc&limit=20` (high-score leads — **no client filter**)
- Line 1352 — `select=lead_status` (score distribution — **no client filter**)
- Line 1386 — `select=...&date_created=gte.<today>&order=date_created.desc&limit=20` (new leads today — **no client filter**)

### `clients` table
- Line 664 — `id=eq.<clientId>&select=id,client_name,client_slug,vertical,dashboard_token&limit=1` (client context banner — id-scoped, correct)
- Line 1221 — `select=id,client_name&active=eq.true` (Client Performance — full list, admin context)
- Line 1299 — `select=client_name,industry,crm_type,...&active=eq.true` (CRM Quick Access — full list)
- Line 1808 — `id=eq.<clientId>&select=...stripe_*` (client-scoped billing panel — correct)
- Line 1848 — `select=...stripe_*&limit=200` (admin MRR summary — full list)
- Line 1935 — `select=...channels_enabled&<clientFilter>&limit=200` (channels active panel — filter applied only for client-scoped)

### `scan_log` / `dashboard_scan_summary` tables
- Line 925-937 — scan-log queries (admin surface; no client filter needed since scans are platform-wide)

### Other
- Line 1493 — Claude API POST (chat assistant)

---

## 3. Current auth logic

### URL parameter convention (lines 624-628)
```javascript
const urlParams = new URLSearchParams(window.location.search);
const clientContext = {
  clientId: urlParams.get('client_id') || '',
  token:    urlParams.get('token') || '',
  admin:    urlParams.get('admin') === 'true',
  ...
};
```

### Three access patterns supported today
- **Admin mode:** `?admin=true&token={MARY_MASTER_TOKEN}`
- **Client mode:** `?client_id={UUID}&token={DASHBOARD_TOKEN}`
- **No params:** fallthrough — loads the same shell unfiltered (problem — see §5)

### Token verification (lines 638-683)
Client mode does a best-effort token check against `clients.dashboard_token` (line 652). Match is string-equality, client-side only. No server-side verification. Admin token (`MARY_MASTER_TOKEN`) is **not verified** anywhere — presence of `admin=true` URL param alone flips admin banner visibility.

### Supabase auth
Single shared anon key stored in browser sessionStorage (line 617 `credentials.supabaseKey`). User pastes it in Settings once; persists until browser closes. All queries authenticate with this key plus RLS determining what rows each role sees.

---

## 4. Current client filtering assessment

**Present and correct:**
- Client context banner (line 664) — by `id`
- Billing panel client view (line 1808) — by `id`
- Channels-active panel client view (line 1935) — conditional `clientFilter` appended to URL

**Missing or unclear:**
- Every panel from 4-10 (Pipeline Stats, Scan Monitor, Enrichment, Funnel, Leads, Emails, Activity) queries leads/scans **without a client_id filter**. If a client-scoped user with their token views the dashboard, they currently see **all leads across all clients** via Supabase RLS only — which means RLS is the single defence layer. If RLS on `leads` isn't hardened for `client_id`, client isolation is broken.
- Client Performance panel (line 1221-1222) intentionally queries across clients; fine for admin, bad for client-scoped view.
- CRM Quick Access (line 1299) — full client list, bad for client-scoped view.

---

## 5. Current billing panel

**Source:** added in commit `f650daf` (Task 4 Stripe scaffolding).
**Location:** `#billingSection`, JS functions `fetchBillingClient` (line 1805+) and `fetchBillingAdmin` (line 1845+).
**Behaviour:**
- Client-scoped: fetches the client's Stripe subscription fields, renders status, plan, next billing date, last payment, trial end, with coloured banner for past_due/trialing
- Admin mode: fetches up to 200 clients, renders MRR summary strip (Active MRR, Active count, Trialing count, Past due count, Canceled count) plus per-client table
- Placeholder URL `https://billing.stripe.com/p/login/PLACEHOLDER_PORTAL_URL` — must be replaced once Stripe Customer Portal configured

**Status:** functional; waits for real Stripe data.

---

## 6. Current channels-active panel

**Source:** added in commit `f650daf`.
**Location:** `#channelsActiveSection`, JS function `fetchChannelsActive` (line 1930+).
**Behaviour:**
- Client-scoped: renders chip per channel (email, linkedin, whatsapp, voice, video, sms) with Configured / Pending Setup status; click opens corresponding OPERATIONS_HANDBOOK section.
- Admin mode: iterates over up to 200 clients and renders one chip-row per client.

**Status:** functional.

---

## 7. Gaps vs multi-role plan

The dashboard today supports two informal modes (admin via `?admin=true`, client via `?client_id=...`). The multi-role plan calls for three distinct roles (admin / client / ops) with strong isolation. The deltas to close:

| Area | Today | Plan requires |
|---|---|---|
| Role detection | 2 modes via URL param | 3 roles via centralised `window.CLX_ROLE` |
| Token verification | Client-side string match, admin unverified | Server-side verification workflow (`clx-verify-dashboard-access-v1`) |
| Client isolation | Relies on RLS + per-panel filters | All queries wrapped in `clxQuery()` that forcibly adds `client_id` when role=client |
| RLS hardening | Assumed but unaudited | Explicit migration enforcing policies on `leads`, `outreach_log`, `appointment_log`, `campaigns`, `apollo_credits_log`, `stripe_events_log` |
| Panel visibility | Two hardcoded groups (admin banner + client banner) | Per-role panel-visibility map |
| Navigation structure | Single viewport, all panels visible | Per-role sidebar menus + hash-routed panel loading |
| Ops role | Not supported | Scaffolded dormant (future) |
| Access-denied page | None; unauth users see the dashboard shell | Dedicated access-denied page for invalid tokens |
| Admin Copilot | Not built | Future Phase 8 (floating assistant with SQL / troubleshoot / Q&A capabilities) |
| Mobile responsiveness | Current CSS mobile-safe | Must hold across all role views |
| Rate limiting | None | 60 req/min per IP on verify-access endpoint |
| Audit log | None for dashboard access | `admin_action_log` table (coming in copilot migration) |

---

## 8. Risk if multi-role extension ships without Phase 2 (client isolation)

If Phase 3 navigation ships before Phase 2 client isolation, a client viewing the dashboard with their valid `client_id` + `dashboard_token` can still see all clients' data via the unfiltered queries in sections 4-10. RLS is the only defence and its current state is not verified.

**This is the highest-priority blocker.** Phase 2 must ship first.

---

## 9. Files that exist and are directly relevant

- `docs/dashboard/index.html` — the shell
- `docs/architecture/migrations/2026-04-23-stripe-billing.sql` — billing schema
- `docs/architecture/migrations/2026-04-23-b2b-b2c-segmentation.sql` — focus_segments column
- `docs/architecture/migrations/2026-04-23-multi-channel.sql` — channels_enabled column
- `docs/architecture/migrations/2026-04-23-video-schema.sql` — video_enabled column
- `docs/architecture/OPERATIONS_HANDBOOK.md` — referenced by Channels Active panel for runbook links

## 10. Files this audit recommends creating in Phase 2+

- `docs/architecture/migrations/2026-04-24-dashboard-rls-hardening.sql` (Phase 2)
- `docs/dashboard/CLIENT_ISOLATION_TEST.md` (Phase 2)
- `workflows/clx-verify-dashboard-access-v1.json` (Phase 1 scaffolding, dormant)
