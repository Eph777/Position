#!/bin/bash

# Full Server Restore Script
# Restores a world backup directly into the luanti minetestworlds folder.

BACKUP_DIR="backup_files"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Error: Backup directory not found at $BACKUP_DIR"
    exit 1
fi

# Gather available archives
archives=()
while IFS= read -r -d '' file; do
    archives+=("$file")
done < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -name "*.tar.gz" -type f -print0)

if [ ${#archives[@]} -eq 0 ]; then
    echo "No backups found in $BACKUP_DIR"
    exit 1
fi

echo "============================================================"
printf "%-5s | %-20s | %-12s | %-10s\n" "No." "World Name" "Date" "Time"
echo "------------------------------------------------------------"

# Create a formatted display array for 'select'
display_list=()
for i in "${!archives[@]}"; do
    filename=$(basename "${archives[$i]}")
    
    # Extract data assuming format: worldname_YYYY-MM-DD_HH:MM:SS.tar.gz
    # Remove .tar.gz
    name_no_ext="${filename%.tar.gz}" 
    
    # Parse out pieces using string manipulation based on underscores
    time="${name_no_ext##*_}"
    tmp="${name_no_ext%_*}"
    date="${tmp##*_}"
    world="${tmp%_*}"

    num=$((i+1))
    printf "%-5s | %-20s | %-12s | %-10s\n" "[$num]" "$world" "$date" "$time"
    display_list+=("$filename")
done
echo "============================================================"

# Read user selection manually to provide clean formatting instead of default select menu
while true; do
    read -p "Select a backup to restore (enter a number): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#archives[@]}" ];; then
        index=$((choice-1))
        ARCHIVE="${archives[$index]}"
        echo "You selected: $(basename "$ARCHIVE")"
        break
    else
        echo "Invalid selection. Please enter a valid number."
    fi
done

WORLDS_DIR="/root/snap/luanti/common/.minetest/worlds"

echo "============================================"
echo "Restoring Archive $(basename "$ARCHIVE")..."
echo "============================================"
# create directory if it accidentally got deleted
mkdir -p "$WORLDS_DIR"
# extract the archive directly to the worlds folder
tar -xzvf "$ARCHIVE" -C "$WORLDS_DIR"

echo ""
echo "============================================"
echo "RESTORE COMPLETE!"
echo "============================================"
