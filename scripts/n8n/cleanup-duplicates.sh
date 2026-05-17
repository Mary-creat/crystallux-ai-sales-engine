#!/usr/bin/env bash
# scripts/n8n/cleanup-duplicates.sh
#
# Delete a list of n8n workflow IDs with safety rails:
#   1. Export every targeted workflow's JSON to backup BEFORE delete.
#   2. Refuse to delete any workflow whose JSON has active=true.
#   3. Log every action (DELETED / REFUSED / SKIPPED / FAIL).
#   4. Dry-run by default; pass --execute to actually delete.
#
# Pair with scripts/n8n/audit-duplicates.sh — its report tells you
# which IDs to put in the delete list.
#
# Usage (on the n8n VPS):
#   bash scripts/n8n/cleanup-duplicates.sh --delete-list=<file>            # dry run
#   bash scripts/n8n/cleanup-duplicates.sh --delete-list=<file> --execute  # for real
#
# Delete-list format:
#   - One workflow ID per line (n8n's internal IDs, e.g. gKLUduzlNtlvxPVE).
#   - Lines starting with '#' are comments.
#   - Blank lines ignored.
#
# Env overrides:
#   N8N_CONTAINER   — docker container name (default: n8n)
#   BACKUP_DIR      — backup destination (default: /tmp/n8n-cleanup-<ts>)
#
# Requirements: docker, python3.

set -u

N8N_CONTAINER="${N8N_CONTAINER:-n8n}"
TS=$(date +%Y%m%d-%H%M%S)
DELETE_LIST=""
EXECUTE=0
BACKUP_DIR_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --delete-list=*) DELETE_LIST="${1#*=}" ;;
    --delete-list)   shift; DELETE_LIST="$1" ;;
    --execute)       EXECUTE=1 ;;
    --backup-dir=*)  BACKUP_DIR_ARG="${1#*=}" ;;
    --backup-dir)    shift; BACKUP_DIR_ARG="$1" ;;
    -h|--help)
      sed -n '2,30p' "$0"; exit 0 ;;
    *)
      echo "Unknown arg: $1"; exit 1 ;;
  esac
  shift
done

if [ -z "$DELETE_LIST" ]; then
  echo "Usage: $0 --delete-list=<file> [--execute] [--backup-dir=<dir>]"
  exit 1
fi
if [ ! -r "$DELETE_LIST" ]; then
  echo "Cannot read delete list: $DELETE_LIST"
  exit 1
fi

BACKUP_DIR="${BACKUP_DIR_ARG:-/tmp/n8n-cleanup-$TS}"
mkdir -p "$BACKUP_DIR"
LOG="$BACKUP_DIR/deletion.log"

MODE_TAG="DRY-RUN"
[ "$EXECUTE" = "1" ] && MODE_TAG="EXECUTE"

{
  echo "n8n cleanup — $TS"
  echo "Mode:       $MODE_TAG"
  echo "Container:  $N8N_CONTAINER"
  echo "Delete-list: $DELETE_LIST"
  echo "Backup dir: $BACKUP_DIR"
  echo "─────────────────────────────────────────────"
} | tee "$LOG"

PROCESSED=0; DELETED=0; REFUSED=0; SKIPPED=0; FAILED=0

while IFS= read -r raw; do
  id=$(echo "$raw" | tr -d '[:space:]' | sed 's/#.*//')
  [ -z "$id" ] && continue
  PROCESSED=$((PROCESSED+1))

  printf "  %-20s " "$id" | tee -a "$LOG"

  # 1. Export to backup
  if ! docker exec "$N8N_CONTAINER" n8n export:workflow --id="$id" --output="/tmp/wf-$id.json" >/dev/null 2>&1; then
    echo "SKIPPED (export failed — id may not exist in this n8n)" | tee -a "$LOG"
    SKIPPED=$((SKIPPED+1))
    continue
  fi
  docker cp "$N8N_CONTAINER:/tmp/wf-$id.json" "$BACKUP_DIR/$id.json" >/dev/null 2>&1
  docker exec "$N8N_CONTAINER" rm -f "/tmp/wf-$id.json" >/dev/null 2>&1

  if [ ! -s "$BACKUP_DIR/$id.json" ]; then
    echo "SKIPPED (backup empty — refusing to delete an empty export)" | tee -a "$LOG"
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  # 2. Inspect backup
  read -r active name webhook <<< "$(python3 - <<PY 2>/dev/null
import json
d = json.load(open("$BACKUP_DIR/$id.json"))
active = str(d.get('active', False)).lower()
name = (d.get('name') or '?').replace(' ', '_')[:60]
ws = [n.get('parameters',{}).get('path','') for n in d.get('nodes',[]) if n.get('type')=='n8n-nodes-base.webhook']
webhook = ','.join(w for w in ws if w) or '-'
print(active, name, webhook)
PY
)"

  if [ "${active:-}" = "true" ]; then
    echo "REFUSED (active=true — \"$name\")" | tee -a "$LOG"
    REFUSED=$((REFUSED+1))
    continue
  fi

  # 3. Delete (or dry-run)
  if [ "$EXECUTE" = "1" ]; then
    if docker exec "$N8N_CONTAINER" n8n delete:workflow --id="$id" >/dev/null 2>&1; then
      echo "DELETED \"$name\" (webhook: $webhook)" | tee -a "$LOG"
      DELETED=$((DELETED+1))
    else
      echo "FAILED (delete:workflow returned non-zero)" | tee -a "$LOG"
      FAILED=$((FAILED+1))
    fi
  else
    echo "WOULD-DELETE \"$name\" (active=$active, webhook: $webhook)" | tee -a "$LOG"
  fi
done < "$DELETE_LIST"

{
  echo "─────────────────────────────────────────────"
  echo "Processed: $PROCESSED"
  echo "Deleted:   $DELETED   (would-delete in dry run)"
  echo "Refused:   $REFUSED   (active=true protection)"
  echo "Skipped:   $SKIPPED   (export failed / empty)"
  echo "Failed:    $FAILED"
  echo "Backups:   $BACKUP_DIR"
  echo "Log:       $LOG"
} | tee -a "$LOG"

if [ "$EXECUTE" = "0" ]; then
  echo
  echo "This was a DRY RUN. Re-run with --execute to actually delete."
fi
