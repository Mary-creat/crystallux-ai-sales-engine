#!/usr/bin/env bash
# Activate the Sales Engine: turns ON the public signup workflow and the full
# lead-gen pipeline (find -> research -> score -> signal -> route -> write ->
# send -> reply -> book -> pipeline-update).
#
# ACTIVATE-ONLY. This flips each workflow's "active" toggle via the n8n REST
# API. It does NOT import, overwrite, or modify any workflow definition, so it
# is safe to run against the protected production workflows. It is idempotent:
# anything already on is left alone.
#
# Run on the VPS:
#   N8N_API_KEY=... bash scripts/n8n/activate-sales-engine.sh
# (N8N_API_KEY is the same key ship.sh uses. If you already export it in your
#  shell / .env, you can just run: bash scripts/n8n/activate-sales-engine.sh)

set -uo pipefail
N8N_URL="${N8N_URL:-http://localhost:5678}"
: "${N8N_API_KEY:?Set N8N_API_KEY first (same key ship.sh uses for activation)}"

# Exact workflow names to switch ON, in pipeline order.
TARGETS=(
  "CLX - Public Client Signup v1"
  "CLX - B2C Discovery v2.1"
  "CLX - City Scan Discovery"
  "CLX - Email Scraper v3"
  "CLX - Lead Research v2"
  "CLX - Lead Scoring v2"
  "CLX - Business Signal Detection v2"
  "CLX - Campaign Router v2"
  "CLX - Outreach Generation v2"
  "CLX - Outreach Sender v2"
  "CLX - Pipeline Update v2"
  "CLX - Reply Ingestion v1"
  "CLX - Booking v2"
  # --- Market Intelligence layer (optional enhancement; auto-tunes campaigns
  #     from real-world signals). Safe to leave on; needs its own data keys to
  #     do anything. Comment these three out if you want core lead-gen only. ---
  "CLX - Signal Ingestion v1"
  "CLX - Signal Intelligence v1"
  "CLX - Intelligence Upsell Detector v1"
)

echo "================================================================"
echo " Activating the Sales Engine (signup + lead-gen pipeline)"
echo " Activate-only: no workflow definitions are changed."
echo "================================================================"
echo "Fetching workflow list from n8n..."

ALL=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows?limit=250")
if [ -z "$ALL" ] || ! echo "$ALL" | grep -q '"data"'; then
  echo "ERROR: could not read workflows from n8n at $N8N_URL."
  echo "Check N8N_API_KEY and that n8n is running."
  exit 1
fi

on=0; already=0; missing=0; failed=0

for name in "${TARGETS[@]}"; do
  # Find id + active state for the workflow with this exact name.
  read -r id active < <(printf '%s' "$ALL" | NAME="$name" node -e '
    let d=""; process.stdin.on("data",c=>d+=c).on("end",()=>{
      const ws=(JSON.parse(d).data||[]);
      const w=ws.find(x=>x.name===process.env.NAME);
      if(w) process.stdout.write(w.id+" "+w.active);
    });')

  if [ -z "${id:-}" ]; then
    echo "  [?] not found in n8n: $name"
    missing=$((missing+1)); continue
  fi
  if [ "${active:-}" = "true" ]; then
    echo "  [=] already on:      $name"
    already=$((already+1)); continue
  fi

  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    "$N8N_URL/api/v1/workflows/$id/activate")
  if [ "$code" = "200" ]; then
    echo "  [+] ACTIVATED:       $name"
    on=$((on+1))
  else
    echo "  [x] FAILED ($code):    $name"
    failed=$((failed+1))
  fi
done

echo "================================================================"
echo " Activated: $on   Already on: $already   Not found: $missing   Failed: $failed"
echo "================================================================"
echo "Next: make sure your ANTHROPIC + GOOGLE keys reach n8n, a Gmail account"
echo "is connected for sending, and one clients row is active with an industry,"
echo "city, calendar link, and notification email. Then discovery will run."
