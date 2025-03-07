#!/bin/bash
set -e

# Load environment variables
source /.env

# Create DB and User based on .env variables
psql -v ON_ERROR_STOP=1 --username "$DB_USER" <<-EOSQL
    CREATE DATABASE $DB_NAME;
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
    CREATE USER airflow WITH PASSWORD '$AIRFLOW_POSTGRES_PASSWORD';
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO airflow;
EOSQL
