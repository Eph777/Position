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

Uses standard Slippy Map tile numbering at zoom 13 (8192x8192 grid).
Game coordinate (0,0) maps to tile (4096, 4096) = lat 0, lon 0.
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
MAX_ZOOM = 13
CENTER = 2 ** (MAX_ZOOM - 1)  # 4096 — the equator/prime meridian tile

HAS_PIL = False
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    print("WARNING: python3-pil / Pillow not found.")
    print("  Fix: sudo apt install python3-pil  OR  pip3 install Pillow")


# ---------------------------------------------------------------------------
# Step 1: Render full map using minetestmapper (the PROVEN working method)
# ---------------------------------------------------------------------------
def render_full_map(mapper_exe, world_path, colors_file, output_png):
    """Calls minetestmapper exactly like render.sh does."""
    extent_cmd = [mapper_exe, "--extent", "--input", world_path, "--colors", colors_file]
    print(f"[1/3] Getting world extent...")
    print(f"  CMD: {' '.join(extent_cmd)}")

    result = subprocess.run(extent_cmd, capture_output=True, text=True)
    combined = result.stdout.strip() + "\n" + result.stderr.strip()
    print(f"  Output: {combined.strip()}")

    m = re.search(r"([-0-9]+):([-0-9]+)\+([0-9]+)\+([0-9]+)", combined)
    if not m:
        print(f"  ERROR: Could not parse extent!")
        return None

    left = int(m.group(1))
    bottom = int(m.group(2))
    width = int(m.group(3))
    height = int(m.group(4))
    top = bottom + height

    print(f"  Extent: left={left}, bottom={bottom}, width={width}, height={height}, top={top}")

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
        print(f"  stdout: {result.stdout.strip()[:200]}")
    if result.stderr.strip():
        print(f"  stderr: {result.stderr.strip()[:200]}")

    if not os.path.exists(output_png):
        print(f"  ERROR: Output file was not created!")
        return None

    size = os.path.getsize(output_png)
    print(f"  Success! {output_png} ({size} bytes)")
    return left, top, width, height


# ---------------------------------------------------------------------------
# Step 2: Slice into standard Slippy Map tiles at zoom 13
# ---------------------------------------------------------------------------
def slice_into_tiles(full_png, output_dir, left, top, width, height):
    """
    Slices the full map PNG into 256x256 tiles using standard Slippy Map
    tile numbering at zoom 13.
    
    At zoom 13, there are 8192 tiles per axis (0..8191).
    Game coordinate (0,0) is placed at tile (4096, 4096) — which corresponds
    to lat=0, lon=0 (equator / prime meridian) in Web Mercator.
    
    QGIS XYZ tiles follow this exact convention, so tiles will display correctly.
    """
    if not HAS_PIL:
        print("  ERROR: Pillow not installed! Cannot slice tiles.")
        return 0

    print(f"[3/3] Slicing into {TILE_SIZE}x{TILE_SIZE} tiles at zoom {MAX_ZOOM}...")
    img = Image.open(full_png)
    img_w, img_h = img.size
    print(f"  Image: {img_w}x{img_h} px")
    print(f"  World: left={left}, top={top}, w={width}, h={height}")

    # The image's top-left pixel represents game coordinate (left, top-1).
    # minetestmapper: X increases right, Y(game Z) increases upward.
    # Image: X increases right, Y increases downward.
    #
    # Mapping game coords to tile coords at zoom 13:
    #   tile_x = CENTER + floor(game_x / TILE_SIZE)
    #   tile_y = CENTER - floor(game_z / TILE_SIZE) - 1
    # (Y flipped: tile Y goes down, game Z goes up)

    # For each tile-sized chunk of the image, calculate its tile coordinate
    cols = math.ceil(img_w / TILE_SIZE) + 1
    rows = math.ceil(img_h / TILE_SIZE) + 1

    tiles_written = 0
    zoom_dir = Path(output_dir) / str(MAX_ZOOM)
    max_coord = 2 ** MAX_ZOOM  # 8192

    for row in range(rows):
        for col in range(cols):
            # Which game coordinates does this image region cover?
            # Image pixel (col*256, row*256) = game coord (left + col*256, top - 1 - row*256)
            game_x = left + col * TILE_SIZE
            game_z = (top - 1) - row * TILE_SIZE

            # Convert to tile coordinates
            tx = CENTER + math.floor(game_x / TILE_SIZE)
            ty = CENTER - math.floor(game_z / TILE_SIZE) - 1

            # Validate range
            if tx < 0 or tx >= max_coord or ty < 0 or ty >= max_coord:
                continue

            # Extract the image region
            src_x = col * TILE_SIZE
            src_y = row * TILE_SIZE

            if src_x >= img_w or src_y >= img_h:
                continue

            tile_img = Image.new("RGB", (TILE_SIZE, TILE_SIZE), (0, 0, 0))
            crop_x2 = min(img_w, src_x + TILE_SIZE)
            crop_y2 = min(img_h, src_y + TILE_SIZE)
            region = img.crop((src_x, src_y, crop_x2, crop_y2))
            tile_img.paste(region, (0, 0))

            # Skip entirely black tiles
            extrema = tile_img.getextrema()
            if all(ch[1] == 0 for ch in extrema):
                continue

            tile_dir = zoom_dir / str(tx)
            tile_dir.mkdir(parents=True, exist_ok=True)
            tile_img.save(tile_dir / f"{ty}.png", "PNG")
            tiles_written += 1

    print(f"  Wrote {tiles_written} tiles at zoom {MAX_ZOOM}")
    img.close()

    # Build zoom pyramid
    if tiles_written > 0:
        build_zoom_pyramid(output_dir, MAX_ZOOM)

    return tiles_written


