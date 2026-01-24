#!/bin/bash
# This script will setup the map hosting and then start the Luanti server

# Default values
WORLD="${1:-myworld}"
PORT="${2:-30000}"

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

WORLD_DIR="$HOME/snap/luanti/common/.minetest/worlds/$WORLD"

if [ -d "$WORLD_DIR" ]; then

    if [ -f "$WORLD_DIR/world.mt" ]; then
        print_info "World $WORLD exists."
        # Ensure mod is enabled
        if ! grep -q "load_mod_position_tracker = true" "$WORLD_DIR/world.mt"; then
            echo "load_mod_position_tracker = true" >> "$WORLD_DIR/world.mt"
            print_info "Enabled position_tracker mod in existing world."
        fi
    else
        print_info "Creating $WORLD's world.mt file."
        echo "gameid = minetest_game" > "$WORLD_DIR/world.mt"
        echo "backend = sqlite3" >> "$WORLD_DIR/world.mt"
        echo "player_backend = sqlite3" >> "$WORLD_DIR/world.mt"
        echo "auth_backend = sqlite3" >> "$WORLD_DIR/world.mt"
        echo "mod_storage_backend = sqlite3" >> "$WORLD_DIR/world.mt"
        echo "load_mod_position_tracker = true" >> "$WORLD_DIR/world.mt"
    fi
else
    print_info "Creating world $WORLD."
    mkdir -p "$WORLD_DIR"
    echo "gameid = minetest_game" > "$WORLD_DIR/world.mt"
    echo "backend = sqlite3" >> "$WORLD_DIR/world.mt"
    echo "player_backend = sqlite3" >> "$WORLD_DIR/world.mt"
    echo "auth_backend = sqlite3" >> "$WORLD_DIR/world.mt"
    echo "mod_storage_backend = sqlite3" >> "$WORLD_DIR/world.mt"
    echo "load_mod_position_tracker = true" >> "$WORLD_DIR/world.mt"
fi

PORT_IN_USE=$(sudo lsof -i :$PORT -t 2>/dev/null || true)
IS_SERVICE=false
if [[ "$3" == "--service" ]]; then
    IS_SERVICE=true
fi

if [ ! -z "$PORT_IN_USE" ]; then
    print_warning "Port $PORT is already in use!"
    
    PROCESS_INFO=$(sudo lsof -i :$PORT | grep LISTEN)
    echo "$PROCESS_INFO"
    
    if [ "$IS_SERVICE" = true ]; then
        print_info "Running in service mode. Killing process on port $PORT automatically..."
        sudo kill -9 $PORT_IN_USE
        sleep 2
        print_info "Process stopped."
    else
        echo ""
        read -p "Do you want to kill this process and continue? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Stopping process on port $PORT..."
            sudo kill -9 $PORT_IN_USE
            sleep 2
            print_info "Process stopped."
        else
            print_error "Cannot proceed while port $PORT is in use. Exiting."
            exit 1
        fi
    fi
fi

/snap/bin/luanti --server --world "$WORLD_DIR" --gameid minetest_game --port $PORT
