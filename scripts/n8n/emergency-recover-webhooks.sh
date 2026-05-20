#!/usr/bin/env bash
# scripts/n8n/emergency-recover-webhooks.sh
#
# ONE COMMAND to recover from the webhook_entity blockage Mary hit
# on 2026-05-19. Works without any of:
#   - n8n API key
#   - sqlite3 in the n8n container
#   - n8n CLI delete:workflow
#
# It uses an Alpine sidecar container (with sqlite3 installed at
# runtime) and the n8n data volume mounted directly. The script:
#   1. git pull (unless --no-pull)
#   2. Hands off to emergency-recover-webhooks.py which:
#      - stops n8n container
#      - sidecar-deletes duplicate workflow rows
#      - starts n8n
#      - imports any missing canonical workflows
#      - activates every workflow requested via folder args
#      - probes each webhook endpoint
#
# Default targets: all 9 folders that had the autounwrap + dedupe
# fallout (admin, carriers, sentinel, training, briefing, completeness,
# supervisor, reports, content). Override by passing your own folder
# list.
#
# Estimated downtime: 10-20 seconds while n8n restarts.

set -euo pipefail
cd "$(dirname "$0")/../.."

BRANCH="${CLX_BRANCH:-scale-sprint-v1}"
PULL=1
PY_ARGS=()

DEFAULT_FOLDERS=(
  workflows/api/admin/
  workflows/api/carriers/
  workflows/api/sentinel/
  workflows/api/training/
  workflows/api/briefing/
  workflows/api/completeness/
  workflows/api/supervisor/
  workflows/api/reports/
  workflows/api/content/
)

# Parse our own --no-pull / --branch=, pass everything else through.
HAS_FOLDER=0
for arg in "$@"; do
  case "$arg" in
    --no-pull)
      PULL=0
      ;;
    --branch=*)
      BRANCH="${arg#--branch=}"
      ;;
    --*)
      PY_ARGS+=("$arg")
      ;;
    *)
      PY_ARGS+=("$arg")
      HAS_FOLDER=1
      ;;
  esac
done

# If no folder positional args passed, use the defaults.
if [[ "$HAS_FOLDER" = "0" ]]; then
  PY_ARGS+=("${DEFAULT_FOLDERS[@]}")
fi

if [[ "$PULL" = "1" ]]; then
  echo "============================================================"
  echo " git pull origin ${BRANCH}"
  echo "============================================================"
  git pull origin "$BRANCH"
  echo
fi

exec python3 scripts/n8n/emergency-recover-webhooks.py "${PY_ARGS[@]}"
