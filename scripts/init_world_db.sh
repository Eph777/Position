#!/bin/bash
# scripts/init_world_db.sh
# Usage: ./init_world_db.sh <DATA_DIR> <PG_PORT> <DB_USER> <DB_PASS> <DB_NAME>

DATA_DIR="$1"
PG_PORT="$2"
DB_USER="$3"
DB_PASS="$4"
DB_NAME="$5"

SCHEMA_FILE="schema.sql" # Assuming run from project root or path provided

# PostgreSQL Binaries Path
PG_BIN="/usr/lib/postgresql/12/bin"
export PATH="$PG_BIN:$PATH"

if [ -d "$DATA_DIR" ]; then
    echo "[DB Init] Data directory $DATA_DIR exists. Skipping initdb."
    exit 0
fi

echo "[DB Init] Initializing database in $DATA_DIR..."
mkdir -p "$DATA_DIR"

# 1. Init DB
"$PG_BIN/initdb" -D "$DATA_DIR" --auth-local=trust --no-instructions > /dev/null 2>&1
if [ $? -ne 0 ]; then
   echo "Error: initdb failed."
   exit 1
fi

# 2. Configure postgresql.conf (Optimize for small ephemeral instance?)
echo "listen_addresses = '*'" >> "$DATA_DIR/postgresql.conf"
echo "port = $PG_PORT" >> "$DATA_DIR/postgresql.conf"
# Reduce RAM usage for per-world instances
echo "shared_buffers = 128MB" >> "$DATA_DIR/postgresql.conf"
echo "max_connections = 20" >> "$DATA_DIR/postgresql.conf"

# 3. Start temporarily to bootstrap
echo "[DB Init] Bootstrapping..."
LOG_FILE="$DATA_DIR/boot.log"
pg_ctl -D "$DATA_DIR" -o "-p $PG_PORT" -l "$LOG_FILE" start

# Wait for start
sleep 2

# 4. Create User and Database
# We connect as 'postgres' (superuser created by initdb)
psql -p "$PG_PORT" -h localhost -U postgres -d postgres <<EOF
CREATE USER "${DB_USER}" WITH PASSWORD '${DB_PASS}' SUPERUSER CREATEROLE;
CREATE DATABASE "${DB_NAME}";
GRANT ALL PRIVILEGES ON DATABASE "${DB_NAME}" TO "${DB_USER}";
\c "${DB_NAME}"
CREATE EXTENSION IF NOT EXISTS postgis;
GRANT ALL ON SCHEMA public TO "${DB_USER}";
EOF

# 5. Import Schema
# Using the new user
export PGPASSWORD="$DB_PASS"
psql -p "$PG_PORT" -h localhost -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE"

# 6. Stop temporary instance
pg_ctl -D "$DATA_DIR" stop
echo "[DB Init] Database initialized successfully."
