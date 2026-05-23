#!/usr/bin/env bash
# scripts/n8n/deploy-postmark-ingestion.sh
#
# One-shot deploy for the Postmark webhook ingestion feature.
# Idempotent — safe to re-run. Performs:
#
#   1. Bring /tmp/clx-latest onto the requested branch (default
#      scale-sprint-v1) and pull.
#   2. Apply db/migrations/email-events-schema.sql to Supabase.
#      Migration is idempotent (CREATE TABLE IF NOT EXISTS + DO blocks).
#   3. Ensure POSTMARK_WEBHOOK_TOKEN exists in /opt/n8n/.env. Generates
#      a fresh 32-byte hex token if absent. Preserves the existing
#      token on re-run.
#   4. Ship clx-webhook-postmark-events-v1.json (new — CLI import path).
#   5. Ship clx-admin-sentinel-comms-health-v1.json (REST PUT update —
#      it's already on n8n).
#   6. Smoke-test by querying email_events for any rows. Prints the
#      Postmark UI configuration the operator still needs to do by hand.
#
# Usage:
#   bash scripts/n8n/deploy-postmark-ingestion.sh
#   bash scripts/n8n/deploy-postmark-ingestion.sh --branch main
#
# Env it needs (must already be set on the VPS):
#   DATABASE_URL        Supabase Postgres URL for psql
#   N8N_API_KEY         REST PUT for the existing comms-health workflow
#   POSTMARK_WEBHOOK_TOKEN  (optional) skip generation if you already have one
#
# Env it sets (writes to /opt/n8n/.env):
#   POSTMARK_WEBHOOK_TOKEN  — only if absent. Re-runs preserve it.

set -uo pipefail

# ─── settings ────────────────────────────────────────────────────
REPO="${CLX_REPO:-/tmp/clx-latest}"
BRANCH="${CLX_BRANCH:-scale-sprint-v1}"
CONTAINER="${CLX_N8N_CONTAINER:-n8n}"
MIGRATION="db/migrations/email-events-schema.sql"
RECEIVER_WF="clx-webhook-postmark-events-v1.json"
COMMS_WF="clx-admin-sentinel-comms-health-v1.json"

# Auto-detect the n8n env file location. Different operators put it in
# different places (/opt/n8n on stock installs, /root/crystallux/n8n on
# Mary's VPS, /etc/crystallux on hardened setups). First path that exists
# wins; CLX_N8N_ENV overrides everything.
detect_env_file() {
  if [ -n "${CLX_N8N_ENV:-}" ] && [ -r "$CLX_N8N_ENV" ]; then echo "$CLX_N8N_ENV"; return; fi
  for candidate in \
    "/root/crystallux/n8n/.env" \
    "/opt/n8n/.env" \
    "/opt/crystallux/n8n/.env" \
    "/etc/crystallux/.env" \
    "$HOME/.crystallux/.env"; do
    if [ -r "$candidate" ]; then echo "$candidate"; return; fi
  done
  # Nothing readable — return the CLX_N8N_ENV override if set, else the
  # most-likely default. The preflight will error with a clear message.
  echo "${CLX_N8N_ENV:-/opt/n8n/.env}"
}
N8N_ENV_FILE="$(detect_env_file)"

# ─── arg parsing ─────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --branch)   BRANCH="$2"; shift 2 ;;
    --branch=*) BRANCH="${1#--branch=}"; shift ;;
    -h|--help)
      sed -n '1,40p' "$0"; exit 0 ;;
    *)
      printf "unknown arg: %s\n" "$1" >&2; exit 2 ;;
  esac
done

# ─── pretty output ───────────────────────────────────────────────
GREEN=$'\033[32m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

