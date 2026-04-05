# Gmail OAuth2 Setup Guide

Complete step-by-step instructions for connecting Gmail to n8n for the CLX Outreach Sender workflow.

---

## Prerequisites

- A Google account (the Gmail address you want to send outreach from)
- Access to your n8n instance at https://automation.crystallux.org
- Access to Google Cloud Console (free)

---

## Part 1 — Create a Google Cloud Project

1. Go to [https://console.cloud.google.com](https://console.cloud.google.com)
2. Click **Select a project** at the top → **New Project**
3. Name it `Crystallux n8n` and click **Create**
4. Make sure the new project is selected before continuing

---

## Part 2 — Enable the Gmail API

1. In Google Cloud Console, go to **APIs & Services → Library**
2. Search for **Gmail API**
3. Click it and press **Enable**

---

## Part 3 — Configure the OAuth Consent Screen

1. Go to **APIs & Services → OAuth consent screen**
2. Select **External** and click **Create**
3. Fill in the required fields:
   - App name: `Crystallux Sales Engine`
   - User support email: your Gmail address
   - Developer contact email: your Gmail address
4. Click **Save and Continue** through the Scopes screen (no changes needed)
5. On the Test users screen, click **Add Users** and add your Gmail address
6. Click **Save and Continue** then **Back to Dashboard**

---

## Part 4 — Create OAuth2 Credentials

1. Go to **APIs & Services → Credentials**
2. Click **Create Credentials → OAuth client ID**
3. Application type: **Web application**
4. Name: `n8n Crystallux`
5. Under **Authorized redirect URIs**, add:
   ```
   https://automation.crystallux.org/rest/oauth2-credential/callback
   ```
6. Click **Create**
7. Copy the **Client ID** and **Client Secret** — you will need them in the next step

---

## Part 5 — Add Gmail Credential in n8n

1. Open your n8n instance at https://automation.crystallux.org
2. Go to **Settings → Credentials**
3. Click **Add credential**
4. Search for and select **Gmail OAuth2**
5. Enter:
   - **Credential name**: `Gmail`  ← must match exactly
   - **Client ID**: paste from Google Cloud Console
   - **Client Secret**: paste from Google Cloud Console
6. Click **Sign in with Google**
7. Select your Gmail account and grant all requested permissions
8. n8n will redirect back and show **Connection tested successfully**
9. Click **Save**

---

## Part 6 — Test Before Activating

Before activating `clx-outreach-sender`, verify the credential works:

1. Create a test workflow with a single Gmail node
2. Set **To** to your own email address
3. Set **Subject** to `CLX Gmail Test`
4. Set **Message** to `Gmail credential is working`
5. Execute manually and confirm the email arrives
6. Delete the test workflow

---

## Gmail Sending Limits

| Limit | Value |
|-------|-------|
| Free Gmail daily limit | 500 emails/day |
| Google Workspace daily limit | 2,000 emails/day |
| CLX Outreach Sender per run | 5 leads |
| Wait between emails | 60 seconds |
| Max emails per hour | 5 |

The CLX workflow is configured conservatively at 5 leads per run with 60-second waits to stay well within all limits.

---

## Troubleshooting

**"Invalid client" error**
- Double-check the Client ID and Client Secret were copied without extra spaces
- Make sure the redirect URI in Google Cloud matches exactly

**"Access blocked: app not verified"**
- Your OAuth consent screen is in Testing mode — this is expected
- Add your Gmail address to the Test Users list (Part 3, step 5)

**Emails going to spam**
- Ask your first few recipients to mark the email as Not Spam
- Consider using Google Workspace instead of a free Gmail account for better deliverability

**"Daily sending limit exceeded"**
- Reduce the workflow schedule frequency in the Schedule Trigger node
- The 5-leads-per-run limit with 60-minute intervals gives a safe maximum of 120 emails per day
