#!/bin/bash
# ══════════════════════════════════════════════════════════════════
# test-restore.sh — Crystallux Backup Verification
#
# Dumps the live n8n-internal postgres, restores into a scratch
# database, and runs sanity checks. Exits non-zero on any failure.
#
# USAGE:
#   ./scripts/test-restore.sh            (runs full dump → restore → verify)
#   ./scripts/test-restore.sh --dry-run  (prints the commands without executing)
#
# REQUIRES:
#   - pg_dump, psql, createdb, dropdb in PATH
#   - .env has POSTGRES_HOST, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB
#   - Run from repo root
#
# Documented in docs/architecture/OPERATIONS_HANDBOOK.md § Backup / Restore.
# ══════════════════════════════════════════════════════════════════

set -e

DRY_RUN=false
if [ "$1" = "--dry-run" ]; then DRY_RUN=true; fi

# Load .env
if [ ! -f .env ]; then
  echo "ERROR: .env not found. Run from repo root."
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DUMP_FILE="/tmp/crystallux-dump-${TIMESTAMP}.sql"
RESTORE_DB="crystallux_restore_test_${TIMESTAMP}"

run() {
  echo "+ $*"
  if [ "$DRY_RUN" = false ]; then eval "$*"; fi
}

echo "═══════════════════════════════════════════════════════════"
echo " Crystallux Restore Verification — ${TIMESTAMP}"
echo "═══════════════════════════════════════════════════════════"

# 1. Dump live DB
echo "[1/5] Dumping ${POSTGRES_DB} from ${POSTGRES_HOST}..."
run "PGPASSWORD=\"${POSTGRES_PASSWORD}\" pg_dump -h \"${POSTGRES_HOST}\" -U \"${POSTGRES_USER}\" -d \"${POSTGRES_DB}\" -f \"${DUMP_FILE}\" --no-owner --no-acl"

if [ "$DRY_RUN" = false ]; then
  DUMP_SIZE=$(wc -c < "${DUMP_FILE}")
  echo "    Dump size: ${DUMP_SIZE} bytes"
  if [ "${DUMP_SIZE}" -lt 10000 ]; then
    echo "    ✗ FAIL: dump file suspiciously small"; exit 1
  fi
fi

# 2. Create scratch DB
echo "[2/5] Creating scratch database ${RESTORE_DB}..."
run "PGPASSWORD=\"${POSTGRES_PASSWORD}\" createdb -h \"${POSTGRES_HOST}\" -U \"${POSTGRES_USER}\" \"${RESTORE_DB}\""

# 3. Restore
echo "[3/5] Restoring dump into ${RESTORE_DB}..."
run "PGPASSWORD=\"${POSTGRES_PASSWORD}\" psql -h \"${POSTGRES_HOST}\" -U \"${POSTGRES_USER}\" -d \"${RESTORE_DB}\" -f \"${DUMP_FILE}\" -q"

# 4. Sanity checks
echo "[4/5] Running sanity checks on restored DB..."
if [ "$DRY_RUN" = false ]; then
  LEAD_COUNT=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -d "${RESTORE_DB}" -t -A -c "SELECT COUNT(*) FROM leads")
  CLIENT_COUNT=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -d "${RESTORE_DB}" -t -A -c "SELECT COUNT(*) FROM clients")
  NICHE_COUNT=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -d "${RESTORE_DB}" -t -A -c "SELECT COUNT(*) FROM niche_overlays")
  echo "    leads: ${LEAD_COUNT}, clients: ${CLIENT_COUNT}, niche_overlays: ${NICHE_COUNT}"
  if [ "${LEAD_COUNT}" -lt 1 ] || [ "${CLIENT_COUNT}" -lt 1 ] || [ "${NICHE_COUNT}" -lt 1 ]; then
    echo "    ✗ FAIL: one or more core tables empty after restore"; exit 1
  fi
fi

# 5. Cleanup
echo "[5/5] Dropping scratch database ${RESTORE_DB}..."
run "PGPASSWORD=\"${POSTGRES_PASSWORD}\" dropdb -h \"${POSTGRES_HOST}\" -U \"${POSTGRES_USER}\" \"${RESTORE_DB}\""
run "rm -f \"${DUMP_FILE}\""

echo ""
echo "✓ PASS: restore verified end-to-end."
echo "   Run this script weekly. Before each new-client wave. Before any schema migration."
