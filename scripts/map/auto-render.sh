#!/bin/bash
# Auto-render map loop - continuously renders the Luanti map
# Usage: ./auto-render.sh <world_name> [interval_seconds]

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

WORLD="$1"
INTERVAL="${2:-15}"  # Default 15 seconds

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 <world_name> [interval_seconds]"
    exit 1
fi

PROJECT_ROOT=$(get_project_root)
RENDER_SCRIPT="$PROJECT_ROOT/scripts/map/render.sh"

if [ ! -f "$RENDER_SCRIPT" ]; then
    print_error "Render script not found: $RENDER_SCRIPT"
    exit 1
fi

print_info "Starting auto-render loop for world: $WORLD (interval: ${INTERVAL}s)"

while true; do
    print_info "Starting render..."
    $RENDER_SCRIPT "$WORLD"
    print_info "Sleeping ${INTERVAL}s..."
    sleep "$INTERVAL"
done
