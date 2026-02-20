#!/bin/bash

# Full Server Backup Script
# Run this on your VPS to prepare for a full machine reset.
# It packages the Database AND User Uploads into one file.

WORLD=$1

if [ -z "$WORLD" ]; then
    echo "Usage: $0 <world_name>"
    exit 1
fi

if [ ! -d "/root/snap/luanti/common/.minetest/worlds/$WORLD" ]; then
    echo "World $WORLD does not exist."
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="backup_files"
ARCHIVE_NAME="world_$WORLD_$TIMESTAMP.tar.gz"

echo "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

echo "============================================"
echo "Compressing World $WORLD Archive..."
echo "============================================"
# -C changes the directory before archiving the $WORLD folder
tar -czvf "$BACKUP_DIR/$ARCHIVE_NAME" -C "/root/snap/luanti/common/.minetest/worlds" "$WORLD"

echo ""
echo "============================================"
echo "BACKUP COMPLETE: $BACKUP_DIR/$ARCHIVE_NAME"
echo "============================================"
echo "Run this command on your LOCAL machine to download it:"
echo "scp root@your-vps-ip:$(pwd)/$BACKUP_DIR/$ARCHIVE_NAME ./"
