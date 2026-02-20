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
BACKUP_DIR="backup_$TIMESTAMP"
ARCHIVE_NAME="world_$WORLD_$TIMESTAMP.tar.gz"

echo "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

echo "============================================"
echo "1. Backing up World $WORLD..."
echo "============================================"
#copy world folder from snap/luanti/common/.minetest/worlds/$WORLD to $BACKUP_DIR

cp -r /root/snap/luanti/common/.minetest/worlds/$WORLD "$BACKUP_DIR"

echo "============================================"
echo "2. Compressing World $WORLD Archive..."
echo "============================================"
tar -czvf "$ARCHIVE_NAME" "$BACKUP_DIR"

# Cleanup staging folder
rm -rf "$BACKUP_DIR"

echo ""
echo "============================================"
echo "BACKUP COMPLETE: $ARCHIVE_NAME"
echo "============================================"
echo "Run this command on your LOCAL machine to download it:"
echo "scp root@your-vps-ip:$(pwd)/$ARCHIVE_NAME ./"
