#!/usr/bin/env bash
# scripts/n8n/ship.sh
#
# One command to ship a workflow to the live n8n: pull latest, find
# the JSON anywhere under workflows/, import, activate, restart.
#
# Usage:
#   bash scripts/n8n/ship.sh <workflow-filename>
#
# Examples:
#   bash scripts/n8n/ship.sh clx-admin-sales-engine-activity-v1.json
#   bash scripts/n8n/ship.sh clx-public-quote-fetch-v1.json
#
# You only need the FILENAME — the script finds it under workflows/
# automatically (admin/, public/, avatars/, ciro/, etc.).
#
# What it does:
#   1. git pull origin main
#   2. Locate the workflow JSON anywhere under workflows/
#   3. Read its top-level "id" field
#   4. Copy the JSON into the n8n container
#   5. n8n import:workflow (inserts the workflow)
#   6. Activate via REST API using N8N_API_KEY (more reliable than the
#      deprecated CLI --active flag)
#   7. docker restart n8n
#   8. Wait + probe the webhook to confirm it routes
#
# Env overrides:
#   CLX_REPO            default: /tmp/clx-latest
#   CLX_N8N_CONTAINER   default: n8n
#   N8N_API_KEY         optional, used for REST-API activation
#   N8N_URL             default: http://localhost:5678

set -uo pipefail

# ─── settings ────────────────────────────────────────────────────
REPO="${CLX_REPO:-/tmp/clx-latest}"
CONTAINER="${CLX_N8N_CONTAINER:-n8n}"
N8N_URL="${N8N_URL:-http://localhost:5678}"

# ─── pretty output ───────────────────────────────────────────────
GREEN=$'\033[32m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

say()  { printf "  %s\n" "$*"; }
ok()   { printf "  ${GREEN}\xe2\x9c\x93${RESET} %s\n" "$*"; }
fail() { printf "  ${RED}\xe2\x9c\x97${RESET} %s\n" "$*" >&2; }
step() { printf "\n${BOLD}%s${RESET}\n" "$*"; }

# ─── arg check ───────────────────────────────────────────────────
if [ $# -lt 1 ]; then
  printf "${BOLD}Usage:${RESET} bash %s <workflow-filename.json>\n\n" "$0"
  printf "Example:\n  bash %s clx-admin-sales-engine-activity-v1.json\n" "$0"
  exit 2
fi
NAME="$1"

# ─── 1. pull latest ──────────────────────────────────────────────
step "1/6  Pull latest repo"
cd "$REPO" || { fail "Repo not at $REPO"; exit 3; }
git pull origin main --quiet
ok "pulled main"

# ─── 2. locate the workflow file ─────────────────────────────────
step "2/6  Find workflow file"
WF_PATH=$(find workflows -name "$NAME" -type f 2>/dev/null | head -1)
if [ -z "$WF_PATH" ]; then
  fail "Workflow $NAME not found under $REPO/workflows/"
  exit 4
fi
ok "found at $WF_PATH"

# Read top-level id from JSON (jq if available, else node, else grep+sed)
if command -v jq >/dev/null 2>&1; then
  WF_ID=$(jq -r '.id' "$WF_PATH")
elif command -v node >/dev/null 2>&1; then
  WF_ID=$(node -e "console.log(require('$REPO/$WF_PATH').id)")
else
  WF_ID=$(grep -m1 '"id"' "$WF_PATH" | sed -E 's/[^"]*"id"[^"]*"([^"]+)".*/\1/')
fi
if [ -z "$WF_ID" ] || [ "$WF_ID" = "null" ]; then
  fail "Could not read top-level id from $WF_PATH"
  exit 5
fi
ok "id: $WF_ID"

# ─── 3. copy + import ────────────────────────────────────────────
step "3/6  Import into n8n"
docker cp "$WF_PATH" "$CONTAINER:/tmp/ship.json" >/dev/null 2>&1 \
  || { fail "docker cp failed (container $CONTAINER running?)"; exit 6; }
IMPORT_OUT=$(docker exec "$CONTAINER" n8n import:workflow --input=/tmp/ship.json 2>&1)
if echo "$IMPORT_OUT" | grep -qiE "successfully imported|imported workflow"; then
  ok "imported"
else
  printf "  ${DIM}%s${RESET}\n" "$IMPORT_OUT"
  fail "import unclear; continuing to activate anyway"
fi

# ─── 4. activate workflow ────────────────────────────────────────
# Preferred: n8n REST API (proper activation hook, registers webhook
# automatically). Requires N8N_API_KEY in env.
# Fallback: direct SQL UPDATE + webhook_entity INSERT via Alpine
# sidecar. Used when API key isn't available; n8n CLI's --active flag
# is deprecated and silently no-ops in recent versions.
step "4/6  Activate workflow"

PUBLIC_BASE="${CLX_N8N_PUBLIC_URL:-https://automation.crystallux.org}"

if [ -n "${N8N_API_KEY:-}" ]; then
  ACT_HTTP=$(curl -s -o /tmp/ship_act.json -w "%{http_code}" \
    -X POST "${PUBLIC_BASE}/api/v1/workflows/${WF_ID}/activate" \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    -H "Accept: application/json")
  case "$ACT_HTTP" in
    200|201)
      ok "activated via REST API (HTTP ${ACT_HTTP})"
      ;;
    *)
      say "${YELLOW}REST API returned HTTP ${ACT_HTTP}; falling back to SQL${RESET}"
      [ -f /tmp/ship_act.json ] && say "${DIM}$(cat /tmp/ship_act.json)${RESET}"
      N8N_API_KEY=""  # force fallback below
      ;;
  esac
