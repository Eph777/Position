#!/usr/bin/env python3
# Copyright (C) 2026 Ephraim BOURIAHI
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

import os
import sys
import subprocess
import time
import argparse
import math
import shutil
from pathlib import Path

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

# --- CONFIGURATION ---
TILE_SIZE = 256
MAX_ZOOM = 18  # 1 node approx 1.6 pixels. Level 17 is approx 0.8px. Level 18 is better for detail.
# At Z=18, the world is 262,144 tiles wide.
# Center (0,0) is at tile (131072, 131072)
CENTER = 2 ** (MAX_ZOOM - 1)
# ---------------------

def get_world_extent(mapper_exe, world_path, colors_file):
    """Get the absolute boundaries of the world in nodes from minetestmapper."""
    cmd = [mapper_exe, "--extent", "--input", world_path, "--colors", colors_file]
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout.strip() + result.stderr.strip()
    
    import re
    # Match format: -640:-144+880+896
    m = re.search(r"([-0-9]+):([-0-9]+)\+([0-9]+)\+([0-9]+)", output)
    if m:
        left = int(m.group(1))
        bottom = int(m.group(2))
        width = int(m.group(3))
        height = int(m.group(4))
        return left, bottom, width, height
    return None

def game_to_tile(gx, gz, zoom):
    """
    Convert game coordinates (nodes) to slippy map tile indices.
    Assumes 1 node = resolution of zoom level 18 approx.
    Using the standard Web Mercator math but normalized for Luanti.
    """
    # At zoom 18, 1 pixel is ~0.597 meters.
    # To keep it simple and aligned, we map 1 node = 1 pixel offset in the grid.
    # This is a 'True-Scale' Luanti-Mercator where node (0,0) is center.
    tx = CENTER + math.floor(gx / TILE_SIZE)
    # Note: Luanti +Z is North (Up), Image +Y is South (Down)
    ty = CENTER - math.floor(gz / TILE_SIZE) - 1
    return int(tx), int(ty)

def tile_to_game(tx, ty, zoom):
    """Convert tile index back to the bottom-left game coordinate of that tile."""
    gx = (tx - CENTER) * TILE_SIZE
    gz = (CENTER - ty - 1) * TILE_SIZE
    return int(gx), int(gz)

def render_tile(mapper_exe, world_path, colors_file, tx, ty, zoom, output_path):
    """Renders a single 256x256 tile using minetestmapper --geometry."""
    gx, gz = tile_to_game(tx, ty, zoom)
    
    # minetestmapper geometry format: x:z+w+h  (z is the bottom-most coordinate)
    geom = f"{gx}:{gz}+{TILE_SIZE}+{TILE_SIZE}"
    
    cmd = [
        mapper_exe,
        "--input", world_path,
        "--output", str(output_path),
        "--geometry", geom,
        "--colors", colors_file,
        "--bgcolor", "#00000000" # Fully transparent
    ]
    
    subprocess.run(cmd, capture_output=True)
    
    # Check if tile has any content (skip if it's just a tiny empty PNG)
    if os.path.exists(output_path) and os.path.getsize(output_path) < 400:
        if HAS_PIL:
            # More thorough check with PIL
            img = Image.open(output_path)
            if not img.getbbox(): # All transparent
                img.close()
                os.remove(output_path)
                return False
            img.close()
    return os.path.exists(output_path)

def build_pyramid(output_dir, z_max):
    """Build lower zoom levels by merging 2x2 blocks of tiles."""
    if not HAS_PIL:
        print("⚠️ Pillow not installed! Skipping pyramid generation.")
        return

    print("[*] Building zoom pyramid...")
    for z in range(z_max - 1, z_max - 6, -1):
        high_dir = Path(output_dir) / str(z + 1)
        low_dir = Path(output_dir) / str(z)
        
        if not high_dir.exists(): continue
        
        processed = set()
        for x_path in high_dir.iterdir():
            if not x_path.is_dir(): continue
            hx = int(x_path.name)
            for y_file in x_path.glob("*.png"):
                hy = int(y_file.stem)
                
                lx, ly = hx // 2, hy // 2
                if (lx, ly) in processed: continue
                processed.add((lx, ly))
                
                # Merge 4 tiles
                dest = Image.new("RGBA", (TILE_SIZE * 2, TILE_SIZE * 2), (0,0,0,0))
                has_data = False
                
                for ox in (0, 1):
                    for oy in (0, 1):
                        src = high_dir / str(lx * 2 + ox) / f"{ly * 2 + oy}.png"
                        if src.exists():
                            with Image.open(src) as tile:
                                dest.paste(tile, (ox * TILE_SIZE, oy * TILE_SIZE))
                                has_data = True
                
                if has_data:
                    out_x_dir = low_dir / str(lx)
                    out_x_dir.mkdir(parents=True, exist_ok=True)
                    # Use Lanczos for best downscaling quality
                    resized = dest.resize((TILE_SIZE, TILE_SIZE), Image.Resampling.LANCZOS)
                    resized.save(out_x_dir / f"{ly}.png")

def run_cycle(args):
    """Main rendering cycle."""
    extent = get_world_extent(args.mapper, args.world, args.colors)
    if not extent:
        print("❌ Error: Could not get world extent.")
        return
    
    left, bottom, width, height = extent
    right = left + width
    top = bottom + height
    
    print(f"[*] World Extent: L:{left} B:{bottom} R:{right} T:{top}")
    
    # Calculate tile range at MAX_ZOOM
    tx_start, ty_end = game_to_tile(left, bottom, MAX_ZOOM)
    tx_end, ty_start = game_to_tile(right, top, MAX_ZOOM)
    
    print(f"[*] Tile Grid: X[{tx_start} to {tx_end}] Y[{ty_start} to {ty_end}]")
    
    tiles_dir = Path(args.output)
    z_dir = tiles_dir / str(MAX_ZOOM)
    
    count = 0
    start_time = time.time()
    
    for tx in range(tx_start, tx_end + 1):
        for ty in range(ty_start, ty_end + 1):
            x_dir = z_dir / str(tx)
            x_dir.mkdir(parents=True, exist_ok=True)
            tile_path = x_dir / f"{ty}.png"
            
            # Simple optimization: Render every time for now (incremental logic can be added later)
            if render_tile(args.mapper, args.world, args.colors, tx, ty, MAX_ZOOM, tile_path):
                count += 1
    
    duration = time.time() - start_time
    print(f"[*] Rendered {count} tiles at Zoom {MAX_ZOOM} in {duration:.1f}s.")
    
    if count > 0:
        build_pyramid(args.output, MAX_ZOOM)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Precise Luanti-to-XYZ Tiler")
    parser.add_argument("--world", required=True, help="Path to world directory")
    parser.add_argument("--mapper", required=True, help="Path to minetestmapper executable")
    parser.add_argument("--colors", required=True, help="Path to colors.txt")
    parser.add_argument("--output", required=True, help="Output directory for tiles")
    parser.add_argument("--daemon", action="store_true", help="Run in loop")
    parser.add_argument("--interval", type=int, default=60, help="Interval in seconds")
    
    args = parser.parse_args()
    
    while True:
        try:
            run_cycle(args)
            if not args.daemon: break
            print(f"[*] Sleeping {args.interval}s...")
            time.sleep(args.interval)
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"❌ Error: {e}")
            time.sleep(10)
