# client-dashboard/ — Crystallux Client App (app.crystallux.org)

Mobile-first vanilla-JS dashboard. No build step. Deploys to a Cloudflare Pages project named `crystallux-app` mapped to `app.crystallux.org`. For paying clients — `client` or `team_member` roles only.

**Cross-tenant isolation is the most important property of this dashboard.** A client must never see another client's data. The boundary is enforced **in the n8n webhooks**: every API call extracts `client_id` from the session row (via `validate_session`), and uses that — not anything sent in the request body — to scope Supabase queries.

## Files

```
client-dashboard/
├── index.html                  Bootstrap (validates session, forwards to overview)
├── _headers                    CSP + cache + noindex
├── _redirects                  Friendly /leads → /pages/leads.html etc.
├── pages/                      One HTML file per panel
│   ├── overview.html           greeting + KPIs + recent leads + upcoming bookings
│   ├── leads.html              your full pipeline + status filter
│   ├── campaigns.html          active campaigns + send/reply rate
│   ├── bookings.html           upcoming bookings + recent replies (split panels)
│   ├── activity.html           lead-status change feed
│   ├── billing.html            your subscription, last payment, manage-billing CTA
│   └── settings.html           account info + notification prefs (write) + sign out
└── shared/
    ├── auth.js                 clxAuth: session gate, role check, logout
    ├── api.js                  clxApi: clientGet/clientPost — strips client_id
    ├── components.js           clxComp: stat grid, list rows (mobile cards), helpers
    ├── layout.css              mobile-first (bottom nav <768px, sidebar 768px+)
    ├── nav.html                sidebar nav fragment (tablet/desktop)
    └── bottom-nav.html         bottom-nav fragment (mobile only, 4 items)
```

## Responsive layout

- **Mobile (≤767px):** bottom nav with 4 tap targets (Overview, Leads, Bookings, Settings). All others reachable via the link cards on overview. Single-column stat grid. List rows replace tables.
- **Tablet (768–1023px):** sidebar appears, bottom nav hides. 2–3 column stat grids.
- **Desktop (1024px+):** wider sidebar, roomier content column.

All tap targets are ≥44px. iOS safe-area insets respected for the bottom nav.

## How a page is wired

```html
<script src="../shared/auth.js"></script>
<script src="../shared/api.js"></script>
<script src="../shared/components.js"></script>
<script>
  clxAuth.require('client').then(function (user) {
    clxComp.injectNav(document.getElementById('clxSidebar'));
    clxComp.injectBottomNav(document.getElementById('clxBottomNav'));
    clxComp.renderTopbarUser(document.getElementById('clxTopbarRight'));
    return clxApi.clientGet('overview');   // NO client_id passed — server derives it
  }).then(function (res) {
    if (!res.ok) { clxApi.renderError(el, res); return; }
    // render…
  });
</script>
```

`clxApi.clientGet` and `clxApi.clientPost` deliberately **strip any `client_id` the caller tries to send.** The server-side webhook would overwrite it anyway, but this is defence-in-depth.

## Deployment

Cloudflare Pages project, source = this repo, root directory = `client-dashboard`, output directory = `client-dashboard` (no build step). Custom domain `app.crystallux.org`. The DNS record:

```
app   CNAME   crystallux-app.pages.dev   (proxied)
```

## Local dev

From the repo root:

```bash
python -m http.server 8080
# open http://localhost:8080/client-dashboard/
```

## Backend dependencies

Client webhooks must be active in n8n (`workflows/api/client/*.json`):

- `client/overview`
- `client/leads`
- `client/campaigns`
- `client/bookings`
- `client/replies`
- `client/activity`
- `client/performance`
- `client/billing`
- `client/settings`   (handles both read and write — body presence detects intent)

Each one:
1. Extracts the Bearer token from `Authorization`
2. Calls `validate_session(p_token)` RPC
3. Confirms `user_role IN ('client','team_member')` AND a non-NULL `client_id`
4. Uses the **session-derived** `client_id` to scope every Supabase query
5. Returns 401 (bad/missing token), 403 (wrong role / no client_id), or 200 with payload

The settings webhook is the only one that mutates state. It additionally rejects writes from `team_member` accounts (read-only role).

## Schema columns expected

The settings panel reads/writes `clients.notification_email`, `clients.daily_digest_opt_in`, `clients.booking_alerts_opt_in`. The first already exists in the schema; the two opt-in flags will need to be added in a small migration before the settings page can save changes (read still works — they'll just be `null` and render as unchecked). I'll author that migration when you give the go-ahead, or skip if you'd rather defer the notification feature to Phase 4.
