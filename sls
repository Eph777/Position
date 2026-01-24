#!/bin/bash
# sls - Unified Session Launcher for Luanti
# Usage: ./sls <WORLD_NAME> [GAME_PORT] [MAP_PORT] [DB_PORT]

WORLD="${1:-myworld}"
REQ_GAME_PORT="$2"
REQ_MAP_PORT="$3"
REQ_DB_PORT="$4"

# Configuration
# If running as root (SUDO_USER is set), we need to handle DB carefully.
# Configuration
SERVICE_USER=${SUDO_USER:-$(whoami)}
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PostgreSQL Explicit Path
PG_BIN="/usr/lib/postgresql/16/bin"
export PATH="$PG_BIN:$PATH"

# Root Handling Logic
if [ "$EUID" -eq 0 ] && [ "$SERVICE_USER" == "root" ]; then
    echo "Request running as bare root. Switching DB operations to 'postgres' user."
    DB_RUNNER="postgres"
    # We cannot use /root/... for DB because postgres user can't access it.
    # Use /var/lib/luanti_sessions instead.
    BASE_DATA_DIR="/var/lib/luanti_sessions"
else
    DB_RUNNER="$SERVICE_USER"
    BASE_DATA_DIR="$PROJECT_DIR/worlds_data"
fi

WORLDS_DATA_DIR="$BASE_DATA_DIR/$WORLD"
DB_DATA_DIR="$WORLDS_DATA_DIR/db"
LOG_DIR="$WORLDS_DATA_DIR/logs"
WORLD_PATH="$HOME/snap/luanti/common/.minetest/worlds/$WORLD"

# Load Helper Functions
source "$PROJECT_DIR/scripts/helper_functions.sh"

echo "=== Luanti Session Launcher ==="
echo "World: $WORLD"
echo "Service User: $SERVICE_USER"
echo "DB Runner: $DB_RUNNER"
echo "Data Dir: $WORLDS_DATA_DIR"

# Ensure directories
mkdir -p "$WORLDS_DATA_DIR" "$LOG_DIR" "$WORLD_PATH"

# Fix permissions if running as root
if [ "$EUID" -eq 0 ]; then
    # If we are using /var/lib, ensure postgres owns the db part
    chown -R "$DB_RUNNER:$DB_RUNNER" "$WORLDS_DATA_DIR"
    # Also ensure log dir is writable by us (root) and maybe db runner?
    # Actually, if we run pg_ctl as postgres, log file must be writable by postgres.
    chown -R "$DB_RUNNER:$DB_RUNNER" "$LOG_DIR"
fi

# ... (Port assignment skipped in diff, assume unchanged)

# --- 2. Process Management ---
PIDS=""

cleanup() {
    echo ""
    echo "--- Stopping Session ---"
    for pid in $PIDS; do
        if ps -p $pid > /dev/null; then
            echo "Stopping PID $pid..."
            kill $pid 2>/dev/null
        fi
    done
    
    echo "Stopping Database..."
    # Stop DB as the correct user
    if [ "$EUID" -eq 0 ]; then
        if [ "$DB_RUNNER" == "postgres" ]; then
             su - postgres -c "$PG_BIN/pg_ctl -D \"$DB_DATA_DIR\" stop -m fast" > /dev/null 2>&1
        else
             su - "$SERVICE_USER" -c "$PG_BIN/pg_ctl -D \"$DB_DATA_DIR\" stop -m fast" > /dev/null 2>&1
        fi
    else
        "$PG_BIN/pg_ctl" -D "$DB_DATA_DIR" stop -m fast > /dev/null 2>&1
    fi
    
    echo "Cleanup complete."
    exit 0
}
trap cleanup SIGINT SIGTERM

# --- 3. Start Database ---
echo "--- Starting Services ---"

DB_USER="$WORLD"
DB_PASS="pass_$WORLD"
DB_NAME="luanti_db"

