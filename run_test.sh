#!/bin/bash

# Configuration
WORLD="${1:-testworld}"
GAME_PORT="${2:-30001}"
MAP_PORT="${3:-8081}"

# ensures port is open
sudo ufw allow "$MAP_PORT"/tcp
sudo ufw allow "$GAME_PORT"/udp 

SERVICE_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo ~$SERVICE_USER)
PROJECT_DIR="$USER_HOME/luanti-qgis"

# Unique output directory for this test instance/world
MAP_OUTPUT="$PROJECT_DIR/map_output_${WORLD}"
mkdir -p "$MAP_OUTPUT"

echo "=== Starting Test Environment ==="
echo "World: $WORLD"
echo "Game Port: $GAME_PORT"
echo "Map Port: $MAP_PORT"
echo "Map Output: $MAP_OUTPUT"
echo "==============================="

# Track PIDs for cleanup
PIDS=""

cleanup() {
    echo ""
    echo "Stopping background processes..."
    for pid in $PIDS; do
        if ps -p $pid > /dev/null; then
            echo "Killing PID $pid"
            kill $pid 2>/dev/null
        fi
    done
    echo "Test environment stopped."
    exit 0
}

# Trap SIGINT (Ctrl+C) and SIGTERM
trap cleanup SIGINT SIGTERM

# 1. Start Auto Renderer in Background
echo "[Test] Starting Map Renderer..."
check_render_script="$PROJECT_DIR/auto_render_loop.sh"
if [ ! -x "$check_render_script" ]; then
    chmod +x "$check_render_script"
fi
$PROJECT_DIR/auto_render_loop.sh "$WORLD" "$MAP_OUTPUT" > "$MAP_OUTPUT/render.log" 2>&1 &
PIDS="$PIDS $!"

# 2. Start Map Server in Background
echo "[Test] Starting Map HTTP Server on port $MAP_PORT..."
# We must CD to the output dir for SimpleHTTPRequestHandler to serve those files
(
    cd "$MAP_OUTPUT"
    python3 "$PROJECT_DIR/range_server.py" "$MAP_PORT"
) > "$MAP_OUTPUT/http.log" 2>&1 &
PIDS="$PIDS $!"

# 3. Start Game Server (Foreground)
# We use the existing sls script which handles world creation/mgmt
echo "[Test] Starting Luanti Game Server on port $GAME_PORT..."
echo "Press Ctrl+C to stop everything."
echo ""
~/sls "$WORLD" "$GAME_PORT"

# When sls exits (if it does), we cleanup
cleanup
