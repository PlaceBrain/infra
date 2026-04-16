#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE telemetry_db;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname telemetry_db <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS timescaledb;
EOSQL
