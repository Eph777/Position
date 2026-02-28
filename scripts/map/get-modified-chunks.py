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
    # Find all blocks modified since last_time
    cur.execute("SELECT pos FROM changed_blocks WHERE mtime > ?", (last_time,))
    rows = cur.fetchall()
    conn.close()
except sqlite3.OperationalError:
    # Table might not exist yet if no blocks changed since migration, or migration hasn't run
    sys.exit(0)

# Unpack pos and find chunks
# We use chunks of 256x256 nodes. A mapblock is 16x16 nodes.
CHUNK_SIZE_NODES = 256
MAPBLOCK_NODES = 16

chunks = set()
for (pos,) in rows:
    # Decode Minetest 64-bit block position
    # X is bits 0-11, Y is bits 12-23, Z is bits 24-35 (unsigned 12-bit encoding)
    u = pos & 0xFFFFFFFFFFFFFFFF
    
    x = u & 0xFFF
    if x >= 0x800: x -= 0x1000
        
    z = (u >> 24) & 0xFFF
    if z >= 0x800: z -= 0x1000
    
    # x, z are mapblock coordinates.
    # To get chunk coordinates: floor((x * MAPBLOCK_NODES) / CHUNK_SIZE_NODES)
    chunk_x = math.floor((x * MAPBLOCK_NODES) / CHUNK_SIZE_NODES)
    chunk_z = math.floor((z * MAPBLOCK_NODES) / CHUNK_SIZE_NODES)
    
    chunks.add((chunk_x, chunk_z))

# Output the bottom-left corner of each chunk boundary (x,z)
for cx, cz in chunks:
    print(f"{cx * CHUNK_SIZE_NODES},{cz * CHUNK_SIZE_NODES}")
