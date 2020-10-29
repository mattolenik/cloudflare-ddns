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
# Set the DEBUG environment variable to print responses from the CloudFlare API.

set -euo pipefail

fail() { echo "$*" 2>&1; exit 1; }
debug() { if [[ -n ${DEBUG:-} ]]; then local val="$1"; shift; printf '\n%s: %s\n' "$val" "$*"; fi }
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

ip="$(dig +short myip.opendns.com @resolver1.opendns.com)"
if [[ -z $ip ]]; then
  echo "Failed to get public IP from OpenDNS, trying Google"
  ip="$(dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')"
  assert_notempty IP "Failed to get public IP from OpenDNS or Google"
fi

# Get zone info
zone="$(curl -X GET "$API_URL/zones?name=$DOMAIN" -H "Authorization: Bearer $TOKEN" -H "Content-Type:application/json")"
debug "Zone info" "$zone"

# Get zone ID for domain
zone_id="$(jq -r '.result[0].id' <<< "$zone")"
assert_notempty zone_id "Failed to retrieve zone ID for $DOMAIN from CloudFlare"

# Get record info
record_info="$(curl -X GET "$API_URL/zones/$zone_id/dns_records?name=$RECORD" -H "Authorization: Bearer $TOKEN" -H "Content-Type:application/json")"
debug "Current record" "$record_info"

old_ip="$(jq -r '.result[0].content' <<< "$record_info")"
debug "Current IP is" "$old_ip"

# Get record for subdomain
record_id="$(jq -r '.result[0].id' <<< "$record_info")"
assert_notempty record_id "Failed to retrieve record ID for $RECORD from CloudFlare"

# Update record with current IP
new_record="$(curl -X PATCH "$API_URL/zones/$zone_id/dns_records/$record_id" -H "Authorization: Bearer $TOKEN" -H "Content-Type:application/json" --data "{\"content\": \"$ip\"}" || fail "Failed to update DNS for $record_info")"
debug "New record" "$new_record"

if [[ $old_ip != "$ip" ]]; then
  echo "Successfully updated $RECORD to point at $ip"
else
  echo "DNS record $RECORD has not changed, points to $ip"
fi

