# dashboard/ — Crystallux operations dashboard

Single-file SPA (`index.html`) serving four roles: admin, client, ops, guest. Public status page at `status.html` (no auth). Form intake at `form.html` (public submission → `clx-form-intake-v1` workflow). Role detection + RLS-backed client isolation documented in `AUDIT.md` and `CLIENT_ISOLATION_TEST.md`.

## Files

```
dashboard/
├── index.html                     Main dashboard shell (3,145 lines)
├── status.html                    Public platform status page (no auth)
├── form.html                      Public intake form (submits to form-intake webhook)
├── AUDIT.md                       Pre-multi-role state snapshot
├── CLIENT_ISOLATION_TEST.md       7-test protocol Mary runs before each client onboarding
└── README.md                      This file
```

## URLs (production, post-Cloudflare-Pages deployment)

- **Admin:**  `https://crystallux.org/dashboard/?token={MARY_MASTER_TOKEN}`
- **Client:** `https://crystallux.org/dashboard/?client_id={UUID}&token={DASHBOARD_TOKEN}`
- **Ops:**    `https://crystallux.org/dashboard/?token={OPS_TOKEN}&ops=1`
- **Status:** `https://crystallux.org/dashboard/status.html` (public, no token)
- **Form:**   `https://crystallux.org/dashboard/form.html`

## Preview locally

From the repo root:

```bash
python -m http.server 8080
# Open http://localhost:8080/dashboard/
```

For meaningful testing you need a Supabase anon key configured in Settings (paste on first load) and either:
- `?token=<anything>` for admin role
- `?client_id=<uuid>&token=<dashboard_token>` for client role

See `AUDIT.md` for role-detection logic, `CLIENT_ISOLATION_TEST.md` for the adversarial test protocol.

## Deployment

Deployed at `crystallux.org/dashboard/*` as a sibling of the public site. See top-level `DEPLOY.md` for Cloudflare Pages setup.

## Reference docs

- `docs/architecture/OPERATIONS_HANDBOOK.md` §26 — Dashboard Role Model
- `docs/architecture/OPERATIONS_HANDBOOK.md` §22 — Admin Copilot
- `docs/architecture/migrations/2026-04-24-dashboard-rls-hardening.sql` — RLS enforcement
- `docs/MARY_ACTIVATION_CHECKLIST.md` Phase 13 — Dashboard activation
- `docs/MARY_ACTIVATION_CHECKLIST.md` Phase 14 — Admin Copilot activation