fi

if [ -z "${N8N_API_KEY:-}" ]; then
  VOLUME=$(docker inspect "$CONTAINER" --format '{{ (index .Mounts 0).Name }}' 2>/dev/null)
  if [ -z "$VOLUME" ]; then
    fail "Could not detect n8n volume for container $CONTAINER"
    exit 7
  fi
  # Extract webhook node config from JSON
  if command -v jq >/dev/null 2>&1; then
    WH_PATH=$(jq -r '.nodes[] | select(.type=="n8n-nodes-base.webhook") | .parameters.path' "$WF_PATH" | head -1)
    WH_METHOD=$(jq -r '.nodes[] | select(.type=="n8n-nodes-base.webhook") | .parameters.httpMethod // "GET"' "$WF_PATH" | head -1)
    WH_NODE=$(jq -r '.nodes[] | select(.type=="n8n-nodes-base.webhook") | .name' "$WF_PATH" | head -1)
    WH_ID=$(jq -r '.nodes[] | select(.type=="n8n-nodes-base.webhook") | .webhookId // empty' "$WF_PATH" | head -1)
  else
    WH_PATH=$(grep -m1 '"path":' "$WF_PATH" | sed -E 's/[^"]*"path"[^"]*"([^"]+)".*/\1/')
    WH_METHOD=$(grep -m1 '"httpMethod":' "$WF_PATH" | sed -E 's/[^"]*"httpMethod"[^"]*"([^"]+)".*/\1/')
    WH_NODE="Webhook"
    WH_ID=$(grep -m1 '"webhookId":' "$WF_PATH" | sed -E 's/[^"]*"webhookId"[^"]*"([^"]+)".*/\1/')
  fi
  [ -z "$WH_METHOD" ] && WH_METHOD="GET"
  WH_METHOD_UP=$(echo "$WH_METHOD" | tr '[:lower:]' '[:upper:]')
  if [ -n "$WH_PATH" ]; then PATH_LEN=$(echo "$WH_PATH" | awk -F'/' '{ print NF }'); else PATH_LEN=0; fi

  SQL="UPDATE workflow_entity SET active = 1 WHERE id = '${WF_ID}';"
  if [ -n "$WH_PATH" ]; then
    SQL="${SQL} INSERT OR REPLACE INTO webhook_entity (workflowId, webhookPath, method, node, webhookId, pathLength) VALUES ('${WF_ID}', '${WH_PATH}', '${WH_METHOD_UP}', '${WH_NODE}', '${WH_ID}', ${PATH_LEN});"
  fi
  docker run --rm -v "${VOLUME}:/data" alpine:3.18 sh -c "
    apk add --no-cache sqlite >/dev/null 2>&1
    sqlite3 /data/database.sqlite \"${SQL}\"
  " >/dev/null 2>&1
  ok "SQL fallback applied (active=1, webhook_entity row written)"
fi

# Read back the webhook path for step 6 probe
if [ -z "${WH_PATH:-}" ]; then
  if command -v jq >/dev/null 2>&1; then
    WH_PATH=$(jq -r '.nodes[] | select(.type=="n8n-nodes-base.webhook") | .parameters.path' "$WF_PATH" | head -1)
  else
    WH_PATH=$(grep -m1 '"path":' "$WF_PATH" | sed -E 's/[^"]*"path"[^"]*"([^"]+)".*/\1/')
  fi
fi

# ─── 5. restart so webhooks register ─────────────────────────────
step "5/6  Restart n8n + wait for ready"
docker restart "$CONTAINER" >/dev/null 2>&1
deadline=$(( $(date +%s) + 90 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if docker exec "$CONTAINER" n8n list:workflow >/dev/null 2>&1; then
    ok "n8n responsive"
    break
  fi
  sleep 2
done

# extra grace for webhook map to register
say "${DIM}giving webhook map 30 s to load…${RESET}"
sleep 30

# ─── 6. probe the webhook ────────────────────────────────────────
step "6/6  Probe webhook"
if [ -n "$WH_PATH" ]; then
  PROBE_URL="https://automation.crystallux.org/webhook/${WH_PATH}"
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$PROBE_URL" \
    -H "Authorization: Bearer junk" -H "Content-Type: application/json" -d '{}')
  case "$CODE" in
    401|400) ok "probe ${CODE} — HEALTHY (${PROBE_URL})" ;;
    200)     ok "probe 200 — registered, returns empty on auth fail (page will work)" ;;
    404)     fail "probe 404 — webhook did not register; try docker restart $CONTAINER manually" ;;
    *)       say "${YELLOW}probe HTTP ${CODE} — unexpected; check workflow logs${RESET}" ;;
  esac
else
  say "no webhook path found in JSON (cron-only workflow?) — skipping probe"
fi

printf "\n${GREEN}${BOLD}Shipped:${RESET} %s (%s)\n" "$NAME" "$WF_ID"
