#!/bin/bash

# Full Server Restore Script
# Restores a world backup directly into the luanti minetestworlds folder.

ARCHIVE=$1

if [ -z "$ARCHIVE" ]; then
    echo "Usage: $0 <archive_file>"
    exit 1
fi

if [ ! -f "$ARCHIVE" ]; then
    echo "Archive $ARCHIVE does not exist."
    exit 1
fi

WORLDS_DIR="/root/snap/luanti/common/.minetest/worlds"

echo "============================================"
echo "Restoring Archive $ARCHIVE..."
echo "============================================"
# create directory if it accidentally got deleted
mkdir -p "$WORLDS_DIR"
# extract the archive directly to the worlds folder
tar -xzvf "$ARCHIVE" -C "$WORLDS_DIR"

echo ""
echo "============================================"
echo "RESTORE COMPLETE!"
echo "============================================"
