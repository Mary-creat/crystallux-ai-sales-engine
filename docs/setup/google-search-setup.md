# Google Custom Search API — Setup Guide
## Required for Phase 4: CLX Business Signal Detection

---

## Overview

Phase 4 uses the Google Custom Search API to search the web for live business signals about each lead — hiring activity, funding news, expansion announcements, and growth indicators. You need two things:

1. A **Google API Key** from Google Cloud Console
2. A **Custom Search Engine ID (cx)** from Programmable Search Engine

Estimated cost: **$5 per 1,000 searches** (first 100/day are free).

---

## Step 1 — Create a Google Cloud Project and Enable the API

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Click **Select a project** → **New Project**
3. Name it `Crystallux Signal Detection` → **Create**
4. In the left sidebar go to **APIs & Services → Library**
5. Search for **Custom Search API**
6. Click it → click **Enable**

---

## Step 2 — Get Your Google API Key

1. In Google Cloud Console go to **APIs & Services → Credentials**
2. Click **+ Create Credentials → API Key**
3. Copy the key — it looks like: `AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX`
4. Click **Edit API Key** and restrict it:
   - Under **API restrictions** → select **Restrict key**
   - Choose **Custom Search API** from the list
   - Save

---

## Step 3 — Create a Custom Search Engine

1. Go to [programmablesearchengine.google.com](https://programmablesearchengine.google.com)
2. Click **Add** or **Get Started**
3. Under **Sites to search** enter: `www.google.com` (this enables searching the entire web)
4. Give it a name: `Crystallux Business Signals`
5. Click **Create**
6. On the next screen click **Customize**
7. Under **Basics** toggle **Search the entire web** to ON
8. Copy your **Search engine ID** — it looks like: `017576662512468239146:omuauf_lfve`

---

## Step 4 — Add the Google Search Credential to n8n

In n8n go to **Settings → Credentials → Add Credential**:

1. Select type: **Header Auth**
2. Fill in:
   - **Credential name:** `Google Search`
   - **Name:** `X-Goog-Api-Key` *(header name — note: the API key is passed as a URL parameter, not a header, so this credential is used for identification only)*
   - **Value:** your Google API Key (`AIzaSy...`)
3. Save

> **Important:** The Google Custom Search API uses `key` as a URL query parameter, not a header. In the `Google Search` node, the API key is passed via the `key` query parameter and the `cx` (Search Engine ID) is also a query parameter. The credential in n8n stores the key securely — the node reads it from the credential reference.

---

## Step 5 — Update the Google Search Node in n8n

After importing `clx-business-signal-detection.json`:

1. Open the **Google Search** node
2. Under **Send Query Parameters** make sure these are set:
   - `key` → your API key (from credential)
   - `cx` → your Custom Search Engine ID (`017576662512468239146:omuauf_lfve`)
   - `num` → `5`
   - `dateRestrict` → `m6`
3. The `q` parameter is built dynamically by the **Build Search Query** code node upstream

---

## Pricing Reference

| Usage | Cost |
|-------|------|
| First 100 queries/day | Free |
| Queries 101–1,000/day | $5 per 1,000 queries |
| Queries 1,001–10,000/day | $5 per 1,000 queries |
| Max queries/day | 10,000 |

At 20 leads processed per hour (Phase 4 limit), with the workflow running every 60 minutes:
- **Worst case:** 20 queries/run × 24 runs/day = 480 queries/day = **within free tier**
- Once you scale past 100 leads/day: approximately **$2–5/day**

---

## Troubleshooting

**`keyInvalid` error:** API key is wrong or the Custom Search API is not enabled in your Cloud project.

**`cx` parameter error:** Custom Search Engine ID is wrong — copy it again from programmablesearchengine.google.com.

**`rateLimitExceeded`:** You've hit the 100 free queries/day limit. Add billing to your Google Cloud account to continue.

**Empty results:** The search query returned no results for that company. The workflow handles this gracefully — Claude will analyze an empty result set and return a `Low` signal confidence.
