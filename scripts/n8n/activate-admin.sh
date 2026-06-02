#!/usr/bin/env bash
# Switch ON the admin-dashboard backend workflows so the pages can fetch data:
# avatars, AVA content/schedule, onboarding pipeline, market intelligence,
# overviews, and the MCP tools.
#
# ACTIVATE-ONLY by id via the n8n REST API. Pure curl. Idempotent. No definitions changed.
# Run:  N8N_API_KEY=yourkey bash scripts/n8n/activate-admin.sh

set -uo pipefail
N8N_URL="${N8N_URL:-${CLX_N8N_PUBLIC_URL:-https://automation.crystallux.org}}"
: "${N8N_API_KEY:?Set N8N_API_KEY first (same key ship.sh uses)}"

IDS=(
  "clxAvatarListV1|Avatar List (fixes the 'dead' avatars)"
  "clxAvatarRouterV1|Avatar Router"
  "wfAdminAvatarContentListV1|Admin Avatar Content (fixes AVA 'could not fetch data')"
  "wfAdminAvatarScheduleV1|Admin Avatar Schedule"
  "wfAdminOnboardingPipeline|Admin Onboarding Pipeline (fixes pipeline not active)"
  "wfAdminMarketIntelligence|Admin Market Intelligence"
  "wfAdminMarketIntelligenceV1|Admin Market Intelligence Summary"
  "clx-mcp-tool-gateway|MCP Tool Gateway (fixes MCP tool not functioning)"
  "clxMcpAgentToolsV1|MCP Agent Tools"
  "wfMcpVideoOrchestrator|MCP Video Orchestrator"
  "clxClientOverviewV1|Client Overview"
  "clxSupervisorOverviewV1|Supervisor Overview"
  "clxMgaInsurancePrincipalOverviewV1|MGA Principal Overview"
  "wfMgaAdvisorOverviewV1|MGA Advisor Overview"
)

echo "================================================================"
echo " Activating admin-dashboard backends (avatars, AVA, pipeline, MCP...)"
echo " Activate-only, by id. No definitions changed.  n8n: $N8N_URL"
echo "================================================================"
on=0; problem=0
for row in "${IDS[@]}"; do
  id="${row%%|*}"; label="${row#*|}"
  code=$(curl -s -o /tmp/clx_admin.json -w "%{http_code}" -X POST \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    "$N8N_URL/api/v1/workflows/$id/activate")
  if [ "$code" = "200" ]; then echo "  [+] ON:        $label"; on=$((on+1))
  else snip=$(head -c 140 /tmp/clx_admin.json 2>/dev/null | tr -d '\n'); echo "  [x] HTTP $code:  $label   $snip"; problem=$((problem+1)); fi
done
echo "================================================================"
echo " ON: $on   Problems: $problem   (of ${#IDS[@]})"
echo "================================================================"
echo "Now hard-refresh the admin dashboard. Avatars, AVA, pipeline, market"
echo "intelligence, and MCP should fetch live data. (Empty sections just mean"
echo "no data yet, not a broken page.)"
