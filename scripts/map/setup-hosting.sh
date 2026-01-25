#!/bin/bash
# Copyright (C) 2026 Ephraim BOURIAHI
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Setup map hosting services (renderer + HTTP server)
# Usage: ./setup-hosting.sh <world_name> [map_port]

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

WORLD="$1"
MAP_PORT="${2:-8080}"  # Default to 8080 if not specified

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 <world_name> [map_port]"
    echo "  Default port: 8080"
    exit 1
fi

# Configuration
SERVICE_USER=$(get_current_user)
USER_HOME=$(get_user_home)
PROJECT_ROOT=$(get_project_root)
WORLD_PATH="$USER_HOME/snap/luanti/common/.minetest/worlds/$WORLD"
MAP_OUTPUT_DIR="$WORLD_PATH/map_output"  # Store maps inside world folder

# Ensure world exists
if [ ! -d "$WORLD_PATH" ]; then
    print_error "World directory not found: $WORLD_PATH"
    print_info "Make sure to create the world first or run the Luanti server once"
    exit 1
fi

# Create map output directory
mkdir -p "$MAP_OUTPUT_DIR"

# Ensure the service user owns the directory
print_info "Setting permissions for $SERVICE_USER on $MAP_OUTPUT_DIR..."
sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$MAP_OUTPUT_DIR"

print_info "Setting up real-time map services..."

# Create Map Renderer Service (world-specific)
print_info "Creating luanti-map-render@${WORLD}.service..."
sudo tee /etc/systemd/system/luanti-map-render@${WORLD}.service > /dev/null <<EOF
[Unit]
Description=Luanti Map Auto-Renderer - ${WORLD} (15s Interval)

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=$PROJECT_ROOT
ExecStart=/bin/bash $PROJECT_ROOT/scripts/map/auto-render.sh $WORLD
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Create HTTP Map Server Service (world-specific)
print_info "Creating luanti-map-server@${WORLD}.service..."
sudo tee /etc/systemd/system/luanti-map-server@${WORLD}.service > /dev/null <<EOF
[Unit]
Description=Luanti Map HTTP Server - ${WORLD} (Port ${MAP_PORT})

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=$MAP_OUTPUT_DIR
ExecStart=/usr/bin/python3 $PROJECT_ROOT/src/range_server.py ${MAP_PORT}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Open Firewall Port
print_info "Opening port ${MAP_PORT}..."
sudo ufw allow ${MAP_PORT}/tcp

# Start Services
print_info "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable luanti-map-render@${WORLD}
sudo systemctl start luanti-map-render@${WORLD}
sudo systemctl enable luanti-map-server@${WORLD}
sudo systemctl start luanti-map-server@${WORLD}

print_info "Map services started successfully!"
echo "Map is now hosted at: http://$(hostname -I | awk '{print $1}'):${MAP_PORT}/map.png"
echo ""
print_info "Service Management Commands:"
echo "  Status:  sudo systemctl status luanti-map-render@${WORLD}"
echo "  Status:  sudo systemctl status luanti-map-server@${WORLD}"
echo "  Logs:    sudo journalctl -u luanti-map-render@${WORLD} -f"
echo "  Logs:    sudo journalctl -u luanti-map-server@${WORLD} -f"
