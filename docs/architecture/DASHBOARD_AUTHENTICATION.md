# Dashboard Authentication — Architecture and Transition Plan

**Status:** Mode A live (transitional), Mode B stub
**Owner:** Mary Akintunde
**Last reviewed:** 2026-04-29
**Related code:** `dashboard/index.html` — `clxAuth` block (~line 1418), role-detection block (~line 1385), `supabaseHeaders` (~line 1845), `clxScopeUrl` (~line 1443)

---

## 1. Today's model — Mode A only (transitional)

```
                 ┌──────────────────────────────────────────┐
  Mary's browser │  paste service-role key in Settings       │
                 │  (sessionStorage, cleared on tab close)   │
                 └────────────────────┬─────────────────────┘
                                      │ Authorization: Bearer <service_role>
                                      ▼
                              ┌──────────────┐
                              │   Supabase   │
                              │   PostgREST  │
                              └──────────────┘
```

**Auth surface:** the dashboard URL is gated by `MARY_MASTER_TOKEN` in the query string (`?admin=true&token=…`). The dashboard reads the token client-side, then expects Mary to paste a Supabase key into the Settings panel. The pasted key is stored in `sessionStorage` (`clx_supabase`) and used in every fetch as both `apikey` and `Authorization: Bearer`.

**What's protecting data:**
- The deployed URL is private — only Mary holds it.
- The pasted key is a service-role-equivalent key, so RLS does not gate it.
- `sessionStorage` is cleared on tab close.

**What is NOT protecting data:**
- DevTools can read `sessionStorage`. Anyone with the browser open can copy the key.
- No audit log of what was queried.
- No per-client scoping enforced server-side.

**Why this is acceptable today:** Mary is the only operator. She uses a single trusted device. The threat model is "Mary's browser is fine." This DOES NOT generalise to clients.

---

## 2. Target model — Mode A + Mode B

```
   ┌─────────────────────────────────────────────────────────────────┐
   │                      Crystallux Dashboard                       │
   └─────────────────────────────────────────────────────────────────┘
                  │                                       │
   ?admin=true&token=…                ?client_id=…&token=…
                  ▼                                       ▼
       ┌─────────────────────┐                ┌──────────────────────────┐
       │ clx-admin-validate  │                │ clx-validate-dashboard-  │
       │   (n8n webhook)     │                │ access (n8n webhook)     │
       └─────────┬───────────┘                └────────────┬─────────────┘
                 │                                          │
                 │  short-lived admin session token         │  scoped client session
                 ▼                                          ▼
       ┌─────────────────────────────┐    ┌─────────────────────────────────┐
       │ All admin reads still go    │    │ ALL client reads route through  │
       │ direct browser→Supabase     │    │ clx-client-data-proxy webhook   │
       │ via apikey injected at      │    │ (n8n) which holds the           │
       │ webhook validation time     │    │ service_role key server-side    │
       │ (Phase 2 hardening — to be  │    │ and enforces client_id scoping  │
       │ revisited; for now Phase 1  │    │ before forwarding to Supabase   │
       │ keeps Mary's paste flow).   │    │                                  │
       └─────────────────────────────┘    └─────────────────────────────────┘
```

**Mode A — Admin (Mary):** the master token is exchanged at `clx-admin-validate` for a session token + an admin "scope receipt" that the dashboard caches in memory (not sessionStorage). Phase 1 keeps the existing paste flow because it's already working; Phase 2 retires the paste in favour of webhook-issued sessions.

**Mode B — Client:** the dashboard token is exchanged at `clx-validate-dashboard-access` for a scoped session bound to one `client_id`. The dashboard then sends every read as a POST to `clx-client-data-proxy` with `{ table, select, filters, client_id, session }`. The webhook holds the service_role key, validates the session, enforces `client_id` scoping, and forwards to Supabase. The browser never holds a Supabase key.

---

## 3. Webhooks to build (deferred to workflow-import phase)

### 3.1 `clx-admin-validate`

| Field | Value |
|---|---|
| Path | `/webhook/clx-admin-validate` |
| Method | POST |
| Auth | none (rate limit only) |
| Rate limit | 10 req/min/IP |
| Request | `{ "token": "<MARY_MASTER_TOKEN>" }` |
| Response (200) | `{ "ok": true, "session": "<jwt>", "expires_at": "<iso8601>" }` |
| Response (401) | `{ "ok": false }` |
| Audit table | `admin_action_log` (existing — see migration 2026-04-24-admin-copilot.sql) |

### 3.2 `clx-validate-dashboard-access`

