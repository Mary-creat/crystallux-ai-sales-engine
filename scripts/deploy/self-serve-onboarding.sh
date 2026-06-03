#!/usr/bin/env bash
# Deploy the self-serve onboarding loop (paid auto-provision + free trial login).
# Run this ON THE VPS. Idempotent — safe to re-run.
#
#   N8N_API_KEY=xxx DATABASE_URL='postgres://...' bash scripts/deploy/self-serve-onboarding.sh
#
# - N8N_API_KEY : same key ship.sh uses (required).
# - DATABASE_URL: Supabase Postgres connection string (optional). If unset, the
#   script prints the two .sql files for you to paste into the Supabase SQL editor.
#
# After this runs, do the Stripe steps it prints at the end (paid path only).

set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
N8N_URL="${N8N_URL:-${CLX_N8N_PUBLIC_URL:-https://automation.crystallux.org}}"
: "${N8N_API_KEY:?Set N8N_API_KEY first (same key ship.sh uses)}"

MIGRATIONS=(
  "db/migrations/auto-provision-paid-buyer.sql"
  "db/migrations/provision-trial-signup.sql"
)
# workflow file | n8n id (to activate)
WORKFLOWS=(
  "clx-stripe-provision-on-payment-v1.json|wfStripeProvisionOnPaymentV1"
  "clx-public-client-signup-v1.json|wfPublicClientSignup"
)

echo "=============================================================="
echo " Deploying self-serve onboarding  (n8n: $N8N_URL)"
echo "=============================================================="

echo; echo "1) Latest code"
git pull --ff-only origin main || echo "  (skip git pull — resolve manually if needed)"

echo; echo "2) Database migrations"
if [ -n "${DATABASE_URL:-}" ]; then
  for m in "${MIGRATIONS[@]}"; do
    echo "   applying $m"
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$m" && echo "   [+] ok" || echo "   [x] FAILED: $m"
  done
else
  echo "   DATABASE_URL not set — paste these two files into the Supabase SQL editor and Run:"
  for m in "${MIGRATIONS[@]}"; do echo "     - $m"; done
fi

echo; echo "3) Ship workflows"
for row in "${WORKFLOWS[@]}"; do
  wf="${row%%|*}"
  echo "   $wf"
  N8N_API_KEY="$N8N_API_KEY" bash scripts/n8n/ship.sh --branch main "$wf" || echo "   [x] ship failed: $wf"
done

echo; echo "4) Activate webhooks"
for row in "${WORKFLOWS[@]}"; do
  id="${row#*|}"
  code=$(curl -s -o /tmp/clx_sso.json -w "%{http_code}" -X POST \
    -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$id/activate")
  if [ "$code" = "200" ]; then echo "   [+] ON: $id"
  else echo "   [x] HTTP $code: $id  $(head -c 140 /tmp/clx_sso.json | tr -d '\n')"; fi
done

echo; echo "5) Restart n8n (so the new public/stripe/provision webhook registers)"
docker restart n8n >/dev/null 2>&1 && echo "   [+] n8n restarted" || echo "   (restart n8n manually if not docker)"

echo
echo "=============================================================="
echo " Done. Manual Stripe step (PAID path only — do in Stripe dashboard):"
echo "   a) Developers -> Webhooks -> Add endpoint:"
echo "        $N8N_URL/webhook/public/stripe/provision"
echo "      event: checkout.session.completed"
echo "   b) Each Payment Link -> Metadata -> product = sales_engine | sentinel | ..."
echo
echo " Test: submit the signup form -> 'set your password' email -> log in."
echo "=============================================================="
