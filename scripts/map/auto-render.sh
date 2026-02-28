#!/bin/bash
# Copyright (C) 2026 Ephraim BOURIAHI
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Auto-render map loop - continuously renders the Luanti map
# Usage: ./auto-render.sh <world_name> [interval_seconds]

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

WORLD="$1"
# Default 15 seconds is no longer needed since we use inotifywait
if [ -z "$WORLD" ]; then
    print_error "Usage: $0 <world_name> [interval_seconds]"
    exit 1
fi

# PROJECT_ROOT=$(get_project_root)
RENDER_SCRIPT="$PROJECT_ROOT/scripts/map/render.sh"

if [ ! -f "$RENDER_SCRIPT" ]; then
    print_error "Render script not found: $RENDER_SCRIPT"
    exit 1
fi

WORLD_PATH="$(get_user_home)/snap/luanti/common/.minetest/worlds/$WORLD"

if [ ! -f "$WORLD_PATH/map.sqlite" ]; then
    print_error "map.sqlite not found at $WORLD_PATH/map.sqlite"
    exit 1
fi

print_info "Starting event-driven auto-render loop for world: $WORLD"

while true; do
    print_info "Waiting for map.sqlite modifications..."
    inotifywait -q -e modify "$WORLD_PATH/map.sqlite"
    
    # Wait to batch rapid block placements
    print_info "Database modified! Waiting 5s to batch changes..."
    sleep 5
    
    print_info "Starting incremental render cycle..."
    $RENDER_SCRIPT "$WORLD"
done
