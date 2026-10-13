#!/usr/bin/env bash
# Manage the ratings-dev A record at GoDaddy (Domains v3 API, PAT auth).
#   set-dns.sh show          list A records for the name
#   set-dns.sh set <ip>      upsert: no-op if already correct; else delete stale + create
#   set-dns.sh delete        remove all A records for the name (idempotent)
set -euo pipefail
: "${GD_PAT:?run: source ~/.config/agent-ratings/env}"
ZONE="${ZONE:-theblockchainarcade.io}"
NAME="${NAME:-ratings-dev}"
TTL=600
API="https://api.godaddy.com/v3/domains/zones/$ZONE/dns-records"

# gd METHOD URL [BODY] -> prints response body; fails loudly on non-2xx
gd() {
  local method=$1 url=$2 body=${3:-} out code
  out=$(mktemp)
  code=$(curl -s -o "$out" -w '%{http_code}' -X "$method" \
    -H "Authorization: Bearer $GD_PAT" -H 'Content-Type: application/json' \
    ${body:+--data "$body"} "$url")
  if [ "$code" = 401 ]; then
    echo "GoDaddy 401: PAT expired or revoked -- regenerate at developer.godaddy.com" >&2; rm -f "$out"; exit 2
  fi
  if [ "${code:0:1}" != 2 ]; then
    echo "GoDaddy $method failed: HTTP $code" >&2; cat "$out" >&2; echo >&2; rm -f "$out"; exit 1
  fi
  cat "$out"; rm -f "$out"
}

# "recordId data" per A record whose name matches exactly
list() {
  gd GET "$API?type=A&name=$NAME" \
    | jq -r --arg n "$NAME" '.items[] | select(.name == $n) | "\(.recordId) \(.data)"'
}

cmd_set() {
  local ip=${1:-} have
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: set-dns.sh set <ipv4>"; exit 1; }
  have=$(list)
  if [ "$(printf '%s\n' "$have" | grep -c .)" = 1 ] && [ "${have#* }" = "$ip" ]; then
    echo "OK: $NAME.$ZONE already -> $ip"; return
  fi
  # Remove stale/duplicate records first: two A records = resolvers hand out both.
  while read -r id data; do
    [ -n "$id" ] || continue
    gd DELETE "$API/$id" >/dev/null; echo "deleted stale $NAME -> $data"
  done <<< "$have"
  gd POST "$API" "$(jq -nc --arg n "$NAME" --arg d "$ip" --argjson t "$TTL" \
    '{type:"A", name:$n, data:$d, ttl:$t}')" >/dev/null
  [ "$(list | awk '{print $2}')" = "$ip" ] || { echo "read-back mismatch after create"; exit 1; }
  echo "created $NAME.$ZONE -> $ip (ttl $TTL), verified via API"
}

cmd_delete() {
  local have; have=$(list)
  if [ -z "$have" ]; then echo "OK: no A record for $NAME.$ZONE"; return; fi
  while read -r id data; do
    gd DELETE "$API/$id" >/dev/null; echo "deleted $NAME -> $data"
  done <<< "$have"
  [ -z "$(list)" ] || { echo "read-back: records remain after delete"; exit 1; }
}

case "${1:-}" in
  show)   list ;;
  set)    cmd_set "${2:-}" ;;
  delete) cmd_delete ;;
  *)      echo "usage: set-dns.sh show | set <ip> | delete"; exit 1 ;;
esac
