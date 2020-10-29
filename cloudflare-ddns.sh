#!/usr/bin/env bash
#
# Dynamic DNS for CloudFlare. Requires bash, curl, dig, and jq.
#
# On Alpine, dig is provided by the `bind-tools` package. On Debian/Ubuntu it's in the `dnsutils` package.
#
# For Alpine:
#   apk add --no-cache bash bind-tools curl jq
#
# For Debian/Ubuntu:
#   apt-get install -y bash curl dns-tools jq
#
# Example of /etc/cloudflare-ddns.json:
#
# {
#   "domain": "mydomain.com",
#   "record": "sub.mydomain.com",
#   "token":  "cloudflare-api-token-here"
# }
#
# Configuration file location can be overridden by setting the CONFIG environment variable.

set -euo pipefail

fail() { echo "$*" 2>&1; exit 1; }
assert_notempty() { [[ -n ${!1} ]] || fail "${2:-Value for $1 can not be empty, failing}"; }
alias curl="curl --fail --silent --show-error"

API_URL="https://api.cloudflare.com/client/v4"
CONFIG="${CONFIG:-/etc/cloudflare-ddns.json}"
assert_notempty CONFIG

DOMAIN="$(jq -r '.domain' "$CONFIG")"
assert_notempty DOMAIN

RECORD="$(jq -r '.record' "$CONFIG")"
assert_notempty RECORD

TOKEN="$(jq -r '.token' "$CONFIG")"
assert_notempty TOKEN

IP="$(dig +short myip.opendns.com @resolver1.opendns.com)"
if [[ -z $IP ]]; then
  echo "Failed to get public IP from OpenDNS, trying Google"
  IP="$(dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')"
  assert_notempty IP "Failed to get public IP from OpenDNS or Google"
fi

# Get zone ID for domain
ZONE_ID="$(curl -X GET "$API_URL/zones?name=$DOMAIN" -H "Authorization: Bearer $TOKEN" -H "Content-Type:application/json" | jq -r '.result[0].id')"
assert_notempty ZONE_ID "Failed to retrieve zone ID for $DOMAIN from CloudFlare"

# Get record for subdomain
RECORD_ID="$(curl -X GET "$API_URL/zones/$ZONE_ID/dns_records?name=$RECORD" -H "Authorization: Bearer $TOKEN" -H "Content-Type:application/json" | jq -r '.result[0].id')"
assert_notempty RECORD_ID "Failed to retrieve record ID for $RECORD from CloudFlare"

# Update record with current IP
curl -X PATCH "$API_URL/zones/$ZONE_ID/dns_records/$RECORD_ID" -H "Authorization: Bearer $TOKEN" -H "Content-Type:application/json" --data "{\"content\": \"$IP\"}" || fail "Failed to update DNS for $RECORD"

