#!/bin/bash
# This script will setup the map hosting and then start the Luanti server
PORT=$2
WORLD="$1"


print_info "Setting up map hosting..."
~/luanti-qgis/setup_map_hosting.sh

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