# ---------------------------------------------------------------------------
# Step 3: Build zoom pyramid by downscaling
# ---------------------------------------------------------------------------
def build_zoom_pyramid(output_dir, from_zoom):
    """Builds lower zoom levels by merging 2x2 groups of higher-zoom tiles."""
    if not HAS_PIL:
        return

    # Build down to zoom 6 (enough for overview)
    min_zoom = max(0, from_zoom - 8)

    for z in range(from_zoom - 1, min_zoom - 1, -1):
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
# Main
# ---------------------------------------------------------------------------
def run_once(mapper_exe, world_path, colors_file, output_dir):
    """Single render + slice cycle."""
    full_png = os.path.join(output_dir, "_fullmap.png")
    Path(output_dir).mkdir(parents=True, exist_ok=True)

    # Clean old tiles first
    for z_dir in Path(output_dir).iterdir():
        if z_dir.is_dir() and z_dir.name.isdigit():
            import shutil
            shutil.rmtree(z_dir)

    result = render_full_map(mapper_exe, world_path, colors_file, full_png)
    if result is None:
        print("FAILED: Could not render full map.")
        return False

    left, top, width, height = result
    tiles = slice_into_tiles(full_png, output_dir, left, top, width, height)
    print(f"\nCycle complete. {tiles} tiles generated.")
    return tiles > 0


def run_daemon(mapper_exe, world_path, colors_file, output_dir, interval=30):
    """Continuous rendering loop."""
    print("=" * 60)
    print("  Luanti Map Tile Daemon")
    print(f"  World:    {world_path}")
    print(f"  Output:   {output_dir}")
    print(f"  Interval: {interval}s")
    print(f"  Zoom:     {MAX_ZOOM} (center tile: {CENTER},{CENTER})")
    print("=" * 60)

    while True:
        try:
            run_once(mapper_exe, world_path, colors_file, output_dir)
            print(f"Sleeping {interval}s...")
            time.sleep(interval)
        except KeyboardInterrupt:
            print("\nDaemon stopped.")
            break
        except Exception as e:
            print(f"ERROR: {e}")
            import traceback
            traceback.print_exc()
            time.sleep(10)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Luanti Map Tile Daemon")
    parser.add_argument("--world", required=True, help="Path to Minetest world directory")
    parser.add_argument("--mapper", required=True, help="Path to minetestmapper executable")
    parser.add_argument("--colors", required=True, help="Path to colors.txt")
    parser.add_argument("--output", required=True, help="Tiles output directory")
    parser.add_argument("--daemon", action="store_true", help="Run continuously")
    parser.add_argument("--interval", type=int, default=30, help="Seconds between cycles")

    args = parser.parse_args()

    # Pre-flight validation
    errors = []
    if not os.path.isdir(args.world):
        errors.append(f"World not found: {args.world}")
    if not os.path.isfile(args.mapper):
        errors.append(f"minetestmapper not found: {args.mapper}")
    if not os.access(args.mapper, os.X_OK):
        errors.append(f"minetestmapper not executable: {args.mapper}")
    if not os.path.isfile(args.colors):
        errors.append(f"colors.txt not found: {args.colors}")
    map_sqlite = os.path.join(args.world, "map.sqlite")
    if not os.path.isfile(map_sqlite):
        errors.append(f"map.sqlite not found: {map_sqlite}")
    if not HAS_PIL:
        errors.append("Pillow (PIL) not installed")

    if errors:
        print("FATAL: Pre-flight checks failed:")
        for e in errors:
            print(f"  ✗ {e}")
        sys.exit(1)

    print("Pre-flight OK:")
    print(f"  ✓ World:  {args.world}")
    print(f"  ✓ Mapper: {args.mapper}")
    print(f"  ✓ Colors: {args.colors}")
    print(f"  ✓ Output: {args.output}")
    print(f"  ✓ Pillow: installed")

    if args.daemon:
        run_daemon(args.mapper, args.world, args.colors, args.output, args.interval)
    else:
        success = run_once(args.mapper, args.world, args.colors, args.output)
        sys.exit(0 if success else 1)
