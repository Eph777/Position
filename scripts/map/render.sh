#!/bin/bash
# Render Luanti world map once
# Usage: ./render.sh <world_name>

# Load common functions
echo $(cd ../../ && pwd) > /root/.proj_root
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
OUTPUT_DIR="$USER_HOME/luanti-qgis/map_output"
OUTPUT_IMAGE="$OUTPUT_DIR/map.png"
OUTPUT_WORLD_FILE="$OUTPUT_DIR/map.pgw"

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
$MAPPER_EXE --input "$WORLD_PATH" --output "$TEMP_IMAGE" --bgcolor "#ffffff" --colors "$COLORS_FILE" --geometry -5000:-5000+10000+10000

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
    echo "-5000.0" >> "$OUTPUT_WORLD_FILE"  # Top-Left X (Min X)
    echo "5000.0" >> "$OUTPUT_WORLD_FILE"   # Top-Left Y (Max Z)
    
    print_info "World file generated: $OUTPUT_WORLD_FILE"
else
    print_error "Rendering failed!"
    exit 1
fi
