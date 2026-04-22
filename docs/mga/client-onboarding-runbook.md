# Crystallux Client Onboarding Runbook

Target time: **30 minutes per client** (after sprint v1 infrastructure).

---

## Prerequisites (one-time)

- [ ] Migration `2026-04-22-scale-sprint-v1.sql` applied in Supabase
- [ ] `CLX - Form Intake v1` workflow active in n8n
- [ ] Client has signed founding agreement at $1,997/mo
- [ ] Client has provided: legal business name, website, Calendly link, industry vertical, preferred sender display name, preferred sender email (or delegated to Crystallux info@crystallux.org)
- [ ] Client's vertical has a row in `niche_overlays` (insurance_broker seeded; any new vertical requires a seed row first)

---

## Step 1 — Fill the onboarding template

Open `docs/mga/client-onboarding-template.sql`. Fill in the placeholders at the top:

```
-- ══ FILL THESE IN BEFORE RUNNING ══
-- :client_name           → e.g. 'Summit Insurance Advisors'
-- :client_slug           → URL-safe, lowercase, no spaces — e.g. 'summit-insurance'
-- :vertical              → must match a niche_overlays.niche_name row
-- :calendly_link         → full Calendly URL
-- :notification_email    → where booking alerts go
-- :sender_display_name   → how 'From' header renders
-- :sender_email          → the email that sends (must be configured in their/our Gmail)
-- :gmail_credential_name → 'Gmail' for default Crystallux credential, else their own
-- :daily_send_cap        → usually 100-200 for founding clients, up to 450
-- :offer_override_json   → '{}' for default, or custom JSON
```

Run the filled-in SQL in Supabase SQL Editor. It's idempotent — safe to re-run if you mistype.

---

## Step 2 — Capture the generated tokens

After the INSERT, the SQL returns `id`, `dashboard_token`, and `client_slug`. Save these.

---

## Step 3 — Send onboarding package to client

Three URLs:

| URL | Purpose | Give to |
|---|---|---|
| `https://dashboard.crystallux.org/?client_id={id}&token={dashboard_token}` | Read-only dashboard (pipeline, leads, reply rate) | Client |
| `https://crystallux.org/intake/{client_slug}` | Public intake form for their website | Client |
| `https://automation.crystallux.org/webhook/form-intake` | Form endpoint (for their dev team if embedding) | Client's dev |

Email template for client handoff: `docs/mga/client-welcome-email-template.md` (TODO: sprint B.5).

---

## Step 4 — Verify end-to-end

Before telling the client to start their list:

- [ ] Load dashboard with their token — confirm "Welcome, {client_name}" renders
- [ ] Submit a test lead via the public form URL — confirm it lands in `leads` with their `client_id`
- [ ] Trigger Outreach Generation v2 manually on the test lead — confirm niche overlay applies
- [ ] Confirm TESTING MODE still redirects the send (check no email went to the test lead's real address)
- [ ] SQL check: `SELECT COUNT(*) FROM leads WHERE client_id = '{id}'` returns 1

---

## Step 5 — Add to client rotation

- [ ] Log client in `docs/mga/active-clients.md` (create if not present)
- [ ] Set up dedicated Slack/email channel for their alerts
- [ ] Schedule 48-hour check-in

---

## Common pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Dashboard shows "Invalid token" | Token regenerated or wrong URL | `SELECT dashboard_token FROM clients WHERE id = '{id}'` |
| Form submits but no lead appears | `client_slug` mismatch OR workflow inactive | Check `clients.client_slug` column; verify workflow active in n8n |
| Outreach Generation produces generic prompt (not niche-aware) | `vertical` column not set OR niche_overlays row missing | `UPDATE leads SET vertical='{vertical}' WHERE client_id='{id}'`; confirm niche_overlays row exists |
| Email goes out from wrong sender | `sender_email` not configured; workflow reading default | Sprint B.5 delivers per-client sender propagation; until then all clients share info@crystallux.org |

---

## Scaling cadence

- **Week 1:** onboard clients 1-3. Monitor daily.
- **Week 2:** clients 4-7 if Week 1 is green.
- **Week 3:** clients 8-10.
- **Always:** complete backup verification (`scripts/test-restore.sh`) before each new wave.