say()  { printf "  %s\n" "$*"; }
ok()   { printf "  ${GREEN}\xe2\x9c\x93${RESET} %s\n" "$*"; }
fail() { printf "  ${RED}\xe2\x9c\x97${RESET} %s\n" "$*" >&2; }
warn() { printf "  ${YELLOW}!${RESET} %s\n" "$*"; }
step() { printf "\n${BOLD}%s${RESET}\n" "$*"; }

# ─── preflight ───────────────────────────────────────────────────
step "0/6  Preflight"
[ -d "$REPO" ] || { fail "Repo not at $REPO (override with CLX_REPO)"; exit 3; }

# DATABASE_URL + N8N_API_KEY usually live in /opt/n8n/.env on the VPS,
# not in the SSH shell. If they're not exported, source them from the
# env file before failing the preflight. Bash uses `set -a` to export
# every var the sourced file defines.
if [ -z "${DATABASE_URL:-}" ] || [ -z "${N8N_API_KEY:-}" ]; then
  if [ -r "$N8N_ENV_FILE" ]; then
    say "${DIM}sourcing $N8N_ENV_FILE for DATABASE_URL + N8N_API_KEY${RESET}"
    set -a
    # shellcheck disable=SC1090
    . "$N8N_ENV_FILE"
    set +a
  fi
fi

[ -n "${DATABASE_URL:-}" ] || { fail "DATABASE_URL not set (not in shell, not in $N8N_ENV_FILE)"; exit 3; }
[ -n "${N8N_API_KEY:-}" ]  || warn "N8N_API_KEY not set — ship.sh will fall back to SQL activation"
command -v psql       >/dev/null || { fail "psql not on PATH"; exit 3; }
command -v docker     >/dev/null || { fail "docker not on PATH"; exit 3; }
command -v openssl    >/dev/null || { fail "openssl not on PATH (needed to generate token)"; exit 3; }
ok "repo=$REPO  branch=$BRANCH  n8n_env=$N8N_ENV_FILE  container=$CONTAINER"

# ─── 1. bring repo onto branch ───────────────────────────────────
step "1/6  Sync repo to ${BRANCH}"
cd "$REPO" || { fail "cd $REPO failed"; exit 3; }
git fetch origin "$BRANCH" --quiet || { fail "git fetch failed"; exit 4; }
CURRENT=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [ "$CURRENT" != "$BRANCH" ]; then
  git checkout "$BRANCH" --quiet || { fail "git checkout $BRANCH failed (uncommitted changes?)"; exit 4; }
fi
git pull origin "$BRANCH" --quiet || { fail "git pull failed"; exit 4; }
HEAD_SHA=$(git rev-parse --short HEAD)
ok "on $BRANCH @ $HEAD_SHA"

# Confirm the deploy targets actually exist on this branch
[ -f "$MIGRATION" ] || { fail "$MIGRATION missing on branch $BRANCH"; exit 5; }
RECEIVER_PATH=$(find workflows -name "$RECEIVER_WF" -type f 2>/dev/null | head -1)
COMMS_PATH=$(find workflows -name "$COMMS_WF" -type f 2>/dev/null | head -1)
[ -n "$RECEIVER_PATH" ] || { fail "$RECEIVER_WF missing on branch $BRANCH"; exit 5; }
[ -n "$COMMS_PATH" ]    || { fail "$COMMS_WF missing on branch $BRANCH"; exit 5; }
ok "deploy targets present"

# ─── 2. apply migration (idempotent) ─────────────────────────────
step "2/6  Apply migration: $MIGRATION"
MIG_OUT=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$MIGRATION" 2>&1)
MIG_RC=$?
if [ $MIG_RC -ne 0 ]; then
  fail "psql failed (rc=$MIG_RC):"
  printf "%s\n" "$MIG_OUT" | sed 's/^/    /'
  exit 6
fi
# Sanity: confirm the table is there
EXISTS=$(psql "$DATABASE_URL" -tAc "SELECT to_regclass('public.email_events') IS NOT NULL;" 2>/dev/null | tr -d '[:space:]')
if [ "$EXISTS" = "t" ]; then
  ok "email_events present"
