#!/usr/bin/env bash
# Auth demo: register and log in through Profile Service, then call Budget Service with the issued token.
# Shows the status codes the API is built around: 201, 200, 422, 401, 403, 404.
# Needs the compose stack running: docker compose up -d --build
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE=http://localhost:8081/api/v1
BUDGET=http://localhost:8082/api/v1
RUN=$(date +%s)

call() {
    local method=$1 url=$2 token=${3:-} body=${4:-}
    printf '\n\033[0;33m$ curl -X %s %s%s%s\033[0m\n' "$method" "${url#http://localhost}" \
        "${token:+ -H 'Authorization: Bearer …'}" "${body:+ -d '$body'}"
    curl -s -i -X "$method" "$url" -H "Content-Type: application/json" \
        ${token:+-H "Authorization: Bearer $token"} ${body:+-d "$body"} \
        | grep -v -i -E '^(date|server|content-length|connection):' | tr -d '\r'
    echo
}
token_for() {
    curl -s -X POST "$PROFILE/auth/login" -H "Content-Type: application/json" \
        -d "{\"email\": \"$1\", \"password\": \"$2\"}" | jq -r .accessToken
}

echo "==== 1. Регистрация и вход"
call POST "$PROFILE/auth/register" "" "{\"email\": \"alibek+$RUN@netly.kz\", \"password\": \"correct horse\", \"role\": \"admin\"}"
call POST "$PROFILE/auth/login" "" "{\"email\": \"alibek+$RUN@netly.kz\", \"password\": \"correct horse\"}"
call POST "$PROFILE/auth/login" "" "{\"email\": \"alibek+$RUN@netly.kz\", \"password\": \"wrong password\"}"
TOKEN=$(token_for "alibek+$RUN@netly.kz" "correct horse")

echo "==== 2. Budget Service принимает токен Profile Service"
call POST "$BUDGET/goals" "$TOKEN" '{"name": "Laptop", "targetAmount": 1500, "targetDate": "2027-12-31", "priority": 8}'
call POST "$BUDGET/goals" "$TOKEN" '{"name": " ", "targetAmount": -5, "targetDate": "2020-01-01", "priority": 11}'
call GET "$BUDGET/goals?status=active&limit=1"

echo "==== 3. Чужая запись и чужая роль"
GOAL=$(curl -s "$BUDGET/goals?limit=1" -H "Authorization: Bearer $TOKEN" | jq -r '.items[0].id')
call POST "$PROFILE/auth/register" "" "{\"email\": \"other+$RUN@netly.kz\", \"password\": \"another secret\"}" >/dev/null
OTHER=$(token_for "other+$RUN@netly.kz" "another secret")
call GET "$BUDGET/goals/$GOAL" "$OTHER"
call GET "$PROFILE/admin/users" "$TOKEN"
call GET "$PROFILE/users/me" "$TOKEN"
