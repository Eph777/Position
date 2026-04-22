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
from pathlib import Path

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

# --- CONSTANTS (EPSG:3857) ---
TILE_SIZE = 256
CIRCUMFERENCE = 40075016.68557849
ORIGIN_SHIFT = CIRCUMFERENCE / 2.0
# -----------------------------

def get_world_extent(mapper_exe, world_path, colors_file):
    """Get the absolute boundaries of the world in nodes from minetestmapper."""
    cmd = [mapper_exe, "--extent", "--input", world_path, "--colors", colors_file]
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout.strip() + result.stderr.strip()
    
    import re
    # Match format: -640:-144+880+896
    m = re.search(r"([-0-9]+):([-0-9]+)\+([0-9]+)\+([0-9]+)", output)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
    return None

def latlon_to_mercator(lon, lat):
    """Convert Lat/Lon to EPSG:3857 Meters."""
    x = lon * ORIGIN_SHIFT / 180.0
    y = math.log(math.tan((90 + lat) * math.pi / 360.0)) / (math.pi / 180.0)
    y = y * ORIGIN_SHIFT / 180.0
    return x, y

def mercator_to_tile(mx, my, zoom):
    """Convert Mercator Meters to Tile Indices."""
    res = CIRCUMFERENCE / (2.0**zoom)
    tx = math.floor((mx + ORIGIN_SHIFT) / res)
    ty = math.floor((ORIGIN_SHIFT - my) / res)
    return int(tx), int(ty)

def tile_bounds_mercator(tx, ty, zoom):
    """Get the exact Mercator bounds for a specific tile."""
    res = CIRCUMFERENCE / (2.0**zoom)
    left = tx * res - ORIGIN_SHIFT
    top = ORIGIN_SHIFT - ty * res
    return left, top - res, left + res, top  # left, bottom, right, top

def render_tile(mapper_exe, world_path, colors_file, tx, ty, zoom, output_path):
    """Renders a single tile with exact Mercator geometry."""
    l, b, r, t = tile_bounds_mercator(tx, ty, zoom)
    
    # minetestmapper geometry: left:bottom+width+height (supports floats)
    width = r - l
    height = t - b
    geom = f"{l}:{b}+{width}+{height}"
    
    # We render to a temporary file at its native resolution, then scale to 256x256
    temp_path = output_path.with_suffix(".tmp.png")
    
    cmd = [
        mapper_exe,
        "--input", world_path,
        "--output", str(temp_path),
        "--geometry", geom,
        "--colors", colors_file,
        "--bgcolor", "#00000000"
    ]
    
    subprocess.run(cmd, capture_output=True)
    
    if os.path.exists(temp_path):
        if os.path.getsize(temp_path) < 400:
            os.remove(temp_path)
            return False
            
        if HAS_PIL:
            with Image.open(temp_path) as img:
                # Use NEAREST resampling to preserve pixel-art/node quality perfectly
                # This fixes the "bad quality/blurriness"
                resized = img.resize((TILE_SIZE, TILE_SIZE), Image.Resampling.NEAREST)
                resized.save(output_path, "PNG", compress_level=0) # No compression for speed/quality
            os.remove(temp_path)
            return True
        else:
            os.replace(temp_path, output_path)
            return True
    return False

def build_pyramid(output_dir, z_max):
    """Upscale high-zoom tiles into lower zoom levels using NEAREST merging."""
    if not HAS_PIL: return
    print("[*] Merging zoom pyramid (lossless)...")
    for z in range(z_max - 1, z_max - 5, -1):
        high_dir = Path(output_dir) / str(z + 1)
        low_dir = Path(output_dir) / str(z)
        if not high_dir.exists(): continue
        processed = set()
        for x_path in high_dir.iterdir():
            if not x_path.is_dir(): continue
            hx = int(x_path.name)
            for y_file in x_path.glob("*.png"):
                if y_file.suffix != ".png" or y_file.name.endswith(".tmp.png"): continue
                hy = int(y_file.stem)
                lx, ly = hx // 2, hy // 2
                if (lx, ly) in processed: continue
                processed.add((lx, ly))
                
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
                    # Use NEAREST to maintain sharpness
                    resized = dest.resize((TILE_SIZE, TILE_SIZE), Image.Resampling.NEAREST)
                    resized.save(out_x_dir / f"{ly}.png")

def run_cycle(args):
    extent = get_world_extent(args.mapper, args.world, args.colors)
    if not extent: return
    l, b, w, h = extent
    
    # Calculate tile range at MAX_ZOOM
    z = args.zoom
    tx_start, ty_start = mercator_to_tile(l, b + h, z) # Top-left
    tx_end, ty_end = mercator_to_tile(l + w, b, z)     # Bottom-right
    
    print(f"[*] Cycle Start: Zoom {z} range X[{tx_start}-{tx_end}] Y[{ty_start}-{ty_end}]")
    
    tiles_dir = Path(args.output)
    z_dir = tiles_dir / str(z)
    
    count = 0
    for tx in range(tx_start, tx_end + 1):
        for ty in range(ty_start, ty_end + 1):
            out_x_dir = z_dir / str(tx)
            out_x_dir.mkdir(parents=True, exist_ok=True)
            if render_tile(args.mapper, args.world, args.colors, tx, ty, z, out_x_dir / f"{ty}.png"):
                count += 1
    
    print(f"[*] Rendered {count} tiles.")
    if count > 0: build_pyramid(args.output, z)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--world", required=True)
    parser.add_argument("--mapper", required=True)
    parser.add_argument("--colors", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--zoom", type=int, default=18)
    parser.add_argument("--daemon", action="store_true")
    parser.add_argument("--interval", type=int, default=30)
    args = parser.parse_args()
    while True:
        try:
            run_cycle(args)
            if not args.daemon: break
            time.sleep(args.interval)
        except KeyboardInterrupt: break
        except Exception as e:
            print(f"Error: {e}")
            time.sleep(10)
