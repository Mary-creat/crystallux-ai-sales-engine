#!/usr/bin/env bash
# Activate the Sales Engine: turns ON the public signup workflow, the full
# lead-gen pipeline, and (optionally) the market-intelligence layer.
#
# ACTIVATE-ONLY. Flips each workflow's "active" toggle via the n8n REST API by
# workflow id. It does NOT import, overwrite, or modify any definition, so it is
# safe for the protected production workflows. Idempotent.
#
# Pure curl — no node/jq/python needed on the host.
#
# Run on the VPS:
#   N8N_API_KEY=yourkey bash scripts/n8n/activate-sales-engine.sh

set -uo pipefail
# Reach n8n at the same public URL ship.sh uses (the management API is not
# published on localhost from the host). Override with N8N_URL if needed.
N8N_URL="${N8N_URL:-${CLX_N8N_PUBLIC_URL:-https://automation.crystallux.org}}"
: "${N8N_API_KEY:?Set N8N_API_KEY first (same key ship.sh uses for activation)}"

# "<workflow id>|<readable label>", in pipeline order.
IDS=(
  "wfPublicClientSignup|Public Client Signup v1"
  "clx-b2c-discovery-v2.1|B2C Discovery v2.1"
  "clx-city-scan-discovery|City Scan Discovery"
  "clx-email-scraper-v3|Email Scraper v3"
  "clx-lead-research-v2|Lead Research v2"
  "clx-lead-scoring-v2|Lead Scoring v2"
  "clx-business-signal-detection-v2|Business Signal Detection v2"
  "clx-campaign-router-v2|Campaign Router v2"
  "clx-outreach-generation-v2|Outreach Generation v2"
  "clx-outreach-sender-v2|Outreach Sender v2"
  "clx-pipeline-update-v2|Pipeline Update v2"
  "clx-reply-ingestion-v1|Reply Ingestion v1"
  "clx-booking-v2|Booking v2"
  "clx-signal-ingestion-v1|Signal Ingestion v1 (market intel)"
  "clx-signal-intelligence-v1|Signal Intelligence v1 (market intel)"
  "clx-intelligence-upsell-detector-v1|Intelligence Upsell Detector v1 (market intel)"
)

echo "================================================================"
echo " Activating the Sales Engine (signup + lead-gen + market intel)"
echo " Activate-only, by id, via the n8n REST API. No definitions changed."
echo " n8n: $N8N_URL"
echo "================================================================"

on=0; problem=0
for row in "${IDS[@]}"; do
  id="${row%%|*}"; label="${row#*|}"
  code=$(curl -s -o /tmp/clx_act.json -w "%{http_code}" -X POST \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    "$N8N_URL/api/v1/workflows/$id/activate")
  if [ "$code" = "200" ]; then
    echo "  [+] ON:          $label"
    on=$((on+1))
  else
    snip=$(head -c 140 /tmp/clx_act.json 2>/dev/null | tr -d '\n')
    echo "  [x] HTTP $code:    $label   $snip"
    problem=$((problem+1))
  fi
done

echo "================================================================"
echo " ON: $on    Problems: $problem    (of ${#IDS[@]})"
echo "================================================================"
echo "Next steps to make leads flow:"
echo "  1. n8n credentials: set 'Google Maps' + 'Claude Anthropic' (HTTP Header Auth)."
echo "  2. Connect a Gmail in n8n for sending outreach."
echo "  3. Add one active clients row (industry, city, calendar link, notify email)."
echo "Then discovery runs on its schedule and leads land in the client's pipeline."
