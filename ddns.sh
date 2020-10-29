#!/usr/bin/env bash

#
# Dynamic DNS for CloudFlare.
#
# Requires bash, curl, and jq.
#
# Example of $HOME/cloudflare-ddns.json:
#
# {
#   "domain": "mydomain.com",
#   "record": "sub.mydomain.com",
#   "token":  "cloudflare-api-token-here"
# }
#

set -euo pipefail
alias curl="curl --fail --silent --show-error"
CONFIG="$HOME/cloudflare-ddns.json"
DOMAIN="$(jq -r '.domain' "$CONFIG")"
RECORD="$(jq -r '.record' "$CONFIG")"
TOKEN="$(jq -r '.token' "$CONFIG")"
IP="$(dig @resolver1.opendns.com ANY myip.opendns.com +short)"
API_URL="https://api.cloudflare.com/client/v4"

# Get zone ID for domain
zone_id="$(curl -X GET "$API_URL/zones?name=$DOMAIN" -H "Authorization: Bearer $TOKEN" -H "Content-Type:application/json" | jq -r '.result[0].id')"

# Get record for subdomain
record_id="$(curl -X GET "$API_URL/zones/$zone_id/dns_records?name=$RECORD" -H "Authorization: Bearer $TOKEN" -H "Content-Type:application/json" | jq -r '.result[0].id')"

# Update record with current IP
curl -X PATCH "$API_URL/zones/$zone_id/dns_records/$record_id" -H "Authorization: Bearer $TOKEN" -H "Content-Type:application/json" --data "{\"content\": \"$IP\"}"

