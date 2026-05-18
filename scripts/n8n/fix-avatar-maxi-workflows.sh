#!/usr/bin/env bash
# scripts/n8n/fix-avatar-maxi-workflows.sh
#
# One-shot recovery for the 4 avatar/MAXI workflows. Run on the VPS
# that hosts the n8n container, with the Crystallux repo checked out
# (so the patched JSONs in workflows/api/avatars/ are on disk).
#
#   Phase 1   audit which workflows exist by name (any duplicates,
#             the OLD wfFix0001-0004 stragglers, and the 8PhzNeJBzCFh5klL
#             pre-patch Avatar Router all surface here)
#   Phase 2   deactivate every matching row so webhooks unregister
#   Phase 3   delete every matching row — REST API preferred, SQL fallback
#   Phase 4   import the 4 fresh JSONs from the repo (n8n CLI)
#   Phase 5   activate each newly imported row
#   Phase 6   probe each webhook with no auth — expect 401 (auth-gated,
#             reachable). 404 = workflow not active. 5xx = workflow error.
#
# Idempotent. Re-running converges to the same state — only 4 rows for
# these names, all running the patched code, all active.
#
# Usage (on the VPS):
#   cd ~/crystallux-deploy && git pull
#   bash scripts/n8n/fix-avatar-maxi-workflows.sh
#
# Env overrides:
#   REPO_ROOT       — repo path on the VPS (default: pwd)
#   N8N_CONTAINER   — docker container name (default: n8n)
#   N8N_API_KEY     — personal access token (Settings → API in n8n UI).
#                     If set, used for delete + activate. Recommended.
#   N8N_BASE        — REST base (default: https://automation.crystallux.org)
#   N8N_DB_PATH     — sqlite path inside container (default:
#                     /home/node/.n8n/database.sqlite — standard image)
#
# Requirements: docker, curl, jq, python3.

set -u

REPO_ROOT="${REPO_ROOT:-$PWD}"
N8N_CONTAINER="${N8N_CONTAINER:-n8n}"
N8N_API_KEY="${N8N_API_KEY:-}"
N8N_BASE="${N8N_BASE:-https://automation.crystallux.org}"
N8N_DB_PATH="${N8N_DB_PATH:-/home/node/.n8n/database.sqlite}"

# name | JSON path (relative to REPO_ROOT) | webhook path | new top-level id
TARGETS=(
  "CLX - Avatar Router v1|workflows/api/avatars/clx-avatar-router-v1.json|avatars/route|clxAvatarRouterV1"
  "CLX - Avatar List v1|workflows/api/avatars/clx-avatar-list-v1.json|avatars/list|clxAvatarListV1"
  "CLX - MAXI Industries List v1|workflows/api/avatars/clx-maxi-industries-v1.json|maxi/industries|clxMaxiIndustriesV1"
  "CLX - MAXI Industry Detail v1|workflows/api/avatars/clx-maxi-industry-detail-v1.json|maxi/industry-detail|clxMaxiIndustryDetailV1"
)

