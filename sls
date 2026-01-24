#!/bin/bash
# sls - Unified Session Launcher for Luanti
# Usage: ./sls <WORLD_NAME> [GAME_PORT] [MAP_PORT] [DB_PORT]

WORLD="${1:-myworld}"
REQ_GAME_PORT="$2"
REQ_MAP_PORT="$3"
REQ_DB_PORT="$4"

# Configuration
SERVICE_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo ~$SERVICE_USER)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLDS_DATA_DIR="$PROJECT_DIR/worlds_data/$WORLD"
DB_DATA_DIR="$WORLDS_DATA_DIR/db"
LOG_DIR="$WORLDS_DATA_DIR/logs"
WORLD_PATH="$HOME/snap/luanti/common/.minetest/worlds/$WORLD"

# PostgreSQL Explicit Path
PG_BIN="/usr/lib/postgresql/12/bin"
export PATH="$PG_BIN:$PATH"

# Load Helper Functions
source "$PROJECT_DIR/scripts/helper_functions.sh"

echo "=== Luanti Session Launcher ==="
echo "World: $WORLD"

# Ensure directories
mkdir -p "$WORLDS_DATA_DIR" "$LOG_DIR" "$WORLD_PATH"

# --- 1. Port Assignment ---

echo "--- Port Assignment ---"

# Game Port
if [ -z "$REQ_GAME_PORT" ]; then
    echo "Finding free Game Port (starting 30000)..."
    GAME_PORT=$(find_free_port 30000)
else
    GAME_PORT=$REQ_GAME_PORT
    check_port_and_prompt $GAME_PORT || exit 1
fi
echo "Game Port: $GAME_PORT"

# Map Port
if [ -z "$REQ_MAP_PORT" ]; then
    echo "Finding free Map Port (starting 8080)..."
    MAP_PORT=$(find_free_port 8080)
else
    MAP_PORT=$REQ_MAP_PORT
    check_port_and_prompt $MAP_PORT || exit 1
fi
echo "Map Port: $MAP_PORT"

# Database Port
if [ -z "$REQ_DB_PORT" ]; then
    echo "Finding free DB Port (starting 5432)..."
    DB_PORT=$(find_free_port 5432)
else
    DB_PORT=$REQ_DB_PORT
    check_port_and_prompt $DB_PORT || exit 1
fi
echo "DB Port: $DB_PORT"

# Middleware Port
echo "Finding free Middleware Port (starting 5000)..."
API_PORT=$(find_free_port 5000)
echo "API Port: $API_PORT"


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
    "$PG_BIN/pg_ctl" -D "$DB_DATA_DIR" stop -m fast > /dev/null 2>&1
    
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
    "$PROJECT_DIR/scripts/init_world_db.sh" "$DB_DATA_DIR" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME"
    if [ $? -ne 0 ]; then
        echo "Error: Database initialization failed."
        exit 1
    fi
fi

# Start Postgres
echo "Starting PostgreSQL on port $DB_PORT..."
"$PG_BIN/pg_ctl" -D "$DB_DATA_DIR" -o "-p $DB_PORT" -l "$LOG_DIR/postgres.log" start -w

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
    "$PROJECT_DIR/scripts/setup_env.sh"
fi

# ... Port Assignment ...

# --- 4. Start Middleware ---
echo "Starting Middleware on port $API_PORT..."
export DB_HOST="localhost"
export DB_PORT="$DB_PORT"
export DB_NAME="$DB_NAME"
export DB_USER="$DB_USER"
export DB_PASS="$DB_PASS"

(
    cd "$PROJECT_DIR"
    # Run using venv python explicitly, pointing to src.api.main
    # We add PROJECT_DIR to PYTHONPATH so it finds src module
    export PYTHONPATH="$PROJECT_DIR"
    "$PROJECT_DIR/venv/bin/python" -m uvicorn src.api.main:app --host 0.0.0.0 --port $API_PORT
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
    # Simple check if port is open using python oneliner because netcat might check TCP connect
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
chmod +x "$PROJECT_DIR/scripts/auto_render_loop.sh"

"$PROJECT_DIR/scripts/auto_render_loop.sh" "$WORLD" "$MAP_OUTPUT" > "$LOG_DIR/map_render.log" 2>&1 &
PIDS="$PIDS $!"

# HTTP Server
(
    cd "$MAP_OUTPUT"
    # range_server is now in src/map/range_server.py
    "$PROJECT_DIR/venv/bin/python" "$PROJECT_DIR/src/map/range_server.py" "$MAP_PORT"
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

if [ -f "$SYSTEM_CONF" ]; then
    cat "$SYSTEM_CONF" > "$SESSION_CONF"
else
    echo "# Base config" > "$SESSION_CONF"
fi

echo "" >> "$SESSION_CONF"
echo "secure.http_mods = position_tracker" >> "$SESSION_CONF"
echo "position_tracker.url = http://localhost:$API_PORT" >> "$SESSION_CONF"

/snap/bin/luanti --server --world "$WORLD_PATH" --gameid minetest_game --port $GAME_PORT --config "$SESSION_CONF"

cleanup
