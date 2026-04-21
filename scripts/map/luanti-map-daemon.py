#!/usr/bin/env python3
# Copyright (C) 2026 Ephraim BOURIAHI
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

"""
Luanti Incremental Map Tile Daemon
===================================
Renders the full Minetest world map using minetestmapper (proven to work),
then slices it into standard Z/X/Y.png tiles for QGIS consumption.

Architecture:
  1. Call minetestmapper ONCE to render the entire explored map
  2. Slice the resulting PNG into 256x256 tiles
  3. Build a zoom pyramid by downscaling
  4. Repeat every N seconds (daemon mode)
"""

import os
import sys
import subprocess
import time
import argparse
import re
import math
from pathlib import Path

TILE_SIZE = 256

# ---------------------------------------------------------------------------
# Step 1: Render full map using minetestmapper (the PROVEN working method)
# ---------------------------------------------------------------------------
def render_full_map(mapper_exe, world_path, colors_file, output_png):
    """
    Calls minetestmapper exactly like render.sh does.
    Returns (left, top, width, height) of the rendered area, or None on failure.
    """
    # First get extent
    extent_cmd = [mapper_exe, "--extent", "--input", world_path, "--colors", colors_file]
    print(f"[1/3] Getting world extent...")
    print(f"  CMD: {' '.join(extent_cmd)}")

    result = subprocess.run(extent_cmd, capture_output=True, text=True)
    combined = result.stdout.strip() + "\n" + result.stderr.strip()
    print(f"  Output: {combined.strip()}")

    m = re.search(r"([-0-9]+):([-0-9]+)\+([0-9]+)\+([0-9]+)", combined)
    if not m:
        print(f"  ERROR: Could not parse extent from output!")
        return None

    left = int(m.group(1))
    bottom = int(m.group(2))
    width = int(m.group(3))
    height = int(m.group(4))
    top = bottom + height

    print(f"  Extent: left={left}, bottom={bottom}, width={width}, height={height}")

    # Now render the map
    geom = f"{left}:{bottom}+{width}+{height}"
    render_cmd = [
        mapper_exe,
        "--input", world_path,
        "--output", output_png,
        "--geometry", geom,
        "--bgcolor", "#000000",
        "--colors", colors_file
    ]
    print(f"[2/3] Rendering full map...")
    print(f"  CMD: {' '.join(render_cmd)}")

    result = subprocess.run(render_cmd, capture_output=True, text=True)
    if result.stdout.strip():
        print(f"  stdout: {result.stdout.strip()}")
    if result.stderr.strip():
        print(f"  stderr: {result.stderr.strip()}")

    if not os.path.exists(output_png):
        print(f"  ERROR: Output file was not created!")
        return None

    size = os.path.getsize(output_png)
    print(f"  Success! Output: {output_png} ({size} bytes)")
    return left, top, width, height


