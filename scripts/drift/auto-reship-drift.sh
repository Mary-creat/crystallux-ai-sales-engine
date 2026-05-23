#!/usr/bin/env bash
# scripts/drift/auto-reship-drift.sh
#
# Self-healing 2/4: when the drift detector finds content_diff
# workflows, this re-ships the repo version via ship.sh.
#
# Safety: by default, only re-ships workflows that have NO recent UI
# changes (you can edit a workflow in n8n UI temporarily — we don't
# want to clobber that without warning).
#
# Usage:
#   bash scripts/drift/auto-reship-drift.sh           # interactive prompt
#   bash scripts/drift/auto-reship-drift.sh --force   # ship without prompting
#   bash scripts/drift/auto-reship-drift.sh --dry-run # list what would ship
#
# Reads from the latest workflow_drift findings in Supabase, filtered
# to content_diff. Requires SUPABASE_SERVICE_KEY env var.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "${SCRIPT_DIR}/../.." && pwd )"
SHIP_SH="${REPO_ROOT}/scripts/n8n/ship.sh"
SUPABASE_URL="${SUPABASE_URL:-https://zqwatouqmqgkmaslydbr.supabase.co}"

dry_run=0
force=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    --force)   force=1   ;;
  esac
done

if [ -z "${SUPABASE_SERVICE_KEY:-}" ]; then
  echo "SUPABASE_SERVICE_KEY not set. Export it before running:"
  echo "  export SUPABASE_SERVICE_KEY=\"...\""
  exit 2
fi

if [ ! -f "$SHIP_SH" ]; then
  echo "ship.sh not found at $SHIP_SH"
  exit 2
fi

# Fetch latest content_diff findings — workflow_id + repo_path
echo "Fetching latest content_diff findings from Supabase..."
findings_json=$(curl -s \
  -H "apikey: $SUPABASE_SERVICE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
  "$SUPABASE_URL/rest/v1/workflow_drift?drift_type=eq.content_diff&resolved_at=is.null&select=workflow_id,workflow_name,repo_path&order=detected_at.desc&limit=200")

if [ -z "$findings_json" ] || [ "$findings_json" = "[]" ]; then
  echo "No content_diff findings to reconcile. Drift is clean or detector hasn't run."
  exit 0
fi

# Parse into filename list. Drop entries with NULL repo_path (cannot ship).
mapfile -t files < <(echo "$findings_json" | python3 -c "
import json, os, sys
data = json.load(sys.stdin)
seen = set()
for f in data:
    p = f.get('repo_path')
    if not p or p in seen: continue
    seen.add(p)
    print(os.path.basename(p))
")

n=${#files[@]}
if [ "$n" -eq 0 ]; then
  echo "No actionable findings (all entries lack repo_path)."
  exit 0
fi

echo
echo "Will re-ship $n workflow(s) where repo and n8n diverged:"
for f in "${files[@]}"; do echo "  - $f"; done
echo

if [ "$dry_run" -eq 1 ]; then
  echo "DRY-RUN: no ships executed."
  exit 0
fi

if [ "$force" -ne 1 ]; then
  read -r -p "Re-ship all $n? (yes/no): " ans
  case "${ans,,}" in
    y|yes) ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

i=0
fails=0
for f in "${files[@]}"; do
  i=$((i + 1))
  printf "\n==== [%d/%d] %s ====\n" "$i" "$n" "$f"
  if ! bash "$SHIP_SH" "$f"; then
    fails=$((fails + 1))
    printf "  WARN: ship failed for %s\n" "$f"
  fi
done

printf "\n==== Done. %d/%d succeeded, %d failed ====\n" "$((n - fails))" "$n" "$fails"

if [ "$fails" -eq 0 ]; then
  echo "Re-run the drift detector to confirm content_diff drops:"
  echo "  python3 scripts/drift/detect-workflow-drift.py --dry-run"
fi

exit $fails
