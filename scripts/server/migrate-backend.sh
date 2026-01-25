#!/bin/bash
# Migrate Luanti backend to SQLite3
# Usage: ./migrate-backend.sh <world_name> [--force]

# Load common functions
echo $(cd ../../ && pwd) > /root/.proj_root
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

WORLD="$1"
FORCE=false

shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --force) FORCE=true; shift ;;
        *) shift ;;
    esac
done

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 <world_name> [--force]"
    exit 1
fi

USER_HOME=$(get_user_home)
WORLD_PATH="$USER_HOME/snap/luanti/common/.minetest/worlds/$WORLD"
WORLD_MT="$WORLD_PATH/world.mt"

if [ ! -d "$WORLD_PATH" ]; then
    print_error "World not found: $WORLD"
    exit 1
fi

# Function to update or append a key=value pair in world.mt
update_world_mt() {
    local key=$1
    local value=$2
    
    if grep -q "^${key} *=" "$WORLD_MT"; then
        sed -i.bak "s|^${key} *=.*|${key} = ${value}|" "$WORLD_MT"
    else
        echo "${key} = ${value}" >> "$WORLD_MT"
    fi
}

# Function to run a migration and handle the "same backend" error
safe_migrate() {
    local flag=$1        # e.g., --migrate-auth
    local name=$2        # e.g., "Auth"
    local config_name=$3 # e.g., "auth_backend"

    print_info "Attempting to migrate $name..."
    
    # Update config first
    update_world_mt "$config_name" "sqlite3"
    
    # Run the command and capture ALL output (errors and info combined)
    output=$(/snap/bin/luanti --server --world "$WORLD_PATH" $flag sqlite3 2>&1)
    exit_code=$?

    # Logic: If success (0) OR if output contains the specific warning
    if [ $exit_code -eq 0 ]; then
        print_info "$name: Successfully migrated."
    elif echo "$output" | grep -q "new backend is same as the old one"; then
        print_info "$name: Already on SQLite3. (Skipped)"
    else
        # If it failed for a real reason, show the error
        print_error "$name: Failed with error:"
        print_error "$output"
    fi
}

if [ "$FORCE" = false ]; then
    print_warning "This will migrate all backends to SQLite3 for world: $WORLD"
    confirm "Do you want to continue?" || exit 1
fi

print_info "Starting migration for world: $WORLD"

# Run the migrations using the function
safe_migrate "--migrate-auth" "Authentication" "auth_backend"
safe_migrate "--migrate-players" "Players" "player_backend"
safe_migrate "--migrate-mod-storage" "Mod Storage" "mod_storage_backend"
safe_migrate "--migrate" "World Map" "backend"

print_info "Migration complete!"
