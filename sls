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

# Load Helper Functions
source "$PROJECT_DIR/helper_functions.sh"

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

# Middleware Port (Internal, also needs finding)
# We assume we always need to find a free one, or default to 5000+
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
    
    # Stop Postgres explicitly if needed (pg_ctl)
    echo "Stopping Database..."
    pg_ctl -D "$DB_DATA_DIR" stop -m fast > /dev/null 2>&1
    
    echo "Cleanup complete."
    exit 0
}
trap cleanup SIGINT SIGTERM

# --- 3. Start Database ---
echo "--- Starting Services ---"

DB_USER="$WORLD"
DB_PASS="pass_$WORLD" # Simple deterministic password for isolation
DB_NAME="luanti_db"

# Initialize if needed
if [ ! -d "$DB_DATA_DIR" ]; then
    echo "Initializing new database cluster for '$WORLD'..."
    chmod +x "$PROJECT_DIR/scripts/init_world_db.sh"
    "$PROJECT_DIR/scripts/init_world_db.sh" "$DB_DATA_DIR" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME"
fi

# Start Postgres
echo "Starting PostgreSQL on port $DB_PORT..."
pg_ctl -D "$DB_DATA_DIR" -o "-p $DB_PORT" -l "$LOG_DIR/postgres.log" start
# Wait for it
sleep 2

# --- 4. Start Middleware ---
echo "Starting Middleware on port $API_PORT..."
export DB_HOST="localhost"
export DB_PORT="$DB_PORT"
export DB_NAME="$DB_NAME"
export DB_USER="$DB_USER" # The middleware connects as the 'superuser' for this instance (owner)
export DB_PASS="$DB_PASS"

# We use uvicorn directly
# Note: server_fastapi.py must be in python path or current dir
(
    cd "$PROJECT_DIR"
    source venv/bin/activate
    uvicorn server_fastapi:app --host 0.0.0.0 --port $API_PORT
) > "$LOG_DIR/api.log" 2>&1 &
PIDS="$PIDS $!"


# --- 5. Start Map System ---
echo "Starting Map System on port $MAP_PORT..."

# Renderer
chmod +x "$PROJECT_DIR/auto_render_loop.sh"
# Check if map output dir exists in world path? 
# User wanted "own map page". 
# auto_render_loop.sh expects WORLD as arg1, OUTPUT as arg2
MAP_OUTPUT="$WORLD_PATH/map_output"
mkdir -p "$MAP_OUTPUT"

"$PROJECT_DIR/auto_render_loop.sh" "$WORLD" "$MAP_OUTPUT" > "$LOG_DIR/map_render.log" 2>&1 &
PIDS="$PIDS $!"

# HTTP Server
(
    cd "$MAP_OUTPUT"
    python3 "$PROJECT_DIR/range_server.py" "$MAP_PORT"
) > "$LOG_DIR/map_http.log" 2>&1 &
PIDS="$PIDS $!"


# --- 6. Start Game ---
echo "--- Starting Game ---"
echo "Game: Port $GAME_PORT"
echo "Map: http://localhost:$MAP_PORT/map.png"
echo "Web Interface: http://localhost:$API_PORT"
echo "Logging to: $LOG_DIR"
echo "Press Ctrl+C to stop."

# Ensure World Config
if [ ! -f "$WORLD_PATH/world.mt" ]; then
    echo "Creating world config..."
    echo "gameid = minetest_game" > "$WORLD_PATH/world.mt"
    echo "backend = sqlite3" >> "$WORLD_PATH/world.mt"
    echo "load_mod_position_tracker = true" >> "$WORLD_PATH/world.mt"
else
    # Ensure mod enabled
    grep -q "load_mod_position_tracker" "$WORLD_PATH/world.mt" || echo "load_mod_position_tracker = true" >> "$WORLD_PATH/world.mt"
fi

# Start Luanti
# Config Generation for this session
SESSION_CONF="$WORLDS_DATA_DIR/minetest.conf"
SYSTEM_CONF="$HOME/snap/luanti/common/.minetest/minetest.conf"

echo "Generating session config: $SESSION_CONF"
# Start fresh or copy system? For total isolation, let's include system but override.
if [ -f "$SYSTEM_CONF" ]; then
    cat "$SYSTEM_CONF" > "$SESSION_CONF"
else
    echo "# Base config" > "$SESSION_CONF"
fi

# Append dynamic settings
echo "" >> "$SESSION_CONF"
echo "# Dynamic Session Settings" >> "$SESSION_CONF"
echo "secure.http_mods = position_tracker" >> "$SESSION_CONF"
echo "position_tracker.url = http://localhost:$API_PORT" >> "$SESSION_CONF"

# Start Luanti
/snap/bin/luanti --server --world "$WORLD_PATH" --gameid minetest_game --port $GAME_PORT --config "$SESSION_CONF"

cleanup