# Initialize
if [ ! -d "$DB_DATA_DIR" ]; then
    echo "Initializing new database cluster..."
    chmod +x "$PROJECT_DIR/scripts/init_world_db.sh"
    
    # Run init script as DB_RUNNER
    if [ "$EUID" -eq 0 ]; then
         # Ensure script is readable by DB_RUNNER?
         # Scripts are in PROJECT_DIR (possibly /root). ROOT can read.
         # But 'su - postgres' might lose access to /root/luanti-qgis/scripts/init...
         # We need to copy the script to tmp? or make it accessible?
         # 'postgres' user definitely can't run /root/.../script.sh
         
         if [ "$DB_RUNNER" == "postgres" ]; then
             echo "Copying init script to /tmp for postgres execution..."
             cp "$PROJECT_DIR/scripts/init_world_db.sh" /tmp/init_world_db_tmp.sh
             cp "$PROJECT_DIR/scripts/schema.sql" /tmp/schema.sql
             chmod 777 /tmp/init_world_db_tmp.sh /tmp/schema.sql
             # Need to patch schema path in the temp script?
             # The script looks for schema.sql relative to itself.
             # So putting them in same dir /tmp works if script does `dirname`.
             
             chown postgres:postgres "$DB_DATA_DIR"
             
             su - postgres -c "/tmp/init_world_db_tmp.sh \"$DB_DATA_DIR\" \"$DB_PORT\" \"$DB_USER\" \"$DB_PASS\" \"$DB_NAME\""
         else
             chown "$SERVICE_USER:$SERVICE_USER" "$PROJECT_DIR/scripts/init_world_db.sh"
             su - "$SERVICE_USER" -c "\"$PROJECT_DIR/scripts/init_world_db.sh\" \"$DB_DATA_DIR\" \"$DB_PORT\" \"$DB_USER\" \"$DB_PASS\" \"$DB_NAME\""
         fi
    else
         "$PROJECT_DIR/scripts/init_world_db.sh" "$DB_DATA_DIR" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME"
    fi
    
    if [ $? -ne 0 ]; then
        echo "Error: Database initialization failed."
        exit 1
    fi
fi

# Start Postgres
echo "Starting PostgreSQL on port $DB_PORT..."
if [ "$EUID" -eq 0 ]; then
    su - "$DB_RUNNER" -c "$PG_BIN/pg_ctl -D \"$DB_DATA_DIR\" -o \"-p $DB_PORT\" -l \"$LOG_DIR/postgres.log\" start -w"
else
    "$PG_BIN/pg_ctl" -D "$DB_DATA_DIR" -o "-p $DB_PORT" -l "$LOG_DIR/postgres.log" start -w
fi

# Wait for DB to be responsive
echo "Waiting for Database readiness..."
MAX_RETRIES=15
for i in $(seq 1 $MAX_RETRIES); do
    if "$PG_BIN/pg_isready" -h localhost -p "$DB_PORT" >/dev/null 2>&1; then
        echo "Database Ready."
        break
    fi
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "Error: Database failed to start."
        echo "LOGS:"
        tail -n 10 "$LOG_DIR/postgres.log"
        cleanup
        exit 1
    fi
    sleep 1
done

# --- 4. Start Middleware ---
echo "Starting Middleware on port $API_PORT..."
export DB_HOST="localhost"
export DB_PORT="$DB_PORT"
export DB_NAME="$DB_NAME"
export DB_USER="$DB_USER"
export DB_PASS="$DB_PASS"

# Ensure Environment
if [ ! -d "$PROJECT_DIR/venv" ]; then
    echo "Python virtual environment missing. Running setup..."
    chmod +x "$PROJECT_DIR/scripts/setup_env.sh"
    if [ "$EUID" -eq 0 ]; then
        chown "$SERVICE_USER:$SERVICE_USER" "$PROJECT_DIR/scripts/setup_env.sh"
        su - "$SERVICE_USER" -c "\"$PROJECT_DIR/scripts/setup_env.sh\""
    else
        "$PROJECT_DIR/scripts/setup_env.sh"
    fi
fi

# Ensure permissions on venv if root created it
if [ "$EUID" -eq 0 ]; then
    chown -R "$SERVICE_USER:$SERVICE_USER" "$PROJECT_DIR/venv"
fi

