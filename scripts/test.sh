#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

DB_USER=${DB_USER:-netly}
DB_PASSWORD=${DB_PASSWORD:-netly}
SERVICES=${*:-profile budget}

docker compose up -d --wait postgres >/dev/null
for service in $SERVICES; do
    database="netly_${service}_test"
    exists=$(docker compose exec -T postgres psql -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$database'")
    [ "$exists" = 1 ] || docker compose exec -T postgres createdb -U "$DB_USER" "$database"
done

mkdir -p coverage
for service in $SERVICES; do
    echo "== $service-service"
    docker run --rm --network netly_default \
        -v "$PWD/services/$service-service":/src -v "$PWD/coverage":/coverage -w /src \
        -e DB_HOST=postgres -e DB_NAME="netly_${service}_test" -e DB_USER="$DB_USER" -e DB_PASSWORD="$DB_PASSWORD" \
        -e SERVICE="$service" \
        swift:6.2-noble bash -c '
            set -euo pipefail
            swift test --enable-code-coverage
            bin=$(swift build --show-bin-path)
            tests="$bin/$SERVICE-servicePackageTests.xctest"
            ignore="(\.build|Tests)/"
            llvm-cov report "$tests" -instr-profile="$bin/codecov/default.profdata" -ignore-filename-regex="$ignore" \
                | tee "/coverage/$SERVICE-service.txt"
            rm -rf "/coverage/$SERVICE-service"
            llvm-cov show "$tests" -instr-profile="$bin/codecov/default.profdata" -ignore-filename-regex="$ignore" \
                -format=html -output-dir="/coverage/$SERVICE-service"
        '
done
echo "Coverage: coverage/<service>-service.txt, HTML in coverage/<service>-service/index.html"
