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
