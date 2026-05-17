#!/usr/bin/env bash
# scripts/n8n/audit-duplicates.sh
#
# Find every workflow in n8n whose name collides with another workflow.
# Export each colliding workflow's full JSON so the operator can diff,
# then write a markdown report listing every group with the metadata
# needed to choose which to keep.
#
# Read-only — this script never deletes anything. Pair with
# scripts/n8n/cleanup-duplicates.sh once the operator has reviewed.
#
# Usage (on the n8n VPS):
#   bash scripts/n8n/audit-duplicates.sh
#
# Env overrides:
#   N8N_CONTAINER   — docker container name (default: n8n)
#   BACKUP_DIR      — where to dump exports + report (default: /tmp/n8n-audit-<ts>)
#
# Requirements: docker, python3 (for JSON parsing), awk.

set -u

N8N_CONTAINER="${N8N_CONTAINER:-n8n}"
TS=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${BACKUP_DIR:-/tmp/n8n-audit-$TS}"
REPORT="$BACKUP_DIR/DUPLICATES.md"

mkdir -p "$BACKUP_DIR"
echo "▸ Backup dir: $BACKUP_DIR"

# ─── 1. Capture the full workflow list ───────────────────────────
if ! docker exec "$N8N_CONTAINER" n8n list:workflow > "$BACKUP_DIR/list.raw.txt" 2>"$BACKUP_DIR/list.err.txt"; then
  echo "✗ docker exec $N8N_CONTAINER n8n list:workflow failed"
  echo "  stderr: $(cat $BACKUP_DIR/list.err.txt)"
  echo "  Verify the container name with: docker ps --format '{{.Names}}'"
  exit 1
fi

# n8n CLI default format is "id|name" per line. Parse defensively —
# names can contain spaces or pipes inside JSON, but the CLI's text
# output escapes them.
awk -F '|' '
{
  id = $1
  sub(/^[ \t]+|[ \t]+$/, "", id)
  if (NF < 2 || id == "") next
  name = $2
  for (i = 3; i <= NF; i++) name = name "|" $i
  sub(/^[ \t]+|[ \t]+$/, "", name)
  print id "\t" name
}' "$BACKUP_DIR/list.raw.txt" > "$BACKUP_DIR/list.tsv"

TOTAL=$(wc -l < "$BACKUP_DIR/list.tsv")
echo "▸ Total workflows in n8n: $TOTAL"

# ─── 2. Group by name; emit any group with count > 1 ─────────────
awk -F '\t' '
{
  ids[$2] = (ids[$2] ? ids[$2] "," $1 : $1)
  cnt[$2]++
}
END {
  for (n in cnt) if (cnt[n] > 1) print cnt[n] "\t" n "\t" ids[n]
}' "$BACKUP_DIR/list.tsv" | sort -k1,1nr -k2 > "$BACKUP_DIR/duplicate-groups.tsv"

DUP_GROUPS=$(wc -l < "$BACKUP_DIR/duplicate-groups.tsv")
echo "▸ Duplicate name groups: $DUP_GROUPS"
echo

# ─── 3. For every duplicate, export the workflow JSON ────────────
export_one() {
  local id="$1"
  if docker exec "$N8N_CONTAINER" n8n export:workflow --id="$id" --output="/tmp/wf-$id.json" >/dev/null 2>&1; then
    docker cp "$N8N_CONTAINER:/tmp/wf-$id.json" "$BACKUP_DIR/$id.json" >/dev/null 2>&1
    docker exec "$N8N_CONTAINER" rm -f "/tmp/wf-$id.json" >/dev/null 2>&1
  fi
}

# Helper: extract a field from an exported workflow JSON via python3
field() {
  local id="$1" expr="$2"
  python3 - <<PY 2>/dev/null || echo "?"
import json, sys
try:
    d = json.load(open("$BACKUP_DIR/$id.json"))
    $expr
except Exception:
    print("?")
PY
}

# ─── 4. Build the report ─────────────────────────────────────────
{
  echo "# n8n duplicate-workflow audit — $TS"
  echo
  echo "Run by:    \`$(whoami)@$(hostname)\`"
  echo "Container: \`$N8N_CONTAINER\`"
  echo "Backups:   \`$BACKUP_DIR/\` (every duplicated workflow's JSON is here)"
  echo
  echo "**$TOTAL workflows total · $DUP_GROUPS duplicate-name groups.**"
  echo
  if [ "$DUP_GROUPS" = "0" ]; then
    echo "No duplicates. Nothing to clean up."
    echo
    echo "_End of report._"
    exit 0
  fi
  echo "## How to read this"
  echo
  echo "For each group below, the rows show every workflow currently in n8n with that name."
  echo "Choose the one to keep using this priority:"
  echo
  echo "1. **\`active = true\`** — never delete an active workflow blind. If multiple are active, only one is actually receiving traffic (n8n collapses to the most-recently-activated); the others are dormant duplicates of the same name."
  echo "2. **\`webhook path\` present** — the one currently serving the URL."
  echo "3. **Newest \`updatedAt\`** — newer typically reflects the more correct content."
  echo "4. Confirm by diffing the JSON exports in \`$BACKUP_DIR/\`."
  echo
  echo "Then write the IDs to delete into \`$BACKUP_DIR/delete-ids.txt\` (one per line; \`#\` comments allowed) and run:"
  echo
  echo "\`\`\`"
  echo "bash scripts/n8n/cleanup-duplicates.sh --delete-list=$BACKUP_DIR/delete-ids.txt"
  echo "# review output, then re-run with --execute to actually delete"
  echo "\`\`\`"
  echo
  echo "---"
  echo

  while IFS=$'\t' read -r cnt name idlist; do
    echo "### \"$name\" — $cnt copies"
    echo
    echo "| ID | Active | UpdatedAt | Webhook path | Nodes |"
    echo "|---|---|---|---|---|"

    IFS=',' read -ra ids <<< "$idlist"
    for id in "${ids[@]}"; do
      export_one "$id"
      if [ -s "$BACKUP_DIR/$id.json" ]; then
        active=$(field "$id" "print(d.get('active','?'))")
        updated=$(field "$id" "print(d.get('updatedAt','?'))")
        webhook=$(field "$id" "
ws=[n.get('parameters',{}).get('path','') for n in d.get('nodes',[]) if n.get('type')=='n8n-nodes-base.webhook']
print(','.join(w for w in ws if w) or '—')")
        node_count=$(field "$id" "print(len(d.get('nodes',[])))")
      else
        active="export-failed"; updated="?"; webhook="?"; node_count="?"
      fi
      echo "| \`$id\` | $active | $updated | $webhook | $node_count |"
    done
    echo
  done < "$BACKUP_DIR/duplicate-groups.tsv"

  echo "---"
  echo
  echo "_End of report. See \`$BACKUP_DIR/\` for the per-workflow JSON exports._"
} > "$REPORT"

echo "▸ Report:  $REPORT"
echo "▸ Next:    review the report, write delete IDs into $BACKUP_DIR/delete-ids.txt"
echo "▸ Then:    bash scripts/n8n/cleanup-duplicates.sh --delete-list=$BACKUP_DIR/delete-ids.txt"
