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

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 <world_name>"
    exit 1
fi

USER_HOME=$(get_user_home)

# Configuration
MAPPER_EXE="$USER_HOME/minetest-mapper/minetestmapper"
COLORS_FILE="$USER_HOME/minetest-mapper/colors.txt"
WORLD_PATH="$USER_HOME/snap/luanti/common/.minetest/worlds/$WORLD"
OUTPUT_DIR="$WORLD_PATH/map_output"  # Store maps inside world folder
LAST_RENDER_FILE="$OUTPUT_DIR/last_render_time.txt"
LAST_RENDER=$(cat "$LAST_RENDER_FILE" 2>/dev/null || echo 0)
NOW=$(date +%s)

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Check if world exists
if [ ! -f "$WORLD_PATH/map.sqlite" ]; then
    print_error "map.sqlite not found at $WORLD_PATH/map.sqlite"
    exit 1
fi

# Check if mapper executable exists
if [ ! -f "$MAPPER_EXE" ]; then
    print_error "Mapper executable not found at $MAPPER_EXE"
    print_info "Run scripts/setup/mapper.sh to install minetest-mapper"
    exit 1
fi

MODIFIED_CHUNKS_SCRIPT="$PROJECT_ROOT/scripts/map/get-modified-chunks.py"
if [ ! -f "$MODIFIED_CHUNKS_SCRIPT" ]; then
    print_error "Python helper script not found at $MODIFIED_CHUNKS_SCRIPT"
    exit 1
fi

print_info "Querying database for modified chunks since $LAST_RENDER..."
CHUNKS=$("$MODIFIED_CHUNKS_SCRIPT" "$WORLD_PATH/map.sqlite" "$LAST_RENDER")

if [[ $? -ne 0 ]]; then
    print_error "Failed to query modified chunks."
    exit 1
fi

if [ -z "$CHUNKS" ]; then
    print_info "No blocks modified since last render. Nothing to do."
    exit 0
fi

# We will chunk into 256x256 node blocks
WIDTH=256
HEIGHT=256

for coord in $CHUNKS; do
    # coord is X,Z of the bottom-left corner of the chunk
    X=${coord%,*}
    Z=${coord#*,}
    TOP=$((Z + HEIGHT))  # Need this for QGIS pgw!

    # The format is `x:z+w+h`
    GEOM_ARG="--geometry ${X}:${Z}+${WIDTH}+${HEIGHT}"
    TILE_IMAGE="$OUTPUT_DIR/chunk_${X}_${Z}.png"
    TILE_PGW="$OUTPUT_DIR/chunk_${X}_${Z}.pgw"
    
    print_info "Rendering chunk $X,$Z..."
    
    $MAPPER_EXE --input "$WORLD_PATH" --output "$TILE_IMAGE" --bgcolor "#ffffff" --colors "$COLORS_FILE" $GEOM_ARG
    
    if [ $? -eq 0 ]; then
        # Generate World File (.pgw) for QGIS
        # Note: PGW coordinates represent the *center* of the top-left pixel
        # The top-left pixel of a minetestmapper chunk is at X, Z+HEIGHT-1
        TOP_Z=$((Z + HEIGHT - 1))
        
        echo "1.0" > "$TILE_PGW"
        echo "0.0" >> "$TILE_PGW"
        echo "0.0" >> "$TILE_PGW"
        echo "-1.0" >> "$TILE_PGW"
        echo "$X" >> "$TILE_PGW"
        echo "$TOP_Z" >> "$TILE_PGW"
    else
        print_error "Failed to render chunk $X $Z"
    fi
done

print_info "Building world_map.vrt for QGIS..."
if command_exists gdalbuildvrt; then
    (cd "$OUTPUT_DIR" && gdalbuildvrt -q "world_map.vrt" chunk_*.png)
    print_info "VRT updated successfully."
else
    print_warning "gdal-bin is not installed. world_map.vrt was not updated."
    print_warning "Install it with: sudo apt-get install gdal-bin"
fi

echo "$NOW" > "$LAST_RENDER_FILE"
print_info "Incremental render cycle complete!"
