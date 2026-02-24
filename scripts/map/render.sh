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

# Render Luanti world map once
# Usage: ./render.sh <world_name>

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

WORLD="$1"
WORLD_SIZE="${2:-10000}"

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 <world_name> [world_size]"
    exit 1
fi

USER_HOME=$(get_user_home)

# Configuration
GEO_SCRIPT="$PROJECT_ROOT/scripts/map/generate_geotiff.py"
COLORS_FILE="$USER_HOME/minetest-mapper/colors.txt"
WORLD_PATH="$USER_HOME/snap/luanti/common/.minetest/worlds/$WORLD"
OUTPUT_DIR="$WORLD_PATH/map_output"  # Store maps inside world folder
OUTPUT_IMAGE="$OUTPUT_DIR/map.tif"

LEFT=$((-WORLD_SIZE/2))
RIGHT=$((WORLD_SIZE/2))
TOP=$((WORLD_SIZE/2))
BOTTOM=$((-WORLD_SIZE/2))

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Check if world exists
if [ ! -f "$WORLD_PATH/map.sqlite" ]; then
    print_error "map.sqlite not found at $WORLD_PATH/map.sqlite"
    exit 1
fi

# Check if python script exists
if [ ! -f "$GEO_SCRIPT" ]; then
    print_error "Script not found at $GEO_SCRIPT"
    exit 1
fi

# Ensure virtual environment exists
if [ ! -d "$PROJECT_ROOT/venv" ]; then
    print_info "Python virtual environment not found in $PROJECT_ROOT/venv."
    print_info "Creating it now to install mapping dependencies..."
    python3 -m venv "$PROJECT_ROOT/venv" || {
        print_error "Failed to create python virtual environment"
        exit 1
    }
fi

# Check if dependencies are installed in the venv
if ! "$PROJECT_ROOT/venv/bin/python3" -c "import rasterio, numpy, zstandard" &> /dev/null; then
    print_info "Installing missing Python dependencies in venv..."
    "$PROJECT_ROOT/venv/bin/pip" install rasterio numpy zstandard || {
        print_error "Failed to install Python dependencies in venv"
        exit 1
    }
fi

print_info "Rendering GeoTIFF map for world: $WORLD"
TEMP_IMAGE="$OUTPUT_DIR/map_temp.tif"

# Render to temp file first (Atomic update)
# Assumes venv is deployed to PROJECT_ROOT by deploy.sh
"$PROJECT_ROOT/venv/bin/python3" "$GEO_SCRIPT" "$WORLD_PATH" "$TEMP_IMAGE" \
    --colors "$COLORS_FILE" \
    --left "$LEFT" --top "$TOP" --right "$RIGHT" --bottom "$BOTTOM"

if [ $? -eq 0 ]; then
    # Atomically move temp file to final file
    mv "$TEMP_IMAGE" "$OUTPUT_IMAGE"
    print_info "GeoTIFF rendered successfully: $OUTPUT_IMAGE"
else
    print_error "Rendering failed!"
    exit 1
fi
