#!/usr/bin/env python3
import sqlite3
import struct
import binascii
import sys
import os
import argparse
import numpy as np
import rasterio
from rasterio.transform import from_bounds
from rasterio.windows import Window
import zlib
import zstandard as zstd

# Add codec to path
import pathlib
codec_src_path = os.path.join(pathlib.Path(__file__).parent.resolve(), 'codec', 'src')
sys.path.append(codec_src_path)
try:
    from luanti_map_builder.decode_postition import getIntegerAsBlock
    from luanti_map_builder.mapBlockDecode import parse_mapblock, decode_node_ids, build_mapping_dict, map_node_ids_to_names
except ImportError as e:
    print(f"Error importing Luanti MapBlock Codec: {e}")
    print(f"Make sure codec is cloned to {codec_src_path}")
    sys.exit(1)

DEFAULT_COLOR = (255, 0, 255) # Magenta for missing mapping
BG_COLOR = (255, 255, 255) # White background

def load_colors(path):
    colors = {
        "air": (255, 255, 255),
        "ignore": (255, 255, 255)
    }
    if not os.path.exists(path):
        print(f"Warning: Colors file {path} not found. Using defaults.")
        return colors
        
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            if len(parts) >= 4:
                name = parts[0]
                r, g, b = int(parts[1]), int(parts[2]), int(parts[3])
                colors[name] = (r, g, b)
    return colors

def decompress_blob(raw_data):
    version = raw_data[0]
    compressed_part = raw_data[1:]
    
    # Try zstd first, then zlib
    try:
        dctx = zstd.ZstdDecompressor()
        decompressed = dctx.decompress(compressed_part)
        return version, decompressed
    except Exception:
        pass
        
    try:
        decompressed = zlib.decompress(compressed_part)
        return version, decompressed
    except Exception:
        return version, None

def main():
    parser = argparse.ArgumentParser(description="Generate GeoTIFF from Luanti map.sqlite")
    parser.add_argument("world", help="Path to world folder")
    parser.add_argument("output", help="Output GeoTIFF path")
    parser.add_argument("--colors", help="Path to colors.txt", required=False)
    parser.add_argument("--left", type=int, required=True, help="Bounding box left (min X)")
    parser.add_argument("--top", type=int, required=True, help="Bounding box top (max Z)")
    parser.add_argument("--right", type=int, required=True, help="Bounding box right (max X)")
    parser.add_argument("--bottom", type=int, required=True, help="Bounding box bottom (min Z)")
    args = parser.parse_args()

    # Load Colors
    colors_file = args.colors if args.colors else os.path.join(args.world, "colors.txt")
    colors = load_colors(colors_file)
    
    db_path = os.path.join(args.world, "map.sqlite")
    if not os.path.exists(db_path):
        print(f"Error: Database {db_path} not found.")
        sys.exit(1)

    print(f"Connecting to map.sqlite at {db_path}...")
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    width = args.right - args.left
    height = args.top - args.bottom
    
    if width <= 0 or height <= 0:
        print("Error: Invalid bounding box.")
        sys.exit(1)

    print(f"Target Image Size: {width}x{height} pixels")
    transform = from_bounds(args.left, args.bottom, args.right, args.top, width, height)

    min_bx = args.left // 16
    max_bx = args.right // 16
    min_bz = args.bottom // 16
    max_bz = args.top // 16

    print(f"Finding MapBlocks in BBox [{min_bx}..{max_bx}, {min_bz}..{max_bz}]...")
    
    # First, get all positions to group by columns
    cursor.execute("SELECT pos FROM blocks")
    columns = {} # (bx, bz) -> list of (pos, by)
    
    for row in cursor:
        pos = row[0]
        bx, by, bz = getIntegerAsBlock(pos)
        
        if bx < min_bx or bx > max_bx or bz < min_bz or bz > max_bz:
            continue
            
        # Ignore deep underground and high sky completely
        if by < -10 or by > 10:
            continue
            
        col_key = (bx, bz)
        if col_key not in columns:
            columns[col_key] = []
        columns[col_key].append((pos, by))

    profile = {
        'driver': 'GTiff',
        'height': height,
        'width': width,
        'count': 3,
        'dtype': rasterio.uint8,
        'crs': 'EPSG:3857',
        'transform': transform,
        'compress': 'lzw',
        'tiled': True,
        'blockxsize': 256,
        'blockysize': 256
    }
    
    print(f"Initializing GeoTIFF at {args.output}...")
    
    total_cols = len(columns)
    processed = 0

    with rasterio.open(args.output, 'w', **profile) as dst:
        for (bx, bz), blocks_in_col in columns.items():
            blocks_in_col.sort(key=lambda item: item[1], reverse=True)
            
            # Start row/col internally for this MapBlock
            start_row = args.top - (bz * 16 + 16)
            start_col = (bx * 16) - args.left
            
            valid_row_start = max(0, start_row)
            valid_row_end = min(height, start_row + 16)
            valid_col_start = max(0, start_col)
            valid_col_end = min(width, start_col + 16)
            
            if valid_row_start >= valid_row_end or valid_col_start >= valid_col_end:
                continue
                
            col_pixels = np.full((3, 16, 16), BG_COLOR[0], dtype=np.uint8)
            col_pixels[0, :, :] = BG_COLOR[0]
            col_pixels[1, :, :] = BG_COLOR[1]
            col_pixels[2, :, :] = BG_COLOR[2]
            
            col_filled = np.zeros((16, 16), dtype=bool)
            
            for pos, by in blocks_in_col:
                if col_filled.all():
                    break
                
                cursor.execute("SELECT data FROM blocks WHERE pos=?", (pos,))
                data_row = cursor.fetchone()
                if not data_row:
                    continue
                
                raw_data = data_row[0]
                version, decompressed = decompress_blob(raw_data)
                
                if not decompressed:
                    continue
                    
                parsed = parse_mapblock(decompressed)
                content_width = parsed.get("content_width")
                param0 = parsed.get("node_data", {}).get("param0")
                if not param0:
                    continue
                
                decoded_node_ids = decode_node_ids(param0, content_width)
                mapping_dict = build_mapping_dict(parsed.get("mappings", []))
                
                for z in range(16):
                    for x in range(16):
                        if col_filled[z, x]:
                            continue
                            
                        # Search from top (Y=15) to bottom (Y=0) of this block
                        for y in range(15, -1, -1):
                            index = z * 256 + y * 16 + x
                            nid = decoded_node_ids[index]
                            name = mapping_dict.get(nid, "unknown")
                            
                            if name != "air" and name != "ignore":
                                color = colors.get(name, DEFAULT_COLOR)
                                img_y = 15 - z
                                img_x = x
                                
                                col_pixels[0, img_y, img_x] = color[0]
                                col_pixels[1, img_y, img_x] = color[1]
                                col_pixels[2, img_y, img_x] = color[2]
                                col_filled[z, x] = True
                                break
            
            win_row_off = valid_row_start - start_row
            win_col_off = valid_col_start - start_col
            win_row_len = valid_row_end - valid_row_start
            win_col_len = valid_col_end - valid_col_start
            
            win = Window(valid_col_start, valid_row_start, win_col_len, win_row_len)
            cropped_pixels = col_pixels[:, win_row_off:win_row_off+win_row_len, win_col_off:win_col_off+win_col_len]
            
            dst.write(cropped_pixels, window=win)
            
            processed += 1
            if processed % 1000 == 0:
                print(f"Processed {processed}/{total_cols} MapBlock columns...")
                
    conn.close()
    print("GeoTIFF generation complete!")

if __name__ == "__main__":
    main()
