# CLIENT Dashboard Audit Report

> ## ⚠️ THIS AUDIT IS INVALID — DO NOT ACT ON IT
>
> **It never logged in.** Established 2026-09-12 while deduplicating the
> repository: seven of the eight screenshots are **byte-identical**
> (36,638 bytes each — activity, billing, bookings, campaigns, leads,
> overview, settings). Playwright captured the same page seven times.
>
> That page was the login screen. It returns HTTP 200, which is why every
> row below reads `200`. It has no sidebar, no stat cards, no charts and no
> tables, which is why every row reads `MISSING` and `0`.
>
> So **"0 / 7 pages pass" is a fact about the audit, not about the client
> dashboard.** The dashboard may be entirely healthy; this run cannot say
> either way. Anyone reading this as "the client dashboard is broken" would
> be rebuilding something on the strength of a screenshot of a login form.
>
> The six duplicate images have been deleted. One is kept as
> `capture-failed-login-redirect.png` — it is the evidence that the capture
> failed, which is the only thing this run actually proved.
>
> **The admin audit is unaffected**: 11 of 11 of its screenshots are
> distinct, so it really did reach the pages it reports on.
>
> To redo this properly the harness needs an authenticated session —
> `testclient@crystallux.org` — before it navigates. Until then these
> numbers should not appear in any readiness claim.

Generated: 2026-05-05T05:37:20.099Z
Base URL: https://app.crystallux.org

**Summary:** 0 / 7 pages pass

## Per-page results

| Page | HTTP | Load (ms) | Sidebar | Stat cards | Charts | Tables | Lists | Interactive | Console errs | Net errs | Pass |
|------|------|-----------|---------|------------|--------|--------|-------|-------------|--------------|----------|------|
| overview | 200 | 1787 | ✗ | 0 | 0 | 0 | 0 | 0 | 0 | 0 | ✗ |
| leads | 200 | 1751 | ✗ | 0 | 0 | 0 | 0 | 0 | 0 | 0 | ✗ |
| campaigns | 200 | 1664 | ✗ | 0 | 0 | 0 | 0 | 0 | 0 | 0 | ✗ |
| bookings | 200 | 1568 | ✗ | 0 | 0 | 0 | 0 | 0 | 0 | 0 | ✗ |
| activity | 200 | 1884 | ✗ | 0 | 0 | 0 | 0 | 0 | 0 | 0 | ✗ |
| billing | 200 | 1675 | ✗ | 0 | 0 | 0 | 0 | 0 | 0 | 0 | ✗ |
| settings | 200 | 1653 | ✗ | 0 | 0 | 0 | 0 | 0 | 0 | 0 | ✗ |

## Detail

### overview
- URL: https://app.crystallux.org/pages/overview.html
- HTTP: 200, load 1787ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/capture-failed-login-redirect.png` (the login page — see the warning above)

### leads
- URL: https://app.crystallux.org/pages/leads.html
- HTTP: 200, load 1751ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/capture-failed-login-redirect.png` (the login page — see the warning above)

### campaigns
- URL: https://app.crystallux.org/pages/campaigns.html
- HTTP: 200, load 1664ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/capture-failed-login-redirect.png` (the login page — see the warning above)

### bookings
- URL: https://app.crystallux.org/pages/bookings.html
- HTTP: 200, load 1568ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/capture-failed-login-redirect.png` (the login page — see the warning above)

### activity
- URL: https://app.crystallux.org/pages/activity.html
- HTTP: 200, load 1884ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/capture-failed-login-redirect.png` (the login page — see the warning above)

### billing
- URL: https://app.crystallux.org/pages/billing.html
- HTTP: 200, load 1675ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/capture-failed-login-redirect.png` (the login page — see the warning above)

### settings
- URL: https://app.crystallux.org/pages/settings.html
- HTTP: 200, load 1653ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/capture-failed-login-redirect.png` (the login page — see the warning above)

## Mobile (375px)
- Pass: ✓
- Detail: burger=false sidebar=false
- Screenshot: `docs/audit/screenshots/client/mobile-overview.png`

## Tenant isolation

| Test | Pass | Detail |
|------|------|--------|
| admin-page-blocked | ✓ | Client redirected away from admin (URL: https://crystallux.org/login?next=https%3A%2F%2Fadmin.crystallux.org%2Fpages%2Foverview&why=no-token) |
| session-token-readable | ✗ | No clx_session_token in localStorage |