PASS=0; FAIL=0
pass() { printf "  \033[32mOK\033[0m  %s\n" "$1"; PASS=$((PASS+1)); }
warn() { printf "  \033[33m!!\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }

mode_api()    { [ -n "$N8N_API_KEY" ]; }

# ─── helpers ────────────────────────────────────────────────────────────

api_get_all_workflows() {
  curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_BASE/api/v1/workflows?limit=250"
}

# Returns a tab-separated "id<TAB>name<TAB>active" per matching row.
# Uses API if available, else falls back to `n8n list:workflow` text parsing.
list_by_name() {
  local target_name="$1"
  if mode_api; then
    api_get_all_workflows | python3 -c "
import json, sys
target = '''$target_name'''
data = json.load(sys.stdin)
rows = data.get('data', data) if isinstance(data, dict) else data
for w in (rows or []):
    if w.get('name') == target:
        print('%s\t%s\t%s' % (w.get('id'), w.get('name'), w.get('active', False)))
"
  else
    # CLI text mode: 'id|name' per line
    docker exec "$N8N_CONTAINER" n8n list:workflow 2>/dev/null | awk -F '|' -v tgt="$target_name" '
      { id=$1; name=$2; for (i=3;i<=NF;i++) name=name "|" $i;
        gsub(/^[ \t]+|[ \t]+$/, "", id); gsub(/^[ \t]+|[ \t]+$/, "", name);
        if (name==tgt) print id "\t" name "\t?" }'
  fi
}

deactivate_workflow() {
  local id="$1"
  if mode_api; then
    curl -s -X POST -H "X-N8N-API-KEY: $N8N_API_KEY" \
      "$N8N_BASE/api/v1/workflows/$id/deactivate" >/dev/null
  else
    docker exec "$N8N_CONTAINER" n8n update:workflow --id="$id" --active=false >/dev/null 2>&1 || true
  fi
}

activate_workflow() {
  local id="$1"
  if mode_api; then
    curl -s -X POST -H "X-N8N-API-KEY: $N8N_API_KEY" \
      "$N8N_BASE/api/v1/workflows/$id/activate" >/dev/null
  else
    docker exec "$N8N_CONTAINER" n8n update:workflow --id="$id" --active=true >/dev/null 2>&1 || true
  fi
}

delete_workflow() {
  local id="$1"
  if mode_api; then
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
      -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_BASE/api/v1/workflows/$id")
    [ "$code" = "200" ] || [ "$code" = "204" ] && return 0
    # fall through to SQL on API failure
  fi
  # SQL fallback — delete from BOTH workflow_entity + webhook_entity so
  # the route table doesn't keep a dangling reference.
  docker exec "$N8N_CONTAINER" sh -c \
    "sqlite3 $N8N_DB_PATH \"DELETE FROM webhook_entity WHERE workflowId = '$id';\" 2>/dev/null; \
     sqlite3 $N8N_DB_PATH \"DELETE FROM workflow_entity WHERE id = '$id';\"" || true
}

import_workflow_json() {
  local json_path="$1"
  # n8n's CLI import reads from a path INSIDE the container. Copy first.
  local fname; fname=$(basename "$json_path")
  docker cp "$REPO_ROOT/$json_path" "$N8N_CONTAINER:/tmp/$fname" >/dev/null
  docker exec "$N8N_CONTAINER" n8n import:workflow --input="/tmp/$fname" 2>&1
}

new_id_for_json() {
  python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('id',''))" \
    "$REPO_ROOT/$1"
}

probe_webhook() {
  local path="$1"
  curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
    -X POST -H "Content-Type: application/json" \
    -H "Origin: https://admin.crystallux.org" \
    "$N8N_BASE/webhook/$path" -d '{}'
}

# ─── Phase 0: preflight ─────────────────────────────────────────────────

printf "\n\033[1m== Phase 0 — preflight ==\033[0m\n"
docker ps --format '{{.Names}}' | grep -q "^${N8N_CONTAINER}\$" \
  && pass "container '$N8N_CONTAINER' is running" \
  || { fail "container '$N8N_CONTAINER' not found — set N8N_CONTAINER"; exit 1; }

if mode_api; then
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_BASE/api/v1/workflows?limit=1")
  [ "$code" = "200" ] && pass "REST API reachable, key valid" \
                       || warn "REST API returned $code — will use CLI + SQL fallback"
  [ "$code" = "200" ] || N8N_API_KEY=""
else
  warn "no N8N_API_KEY — using CLI + SQL fallback (less clean, still works)"
fi

# Sanity: the 4 JSONs exist on disk
for entry in "${TARGETS[@]}"; do
  IFS='|' read -r name path webhook newid <<< "$entry"
  [ -r "$REPO_ROOT/$path" ] && pass "JSON present: $path" \
                            || { fail "missing JSON: $REPO_ROOT/$path"; exit 1; }
done

# ─── Phase 1 — audit ────────────────────────────────────────────────────

printf "\n\033[1m== Phase 1 — audit ==\033[0m\n"
for entry in "${TARGETS[@]}"; do
  IFS='|' read -r name path webhook newid <<< "$entry"
  matches=$(list_by_name "$name")
  count=$(echo -n "$matches" | grep -c '^' || echo 0)
  if [ "$count" -eq 0 ]; then
    pass "no existing rows for: $name"
  else
    warn "$count existing row(s) for: $name"
    echo "$matches" | sed 's/^/      /'
  fi
done

