#!/bin/bash
WORLD="$1"

SERVICE_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo ~$SERVICE_USER)
PROJECT_DIR="$USER_HOME/luanti-qgis"
RENDER_SCRIPT="$PROJECT_DIR/render_map.sh"

while true; do
    echo "Starting render..."
    $RENDER_SCRIPT $WORLD
    echo "Sleeping 15s..."
    sleep 15
done