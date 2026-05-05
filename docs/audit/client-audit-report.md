# CLIENT Dashboard Audit Report

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
- Screenshot: `docs/audit/screenshots/client/overview.png`

### leads
- URL: https://app.crystallux.org/pages/leads.html
- HTTP: 200, load 1751ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/leads.png`

### campaigns
- URL: https://app.crystallux.org/pages/campaigns.html
- HTTP: 200, load 1664ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/campaigns.png`

### bookings
- URL: https://app.crystallux.org/pages/bookings.html
- HTTP: 200, load 1568ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/bookings.png`

### activity
- URL: https://app.crystallux.org/pages/activity.html
- HTTP: 200, load 1884ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/activity.png`

### billing
- URL: https://app.crystallux.org/pages/billing.html
- HTTP: 200, load 1675ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/billing.png`

### settings
- URL: https://app.crystallux.org/pages/settings.html
- HTTP: 200, load 1653ms
- Sidebar: MISSING
- Stat cards: 0
- Charts (sparkline/donut/bar): 0 (n/a)
- Table rows: 0, list rows: 0
- Interactive: 0
- Screenshot: `docs/audit/screenshots/client/settings.png`

## Mobile (375px)
- Pass: ✓
- Detail: burger=false sidebar=false
- Screenshot: `docs/audit/screenshots/client/mobile-overview.png`

## Tenant isolation

| Test | Pass | Detail |
|------|------|--------|
| admin-page-blocked | ✓ | Client redirected away from admin (URL: https://crystallux.org/login?next=https%3A%2F%2Fadmin.crystallux.org%2Fpages%2Foverview&why=no-token) |
| session-token-readable | ✗ | No clx_session_token in localStorage |