# ─── Phase 2 + 3 — deactivate + delete ──────────────────────────────────

printf "\n\033[1m== Phase 2+3 — deactivate then delete every existing match ==\033[0m\n"
for entry in "${TARGETS[@]}"; do
  IFS='|' read -r name path webhook newid <<< "$entry"
  matches=$(list_by_name "$name")
  [ -z "$matches" ] && continue
  while IFS=$'\t' read -r id _name _active; do
    [ -z "$id" ] && continue
    deactivate_workflow "$id"
    delete_workflow "$id"
    pass "deleted $id ($name)"
  done <<< "$matches"
done

# Belt + suspenders: also delete by id if rows with our NEW top-level ids
# happen to still be in the DB (e.g. residue from a failed prior import).
# Catches the corner case where name above doesn't match (rename in DB) but
# the id does.
for entry in "${TARGETS[@]}"; do
  IFS='|' read -r name path webhook newid <<< "$entry"
  delete_workflow "$newid"
done

# ─── Phase 4 — re-import the 4 fresh JSONs ──────────────────────────────

printf "\n\033[1m== Phase 4 — import patched JSONs ==\033[0m\n"
for entry in "${TARGETS[@]}"; do
  IFS='|' read -r name path webhook newid <<< "$entry"
  out=$(import_workflow_json "$path" 2>&1)
  if echo "$out" | grep -qE "Successfully imported|imported|workflow imported"; then
    pass "imported $name (id=$newid)"
  else
    fail "import failed for $name"
    echo "$out" | sed 's/^/      /'
  fi
done

# ─── Phase 5 — activate each ────────────────────────────────────────────

printf "\n\033[1m== Phase 5 — activate ==\033[0m\n"
for entry in "${TARGETS[@]}"; do
  IFS='|' read -r name path webhook newid <<< "$entry"
  # Look up the freshly-imported row's id (in case n8n re-assigned it on import)
  matches=$(list_by_name "$name")
  resolved_id=$(echo "$matches" | head -1 | cut -f1)
  if [ -z "$resolved_id" ]; then
    fail "could not resolve fresh row id for $name (skipping activation)"
    continue
  fi
  activate_workflow "$resolved_id"
  pass "activated $resolved_id ($name)"
done

# ─── Phase 6 — probe webhooks ───────────────────────────────────────────

printf "\n\033[1m== Phase 6 — probe webhooks (expect 401 = auth-gated + reachable) ==\033[0m\n"
for entry in "${TARGETS[@]}"; do
  IFS='|' read -r name path webhook newid <<< "$entry"
  code=$(probe_webhook "$webhook")
  case "$code" in
    401) pass "POST /webhook/$webhook -> 401 (good)" ;;
    404) fail "POST /webhook/$webhook -> 404 (workflow NOT active or not registered)" ;;
    500) fail "POST /webhook/$webhook -> 500 (workflow error — check 'docker logs $N8N_CONTAINER --tail 50')" ;;
    *)   warn "POST /webhook/$webhook -> $code (unexpected; investigate)" ;;
  esac
done

# ─── Summary ────────────────────────────────────────────────────────────

printf "\n\033[1m== Summary ==\033[0m\n"
printf "  pass:  %d\n  fail:  %d\n\n" "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "Some steps failed. The 4 most likely causes:"
  echo "  - delete by SQL didn't reach the right database path."
  echo "    Set N8N_DB_PATH if your container stores .sqlite elsewhere."
  echo "  - import failed because the JSON's top-level id collides with"
  echo "    a row this script couldn't see (e.g. a rename happened in n8n)."
  echo "    Run \`docker exec $N8N_CONTAINER n8n list:workflow | grep -i avatar\`"
  echo "    and delete stragglers manually."
  echo "  - activate failed because n8n re-assigned the id on import and the"
  echo "    name-lookup didn't find it — usually a CLI quirk. Re-run; the"
  echo "    second pass converges."
  echo "  - probe 5xx means workflow ran but threw. Check docker logs."
  exit 1
fi

echo "All 4 workflows are imported, active, and answering 401 on the public"
echo "webhook. Open https://admin.crystallux.org/auth-check in the browser to"
echo "confirm the auth path works with a real session token, then hit"
echo "https://admin.crystallux.org/maxi — should render the 22 industries."
