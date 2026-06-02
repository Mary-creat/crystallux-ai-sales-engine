#!/usr/bin/env bash
# Activate LUXI commerce: auctions, Buy Now, bidding, Stripe capture, admin.
# ACTIVATE-ONLY by workflow id via the n8n REST API. Pure curl. Idempotent.
# Run:  N8N_API_KEY=yourkey bash scripts/n8n/activate-luxi.sh

set -uo pipefail
N8N_URL="${N8N_URL:-${CLX_N8N_PUBLIC_URL:-https://automation.crystallux.org}}"
: "${N8N_API_KEY:?Set N8N_API_KEY first (same key ship.sh uses)}"

IDS=(
  "wfLuxiPublicAuctionV1|Public Auction (the buy/bid page reads this)"
  "wfLuxiPublicBuyNowIntentV1|Public Buy Now Intent (starts the card payment)"
  "wfLuxiPublicBuyNowConfirmV1|Public Buy Now Confirm (finishes the sale)"
  "wfLuxiPublicCreateIntentV1|Public Create Bid Intent"
  "wfLuxiPublicConfirmBidV1|Public Confirm Bid"
  "wfLuxiPublicStreamV1|Public Stream Status"
  "clxLuxiStripeCaptureV1|Stripe Capture (collects the money)"
  "wfAdminLuxiAuctionManageV1|Admin: create/edit a listing"
  "wfAdminLuxiAuctionsListV1|Admin: list auctions"
  "wfAdminLuxiBuyNowV1|Admin: Buy Now action"
  "wfAdminLuxiPlaceBidV1|Admin: place a bid"
  "wfAdminLuxiProxyBidV1|Admin: set auto-bid"
  "wfAdminLuxiStreamManageV1|Admin: stream control"
  "wfLuxiAuctionTickV1|Auction tick (anti-snipe + proxy bids)"
  "wfLuxiProxySettleV1|Proxy settle"
  "clxLuxiBidParserV1|Comment-to-bid parser"
)

echo "================================================================"
echo " Activating LUXI commerce (auctions + Buy Now + bidding + capture)"
echo " Activate-only, by id. No definitions changed.  n8n: $N8N_URL"
echo "================================================================"
on=0; problem=0
for row in "${IDS[@]}"; do
  id="${row%%|*}"; label="${row#*|}"
  code=$(curl -s -o /tmp/clx_luxi.json -w "%{http_code}" -X POST \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    "$N8N_URL/api/v1/workflows/$id/activate")
  if [ "$code" = "200" ]; then echo "  [+] ON:        $label"; on=$((on+1))
  else snip=$(head -c 140 /tmp/clx_luxi.json 2>/dev/null | tr -d '\n'); echo "  [x] HTTP $code:  $label   $snip"; problem=$((problem+1)); fi
done
echo "================================================================"
echo " ON: $on   Problems: $problem   (of ${#IDS[@]})"
echo "================================================================"
echo "Next: confirm STRIPE_SECRET_KEY + STRIPE_PUBLISHABLE_KEY reach n8n,"
echo "create one Buy Now listing, then share the buy link. Money goes to Stripe."