(
    cd "$PROJECT_DIR"
    export PYTHONPATH="$PROJECT_DIR"
    # Run using venv python explicitly, pointing to src.api.main
    CMD="\"$PROJECT_DIR/venv/bin/python\" -m uvicorn src.api.main:app --host 0.0.0.0 --port $API_PORT"
    
    if [ "$EUID" -eq 0 ]; then
        su - "$SERVICE_USER" -c "$CMD"
    else
        eval $CMD
    fi
) > "$LOG_DIR/api.log" 2>&1 &
API_PID=$!
PIDS="$PIDS $API_PID"

# Wait for API
echo "Waiting for Middleware..."
for i in {1..10}; do
    if ! ps -p $API_PID > /dev/null; then
        echo "Error: Middleware crashed."
        cat "$LOG_DIR/api.log"
        cleanup
        exit 1
    fi
    if python3 -c "import socket; s=socket.socket(); s.connect(('localhost', $API_PORT))" >/dev/null 2>&1; then
        echo "Middleware Ready."
        break
    fi
    sleep 1
done


# --- 5. Start Map System ---
echo "Starting Map System on port $MAP_PORT..."

# Renderer
MAP_OUTPUT="$WORLD_PATH/map_output"
mkdir -p "$MAP_OUTPUT"
if [ "$EUID" -eq 0 ]; then
    chown -R "$SERVICE_USER:$SERVICE_USER" "$MAP_OUTPUT"
fi
chmod +x "$PROJECT_DIR/scripts/auto_render_loop.sh"

# Run renderer as user
CMD="\"$PROJECT_DIR/scripts/auto_render_loop.sh\" \"$WORLD\" \"$MAP_OUTPUT\""
if [ "$EUID" -eq 0 ]; then
    su - "$SERVICE_USER" -c "$CMD" > "$LOG_DIR/map_render.log" 2>&1 &
    PIDS="$PIDS $!"
else
    eval "$CMD" > "$LOG_DIR/map_render.log" 2>&1 &
    PIDS="$PIDS $!"
fi

# HTTP Server
(
    cd "$MAP_OUTPUT"
    # range_server is now in src/map/range_server.py
    # Using python from venv
    CMD="\"$PROJECT_DIR/venv/bin/python\" \"$PROJECT_DIR/src/map/range_server.py\" \"$MAP_PORT\""
    if [ "$EUID" -eq 0 ]; then
        su - "$SERVICE_USER" -c "$CMD"
    else
        eval $CMD
    fi
) > "$LOG_DIR/map_http.log" 2>&1 &
PIDS="$PIDS $!"


# --- 6. Start Game ---
echo "--- Session Active ---"
echo "Game Port: $GAME_PORT"
echo "Web Manager: http://localhost:$API_PORT"
echo "Live Map: http://localhost:$MAP_PORT/map.png"
echo "Ctrl+C to stop."

# Config Generation
SESSION_CONF="$WORLDS_DATA_DIR/minetest.conf"
SYSTEM_CONF="$HOME/snap/luanti/common/.minetest/minetest.conf"

# Fix ownership of config if root
if [ "$EUID" -eq 0 ]; then
    touch "$SESSION_CONF"
    chown "$SERVICE_USER:$SERVICE_USER" "$SESSION_CONF"
fi

if [ -f "$SYSTEM_CONF" ]; then
    cat "$SYSTEM_CONF" > "$SESSION_CONF"
else
    echo "# Base config" > "$SESSION_CONF"
fi

echo "" >> "$SESSION_CONF"
echo "secure.http_mods = position_tracker" >> "$SESSION_CONF"
echo "position_tracker.url = http://localhost:$API_PORT" >> "$SESSION_CONF"

# Luanti might need running as user too?
# Usually snap binaries are fine, but prefer running as user to access user's home/worlds.
CMD="/snap/bin/luanti --server --world \"$WORLD_PATH\" --gameid minetest_game --port $GAME_PORT --config \"$SESSION_CONF\""

if [ "$EUID" -eq 0 ]; then
     # Use su to run as service user
     su - "$SERVICE_USER" -c "$CMD"
else
     eval $CMD
fi

cleanup
