#!/usr/bin/env bash
# Crystallux smoke test — exercises every key URL across the 7 deployed
# domains, plus content markers that prove the latest commit is live and
# that critical webhooks reach the auth gate (not an n8n 500 page).
#
# Usage:
#   bash tests/audit/smoke-domains.sh           # full run
#   bash tests/audit/smoke-domains.sh deploy    # just the deploy-marker check
#   bash tests/audit/smoke-domains.sh n8n       # just the webhook probes
#
# Exits non-zero if any check fails. Designed for a fresh terminal and
# `curl` only — no Node, no other deps.

set -u

PASS=0
FAIL=0
WARN=0

pass()  { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail()  { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }
warn()  { printf "  \033[33m!\033[0m %s\n" "$1"; WARN=$((WARN+1)); }
head()  { printf "\n\033[1m== %s ==\033[0m\n" "$1"; }

# --------- URL check: expect a specific HTTP status ----------
check_http() {
  local url="$1" expected="$2" label="${3:-$url}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$url" || echo "000")
  if [ "$code" = "$expected" ]; then
    pass "$label → $code"
  else
    fail "$label → $code (expected $expected)"
  fi
}

# --------- URL check: HTTP 200 AND body matches a regex ----------
check_content() {
  local url="$1" pattern="$2" label="${3:-$url}"
  local body
  body=$(curl -s --max-time 15 "$url" || echo "")
  if echo "$body" | grep -qE "$pattern"; then
    pass "$label contains /$pattern/"
  else
    fail "$label MISSING /$pattern/"
  fi
}

# --------- Webhook probe: POST with Origin, expect specific status ----------
check_webhook() {
  local url="$1" expected="$2" label="${3:-$url}" origin="${4:-https://admin.crystallux.org}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
    -X POST -H "Content-Type: application/json" -H "Origin: $origin" \
    "$url" -d '{}' || echo "000")
  if [ "$code" = "$expected" ]; then
    pass "$label → $code"
  else
    fail "$label → $code (expected $expected)"
  fi
}

MODE="${1:-all}"

# ════════════════════════════════════════════════════════════════════════
# 1. Deploy marker — does live admin/client auth.js contain the array fix?
# ════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "all" ] || [ "$MODE" = "deploy" ]; then
  head "Deploy marker (commit 1c41a4b — auth.js array fix)"
  check_content "https://admin.crystallux.org/shared/auth.js" "Role inventory" "admin auth.js has Role inventory comment"
  check_content "https://admin.crystallux.org/shared/auth.js" "allowed\.indexOf" "admin auth.js uses indexOf check"
  check_content "https://app.crystallux.org/shared/auth.js"   "allowed\.indexOf" "client auth.js uses indexOf check"
fi

# ════════════════════════════════════════════════════════════════════════
# 2. admin.crystallux.org pages — each should serve sentinel/carrier/etc.
#    title, not the bootstrap title "Crystallux Admin".
# ════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "all" ] || [ "$MODE" = "admin" ]; then
  head "admin.crystallux.org pages"
  check_http    "https://admin.crystallux.org/"                       "200" "/"
  check_content "https://admin.crystallux.org/pages/sentinel"         "Sentinel · Crystallux"     "/pages/sentinel"
  check_content "https://admin.crystallux.org/pages/carriers/overview" "Carriers"                 "/pages/carriers/overview"
  check_content "https://admin.crystallux.org/pages/carriers/appointments" "Carrier appointments|Appointments" "/pages/carriers/appointments"
  check_content "https://admin.crystallux.org/pages/carriers/submissions"  "Submissions"          "/pages/carriers/submissions"
  check_content "https://admin.crystallux.org/pages/carriers/commissions"  "Commissions"          "/pages/carriers/commissions"
  check_content "https://admin.crystallux.org/pages/carriers/reconciliation" "Reconciliation"     "/pages/carriers/reconciliation"
  check_content "https://admin.crystallux.org/pages/new-client"      "New client"                 "/pages/new-client (stub)"
  check_content "https://admin.crystallux.org/pages/saas-onboarding" "SaaS onboarding"            "/pages/saas-onboarding (stub)"
  check_content "https://admin.crystallux.org/pages/clients/onboarding" "Client onboarding"       "/pages/clients/onboarding (stub)"
fi

# ════════════════════════════════════════════════════════════════════════
# 3. MGA dashboard reachability
# ════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "all" ] || [ "$MODE" = "mga" ]; then
  head "mga.crystallux.org pages"
  check_content "https://mga.crystallux.org/advisor/onboarding"   "30-Day Onboarding"   "advisor/onboarding"
  check_content "https://mga.crystallux.org/principal/carriers"   "Carriers"            "principal/carriers"
  check_content "https://mga.crystallux.org/advisor/overview"     "Crystallux"          "advisor/overview"
fi

# ════════════════════════════════════════════════════════════════════════
# 4. n8n webhook reachability — these MUST return 401 (no token), NOT
#    HTTP 500 (n8n internal error) or 404 (webhook not registered).
#    A 401 proves: workflow active + reaches the auth gate.
# ════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "all" ] || [ "$MODE" = "n8n" ]; then
  head "n8n webhooks (expect 401 = auth-gated and reachable)"
  check_webhook "https://automation.crystallux.org/webhook/auth/validate-session"           "401" "validate-session"
  check_webhook "https://automation.crystallux.org/webhook/mga/insurance/onboarding-status" "401" "mga/onboarding-status" "https://mga.crystallux.org"
  check_webhook "https://automation.crystallux.org/webhook/mga/insurance/carriers-list"     "401" "mga/carriers-list"      "https://mga.crystallux.org"
fi

# ════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════
echo
echo "────────────────────────────────────────────"
printf "Results: \033[32m%d pass\033[0m" "$PASS"
[ "$WARN" -gt 0 ] && printf "  \033[33m%d warn\033[0m" "$WARN"
[ "$FAIL" -gt 0 ] && printf "  \033[31m%d fail\033[0m" "$FAIL"
echo
echo "────────────────────────────────────────────"

if [ "$FAIL" -gt 0 ]; then
  echo "See docs/audit/blockers.md (0g, 0h, 0i) for likely causes."
  exit 1
fi
exit 0
