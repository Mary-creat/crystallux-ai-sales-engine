#!/usr/bin/env bash
# scripts/n8n/nuke-and-reimport.sh
#
# Interactive wrapper around nuke-and-reimport.py. Reset n8n workflow
# state to match the repo. Prompts for confirmation before doing
# anything destructive.
#
# Usage on the VPS:
#   cd /root/crystallux-ai-sales-engine
#   git pull origin main
#   bash scripts/n8n/nuke-and-reimport.sh
#
# Flags (forwarded to the Python script):
#   --dry-run            # plan only, no destruction
#   --activate-roots     # also activate root-level Sales Engine cron workflows
#   --no-probe           # skip the final endpoint probe
#
# Env overrides:
#   CLX_N8N_CONTAINER   default: n8n
#   CLX_WEBHOOK_BASE    default: https://automation.crystallux.org/webhook

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PY="${SCRIPT_DIR}/nuke-and-reimport.py"

# Pass-through dry run / no-confirm modes
if [[ " $* " == *" --dry-run "* ]]; then
  exec python3 "${PY}" "$@"
fi
if [[ " $* " == *" --confirm-destructive "* ]]; then
  exec python3 "${PY}" "$@"
fi

cat <<'BANNER'
=================================================================
  NUKE + REIMPORT — DESTRUCTIVE n8n state reset
=================================================================

This will:
  - Stop n8n
  - TRUNCATE workflow_entity, webhook_entity, execution_entity
  - Restart n8n
  - Import every workflow JSON from this repo
  - Activate the canonical set (admin / avatars / public / dashboards)
  - Restart n8n once more so webhooks register
  - Probe every key endpoint and report status

What is PRESERVED:
  - n8n credentials (separate table, untouched)
  - n8n env vars, users, API keys
  - Supabase / Postgres data

What is LOST:
  - n8n execution history
  - Any workflow created in the n8n UI that isn't in the repo

Repo is the source of truth (per CLAUDE.md), so this should put
the live n8n into a clean, predictable state.

=================================================================
BANNER

read -r -p "Type NUKE to proceed (anything else aborts): " ans
if [[ "${ans}" != "NUKE" ]]; then
  echo "Aborted."
  exit 1
fi

exec python3 "${PY}" --confirm-destructive "$@"
