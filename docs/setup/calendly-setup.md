# Calendly API Setup Guide

Step-by-step instructions for connecting Calendly to n8n for the CLX Booking workflow.

---

## Prerequisites

- A Calendly account (free or paid) at [calendly.com](https://calendly.com)
- At least one event type created in Calendly (e.g. "15 Minute Discovery Call")
- Access to your n8n instance at https://automation.crystallux.org

---

## Part 1 — Get Your Calendly API Token

1. Log in to your Calendly account
2. Go to **Integrations** in the top navigation
3. Click **API & Webhooks**
4. Under **Personal Access Tokens**, click **Generate New Token**
5. Give it a name: `Crystallux n8n`
6. Click **Create Token**
7. Copy the token immediately — it will not be shown again

---

## Part 2 — Add Calendly Credential in n8n

1. Open your n8n instance at https://automation.crystallux.org
2. Go to **Settings → Credentials**
3. Click **Add credential**
4. Select **Header Auth**
5. Fill in:
   - **Credential name**: `Calendly`  ← must match exactly
   - **Name**: `Authorization`
   - **Value**: `Bearer YOUR_CALENDLY_TOKEN`  ← paste your token here, keep "Bearer " prefix
6. Click **Save**
7. Click **Test** to confirm the credential works

---

## Part 3 — Verify Your Scheduling Link

The CLX Booking workflow calls `https://api.calendly.com/user/me` to retrieve your scheduling URL automatically. To verify it will work:

1. In n8n, create a quick test HTTP Request node
2. Set method to **GET**
3. Set URL to `https://api.calendly.com/user/me`
4. Set authentication to `Calendly` credential
5. Execute — the response should include `scheduling_url`

The `scheduling_url` will look like: `https://calendly.com/yourname/15min`

---

## Part 4 — Set Up Your Discovery Call Event

For best results, create a short event type in Calendly:

1. Go to **Event Types → New Event Type**
2. Choose **One-on-One**
3. Set duration to **15 minutes**
4. Name it: `15-Minute Discovery Call`
5. Add a brief description that matches your value proposition
6. Enable buffer time (15 min after) to avoid back-to-back calls
7. Set your available hours
8. Save and copy the event link

This link is what prospects will see when they receive the booking email.

---

## Part 5 — Test Before Activating

Before activating `clx-booking`, verify end-to-end:

1. Manually set one test lead's `lead_status` to `Replied` in Supabase
2. Add a sample `reply_text` like `"Yes, I'm interested, let's talk"`
3. Run the workflow manually
4. Confirm Claude detects interest
5. Confirm Calendly link is retrieved
6. Confirm booking email arrives in your inbox
7. Reset the test lead status when done

---

## Calendly API Reference

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/user/me` | GET | Get current user profile and scheduling URL |
| `/event_types` | GET | List all event types |
| `/scheduled_events` | GET | List booked meetings |

---

## Troubleshooting

**401 Unauthorized**
- Check that the `Authorization` header value starts with `Bearer ` (with a space)
- Regenerate the token in Calendly if it was accidentally exposed

**scheduling_url is null**
- Your Calendly profile may not have a public scheduling link enabled
- Go to Calendly → Profile → turn on your public page

**Booking email not sending**
- Confirm the Gmail credential is still authorized (OAuth tokens expire)
- Re-authorize Gmail in n8n if needed
