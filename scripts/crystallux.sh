#!/bin/bash
set -a
source "$(dirname "$0")/../.env"
set +a

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

list() {
  echo -e "${BLUE}Crystallux Workflows:${NC}"
  curl -s -X GET "$N8N_URL/api/v1/workflows" \
    -H "X-N8N-API-KEY: $N8N_API_KEY"
}

deploy() {
  curl -s -X POST "$N8N_URL/api/v1/workflows" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -H "Content-Type: application/json" \
    -d @"workflows/$1.json"
  echo -e "${GREEN}Deployed: $1${NC}"
}

execute() {
  curl -s -X POST "$N8N_URL/api/v1/workflows/$1/execute" \
    -H "X-N8N-API-KEY: $N8N_API_KEY"
  echo -e "${GREEN}Executed: $1${NC}"
}

case "$1" in
  list)    list ;;
  deploy)  deploy "$2" ;;
  execute) execute "$2" ;;
  *)
    echo "Usage: ./scripts/crystallux.sh [list|deploy <filename-no-ext>|execute <workflow-id>]"
    ;;
esac
