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
OUTPUT_IMAGE="$OUTPUT_DIR/map.png"
OUTPUT_WORLD_FILE="$OUTPUT_DIR/map.pgw"

# Get actual bounds of the entire map
EXTENT_STR=$($MAPPER_EXE --extent --input "$WORLD_PATH" 2>&1)
if [[ "$EXTENT_STR" =~ ([-0-9]+):([-0-9]+)\+([0-9]+)\+([0-9]+) ]]; then
    ACTUAL_LEFT="${BASH_REMATCH[1]}"
    ACTUAL_BOTTOM="${BASH_REMATCH[2]}"
    ACTUAL_WIDTH="${BASH_REMATCH[3]}"
    ACTUAL_HEIGHT="${BASH_REMATCH[4]}"
    ACTUAL_TOP=$((ACTUAL_BOTTOM + ACTUAL_HEIGHT))
    
    # For reliable georeferencing without cropping issues, we map the exact known bounds
    GEOM_ARG="--geometry $ACTUAL_LEFT:$ACTUAL_BOTTOM+$ACTUAL_WIDTH+$ACTUAL_HEIGHT"
else
    print_error "Could not determine map extent. Got: '$EXTENT_STR'"
    exit 1
fi


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

print_info "Rendering map for world: $WORLD"
TEMP_IMAGE="$OUTPUT_DIR/map_temp.png"

# Render to temp file first (Atomic update)
$MAPPER_EXE --input "$WORLD_PATH" --output "$TEMP_IMAGE" --bgcolor "#ffffff" --colors "$COLORS_FILE" $GEOM_ARG

if [ $? -eq 0 ]; then
    # Atomically move temp file to final file
    mv "$TEMP_IMAGE" "$OUTPUT_IMAGE"
    print_info "Map rendered successfully: $OUTPUT_IMAGE"
    
    # Generate World File (.pgw) for QGIS
    # Format:
    # Line 1: x-scale (meters per pixel) = 1.0
    # Line 2: y-rotation = 0
    # Line 3: x-rotation = 0
    # Line 4: y-scale (meters per pixel, negative because image Y is down) = -1.0
    # Line 5: Upper-left X coordinate
    # Line 6: Upper-left Y coordinate
    
    echo "1.0" > "$OUTPUT_WORLD_FILE"
    echo "0.0" >> "$OUTPUT_WORLD_FILE"
    echo "0.0" >> "$OUTPUT_WORLD_FILE"
    echo "-1.0" >> "$OUTPUT_WORLD_FILE"
    echo "$ACTUAL_LEFT" >> "$OUTPUT_WORLD_FILE"  # True Top-Left X
    echo "$ACTUAL_TOP" >> "$OUTPUT_WORLD_FILE"   # True Top-Left Y
    
    print_info "World file generated: $OUTPUT_WORLD_FILE"

    # Step: Dynamic GDAL Tiling
    TILES_DIR="$OUTPUT_DIR/tiles"
    VRT_FILE="$OUTPUT_DIR/map.vrt"
    
    if command_exists gdal_translate; then
        print_info "Generating XYZ Tiles (calculating dynamic zoom levels)..."
        START_TIME=$(date +%s)
        
        # 1. Create VRT (Virtual Dataset) to apply .pgw georeferencing
        gdal_translate -of VRT -a_srs EPSG:3857 "$OUTPUT_IMAGE" "$VRT_FILE" > /dev/null
        
        # 2. Generate Tiles
        # We use --xyz to ensure standard XYZ format for QGIS
        # We use --processes=4 as requested
        # We use --profile=mercator for Web Mercator compatibility
        GDAL_TILES_CMD="gdal2tiles.py"
        if ! command_exists gdal2tiles.py; then
            GDAL_TILES_CMD="gdal2tiles"
        fi
        
        $GDAL_TILES_CMD --profile=mercator --processes=4 --xyz "$VRT_FILE" "$TILES_DIR" > /dev/null
        
        # Cleanup VRT
        rm -f "$VRT_FILE"
        
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        print_info "Tiles generated in ${DURATION}s."
        print_info "Tiles location: $TILES_DIR"
    else
        print_warning "GDAL (gdal_translate) not found. Skipping tile generation."
        print_info "Run scripts/setup/gdal.sh to enable dynamic tiling."
    fi
else
    print_error "Rendering failed!"
    exit 1
fi
