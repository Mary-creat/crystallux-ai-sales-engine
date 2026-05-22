#!/usr/bin/env bash
# scripts/n8n/ship-em-dash-fixes.sh
#
# Ships all 13 customer-facing workflows that had em-dashes scrubbed
# (commit ccd3644). Each ship.sh call updates the workflow in place
# via REST API PUT, activates, and probes. Stops on first failure.
#
# Usage on the VPS:
#   cd /tmp/clx-latest && git pull origin main
#   bash scripts/n8n/ship-em-dash-fixes.sh

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

FILES=(
  clx-booking-v2.json
  clx-follow-up-v2.json
  clx-pipeline-update-v2.json
  clx-outreach-sender-v2.json
  clx-outreach-generation-v2.json
  clx-no-show-sms-recovery-v1.json
  clx-whatsapp-outreach-v1.json
  clx-linkedin-outreach-v1.json
  clx-video-outreach-v1.json
  clx-voice-outreach-v1.json
  clx-public-mga-apply-v1.json
  clx-public-quote-fetch-v1.json
  clx-admin-smart-quote-flow-v1.json
  clx-mga-insurance-lead-capture-v1.json
)

total="${#FILES[@]}"
i=0
fails=0

for f in "${FILES[@]}"; do
  i=$((i + 1))
  printf "\n==== [%d/%d] %s ====\n" "$i" "$total" "$f"
  if ! bash "${SCRIPT_DIR}/ship.sh" "$f"; then
    fails=$((fails + 1))
    printf "  WARN: ship failed for %s\n" "$f"
  fi
done

printf "\n==== Done. %d/%d succeeded, %d failed ====\n" "$((total - fails))" "$total" "$fails"
exit $fails
