#!/bin/bash

# Full Server Backup Script
# Run this on your VPS to prepare for a full machine reset.
# It packages the Database AND User Uploads into one file.

WORLDS_DIR="/root/snap/luanti/common/.minetest/worlds"

if [ ! -d "$WORLDS_DIR" ]; then
    echo "Error: Minetest worlds directory not found at $WORLDS_DIR"
    exit 1
fi

# Gather available worlds
worlds=()
while IFS= read -r -d '' dir; do
    worlds+=("$(basename "$dir")")
done < <(find "$WORLDS_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

if [ ${#worlds[@]} -eq 0 ]; then
    echo "No worlds found in $WORLDS_DIR"
    exit 1
fi

echo "============================================"
echo "Available Worlds:"
echo "============================================"
PS3="Select a world to backup (enter a number): "
select WORLD in "${worlds[@]}"; do
    if [ -n "$WORLD" ]; then
        echo "You selected: $WORLD"
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

TIMESTAMP_DATE=$(date +"%Y-%m-%d")
TIMESTAMP_TIME=$(date +"%H:%M:%S")
BACKUP_DIR="backup_files"
ARCHIVE_NAME="${WORLD}_${TIMESTAMP_DATE}_${TIMESTAMP_TIME}.tar.gz"

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
