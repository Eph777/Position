#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Determine if running as root
if [ "$EUID" -eq 0 ]; then
    print_warning "Running as root user."
    USER_HOME="/root"
    CURRENT_USER="root"
else
    USER_HOME="$HOME"
    CURRENT_USER=$(whoami)
fi





# Function to update or append a key=value pair in world.mt
update_world_mt() {
    local key=$1
    local value=$2
    local file="${USER_HOME}/snap/luanti/common/.luanti/worlds/myworld/world.mt"
    
    if grep -q "^${key} *=" "$file"; then
        sed -i "s|^${key} *=.*|${key} = ${value}|" "$file"
    else
        echo "${key} = ${value}" >> "$file"
    fi
}

# Migrate database to SQLite3
print_info "Migrating database to SQLite3..."

update_world_mt "mod_storage_backend" "sqlite3"
/snap/bin/luanti --server --world ~/snap/luanti/common/.luanti/worlds/myworld --migrate-mod-storage sqlite3

update_world_mt "auth_backend" "sqlite3"
/snap/bin/luanti --server --world ~/snap/luanti/common/.luanti/worlds/myworld --migrate-auth sqlite3

update_world_mt "player_backend" "sqlite3"
/snap/bin/luanti --server --world ~/snap/luanti/common/.luanti/worlds/myworld --migrate-players sqlite3

update_world_mt "backend" "sqlite3"
/snap/bin/luanti --server --world ~/snap/luanti/common/.luanti/worlds/myworld --migrate sqlite3

# # Define your paths here for cleaner usage
# LUANTI_BIN="/snap/bin/luanti"
# WORLD_PATH="${USER_HOME}/snap/luanti/common/.luanti/worlds/myworld" 

# # Function to run a migration and handle the "same backend" error
# safe_migrate() {
#     FLAG=$1 # e.g., --migrate-auth
#     NAME=$2 # e.g., "Auth"

#     echo "Attempting to migrate $NAME..."
    
#     # Run the command and capture ALL output (errors and info combined)
#     OUTPUT=$($LUANTI_BIN --server --world "$WORLD_PATH" $FLAG sqlite3 2>&1)
#     EXIT_CODE=$?

#     # Logic: If success (0) OR if output contains the specific warning
#     if [ $EXIT_CODE -eq 0 ]; then
#         echo "$NAME: Successfully migrated."
#     elif echo "$OUTPUT" | grep -q "new backend is same as the old one"; then
#         echo "$NAME: Already on SQLite3. (Skipped)"
#     else
#         # If it failed for a real reason, show the error
#         echo "$NAME: Failed with error:"
#         echo "$OUTPUT"
#     fi
# }

# # Run the migrations using the function
# safe_migrate "--migrate-auth" "Authentication"
# safe_migrate "--migrate-players" "Players"
# safe_migrate "--migrate-mod-storage" "Mod Storage"

# # Note: Map migration uses just '--migrate', not '--migrate-map'
# safe_migrate "--migrate" "World Map"