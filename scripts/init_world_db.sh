#!/bin/bash
# scripts/init_world_db.sh
# Usage: ./init_world_db.sh <DATA_DIR> <PG_PORT> <DB_USER> <DB_PASS> <DB_NAME>

DATA_DIR="$1"
PG_PORT="$2"
DB_USER="$3"
DB_PASS="$4"
DB_NAME="$5"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/schema.sql" ]; then
    SCHEMA_FILE="$SCRIPT_DIR/schema.sql"
else
    PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    SCHEMA_FILE="$PROJECT_DIR/scripts/schema.sql"
fi

# Explicit Paths for User Environment
PG_BIN="/usr/lib/postgresql/16/bin"
export PATH="$PG_BIN:$PATH"

if [ ! -x "$PG_BIN/initdb" ]; then
    echo "Error: initdb not found at $PG_BIN/initdb"
    exit 1
fi

if [ -d "$DATA_DIR" ]; then
    # Directory exists, check if empty
    if [ "$(ls -A $DATA_DIR 2>/dev/null)" ]; then
         echo "[DB Init] Data directory $DATA_DIR exists and is not empty. Skipping initdb."
         exit 0
    fi
fi

echo "[DB Init] Initializing database in $DATA_DIR..."
mkdir -p "$DATA_DIR"

# 1. Init DB
"$PG_BIN/initdb" -D "$DATA_DIR" --auth-local=trust --no-instructions > /dev/null
if [ $? -ne 0 ]; then
   echo "Error: initdb failed."
   exit 1
fi

# 2. Configure postgresql.conf
echo "listen_addresses = '*'" >> "$DATA_DIR/postgresql.conf"
echo "port = $PG_PORT" >> "$DATA_DIR/postgresql.conf"
echo "shared_buffers = 128MB" >> "$DATA_DIR/postgresql.conf"
echo "max_connections = 20" >> "$DATA_DIR/postgresql.conf"

# 3. Start temporarily to bootstrap
echo "[DB Init] Bootstrapping..."
LOG_FILE="$DATA_DIR/boot.log"
"$PG_BIN/pg_ctl" -D "$DATA_DIR" -o "-p $PG_PORT" -l "$LOG_FILE" start -w

# Wait for start (pg_ctl -w should handle it, but allow a moment)
sleep 2

# 4. Create User and Database
# We connect as 'postgres' (superuser created by initdb) using local trust
"$PG_BIN/psql" -p "$PG_PORT" -h localhost -U postgres -d postgres <<EOF
DROP USER IF EXISTS "${DB_USER}";
CREATE USER "${DB_USER}" WITH PASSWORD '${DB_PASS}' SUPERUSER CREATEROLE;
DROP DATABASE IF EXISTS "${DB_NAME}";
CREATE DATABASE "${DB_NAME}";
GRANT ALL PRIVILEGES ON DATABASE "${DB_NAME}" TO "${DB_USER}";
\c "${DB_NAME}"
CREATE EXTENSION IF NOT EXISTS postgis;
GRANT ALL ON SCHEMA public TO "${DB_USER}";
EOF

if [ $? -ne 0 ]; then
    echo "Error: Failed to create user/database."
    cat "$LOG_FILE"
    "$PG_BIN/pg_ctl" -D "$DATA_DIR" stop -m fast
    exit 1
fi

# 5. Import Schema
export PGPASSWORD="$DB_PASS"
"$PG_BIN/psql" -p "$PG_PORT" -h localhost -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE"

# 6. Stop temporary instance
"$PG_BIN/pg_ctl" -D "$DATA_DIR" stop -m fast
echo "[DB Init] Database initialized successfully."
