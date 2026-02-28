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
    
    # Check schema of the main blocks table
    cur.execute("PRAGMA table_info(blocks)")
    columns = [row[1] for row in cur.fetchall()]
    
    if not columns:
        sys.exit(0)
        
    if 'x' in columns:
        cur.execute("SELECT DISTINCT x, z FROM blocks")
        rows = cur.fetchall()
        is_xyz = True
    else:
        cur.execute("SELECT pos FROM blocks")
        rows = cur.fetchall()
        is_xyz = False
        
    conn.close()
except sqlite3.OperationalError:
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
        u = pos & 0xFFFFFFFFFFFFFFFF
        x = u & 0xFFF
        if x >= 0x800: x -= 0x1000
        z = (u >> 24) & 0xFFF
        if z >= 0x800: z -= 0x1000
    
    node_x = x * MAPBLOCK_NODES
    node_z = z * MAPBLOCK_NODES
    
    chunk_index_x = node_x // CHUNK_SIZE_NODES
    chunk_index_z = node_z // CHUNK_SIZE_NODES
    
    chunks.add((chunk_index_x, chunk_index_z))

# Output the bottom-left corner of each chunk boundary (x,z)
for cx, cz in chunks:
    print(f"{cx * CHUNK_SIZE_NODES},{cz * CHUNK_SIZE_NODES}")
