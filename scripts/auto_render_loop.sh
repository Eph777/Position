#!/bin/bash
WORLD="$1"

SERVICE_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo ~$SERVICE_USER)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER_SCRIPT="$PROJECT_DIR/scripts/render_map.sh"

while true; do
    echo "Starting render..."
    if [ ! -x "$RENDER_SCRIPT" ]; then
         chmod +x "$RENDER_SCRIPT"
    fi
    "$RENDER_SCRIPT" "$WORLD" "$OUTPUT_DIR"
    echo "Sleeping 15s..."
    sleep 15
done