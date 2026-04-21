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

# Setup real-time Luanti Go Mapserver hosting
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
MAPSERVER_BIN="$PROJECT_ROOT/scripts/map/mapserver"

# Ensure world exists
if [ ! -d "$WORLD_PATH" ]; then
    print_error "World directory not found: $WORLD_PATH"
    print_info "Make sure to create the world first or run the Luanti server once"
    exit 1
fi

# Ensure Mapserver binary exists
if [ ! -f "$MAPSERVER_BIN" ]; then
    print_error "Mapserver binary not found at: $MAPSERVER_BIN"
    print_info "Please ensure the mapserver binary is located at scripts/map/mapserver"
    exit 1
fi

# Make binary executable
chmod +x "$MAPSERVER_BIN"

print_info "Setting up real-time Go Mapserver service..."

# Create Go Mapserver Systemd Service
print_info "Creating luanti-mapserver@${WORLD}.service..."
sudo tee /etc/systemd/system/luanti-mapserver@${WORLD}.service > /dev/null <<EOF
[Unit]
Description=Luanti Go Mapserver - ${WORLD} (Port ${MAP_PORT})
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=$WORLD_PATH
Environment="MAPSERVER_PORT=${MAP_PORT}"
# By running mapserver inside the world directory, it auto-detects world.mt
ExecStartPre=/usr/bin/python3 -c "import json, os; f='mapserver.json'; d = json.load(open(f)) if os.path.exists(f) else {}; d['port'] = int('${MAP_PORT}'); json.dump(d, open(f, 'w'), indent=4)"
ExecStart=$MAPSERVER_BIN
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Note: We configure the port directly into mapserver.json via the ExecStartPre Python hook.

# Open Firewall Port
print_info "Opening port ${MAP_PORT}..."
sudo ufw allow ${MAP_PORT}/tcp

# Start Services
print_info "Starting service..."
sudo systemctl daemon-reload

# Disable old legacy python-based services if they existed
sudo systemctl disable --now luanti-map-render@${WORLD} 2>/dev/null || true
sudo systemctl disable --now luanti-map-server@${WORLD} 2>/dev/null || true

# Enable new go mapserver service
sudo systemctl enable luanti-mapserver@${WORLD}
sudo systemctl start luanti-mapserver@${WORLD}

print_info "Mapserver service started successfully!"
echo "Map interface is now hosted at: http://$(hostname -I | awk '{print $1}'):${MAP_PORT}/"
echo "QGIS Tile Endpoint: http://$(hostname -I | awk '{print $1}'):${MAP_PORT}/api/tile/1/{z}/{x}/{y}"
echo ""
print_info "Service Management Commands:"
echo "  Status:  sudo systemctl status luanti-mapserver@${WORLD}"
echo "  Logs:    sudo journalctl -u luanti-mapserver@${WORLD} -f"

