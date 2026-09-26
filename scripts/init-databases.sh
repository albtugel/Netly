#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE netly_budget;
    GRANT ALL PRIVILEGES ON DATABASE netly_budget TO $POSTGRES_USER;
EOSQL
