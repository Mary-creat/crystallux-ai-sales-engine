#!/usr/bin/env bash
# scripts/n8n/ship-today.sh
#
# Ships every workflow built or modified in today's session. Run after
# git pull to bring the live n8n in sync with the repo, then re-run
# drift detection — should drop content_diff substantially.
#
# Pass --branch <name> to ship from a non-main branch (e.g. before merge):
#   bash scripts/n8n/ship-today.sh --branch scale-sprint-v1

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Pass-through for ship.sh's --branch flag.
SHIP_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --branch)     SHIP_ARGS+=( --branch "$2" ); shift 2 ;;
    --branch=*)   SHIP_ARGS+=( "$1" );          shift ;;
    *)            break ;;
  esac
done

FILES=(
  # New admin endpoints
  clx-admin-sales-engine-activity-v1.json
  clx-admin-sentinel-comms-health-v1.json
  clx-admin-market-intelligence-v1.json

  # Chat platform (v3 has write-action confirmation gate added; history is new)
  clx-admin-chat-v3.json
  clx-admin-chat-history-v1.json

  # Digital employees
  clx-devops-daily-briefing-v1.json
  clx-coo-weekly-review-v1.json

  # Self-healing + observability
  clx-sentinel-webhook-health-probe-v1.json
  clx-admin-workflow-drift-v1.json
  clx-sentinel-vendor-health-monitor-v1.json
  clx-sentinel-outreach-retry-v1.json
)

total="${#FILES[@]}"
i=0
fails=0

for f in "${FILES[@]}"; do
  i=$((i + 1))
  printf "\n==== [%d/%d] %s ====\n" "$i" "$total" "$f"
  # ${arr[@]+...} guard keeps set -u happy when SHIP_ARGS is empty (older bash).
  if ! bash "${SCRIPT_DIR}/ship.sh" ${SHIP_ARGS[@]+"${SHIP_ARGS[@]}"} "$f"; then
    fails=$((fails + 1))
    printf "  WARN: ship failed for %s\n" "$f"
  fi
done

printf "\n==== Done. %d/%d succeeded, %d failed ====\n" "$((total - fails))" "$total" "$fails"
exit $fails
