#!/bin/bash

# Configuration
MAPPER_EXE="$HOME/minetest-mapper/minetestmapper"
COLORS_FILE="$HOME/minetest-mapper/colors.txt"
WORLD_PATH="$HOME/snap/luanti/common/.minetest/worlds/myworld"
OUTPUT_DIR="$HOME/Position/map_output"
OUTPUT_IMAGE="$OUTPUT_DIR/map.png"
OUTPUT_WORLD_FILE="$OUTPUT_DIR/map.pgw"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Check if world exists
if [ ! -f "$WORLD_PATH/map.sqlite" ]; then
    echo "Error: map.sqlite not found at $WORLD_PATH/map.sqlite"
    exit 1
fi

echo "Rendering map..."
TEMP_IMAGE="$OUTPUT_DIR/map_temp.png"

# Render to temp file first (Atomic update)
$MAPPER_EXE --input "$WORLD_PATH" --output "$TEMP_IMAGE" --colors "$COLORS_FILE" --geometry -5000:-5000+10000+10000

if [ $? -eq 0 ]; then
    # Atomically move temp file to final file
    mv "$TEMP_IMAGE" "$OUTPUT_IMAGE"
    echo "Map rendered successfully: $OUTPUT_IMAGE"
    
    # Generate World File (.pgw) for QGIS
    # Format:
    # Line 1: x-scale (meters per pixel) = 1.0
    # Line 2: y-rotation = 0
    # Line 3: x-rotation = 0
    # Line 4: y-scale (meters per pixel, negative because image Y is down) = -1.0
    # Line 5: Upper-left X coordinate
    # Line 6: Upper-left Y coordinate
    
    # NOTE: minetest-mapper geometry format is `minx:minz:w:h`
    # We used -5000:-5000:10000:10000
    # So Top-Left X = -5000
    #    Top-Left Y = 5000 (Because +Z is North/Up in QGIS, but Z increases North in Minetest too?)
    #    
    #    Wait, in Minetest: +X=East, +Z=North, +Y=Up(Elevation)
    #    In QGIS: +X=East, +Y=North
    #    So Minetest Z maps to QGIS Y.
    #    
    #    If our extent starts at Z=-5000 (Bottom) and height is 10000, 
    #    then the Top boundary is -5000 + 10000 = +5000.
    
    echo "1.0" > "$OUTPUT_WORLD_FILE"
    echo "0.0" >> "$OUTPUT_WORLD_FILE"
    echo "0.0" >> "$OUTPUT_WORLD_FILE"
    echo "-1.0" >> "$OUTPUT_WORLD_FILE"
    echo "-5000.0" >> "$OUTPUT_WORLD_FILE"  # Top-Left X (Min X)
    echo "5000.0" >> "$OUTPUT_WORLD_FILE"   # Top-Left Y (Max Z)
    
    echo "World file generated: $OUTPUT_WORLD_FILE"
else
    echo "Rendering failed!"
    exit 1
fi

# If using tile server (Optional for future)
# python3 -m http.server --directory "$OUTPUT_DIR" 8000 &