| Field | Value |
|---|---|
| Path | `/webhook/clx-validate-dashboard-access` |
| Method | POST |
| Auth | none (rate limit only) |
| Rate limit | 60 req/min/IP |
| Request | `{ "client_id": "<uuid>", "token": "<dashboard_token>" }` |
| Response (200) | `{ "ok": true, "session": "<jwt>", "client_id": "<uuid>", "expires_at": "<iso8601>" }` |
| Response (401) | `{ "ok": false }` |
| Audit table | new `dashboard_access_log` (TBD migration) |

### 3.3 `clx-client-data-proxy`

| Field | Value |
|---|---|
| Path | `/webhook/clx-client-data-proxy` |
| Method | POST |
| Auth | header `X-Crystallux-Session: <jwt>` |
| Rate limit | 120 req/min/IP |
| Request | `{ "table": "<name>", "select": "<csv>", "filters": {...}, "order": "<col.dir>", "limit": <n> }` or `{ "rpc": "<fn>", "args": {...} }` |
| Response (200) | array of rows (admin-shaped) |
| Response (403) | session invalid or table not allowlisted for client mode |
| Implementation note | webhook holds `SUPABASE_SERVICE_ROLE_KEY` in n8n credential store; rebuilds PostgREST URL with forced `client_id=eq.<session.client_id>` filter; maintains per-table allowlist (no schema introspection from request). |

---

## 4. Migration plan

| Phase | Step | Code change |
|---|---|---|
| 1 (today) | `clxAuth` boundary in dashboard, beta banner for Mode B | ✅ landed in `dashboard/index.html` 2026-04-29 |
| 2 | Build `clx-validate-dashboard-access` + `clx-client-data-proxy` webhooks | n8n workflows + new `dashboard_access_log` migration |
| 3 | Switch each Mode B panel from direct fetch to `clxAuth.proxyFetch` | `dashboard/index.html` per-panel — start with Pipeline Stats, Recent Leads, Scan Monitor |
| 4 | Build `clx-admin-validate` + remove Settings paste from Mary's flow | n8n workflow + dashboard removes `supabaseKey` from sessionStorage |
| 5 | Lock the deployed Cloudflare Pages URL behind a header check (admin-only routes get a CF Access policy) | infra-only |

Order matters: client mode hardens first (higher real-world risk), Mary's flow retires last (single trusted operator).

---

## 5. Risks of staying on Mode A indefinitely

- **DevTools key extraction.** Anyone with `sessionStorage` access can lift the service-role key. If Mary's laptop is shared or compromised, the key is gone.
- **No audit trail.** Direct PostgREST queries don't carry actor identity beyond "anyone with the key." When something gets deleted, we can't say who did it.
- **No client scoping.** RLS isn't on the path, so a typo in a panel's filter (`client_id=eq.X`) silently leaks across tenants. Phase 3 RLS hardening (`migration 2026-04-24-dashboard-rls-hardening.sql`) is in place but it's defence-in-depth, not the primary boundary.
- **No rate limiting.** Direct Supabase calls bill per request and have no app-level throttling.

The webhook-proxy pattern fixes all four. Mode A stays usable for Mary in the interim because the URL is private and the operator is trusted.

---

## 6. How this maps to the dashboard code

| Concern | File / line | Notes |
|---|---|---|
| URL → role decision | `dashboard/index.html` ~1385 | `window.CLX_ROLE` in `'admin' / 'client' / 'ops' / 'guest'` |
| Auth boundary | `dashboard/index.html` ~1418 | `clxAuth.validateAdmin / validateClient / proxyFetch` |
| Client-scope helper | `dashboard/index.html` ~1443 | `clxScopeUrl` — defence-in-depth filter, not the boundary |
| Per-panel beta banner | `dashboard/index.html` `#clientBetaBanner` | Shown only when `role === 'client'` |
| Settings paste flow (Mode A) | `dashboard/index.html` ~2700 | `saveKeys / loadKeysFromSession` |
| Error helper | `dashboard/index.html` ~1855 | `supabaseErrorMessage` distinguishes auth/RLS/missing-fn |

---

## 7. Open questions

- Should the admin-validate webhook return the service-role key directly (bad — same exposure as today) or a short-lived signed token that the dashboard exchanges per request? **Lean: signed token, max 1-hour TTL.**
- Should the client-data-proxy be one webhook with `{table, select, filters}` (flexible, big allowlist) or N webhooks (one per panel, narrow contract)? **Lean: one webhook with allowlist, simpler to reason about.**
- Where do we store the audit log retention policy? **Decision needed before Phase 4.**
