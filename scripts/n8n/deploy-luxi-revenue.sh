#!/usr/bin/env bash
# One-shot deploy of the 2026-05-30 batch: LUXI (Buy Now / auto-bid / web bidding /
# streaming) + revenue checkout + import-leads fix + auth workflows.
#
# Run on the VPS:  bash scripts/n8n/deploy-luxi-revenue.sh
# Ships each workflow to live n8n via the existing ship.sh (import/update +
# activate + restart + probe). Continues past any single failure and prints a
# summary at the end so you can see exactly what landed.

set -uo pipefail

WORKFLOWS=(
  clx-admin-bulk-import-leads-v1.json
  clx-admin-luxi-auction-manage-v1.json
  clx-admin-luxi-auctions-list-v1.json
  clx-admin-luxi-buy-now-v1.json
  clx-admin-luxi-proxy-bid-v1.json
  clx-admin-luxi-stream-manage-v1.json
  clx-luxi-auction-tick-v1.json
  clx-luxi-proxy-settle-v1.json
  clx-luxi-public-auction-v1.json
  clx-luxi-public-create-intent-v1.json
  clx-luxi-public-confirm-bid-v1.json
  clx-luxi-public-buy-now-intent-v1.json
  clx-luxi-public-buy-now-confirm-v1.json
  clx-luxi-public-stream-v1.json
  clx-public-checkout-v1.json
  clx-public-checkout-complete-v1.json
  clx-auth-validate-session.json
  clx-auth-magic-link-verify.json
  clx-auth-resend-verification-v1.json
  clx-stripe-webhook-v1.json
)

total=${#WORKFLOWS[@]}
ok=0
fail=0
failed_list=""
i=0

echo "================================================================"
echo "Deploying $total workflows to live n8n. This restarts n8n after"
echo "each one, so it takes ~20-30 min. Let it run; don't close the window."
echo "================================================================"

for wf in "${WORKFLOWS[@]}"; do
  i=$((i+1))
  echo ""
  echo "############## [$i/$total] $wf ##############"
  if bash scripts/n8n/ship.sh --branch main "$wf"; then
    ok=$((ok+1))
  else
    fail=$((fail+1))
    failed_list="$failed_list $wf"
  fi
done

echo ""
echo "================================================================"
echo "DONE.  shipped OK: $ok / $total     failed: $fail"
if [ "$fail" -gt 0 ]; then
  echo "Failed workflows:$failed_list"
  echo "(Re-run this script — it's safe — or paste this summary to Claude.)"
fi
echo "================================================================"
