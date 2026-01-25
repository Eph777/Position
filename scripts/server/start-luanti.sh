#!/bin/bash
# Start Luanti game server
# Usage: ./start-luanti.sh <world_name> [port] [--service] [--map MAP_PORT]
#   Without --service: Runs in foreground
#   With --service: Creates and starts systemd service
#   With --map PORT: Also starts map rendering and hosting services on specified port

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

WORLD="$1"
PORT="${2:-30000}"
IS_SERVICE=false
MAP_PORT=""

# Open firewall for game server port
sudo ufw allow "$PORT/udp"

# Parse arguments
shift 2 2>/dev/null || shift $#
while [[ $# -gt 0 ]]; do
    case $1 in
        --service) IS_SERVICE=true; shift ;;
        --map) MAP_PORT="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 <world_name> [port] [--service] [--map MAP_PORT]"
    echo "  Without --service: Runs in foreground"
    echo "  With --service: Creates and starts systemd service"
    echo "  With --map PORT: Also starts map rendering and hosting on specified port"
    exit 1
fi

USER_HOME=$(get_user_home)
CURRENT_USER=$(get_current_user)
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

# Setup map services if --map is specified
if [ -n "$MAP_PORT" ]; then
    print_info "Setting up map rendering and hosting services on port $MAP_PORT..."
    
    # Open firewall for map server
    print_info "Opening firewall port $MAP_PORT/tcp..."
    sudo ufw allow "$MAP_PORT/tcp"
    
    # Run map hosting setup script
    print_info "Configuring map services..."
    "$PROJECT_ROOT/scripts/map/setup-hosting.sh" "$WORLD" "$MAP_PORT" || {
        print_error "Failed to setup map services"
        exit 1
    }
    
    # Verify services are running
    sleep 2
    if systemctl is-active --quiet luanti-map-render && systemctl is-active --quiet luanti-map-server; then
        print_info "Map services started successfully!"
        print_info "Map will be available at: http://$(hostname -I | awk '{print $1}'):$MAP_PORT/map.png"
    else
        print_warning "Map services may not have started correctly. Check with:"
        echo "  sudo systemctl status luanti-map-render"
        echo "  sudo systemctl status luanti-map-server"
    fi
    echo ""
fi

# Service mode: Create and start systemd service
if [ "$IS_SERVICE" = true ]; then
    print_info "Setting up Luanti server as systemd service..."
    
    SERVICE_NAME="luanti-server@${WORLD}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    
    print_info "Creating systemd service: ${SERVICE_NAME}"
    
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Luanti Game Server - ${WORLD} (Port ${PORT})
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${USER_HOME}
ExecStart=/snap/bin/luanti --server --world ${WORLD_PATH} --gameid minetest_game --port ${PORT}
Restart=always
RestartSec=10

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=luanti-${WORLD}

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    print_info "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    
    # Enable service
    print_info "Enabling ${SERVICE_NAME}..."
    sudo systemctl enable "${SERVICE_NAME}"
    
    # Start service
    print_info "Starting ${SERVICE_NAME}..."
    sudo systemctl start "${SERVICE_NAME}"
    
    # Show status
    echo ""
    print_info "Service started successfully!"
    print_info "Status:"
    sudo systemctl status "${SERVICE_NAME}" --no-pager | head -n 10
    
    echo ""
    print_info "Service Management Commands:"
    echo "  Stop:    sudo systemctl stop ${SERVICE_NAME}"
    echo "  Restart: sudo systemctl restart ${SERVICE_NAME}"
    echo "  Status:  sudo systemctl status ${SERVICE_NAME}"
    echo "  Logs:    sudo journalctl -u ${SERVICE_NAME} -f"
    
else
    # Foreground mode: Run luanti directly
    print_info "Running Luanti server in foreground mode..."
    print_info "World: $WORLD"
    print_info "Port: $PORT"
    print_info "Press Ctrl+C to stop the server"
    echo ""
    
    /snap/bin/luanti --server --world "$WORLD_PATH" --gameid minetest_game --port "$PORT"
fi
