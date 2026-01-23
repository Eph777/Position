#!/bin/bash
# This script will setup the map hosting and then start the Luanti server
PORT=$2
WORLD="$1"

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

if [ -d "~/snap/luanti/common/.minetest/worlds/$WORLD" ]; then

    if [ -f "~/snap/luanti/common/.minetest/worlds/$WORLD/world.mt" ]; then
        print_info "World $WORLD exists."
    else
        print_info "creating $WORLD's world.mt file."
        echo "gameid = minetest_game" > "~/snap/luanti/common/.minetest/worlds/$WORLD/world.mt"
        echo "backend = sqlite3" >> "~/snap/luanti/common/.minetest/worlds/$WORLD/world.mt"
        echo "player_backend = sqlite3" >> "~/snap/luanti/common/.minetest/worlds/$WORLD/world.mt"
        echo "auth_backend = sqlite3" >> "~/snap/luanti/common/.minetest/worlds/$WORLD/world.mt"
        echo "mod_storage_backend = sqlite3" >> "~/snap/luanti/common/.minetest/worlds/$WORLD/world.mt"
    fi
else
    print_info "creating world $WORLD."
    mkdir -p "~/snap/luanti/common/.minetest/worlds/$WORLD"
    echo "gameid = minetest_game" > "~/snap/luanti/common/.minetest/worlds/$WORLD/world.mt"
    echo "backend = sqlite3" >> "~/snap/luanti/common/.minetest/worlds/$WORLD/world.mt"
    echo "player_backend = sqlite3" >> "~/snap/luanti/common/.minetest/worlds/$WORLD/world.mt"
    echo "auth_backend = sqlite3" >> "~/snap/luanti/common/.minetest/worlds/$WORLD/world.mt"
    echo "mod_storage_backend = sqlite3" >> "~/snap/luanti/common/.minetest/worlds/$WORLD/world.mt"
fi

PORT_IN_USE=$(sudo lsof -i :$PORT -t 2>/dev/null || true)

if [ ! -z "$PORT_IN_USE" ]; then
    print_warning "Port $PORT is already in use!"
    
    PROCESS_INFO=$(sudo lsof -i :$PORT | grep LISTEN)
    echo "$PROCESS_INFO"
    
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

/snap/bin/luanti --server --world ~/snap/luanti/common/.minetest/worlds/$WORLD --gameid minetest_game --port $PORT
