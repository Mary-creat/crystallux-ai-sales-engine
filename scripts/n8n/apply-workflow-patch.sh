#!/usr/bin/env bash
# scripts/n8n/apply-workflow-patch.sh
#
# Apply every workflow JSON in a folder to the live n8n. Replaces
# manual UI Import-from-File for batches of patched workflows.
#
# Usage:
#   bash scripts/n8n/apply-workflow-patch.sh workflows/api/carriers/
#
# Flags (all passed through to apply-workflow-patch.py):
#   --dry-run        Show actions without touching the container.
#   --no-restart     Skip docker restart (use if iterating quickly).
#   --no-probe       Skip the curl smoke test.
#   --no-pull        Skip the `git pull` at the start.
#   --container=X    Override container name (default: n8n)
#   --db-path=X      Override SQLite DB path inside container.
#   --base=URL       Override webhook base URL for probing.
#
# Examples (the 5 commands for commit 486831d):
#   bash scripts/n8n/apply-workflow-patch.sh workflows/api/carriers/
#   bash scripts/n8n/apply-workflow-patch.sh workflows/api/sentinel/
#   bash scripts/n8n/apply-workflow-patch.sh workflows/api/training/
#   bash scripts/n8n/apply-workflow-patch.sh workflows/api/briefing/
#   bash scripts/n8n/apply-workflow-patch.sh workflows/api/completeness/
#
# Designed to run on the n8n VPS host. Requires: bash, python3, curl,
# docker, the n8n container running.

set -euo pipefail
cd "$(dirname "$0")/../.."

BRANCH="${CLX_BRANCH:-scale-sprint-v1}"
PULL=1
ARGS=()

for arg in "$@"; do
  case "$arg" in
    --no-pull)
      PULL=0
      ;;
    --branch=*)
      BRANCH="${arg#--branch=}"
      ;;
    *)
      ARGS+=("$arg")
      ;;
  esac
done

if [[ ${#ARGS[@]} -lt 1 || "${ARGS[0]}" = "-h" || "${ARGS[0]}" = "--help" ]]; then
  sed -n '2,30p' "$0"
  exit 2
fi

if [[ "$PULL" = "1" ]]; then
  echo "============================================================"
  echo " git pull origin ${BRANCH}"
  echo "============================================================"
  git pull origin "$BRANCH"
  echo
fi

# Hand off to the Python helper. exec so its exit code is ours.
exec python3 scripts/n8n/apply-workflow-patch.py "${ARGS[@]}"
