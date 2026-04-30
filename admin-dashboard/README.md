# admin-dashboard/ — Crystallux Admin (admin.crystallux.org)

Multi-file vanilla-JS dashboard. No build step. Deploys to a Cloudflare Pages project named `crystallux-admin` mapped to `admin.crystallux.org`. For Mary only — admin role required.

## Files

```
admin-dashboard/
├── index.html                  Bootstrap (validates session, forwards to overview)
├── login-redirect.html         Thin bounce to crystallux.org/login (used by _redirects)
├── _headers                    CSP + cache + noindex
├── _redirects                  Friendly /clients → /pages/clients.html etc.
├── pages/                      One HTML file per panel
│   ├── overview.html
│   ├── clients.html            list + search + filter
│   ├── client-detail.html      single client + recent leads + KPIs
│   ├── leads.html              all leads, filterable
│   ├── workflows.html          n8n run summary
│   ├── billing.html            MRR + per-client billing
│   ├── onboarding.html         clients in onboarding stages
│   ├── market-intelligence.html signal counts + active signals
│   ├── audit-log.html          sessions + admin actions
│   └── settings.html           account + sign out + system info
└── shared/
    ├── auth.js                 clxAuth: session validation + page gate + logout
    ├── api.js                  clxApi: fetch wrapper + status→message mapper
    ├── components.js           clxComp: tables, stat grids, dates, badges, nav inject
    ├── layout.css              shared design tokens + responsive shell
    └── nav.html                sidebar nav fragment (loaded via fetch)
```

## How a page is wired

```html
<script src="../shared/auth.js"></script>
<script src="../shared/api.js"></script>
<script src="../shared/components.js"></script>
<script>
  clxAuth.require('admin').then(function (user) {
    clxComp.injectNav(document.getElementById('clxSidebar'));
    clxComp.renderTopbarUser(document.getElementById('clxTopbarRight'));
    return clxApi.adminGet('list-clients', { active: true });
  }).then(function (res) {
    if (!res.ok) { clxApi.renderError(document.getElementById('myEl'), res); return; }
    clxComp.renderTable(document.getElementById('myEl'), res.data.clients, [...]);
  });
</script>
```

`clxAuth.require('admin')` hides the body until validate-session returns OK. If the user isn't an admin (or the session is expired), it redirects to `crystallux.org/login` before the page paints — no UI flash.

## Deployment

Cloudflare Pages project, source = this repo, root directory = `admin-dashboard`, output directory = `admin-dashboard` (no build step). Custom domain `admin.crystallux.org`. The DNS record:

```
admin   CNAME   crystallux-admin.pages.dev   (proxied)
```

## Local dev

From the repo root:

```bash
python -m http.server 8080
# open http://localhost:8080/admin-dashboard/
```

The page will redirect you to `https://crystallux.org/login.html` if you have no session — sign in there first, then come back.

## Backend dependencies

Admin webhooks must be active in n8n (`workflows/api/admin/*.json`):

- `admin/list-clients`
- `admin/client-detail`
- `admin/list-leads`
- `admin/system-health`
- `admin/billing-summary`
- `admin/workflow-status`
- `admin/onboarding-pipeline`
- `admin/market-intelligence`
- `admin/audit-log`

Each one validates the session via `validate_session(p_token)` RPC before doing any work. The browser never holds a Supabase key.
