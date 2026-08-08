#!/usr/bin/env bash
# Probe every LUXI webhook and report which are actually registered.
#
# ship.sh probes each workflow 30 s after restarting n8n, which on a box with
# ~200 workflows is often too early — it reports 404 on endpoints that register
# fine a minute later. This re-probes them all once, after everything has
# settled, so you get a true picture instead of a race.
#
# Run on the VPS, after deploy-luxi-revenue.sh has finished:
#   bash scripts/n8n/probe-luxi.sh
#
# Reading the output:
#   401 / 400  HEALTHY — registered, rejected our junk auth (expected)
#   200        HEALTHY — registered, returns empty on auth failure
#   404        NOT REGISTERED — the real problem
#   000        n8n unreachable (still restarting? wait and re-run)

set -uo pipefail
BASE="${CLX_N8N_PUBLIC_URL:-https://automation.crystallux.org}/webhook"

PATHS=(
  "public/luxi/auction|public bid page reads the auction"
  "public/luxi/create-intent|starts the card hold"
  "public/luxi/confirm-bid|registers the auto-bid"
  "public/luxi/buy-now-intent|starts a Buy Now payment"
  "public/luxi/buy-now-confirm|completes a Buy Now sale"
  "public/luxi/stream-status|LIVE banner on the bid page"
  "admin/luxi/auctions|admin: list auctions"
  "admin/luxi/auctions/manage|admin: create/edit a listing"
  "admin/luxi/place-bid|admin: place a bid"
  "admin/luxi/buy-now|admin: Buy Now action"
  "admin/luxi/proxy-bid|admin: set auto-bid"
  "admin/luxi/stream|admin: Go Live control"
  "luxi/bid-parse|comment-to-bid parser"
)

echo "================================================================"
echo " Probing LUXI webhooks at $BASE"
echo "================================================================"

healthy=0; broken=0; unreachable=0; bad_list=""
for row in "${PATHS[@]}"; do
  p="${row%%|*}"; label="${row#*|}"
  body=$(curl -s --max-time 20 -X POST \
    -H "Authorization: Bearer junk" -H "Content-Type: application/json" \
    -d '{}' -w $'\n%{http_code}' "$BASE/$p")
  code="${body##*$'\n'}"
  payload="${body%$'\n'*}"

  # A 404 means two completely different things here, and only one is a problem:
  #   - n8n saying the webhook is not registered  -> broken
  #   - the workflow itself answering "Auction not found" for our junk body,
  #     which is a CORRECT response from a healthy endpoint -> fine
  # n8n's unregistered-webhook 404 carries a distinctive message, so match on
  # that rather than trusting the status code alone.
  if [ "$code" = "404" ]; then
    if printf '%s' "$payload" | grep -qi "not registered"; then
      printf "  [XX]  404  %-28s %s  <- NOT REGISTERED\n" "$p" "$label"
      broken=$((broken+1)); bad_list="$bad_list $p"; continue
    fi
    printf "  [ok]  404  %-28s %s  (app 404: registered, no such record)\n" "$p" "$label"
    healthy=$((healthy+1)); continue
  fi

  case "$code" in
    200|400|401) printf "  [ok]  %-3s  %-28s %s\n" "$code" "$p" "$label"; healthy=$((healthy+1)) ;;
    502|500)     printf "  [ok]  %-3s  %-28s %s  (routed; workflow errored - missing key?)\n" "$code" "$p" "$label"; healthy=$((healthy+1)) ;;
    000)         printf "  [??]  ---  %-28s (n8n unreachable)\n" "$p"; unreachable=$((unreachable+1)) ;;
    *)           printf "  [?]   %-3s  %-28s %s\n" "$code" "$p" "$label"; healthy=$((healthy+1)) ;;
  esac
done

echo "================================================================"
echo " healthy: $healthy   not-registered: $broken   unreachable: $unreachable   (of ${#PATHS[@]})"
if [ "$broken" -gt 0 ]; then
  echo ""
  echo " Not registered:$bad_list"
  echo ""
  echo " Next: 'docker restart n8n', wait 90 s, re-run this script. If the same"
  echo " paths still 404, they are orphan webhook_entity rows (blockers 0q) —"
  echo " paste this output to Claude."
fi
if [ "$unreachable" -gt 0 ]; then
  echo " n8n did not answer — it may still be restarting. Wait 60 s, re-run."
fi
echo "================================================================"
