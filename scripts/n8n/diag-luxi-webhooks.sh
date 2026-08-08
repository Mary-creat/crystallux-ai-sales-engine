#!/usr/bin/env bash
# Diagnose why some LUXI webhooks 404 while their neighbours register fine.
#
# Three things can cause it, and they need different fixes:
#   1. The workflow isn't actually active (activation returned 200 but didn't stick)
#   2. An orphan webhook_entity row from a deleted/deactivated workflow is
#      squatting on the path, so the real workflow can't claim it (blockers 0q)
#   3. A duplicate workflow holds the same path (blockers 0n)
#
# Read-only. Changes nothing. Run on the VPS:
#   bash scripts/n8n/diag-luxi-webhooks.sh

set -uo pipefail
CONTAINER="${CLX_N8N_CONTAINER:-n8n}"
API="${CLX_N8N_PUBLIC_URL:-https://automation.crystallux.org}/api/v1"

echo "================================================================"
echo " LUXI webhook diagnosis"
echo "================================================================"

# ─── 1. active flag per workflow, via REST ───────────────────────
echo ""
echo "--- 1. Is each workflow actually active? -----------------------"
if [ -z "${N8N_API_KEY:-}" ]; then
  echo "  N8N_API_KEY not set in this shell — skipping (section 2 still works)."
else
  for row in \
    "wfLuxiPublicAuctionV1|auction        (404)" \
    "wfLuxiPublicCreateIntentV1|create-intent  (404)" \
    "wfLuxiPublicBuyNowIntentV1|buy-now-intent (404)" \
    "wfLuxiPublicConfirmBidV1|confirm-bid    (502, works)" \
    "wfLuxiPublicStreamV1|stream-status  (200, works)"
  do
    id="${row%%|*}"; label="${row#*|}"
    body=$(curl -s --max-time 20 -H "X-N8N-API-KEY: $N8N_API_KEY" "$API/workflows/$id")
    act=$(printf '%s' "$body" | grep -o '"active":[a-z]*' | head -1 | cut -d: -f2)
    [ -z "$act" ] && act="(no response / not found)"
    printf "  %-30s active=%s\n" "$label" "$act"
  done
fi

# ─── 2. what the database thinks ─────────────────────────────────
echo ""
echo "--- 2. webhook_entity + workflow_entity rows -------------------"
VOLUME=$(docker inspect "$CONTAINER" --format '{{ (index .Mounts 0).Name }}' 2>/dev/null)
if [ -z "$VOLUME" ]; then
  echo "  Could not find the n8n volume for container '$CONTAINER'."
  echo "  If n8n uses Postgres rather than sqlite, this section won't apply."
  exit 0
fi

docker run --rm -v "${VOLUME}:/data" alpine:3.18 sh -c '
  apk add --no-cache sqlite >/dev/null 2>&1
  if [ ! -f /data/database.sqlite ]; then
    echo "  No sqlite database at /data/database.sqlite (Postgres-backed n8n?)"
    exit 0
  fi
  echo ""
  echo "  webhook_entity rows containing \"luxi\":"
  echo "  path | method | workflowId"
  sqlite3 /data/database.sqlite \
    "SELECT webhookPath || \"  |  \" || method || \"  |  \" || workflowId
     FROM webhook_entity WHERE webhookPath LIKE \"%luxi%\" ORDER BY webhookPath;" \
    | sed "s/^/    /"

  echo ""
  echo "  workflow_entity rows named LUXI:"
  echo "  id | active | name"
  sqlite3 /data/database.sqlite \
    "SELECT id || \"  |  \" || active || \"  |  \" || name
     FROM workflow_entity WHERE name LIKE \"%LUXI%\" ORDER BY name;" \
    | sed "s/^/    /"

  echo ""
  echo "  orphans (webhook rows whose workflow no longer exists):"
  sqlite3 /data/database.sqlite \
    "SELECT w.webhookPath || \"  ->  missing workflow \" || w.workflowId
     FROM webhook_entity w
     LEFT JOIN workflow_entity f ON f.id = w.workflowId
     WHERE f.id IS NULL;" \
    | sed "s/^/    /"
'

echo ""
echo "================================================================"
echo " What to look for:"
echo "  - A 404 path MISSING from webhook_entity  -> never registered"
echo "  - A 404 path present but pointing at a DIFFERENT workflowId"
echo "    than the LUXI one -> a squatter is holding it (blockers 0q)"
echo "  - active=0 on a 404 workflow -> activation did not stick"
echo "  - two rows with the same path -> duplicate workflow (blockers 0n)"
echo "================================================================"