else
  fail "email_events NOT present after migration — check psql output above"
  exit 6
fi

# ─── 3. ensure POSTMARK_WEBHOOK_TOKEN in env ─────────────────────
step "3/6  Ensure POSTMARK_WEBHOOK_TOKEN in $N8N_ENV_FILE"
if [ ! -f "$N8N_ENV_FILE" ]; then
  warn "$N8N_ENV_FILE does not exist — creating"
  : > "$N8N_ENV_FILE" || { fail "cannot create $N8N_ENV_FILE (need sudo?)"; exit 7; }
fi
EXISTING_TOKEN=$(grep -E '^POSTMARK_WEBHOOK_TOKEN=' "$N8N_ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)
if [ -n "$EXISTING_TOKEN" ]; then
  TOKEN="$EXISTING_TOKEN"
  ok "token already present in $N8N_ENV_FILE — preserved"
else
  TOKEN=$(openssl rand -hex 32)
  printf "POSTMARK_WEBHOOK_TOKEN=%s\n" "$TOKEN" >> "$N8N_ENV_FILE"
  ok "generated + appended new token"
  # Force a restart so n8n picks the new env var up before ship.sh
  # runs the workflow. ship.sh restarts anyway as part of its flow,
  # but doing it here means even the receiver's own first invocation
  # sees the token.
  docker restart "$CONTAINER" >/dev/null 2>&1 || warn "docker restart failed (ship.sh will retry)"
fi

# ─── 4. ship receiver workflow (new — CLI import path) ──────────
step "4/6  Ship $RECEIVER_WF"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
bash "$SCRIPT_DIR/ship.sh" --branch "$BRANCH" "$RECEIVER_WF" || { fail "ship.sh failed for $RECEIVER_WF"; exit 8; }

# ─── 5. ship comms-health (REST PUT path) ────────────────────────
step "5/6  Ship $COMMS_WF (REST PUT update)"
bash "$SCRIPT_DIR/ship.sh" --branch "$BRANCH" "$COMMS_WF" || { fail "ship.sh failed for $COMMS_WF"; exit 9; }

# ─── 6. smoke-test ───────────────────────────────────────────────
step "6/6  Smoke-test"
EVT_COUNT=$(psql "$DATABASE_URL" -tAc "SELECT COUNT(*) FROM email_events;" 2>/dev/null | tr -d '[:space:]')
if [ -z "$EVT_COUNT" ]; then
  warn "could not query email_events (DB hiccup?). Skipping count check."
else
  say "email_events row count: ${BOLD}$EVT_COUNT${RESET}"
  if [ "$EVT_COUNT" = "0" ]; then
    say "${DIM}(0 is expected until Postmark starts sending events — see footer)${RESET}"
  else
    psql "$DATABASE_URL" -c "SELECT event_type, COUNT(*) FROM email_events WHERE received_at >= now() - interval '7 days' GROUP BY event_type ORDER BY 2 DESC;"
  fi
fi

# ─── footer: what the operator still does by hand in Postmark ────
printf "\n${BOLD}${GREEN}Deploy complete — %s${RESET}\n" "$HEAD_SHA"
printf "\n${BOLD}Manual step remaining (Postmark UI):${RESET}\n"
cat <<EOF
  1. Go to Postmark > Servers > <your server> > Settings > Webhooks
  2. Add webhook (or edit existing). URL:
       https://automation.crystallux.org/webhook/webhook/postmark/events
  3. Custom HTTP headers, add:
       X-Postmark-Webhook-Token = ${TOKEN}
  4. Tick event types: Delivery, Bounce, SpamComplaint, Open, Click, SubscriptionChange
  5. Click "Send test" — within 5 sec a row appears in email_events.

Then purge Cloudflare cache for /pages/sentinel.html so the new
Bounces card renders.
EOF
