#!/bin/bash
# Start Luanti game server
# Usage: ./start-luanti.sh <world_name> <port> [--service]

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh






WORLD="$1"
PORT="${2:-30000}"
IS_SERVICE=false

# Parse arguments
shift 2 2>/dev/null || shift $#
while [[ $# -gt 0 ]]; do
    case $1 in
        --service) IS_SERVICE=true; shift ;;
        *) shift ;;
    esac
done

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 <world_name> [port] [--service]"
    exit 1
fi

USER_HOME=$(get_user_home)
WORLD_PATH="$USER_HOME/snap/luanti/common/.minetest/worlds/$WORLD"
WORLD_MT="$WORLD_PATH/world.mt"

# Create world directory if it doesn't exist
if [ ! -d "$WORLD_PATH" ]; then
    print_info "Creating world directory: $WORLD"
    mkdir -p "$WORLD_PATH"
fi

# Create or verify world.mt file
if [ ! -f "$WORLD_MT" ]; then
    print_info "Creating world.mt configuration file..."
    cat > "$WORLD_MT" <<EOF
gameid = minetest_game
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
load_mod_position_tracker = true
EOF
    print_info "World configuration created."
else
    print_info "World $WORLD exists."
fi

# Check port availability
if [ "$IS_SERVICE" = true ]; then
    check_port "$PORT" --kill --force || exit 1
else
    check_port "$PORT" --kill || exit 1
fi

print_info "Starting Luanti server..."
print_info "World: $WORLD"
print_info "Port: $PORT"

/snap/bin/luanti --server --world "$WORLD_PATH" --gameid minetest_game --port "$PORT"
