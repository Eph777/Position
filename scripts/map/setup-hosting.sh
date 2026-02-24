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

# Setup map hosting services (mapserver)
# Usage: ./setup-hosting.sh <world_name> [map_port]

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

WORLD="$1"
MAP_PORT="${2:-8080}"  # Default to 8080

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

# Ensure world exists
if [ ! -d "$WORLD_PATH" ]; then
    print_error "World directory not found: $WORLD_PATH"
    print_info "Make sure to create the world first or run the mapserver setup once"
    exit 1
fi

print_info "Setting up real-time map services..."

# Create Mapserver Service (world-specific)
print_info "Creating luanti-mapserver@${WORLD}.service..."
sudo tee /etc/systemd/system/luanti-mapserver@${WORLD}.service > /dev/null <<EOF
[Unit]
Description=Luanti Mapserver - ${WORLD} (Port ${MAP_PORT})

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${WORLD_PATH}
ExecStartPre=/usr/bin/python3 -c "import json,os; c='$WORLD_PATH/mapserver.json'; d=json.load(open(c)) if os.path.exists(c) else {}; w=d.setdefault('webserver', {}); w['port']=int('${MAP_PORT}'); json.dump(d,open(c,'w'),indent=4);"
ExecStart=${WORLD_PATH}/mapserver
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

# Disable old services if they exist
sudo systemctl stop luanti-map-render@${WORLD} 2>/dev/null || true
sudo systemctl disable luanti-map-render@${WORLD} 2>/dev/null || true
sudo systemctl stop luanti-map-server@${WORLD} 2>/dev/null || true
sudo systemctl disable luanti-map-server@${WORLD} 2>/dev/null || true

sudo systemctl enable luanti-mapserver@${WORLD}
sudo systemctl start luanti-mapserver@${WORLD}

print_info "Map services started successfully!"
echo "Map is now hosted at: http://$(hostname -I | awk '{print $1}'):${MAP_PORT}"
echo ""
print_info "Service Management Commands:"
echo "  Status:  sudo systemctl status luanti-mapserver@${WORLD}"
echo "  Logs:    sudo journalctl -u luanti-mapserver@${WORLD} -f"
