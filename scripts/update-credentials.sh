#!/bin/bash
set -a
source "$(dirname "$0")/../.env"
set +a

N8N_API="$N8N_URL/api/v1"
AUTH="X-N8N-API-KEY: $N8N_API_KEY"

echo "Updating Crystallux credentials..."

# Get all credentials
CREDS=$(curl -s -X GET "$N8N_API/credentials" \
  -H "$AUTH" \
  -H "Content-Type: application/json")

echo "Connected to n8n successfully"
echo "Credentials found: $(echo $CREDS | grep -o '"name"' | wc -l)"

# Update Supabase Crystallux
SUPABASE_ID=$(echo "$CREDS" | python -c "
import json, sys
data = json.loads(sys.stdin.read())
creds = data.get('data', data) if isinstance(data, dict) else data
for c in creds:
    if c.get('name') == 'Supabase Crystallux':
        print(c.get('id',''))
        break
")

if [ ! -z "$SUPABASE_ID" ]; then
  curl -s -X PATCH "$N8N_API/credentials/$SUPABASE_ID" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d "{\"data\":{\"json\":{\"headers\":{\"apikey\":\"$SUPABASE_SERVICE_KEY\",\"Authorization\":\"Bearer $SUPABASE_SERVICE_KEY\"}}}}"
  echo "✅ Supabase Crystallux updated"
else
  echo "❌ Supabase Crystallux not found"
fi

# Update Claude Anthropic
CLAUDE_ID=$(echo "$CREDS" | python -c "
import json, sys
data = json.loads(sys.stdin.read())
creds = data.get('data', data) if isinstance(data, dict) else data
for c in creds:
    if c.get('name') == 'Claude Anthropic':
        print(c.get('id',''))
        break
")

echo "Supabase Crystallux ID: $SUPABASE_ID"
echo "Claude Anthropic ID: $CLAUDE_ID"

if [ ! -z "$CLAUDE_ID" ]; then
  curl -s -X PATCH "$N8N_API/credentials/$CLAUDE_ID" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d "{\"data\":{\"value\":\"$ANTHROPIC_API_KEY\"}}"
  echo "✅ Claude Anthropic updated"
else
  echo "❌ Claude Anthropic not found"
fi

echo "Done. Run bash scripts/test-credentials.sh to verify."
