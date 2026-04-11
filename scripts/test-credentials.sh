#!/bin/bash
set -a
source "$(dirname "$0")/../.env"
set +a

echo "Testing Crystallux API credentials..."
echo ""

# Test n8n API
echo -n "n8n API ($N8N_URL): "
N8N_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X GET "$N8N_URL/api/v1/workflows" \
  -H "X-N8N-API-KEY: $N8N_API_KEY")
if [ "$N8N_STATUS" = "200" ]; then
  echo "✅ OK ($N8N_STATUS)"
else
  echo "❌ FAIL ($N8N_STATUS)"
fi

# Test Anthropic API
echo -n "Anthropic Claude API: "
CLAUDE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.anthropic.com/v1/messages" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}')
if [ "$CLAUDE_STATUS" = "200" ]; then
  echo "✅ OK ($CLAUDE_STATUS)"
else
  echo "❌ FAIL ($CLAUDE_STATUS)"
fi

# Test Supabase REST API
echo -n "Supabase REST API: "
SUPABASE_URL="https://$SUPABASE_PROJECT_ID.supabase.co"
SUPABASE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X GET "$SUPABASE_URL/rest/v1/" \
  -H "apikey: $SUPABASE_SERVICE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_KEY")
if [ "$SUPABASE_STATUS" = "200" ] || [ "$SUPABASE_STATUS" = "404" ]; then
  echo "✅ OK ($SUPABASE_STATUS)"
else
  echo "❌ FAIL ($SUPABASE_STATUS)"
fi

echo ""
echo "Done."
