#!/usr/bin/env bash
# scripts/n8n/probe-admin.sh
#
# Quick health probe of critical admin endpoints. Returns the HTTP
# response code for each path so you can see at a glance whether the
# webhook is registered and routing correctly.
#
# Expected response codes:
#   401  = healthy, auth gate working (rejects junk Bearer)
#   400  = healthy, input-validation gate working
#   200  = registered, workflow ran (may have returned empty body)
#   404  = NOT registered, real problem
#
# Usage:
#   bash scripts/n8n/probe-admin.sh
#
# Env overrides:
#   CLX_WEBHOOK_BASE   default: https://automation.crystallux.org/webhook

BASE="${CLX_WEBHOOK_BASE:-https://automation.crystallux.org/webhook}"

ENDPOINTS=(
  "admin/list-leads"
  "admin/list-clients"
  "admin/client-detail"
  "admin/system-health"
  "admin/workflow-status"
  "admin/billing-summary"
  "admin/audit-log"
  "admin/comms-log"
  "admin/market-intelligence"
  "admin/onboarding-pipeline"
  "admin/smart-quote/list"
  "admin/smart-quote/flow"
  "admin/avatar-content/list"
  "admin/avatar-schedule"
  "admin/luxi/auctions"
  "admin/ciro/alerts"
  "maxi/industries"
  "avatars/list"
  "avatars/route"
  "public/quote/fetch"
  "public/mga/apply"
)

echo "Probing $BASE/* with junk Bearer (so HEALTHY = 401 or 400)"
echo "---"

healthy=0
empty200=0
notfound=0
other=0

for ep in "${ENDPOINTS[@]}"; do
  code=$(curl -so /dev/null -w "%{http_code}" -X POST \
    "$BASE/$ep" \
    -H "Authorization: Bearer junk" \
    -H "Content-Type: application/json" \
    -d '{}')
  case "$code" in
    401|400) printf "  %s  %-40s  HEALTHY\n"   "$code" "$ep"; ((healthy++)) ;;
    200)     printf "  %s  %-40s  EMPTY-200\n" "$code" "$ep"; ((empty200++)) ;;
    404)     printf "  %s  %-40s  NOT-FOUND\n" "$code" "$ep"; ((notfound++)) ;;
    *)       printf "  %s  %-40s  HTTP-%s\n"   "$code" "$ep" "$code"; ((other++)) ;;
  esac
done

echo "---"
echo "Healthy: $healthy  Empty-200: $empty200  Not-Found: $notfound  Other: $other"
if [ "$notfound" -eq 0 ]; then
  echo "ALL CLEAR — every endpoint is reachable."
else
  echo "WARNING — $notfound endpoint(s) returned 404"
fi
