#!/usr/bin/env bash
# OPEN EVERYTHING — one command to switch on the full engine.
# Activate-only, by id, idempotent. No workflow definitions are changed, so the
# 7 protected production workflows are untouched. Run on the VPS:
#
#   N8N_API_KEY=yourkey bash scripts/n8n/activate-all.sh
#
# What it turns on:
#   * Sales engine (discovery -> research -> scoring -> router -> outreach -> pipeline -> replies -> booking)
#   * Admin backends (avatars, AVA, onboarding pipeline, market intelligence, MCP, overviews)
#   * Stripe lifecycle webhook (cancellations / failed payments -> suspend)
#   * Self-serve onboarding (pay -> provision, signup -> trial login)

set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
N8N_URL="${N8N_URL:-${CLX_N8N_PUBLIC_URL:-https://automation.crystallux.org}}"
: "${N8N_API_KEY:?Set N8N_API_KEY first (same key ship.sh uses)}"
export N8N_API_KEY N8N_URL

echo "################################################################"
echo "#  OPEN EVERYTHING — full engine activation"
echo "################################################################"

bash "$DIR/activate-sales-engine.sh"
echo
bash "$DIR/activate-admin.sh"

echo
echo "=== Auth (login, magic link, password reset, verification) ==="
AUTH=(
  "clxAuthLoginV1|Login"
  "clxAuthMagicLinkV1|Magic-link request (sends sign-in email)"
  "clxAuthMagicLinkVerifyV1|Magic-link verify"
  "clxAuthPasswordResetRequestV1|Password-reset request (sends set-password email)"
  "clxAuthPasswordResetCompleteV1|Password-reset complete"
  "clxAuthResendVerificationV1|Resend verification"
  "clxEmailSendPostmark|Email send (Postmark) sub-workflow"
)
for row in "${AUTH[@]}"; do
  id="${row%%|*}"; label="${row#*|}"
  code=$(curl -s -o /tmp/clx_all.json -w "%{http_code}" -X POST \
    -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$id/activate")
  if [ "$code" = "200" ]; then echo "  [+] ON:        $label"
  else echo "  [x] HTTP $code:  $label   $(head -c 140 /tmp/clx_all.json | tr -d '\n')"; fi
done

echo
echo "=== Stripe + self-serve onboarding ==="
EXTRAS=(
  "clx-stripe-webhook-v1|Stripe lifecycle (cancels / failed payments)"
  "wfStripeProvisionOnPaymentV1|Pay -> auto-provision + login email"
  "wfPublicClientSignup|Signup form -> trial login"
)
for row in "${EXTRAS[@]}"; do
  id="${row%%|*}"; label="${row#*|}"
  code=$(curl -s -o /tmp/clx_all.json -w "%{http_code}" -X POST \
    -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$id/activate")
  if [ "$code" = "200" ]; then echo "  [+] ON:        $label"
  else echo "  [x] HTTP $code:  $label   $(head -c 140 /tmp/clx_all.json | tr -d '\n')"; fi
done

echo
echo "################################################################"
echo "# Engine is open. Leads will appear in the dashboard on schedule."
echo "#"
echo "# ONE thing still needed for outreach to actually SEND to leads:"
echo "#   connect the 'Gmail' OAuth credential in n8n (Credentials -> Gmail"
echo "#   -> Connect / sign in with your Google account). Until then leads are"
echo "#   found + scored but no emails go out."
echo "################################################################"
