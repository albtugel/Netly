#!/bin/bash
# Issues a development JWT (HS256) accepted by Budget Service, for curl and manual testing.
#
# Usage: scripts/dev-token.sh [user-uuid] [ttl-seconds]
# Env:   JWT_SECRET  signing secret, defaults to the docker-compose development secret
set -euo pipefail

secret="${JWT_SECRET:-netly-dev-jwt-secret-change-me-32bytes}"
user_id="${1:-$(uuidgen | tr '[:upper:]' '[:lower:]')}"
ttl="${2:-86400}"
exp=$(( $(date +%s) + ttl ))

base64url() {
  openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

header=$(printf '{"alg":"HS256","typ":"JWT"}' | base64url)
payload=$(printf '{"sub":"%s","exp":%d}' "$user_id" "$exp" | base64url)
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -hmac "$secret" -binary | base64url)

printf '%s.%s.%s\n' "$header" "$payload" "$signature"
