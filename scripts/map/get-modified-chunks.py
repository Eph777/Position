#!/usr/bin/env python3
import sqlite3
import sys
import math

if len(sys.argv) < 3:
    print("Usage: get-modified-chunks.py <map.sqlite> <last_render_time>")
    sys.exit(1)

db_path = sys.argv[1]
last_time = int(sys.argv[2])

try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    
    # Check schema
    cur.execute("PRAGMA table_info(changed_blocks)")
    columns = [row[1] for row in cur.fetchall()]
    
    if not columns:
        sys.exit(0)
        
    if 'x' in columns:
        cur.execute("SELECT x, z FROM changed_blocks WHERE mtime > ?", (last_time,))
        rows = cur.fetchall()
        is_xyz = True
    else:
        cur.execute("SELECT pos FROM changed_blocks WHERE mtime > ?", (last_time,))
        rows = cur.fetchall()
        is_xyz = False
        
    conn.close()
except sqlite3.OperationalError:
    # Table might not exist yet if no blocks changed since migration, or migration hasn't run
    sys.exit(0)

# Unpack pos and find chunks
# We use chunks of 256x256 nodes. A mapblock is 16x16 nodes.
CHUNK_SIZE_NODES = 256
MAPBLOCK_NODES = 16

chunks = set()
for row in rows:
    if is_xyz:
        x, z = row[0], row[1]
    else:
        pos = row[0]
        # Decode Minetest 64-bit block position
        # X is bits 0-11, Y is bits 12-23, Z is bits 24-35 (unsigned 12-bit encoding)
        u = pos & 0xFFFFFFFFFFFFFFFF
        
        x = u & 0xFFF
        if x >= 0x800: x -= 0x1000
            
        z = (u >> 24) & 0xFFF
        if z >= 0x800: z -= 0x1000
    
    # x, z are mapblock coordinates (-2048 to +2047 etc). Each mapblock is 16 nodes.
    # Total node coordinates are x * 16, z * 16.
    # We want to find which 256x256 chunk this node falls into.
    # The chunk boundary align grid is: ..., -256, 0, 256, 512, ...
    
    node_x = x * MAPBLOCK_NODES
    node_z = z * MAPBLOCK_NODES
    
    # Floor division by 256 gives us the chunk grid index
    chunk_index_x = node_x // CHUNK_SIZE_NODES
    chunk_index_z = node_z // CHUNK_SIZE_NODES
    
    chunks.add((chunk_index_x, chunk_index_z))

# Now also find all chunks that should exist but have no PNG file
import os

world_path = os.path.dirname(db_path)
output_dir = os.path.join(world_path, "map_output")

# Query all blocks ever modified to see all valid chunks
try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    if is_xyz:
        cur.execute("SELECT x, z FROM changed_blocks")
    else:
        cur.execute("SELECT pos FROM changed_blocks")
    all_rows = cur.fetchall()
    conn.close()
    
    for row in all_rows:
        if is_xyz:
            x, z = row[0], row[1]
        else:
            pos = row[0]
            u = pos & 0xFFFFFFFFFFFFFFFF
            x = u & 0xFFF
            if x >= 0x800: x -= 0x1000
            z = (u >> 24) & 0xFFF
            if z >= 0x800: z -= 0x1000
            
        node_x = x * MAPBLOCK_NODES
        node_z = z * MAPBLOCK_NODES
        cx = node_x // CHUNK_SIZE_NODES
        cz = node_z // CHUNK_SIZE_NODES
        
        # Check if the PNG exists
        png_path = os.path.join(output_dir, f"chunk_{cx * CHUNK_SIZE_NODES}_{cz * CHUNK_SIZE_NODES}.png")
        if not os.path.exists(png_path):
            chunks.add((cx, cz))
except Exception:
    pass

# Output the bottom-left corner of each chunk boundary (x,z)
for cx, cz in chunks:
    print(f"{cx * CHUNK_SIZE_NODES},{cz * CHUNK_SIZE_NODES}")