# ---------------------------------------------------------------------------
# Step 2: Slice the full map PNG into Z/X/Y tiles
# ---------------------------------------------------------------------------
def slice_into_tiles(full_png, output_dir, left, top, width, height):
    """
    Slices a full map PNG into 256x256 tile grid.
    
    Coordinate mapping:
      - minetestmapper outputs 1 pixel per game node
      - Tile (0,0) at any zoom = top-left of the rendered image
      - We use a simple offset scheme: game coord (0,0) sits at the pixel
        offset (-left, top) within the image, since the image starts at (left, top-height).
    
    For QGIS we use a custom flat CRS where tile coordinates directly
    map to game node positions. No Web Mercator needed.
    """
    try:
        from PIL import Image
    except ImportError:
        print("  ERROR: python3-pil / Pillow not installed! Cannot slice tiles.")
        print("  Fix: sudo apt install python3-pil  OR  pip3 install Pillow")
        return 0

    print(f"[3/3] Slicing into {TILE_SIZE}x{TILE_SIZE} tiles...")
    img = Image.open(full_png)
    img_w, img_h = img.size
    print(f"  Image dimensions: {img_w}x{img_h} pixels")

    # Calculate how many tiles we need
    cols = math.ceil(img_w / TILE_SIZE)
    rows = math.ceil(img_h / TILE_SIZE)
    print(f"  Grid: {cols} columns x {rows} rows = {cols * rows} potential tiles")

    # We'll generate zoom level 0 as the "native" resolution (1px = 1 node)
    # Then build a pyramid of lower zooms by downscaling
    
    # Determine the maximum zoom where we have full resolution
    max_zoom = max(math.ceil(math.log2(max(cols, rows, 1))), 1)
    print(f"  Max zoom level: {max_zoom}")

    # At max_zoom, total grid is 2^max_zoom tiles
    grid_size = 2 ** max_zoom

    # Place the game world so that game coordinate (0,0) maps to 
    # tile grid center. The image's top-left pixel represents game 
    # coordinate (left, top).
    # Pixel offset of game (0,0) within the image:
    origin_px_x = -left  # game x=0 is at pixel -left
    origin_px_y = top - 1  # game z=0 is at pixel (top - 1) because Y flips (top of image = max game Z)

    # Tile index of game (0,0): place it at center of grid
    center_tile_x = grid_size // 2
    center_tile_y = grid_size // 2

    # The image top-left pixel starts at this tile offset:
    img_start_tile_x = center_tile_x - (origin_px_x // TILE_SIZE)
    img_start_tile_y = center_tile_y - (origin_px_y // TILE_SIZE)

    # Fine pixel offset within the starting tile
    px_offset_x = origin_px_x % TILE_SIZE
    px_offset_y = origin_px_y % TILE_SIZE

    tiles_written = 0
    zoom_dir = Path(output_dir) / str(max_zoom)

    for row in range(rows + 1):
        for col in range(cols + 1):
            # Source pixel region from the full image
            src_x = col * TILE_SIZE - px_offset_x
            src_y = row * TILE_SIZE - px_offset_y

            # Skip if completely outside the image
            if src_x + TILE_SIZE <= 0 or src_x >= img_w:
                continue
            if src_y + TILE_SIZE <= 0 or src_y >= img_h:
                continue

            # Crop the tile (PIL handles out-of-bounds by filling with black)
            tile_img = Image.new("RGB", (TILE_SIZE, TILE_SIZE), (0, 0, 0))
            
            # Calculate paste region
            paste_x = max(0, -src_x)
            paste_y = max(0, -src_y)
            crop_x = max(0, src_x)
            crop_y = max(0, src_y)
            crop_x2 = min(img_w, src_x + TILE_SIZE)
            crop_y2 = min(img_h, src_y + TILE_SIZE)

            if crop_x2 <= crop_x or crop_y2 <= crop_y:
                continue

            region = img.crop((crop_x, crop_y, crop_x2, crop_y2))
            tile_img.paste(region, (paste_x, paste_y))

            # Check if tile is entirely black (empty)
            extrema = tile_img.getextrema()
            if all(ch[1] == 0 for ch in extrema):
                continue  # Skip empty tiles

            # Output tile coordinates
            tx = img_start_tile_x + col
            ty = img_start_tile_y + row

            tile_dir = zoom_dir / str(tx)
            tile_dir.mkdir(parents=True, exist_ok=True)
            tile_path = tile_dir / f"{ty}.png"
            tile_img.save(tile_path, "PNG")
            tiles_written += 1

    print(f"  Wrote {tiles_written} tiles at zoom {max_zoom}")
    img.close()

    # Build zoom pyramid
    if tiles_written > 0:
        build_zoom_pyramid(output_dir, max_zoom)

    # Write metadata for QGIS setup script to read
    meta_path = Path(output_dir) / "metadata.txt"
    meta_path.write_text(f"max_zoom={max_zoom}\ngrid_size={grid_size}\n")

    return tiles_written


# ---------------------------------------------------------------------------
# Step 3: Build zoom pyramid by downscaling
# ---------------------------------------------------------------------------
def build_zoom_pyramid(output_dir, max_zoom):
    """Builds lower zoom levels by merging 2x2 groups of higher-zoom tiles."""
    try:
        from PIL import Image
    except ImportError:
        return

    min_zoom = max(0, max_zoom - 6)  # Don't go below 6 levels of zoom out

    for z in range(max_zoom - 1, min_zoom - 1, -1):
        z_high = z + 1
        high_dir = Path(output_dir) / str(z_high)
        z_dir = Path(output_dir) / str(z)

        if not high_dir.exists():
            continue

        processed = set()
        count = 0

        for x_dir in sorted(high_dir.iterdir()):
            if not x_dir.is_dir():
                continue
            hx = int(x_dir.name)
            for y_file in x_dir.glob("*.png"):
                hy = int(y_file.stem)

                lx, ly = hx // 2, hy // 2
                if (lx, ly) in processed:
                    continue
                processed.add((lx, ly))

                merged = Image.new("RGB", (TILE_SIZE * 2, TILE_SIZE * 2), (0, 0, 0))
                has_content = False

                for ox in (0, 1):
                    for oy in (0, 1):
                        src = high_dir / str(lx * 2 + ox) / f"{ly * 2 + oy}.png"
                        if src.exists():
                            with Image.open(src) as tile:
                                merged.paste(tile, (ox * TILE_SIZE, oy * TILE_SIZE))
                                has_content = True

                if has_content:
                    out_dir = z_dir / str(lx)
                    out_dir.mkdir(parents=True, exist_ok=True)
                    scaled = merged.resize((TILE_SIZE, TILE_SIZE), Image.Resampling.LANCZOS)
                    scaled.save(out_dir / f"{ly}.png", "PNG")
                    count += 1

        print(f"  Zoom {z}: {count} tiles")


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
def run_once(mapper_exe, world_path, colors_file, output_dir):
    """Single render + slice cycle."""
    full_png = os.path.join(output_dir, "_fullmap.png")
    Path(output_dir).mkdir(parents=True, exist_ok=True)

    result = render_full_map(mapper_exe, world_path, colors_file, full_png)
    if result is None:
        print("FAILED: Could not render full map. Check minetestmapper output above.")
        return False

    left, top, width, height = result
    tiles = slice_into_tiles(full_png, output_dir, left, top, width, height)
    print(f"Cycle complete. {tiles} tiles generated/updated.")
    return tiles > 0


def run_daemon(mapper_exe, world_path, colors_file, output_dir, interval=30):
    """Continuous rendering loop."""
    print("=" * 60)
    print("  Luanti Map Tile Daemon - Starting")
    print(f"  World:  {world_path}")
    print(f"  Output: {output_dir}")
    print(f"  Interval: {interval}s")
    print("=" * 60)

    while True:
        try:
            print(f"\n{'='*40} CYCLE START {'='*40}")
            run_once(mapper_exe, world_path, colors_file, output_dir)
            print(f"Sleeping {interval}s...")
            time.sleep(interval)
        except KeyboardInterrupt:
            print("\nDaemon stopped.")
            break
        except Exception as e:
            print(f"ERROR in cycle: {e}")
            import traceback
            traceback.print_exc()
            time.sleep(10)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Luanti Incremental Map Tile Daemon",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Single render (test):
  python3 %(prog)s --world /path/to/world --mapper /path/to/minetestmapper --colors /path/to/colors.txt --output ./tiles

  # Continuous daemon:
  python3 %(prog)s --daemon --world /path/to/world --mapper /path/to/minetestmapper --colors /path/to/colors.txt --output ./tiles
        """
    )
    parser.add_argument("--world", required=True, help="Path to Minetest world directory")
    parser.add_argument("--mapper", required=True, help="Path to minetestmapper executable")
    parser.add_argument("--colors", required=True, help="Path to colors.txt")
    parser.add_argument("--output", required=True, help="Tiles output directory")
    parser.add_argument("--daemon", action="store_true", help="Run continuously")
    parser.add_argument("--interval", type=int, default=30, help="Seconds between cycles (default: 30)")

    args = parser.parse_args()

    # Validate inputs before doing anything
    errors = []
    if not os.path.isdir(args.world):
        errors.append(f"World directory not found: {args.world}")
    if not os.path.isfile(args.mapper):
        errors.append(f"minetestmapper not found: {args.mapper}")
    if not os.access(args.mapper, os.X_OK):
        errors.append(f"minetestmapper not executable: {args.mapper}")
    if not os.path.isfile(args.colors):
        errors.append(f"colors.txt not found: {args.colors}")
    map_sqlite = os.path.join(args.world, "map.sqlite")
    if not os.path.isfile(map_sqlite):
        errors.append(f"map.sqlite not found: {map_sqlite}")

    if errors:
        print("FATAL: Pre-flight validation failed:")
        for e in errors:
            print(f"  ✗ {e}")
        sys.exit(1)
    else:
        print("Pre-flight validation passed:")
        print(f"  ✓ World: {args.world}")
        print(f"  ✓ Mapper: {args.mapper}")
        print(f"  ✓ Colors: {args.colors}")
        print(f"  ✓ map.sqlite: {map_sqlite}")
        print(f"  ✓ Output: {args.output}")

    if args.daemon:
        run_daemon(args.mapper, args.world, args.colors, args.output, args.interval)
    else:
        success = run_once(args.mapper, args.world, args.colors, args.output)
        sys.exit(0 if success else 1)
