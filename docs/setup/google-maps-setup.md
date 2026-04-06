# Google Maps Places API Setup Guide

Step-by-step instructions for connecting Google Maps Places API to n8n for the CLX City Scan Discovery workflow.

---

## Prerequisites

- A Google Cloud account with billing enabled
- Access to the `crystallux-engine` project in Google Cloud Console
- Access to your n8n instance at https://automation.crystallux.org

---

## Part 1 — Enable Places API

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Select the `crystallux-engine` project
3. Navigate to **APIs & Services > Library**
4. Search for **Places API**
5. Click **Places API** and then **Enable**
6. Wait for activation to complete

> **Note:** If you already have a Google API key for Custom Search (Phase 4), the same key works for Places API as long as it is enabled on the same project.

---

## Part 2 — Get or Verify API Key

If you already have a key from the Google Search setup:

1. Go to **APIs & Services > Credentials**
2. Find your existing API key
3. Click it and verify that **Places API** is listed under API restrictions (or set to "Don't restrict key" for development)

If you need a new key:

1. Go to **APIs & Services > Credentials**
2. Click **Create Credentials > API Key**
3. Copy the key immediately
4. Click **Edit API Key** to add restrictions:
   - Application restrictions: **HTTP referrers** or **IP addresses** (your VPS IP)
   - API restrictions: Select **Places API** and **Custom Search API**

---

## Part 3 — Create Google Maps Credential in n8n

The Google Maps Places API passes the key as a **query parameter** (`key=`), not a header. However, n8n's Header Auth credential still works because the workflow appends the key via the credential system.

1. Open your n8n instance at https://automation.crystallux.org
2. Go to **Settings > Credentials**
3. Click **Add credential**
4. Select **Header Auth**
5. Fill in:
   - **Credential name:** `Google Maps` — must match exactly
   - **Name:** `key`
   - **Value:** your Google Maps API key
6. Click **Save**

> **Important:** The Places API text search endpoint uses a query parameter `key` for authentication. The n8n HTTP Request node with this credential will pass the API key correctly.

---

## Part 4 — Verify the API Key Works

Test with a simple HTTP request in n8n:

1. Create a test HTTP Request node
2. Set method to **GET**
3. Set URL to `https://maps.googleapis.com/maps/api/place/textsearch/json`
4. Add query parameter: `query` = `insurance broker in Toronto Canada`
5. Set authentication to `Google Maps` credential
6. Execute — you should see results with business names and addresses

---

## Part 5 — Estimated Cost Per Scan Run

The CLX City Scan Discovery workflow runs **35 queries per night** (5 cities x 7 industries).

| Item | Cost |
|------|------|
| Text Search request | $0.032 per request |
| 35 queries per night | ~$1.12 per night |
| 30 nights per month | ~$33.60 per month |
| Google $200/month free credit | Covers ~178 nights |

**You will not be charged** until you exceed the $200 monthly free credit, which covers roughly 6 months of nightly scans.

---

## Part 6 — Adding More Cities and Industries

To add more cities or industries, edit the **Build Scan List** code node in the workflow:

**Add a city:**
```javascript
const cities = ['Toronto', 'Vancouver', 'Calgary', 'Ottawa', 'Mississauga', 'Edmonton'];
```

**Add an industry:**
```javascript
const industries = [
  { query: 'insurance broker', product_type: 'insurance' },
  { query: 'construction company', product_type: 'construction' },
  // ... existing industries ...
  { query: 'landscaping company', product_type: 'landscaping' }
];
```

Each new city adds 7 queries per run. Each new industry adds 5 queries per run.

---

## Rate Limits

| Limit | Value |
|-------|-------|
| Requests per second | 10 |
| Results per text search | Up to 20 |
| Free monthly credit | $200 |

The 2-second wait between API calls in the workflow keeps usage well within rate limits.

---

## Troubleshooting

**REQUEST_DENIED error**
- Places API is not enabled on the project — enable it in Cloud Console
- API key restrictions are blocking the request — check key settings

**ZERO_RESULTS for a query**
- The search query may be too specific — try broader terms
- The city may not have businesses matching that industry

**OVER_QUERY_LIMIT**
- You've exceeded rate limits — increase the Wait node delay
- You've exceeded the $200 monthly credit — check billing

**Businesses found but no website/phone**
- Text Search returns limited fields — use Place Details API for full data
- The workflow handles missing fields gracefully (empty strings)
