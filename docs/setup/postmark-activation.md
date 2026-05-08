# Postmark activation — step by step

> **Goal:** flip transactional email from "Console.log placeholder" to "Postmark delivers."
> **Time budget:** 30-45 minutes including DNS propagation wait.

## Step 1 — Sign up for Postmark

1. Go to [postmarkapp.com](https://postmarkapp.com) → **Sign up**.
2. Use `info@crystallux.org` for the account.
3. Verify the email; you'll land in the **default Server** (call it "Crystallux Production" if Postmark prompts).
4. Free tier covers 100 emails/month — fine for early. Switch to a paid plan ($10-15/mo for 10K emails) before any real volume.

## Step 2 — Verify sender domain

This is what unlocks deliverability past Gmail/Outlook spam folders.

1. Postmark Dashboard → **Sender Signatures** → **Add Domain**.
2. Enter `crystallux.org`.
3. Postmark gives you 3 DNS records to add:
   - **DKIM** TXT record (looks like `crystalluxorg._domainkey.crystallux.org`)
   - **Return-Path** CNAME (e.g. `pm-bounces.crystallux.org`)
   - **SPF** include (add `include:spf.mtasv.net` to your existing SPF if you have one, or create a new one if not)
4. Add all 3 records in **Cloudflare DNS** for `crystallux.org`.
5. Wait 10-30 minutes for DNS propagation. Postmark dashboard refreshes verification status automatically.
6. Once all 3 are green, you can send from any `@crystallux.org` address.

## Step 3 — Get API token

1. Postmark Dashboard → **Servers** → click your server → **API Tokens** tab.
2. Copy the **Server API token** (looks like `abc123...`).

## Step 4 — Create the 9 templates in Postmark

1. Dashboard → **Templates** → **Add Template**.
2. For each of the 9 templates in `templates/emails/`:
   - **Name:** human-readable (e.g., "Magic link login")
   - **Alias:** matches the alias in our code (`magic-link`, `password-reset`, `welcome`, `subscription-active`, `subscription-past-due`, `subscription-canceled`, `invoice-receipt`, `lead-meeting-booked`, `agent-daily-summary`)
   - **Subject:** copy from the comment header at the top of each `.html` file (`<!-- Subject: ... -->`)
   - **HTML body:** copy the body of the `.html` file (everything below the comment header)
   - **Plain-text body:** Postmark's "Generate from HTML" button is fine for v1; refine later if needed
3. Save each template.
4. Test one in the Postmark UI: pick a template → **Test sending** → fill the variables → send to your own email. Confirm formatting.

## Step 5 — Set environment variables on n8n VPS

Edit the n8n env file:

```bash
POSTMARK_API_TOKEN=abc123-server-token-from-step-3
INTERNAL_EMAIL_SECRET=<generate-a-random-32-char-string>
N8N_INTERNAL_BASE=http://localhost:5678   # n8n's own URL on the VPS so workflows can call each other
```

The `INTERNAL_EMAIL_SECRET` value gates the `clx-email-send` workflow so external traffic can't spam Postmark via the public webhook URL. Only other n8n workflows (which know the secret from env) can trigger sends.

Generate a random secret:
```bash
openssl rand -base64 24
```

Restart n8n: `docker restart n8n`.

## Step 6 — Import + activate workflows

```bash
# On VPS
cd /root/crystallux-workflows
git pull origin scale-sprint-v1
# Import the new workflow:
# - workflows/api/email/clx-email-send.json
# - workflows/api/auth/clx-auth-welcome.json
# Either via the n8n UI (Import) or via /tmp/clx-import.sh if Mary's bulk-import script handles it.
# Then activate both in the n8n UI.
```

## Step 7 — Wire existing auth workflows to Postmark

The existing `clx-auth-magic-link` and `clx-auth-password-reset-request` workflows have `Send Email (placeholder)` Code nodes that just log. Replace each with an HTTP node calling our `clx-email-send` workflow.

For each of those two workflows in the n8n UI:

1. Open the workflow.
2. Delete the `Send Email (placeholder)` Code node.
3. Add an **HTTP Request** node in the same position:
   - **Method:** POST
   - **URL:** `={{ $env.N8N_INTERNAL_BASE || 'http://localhost:5678' }}/webhook/email/send`
   - **Headers:** `Content-Type: application/json`
   - **Body (JSON):** see below per workflow
4. Reconnect the inputs/outputs as before.
5. Save + activate.

### Magic-link body

```json
{
  "internal_secret": "{{ $env.INTERNAL_EMAIL_SECRET }}",
  "template": "magic-link",
  "to": "{{ $json.email }}",
  "vars": {
    "magic_url": "https://app.crystallux.org/magic-verify?token={{ $json.token }}",
    "expires_minutes": 15,
    "support_email": "support@crystallux.org"
  }
}
```

### Password-reset body

```json
{
  "internal_secret": "{{ $env.INTERNAL_EMAIL_SECRET }}",
  "template": "password-reset",
  "to": "{{ $json.email }}",
  "vars": {
    "reset_url": "https://app.crystallux.org/reset-password?token={{ $json.token }}",
    "expires_hours": 1,
    "support_email": "support@crystallux.org"
  }
}
```

## Step 8 — Wire welcome email trigger

The `clx-auth-welcome` workflow we just imported is fired by:

**Option A (recommended) — Stripe webhook on `checkout.session.completed`:**
- Edit `clx-stripe-webhook-v1`'s `Dispatch Event Type` Code node — when event type is `checkout.session.completed`, add an HTTP call to `/webhook/auth/welcome` with `{ internal_secret, client_id, email, first_name, trial_days }`.

**Option B — first successful login:**
- Edit `clx-auth-login`'s response path: after a successful session creation, fire-and-forget call to `/webhook/auth/welcome`. The workflow is idempotent (checks `clients.welcome_email_sent_at`) so calling on every login is safe.

Pick A for paid signups (cleanest semantics), B if you want to welcome trial users who never paid.

## Step 9 — Database column for idempotency

The welcome workflow checks `clients.welcome_email_sent_at`. Add the column:

```sql
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS welcome_email_sent_at timestamptz;

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS daily_digest_email_sent_at timestamptz;

-- Optional: log of every transactional email sent
CREATE TABLE IF NOT EXISTS email_log (
  id                   uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  template_alias       text NOT NULL,
  to_email             text NOT NULL,
  postmark_message_id  text,
  postmark_error_code  integer,
  sent_at              timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_email_log_to ON email_log(to_email);
CREATE INDEX IF NOT EXISTS idx_email_log_sent ON email_log(sent_at DESC);
```

Apply that in Supabase SQL editor.

## Step 10 — Smoke test end-to-end

1. Trigger a magic link from the marketing site login page.
2. Confirm:
   - Postmark Dashboard → Activity shows the send.
   - Email lands in your inbox within 5 seconds.
   - Clicking the link signs you in.
3. Force a password reset.
4. Trigger Stripe checkout (test card 4242…) → confirm welcome email lands.
5. Open Supabase → check `email_log` table has rows for each.

## Operational notes

- **Bounce handling:** Postmark auto-tracks bounces. Hard bounces should be reflected in `clients.email_bounced_at` (Phase 2 enhancement — not built yet).
- **Spam complaints:** Postmark suppresses automatically. If a customer complains, their address is flagged and won't be sent to again.
- **Streams:** the `outbound` MessageStream is for transactional. If you later add bulk marketing emails, create a separate `broadcast` stream — they have different deliverability rules.
- **Custom from:** templates default to `Crystallux <hello@crystallux.org>`. Per-vertical or per-client custom from-addresses are a Phase 2 enhancement (would require adding `clients.transactional_from_email` column).
