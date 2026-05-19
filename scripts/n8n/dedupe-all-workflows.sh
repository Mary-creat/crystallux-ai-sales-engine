#!/usr/bin/env bash
# scripts/n8n/dedupe-all-workflows.sh
#
# Thin ergonomic wrapper around dedupe-workflows.py for Mary to run on
# the n8n VPS host. All real logic lives in the Python script — this
# wrapper just sequences the phases and prompts for confirmation
# between destructive steps.
#
# Run:   ./scripts/n8n/dedupe-all-workflows.sh
# Force: NO_PROMPT=1 ./scripts/n8n/dedupe-all-workflows.sh   # skip Y/N
#
# Requirements: docker, python3, n8n container running.

set -euo pipefail

cd "$(dirname "$0")/../.."
SCRIPT="scripts/n8n/dedupe-workflows.py"
PLAN_OUT="/tmp/dedupe-plan-$(date +%Y%m%d-%H%M%S).md"

if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT not found. Run from the repo root."
  exit 1
fi

confirm() {
  if [[ "${NO_PROMPT:-0}" = "1" ]]; then
    return 0
  fi
  read -rp "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

echo "=========================================="
echo " Phase 1/4: AUDIT (read-only)"
echo "=========================================="
python3 "$SCRIPT" --phase=audit | tee "$PLAN_OUT"
echo
echo "Plan saved to: $PLAN_OUT"
echo

confirm "Proceed to DEACTIVATE all duplicates?" || { echo "Stopped."; exit 0; }

echo
echo "=========================================="
echo " Phase 2/4: DEACTIVATE duplicates"
echo "=========================================="
python3 "$SCRIPT" --phase=deactivate

echo
echo "Soaking for 30s (let webhook cache settle, check pages still respond)..."
sleep 30

confirm "Proceed to HARD-DELETE duplicate rows? (DESTRUCTIVE)" || {
  echo "Stopped after deactivation. Duplicates are inactive but rows remain."
  echo "Run later with: python3 $SCRIPT --phase=delete --confirm-destructive"
  exit 0
}

echo
echo "=========================================="
echo " Phase 3/4: DELETE duplicate rows"
echo "=========================================="
python3 "$SCRIPT" --phase=delete --confirm-destructive

echo
echo "Restarting n8n to clear in-memory webhook cache..."
docker restart n8n
sleep 10

echo
echo "=========================================="
echo " Phase 4/4: VERIFY"
echo "=========================================="
python3 "$SCRIPT" --phase=verify

echo
echo "Done. Next: UI Import-from-File the canonical JSONs listed in the plan ($PLAN_OUT)."
echo "After re-import, re-run the webhook audit to confirm rows flip to HEALTHY:"
echo "  python3 scripts/n8n/audit-webhook-endpoints.py > docs/audit/WEBHOOK_INVENTORY.md"
