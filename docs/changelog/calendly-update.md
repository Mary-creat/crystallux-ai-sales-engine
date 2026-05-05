# Calendly + notification-email update — Crystallux Insurance Network

**Date:** 2026-05-05
**Branch:** scale-sprint-v1
**Migration:** [db/migrations/update-calendly-info.sql](../../db/migrations/update-calendly-info.sql)

## Change

| Field                | Before                          | After                                            |
|----------------------|---------------------------------|--------------------------------------------------|
| `notification_email` | `adesholaakintunde@gmail.com`   | `info@crystallux.org`                            |
| `calendly_link`      | (personal/unknown)              | `https://calendly.com/crystallux-info/30min`     |

Applies only to `clients.id = 6edc687d-07b0-4478-bb4b-820dc4eebf5d` (Crystallux Insurance Network).

## Why

Crystallux is a **multi-vertical service-industry platform**. Insurance is one of several verticals the engine serves (movers, contractors, dental practices, financial advisors, etc.). The customer-facing booking link and notification address need to reflect the **platform brand** rather than a single tenant's industry or a founder's personal account.

This consolidation:

1. Routes prospect booking emails to the shared `info@crystallux.org` inbox so the team (not just one person) sees them.
2. Aligns the Calendly URL with the Crystallux brand → avoids vertical-specific naming that would feel off-brand on cross-vertical outreach.
3. Removes a personal email from the production workflow surface area (security + handoff hygiene).

## Apply

```sql
\i db/migrations/update-calendly-info.sql
```

The migration is idempotent — re-running it on an already-updated row is a no-op.

## Verify

The migration ends with a `SELECT` that should return one row showing the new values:

```
 id                                   | client_name                  | calendly_link                                | notification_email
--------------------------------------+------------------------------+----------------------------------------------+------------------------
 6edc687d-07b0-4478-bb4b-820dc4eebf5d | Crystallux Insurance Network | https://calendly.com/crystallux-info/30min   | info@crystallux.org
```

## Downstream effects

- **Outbound email workflows** that templated `notification_email` will now CC `info@crystallux.org` instead of the founder's Gmail.
- **Calendly booking links** rendered into client outreach for this tenant now point to the shared link.
- **No frontend code change required** — the dashboard reads these fields directly from the API.

## Roll-back

Roll-back is a SQL one-liner if needed (replace with the previous values from your backup):

```sql
UPDATE clients
SET calendly_link = '<previous>', notification_email = '<previous>'
WHERE id = '6edc687d-07b0-4478-bb4b-820dc4eebf5d';
```
