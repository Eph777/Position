#!/bin/bash
WORLD="$1"
OUTPUT_DIR="$2"

SERVICE_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo ~$SERVICE_USER)
PROJECT_DIR="$USER_HOME/luanti-qgis"
RENDER_SCRIPT="$PROJECT_DIR/render_map.sh"

while true; do
    echo "Starting render..."
    $RENDER_SCRIPT "$WORLD" "$OUTPUT_DIR"
    echo "Sleeping 15s..."
    sleep 15
done