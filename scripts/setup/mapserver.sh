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

# Install mapserver for incremental map rendering
# Usage: ./mapserver.sh <world_name>

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

WORLD="$1"

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 <world_name>"
    exit 1
fi

USER_HOME=$(get_user_home)
WORLD_PATH="$USER_HOME/snap/luanti/common/.minetest/worlds/$WORLD"

if [ ! -d "$WORLD_PATH" ]; then
    print_error "World directory not found at $WORLD_PATH"
    print_info "Make sure to create the world first or run the Luanti server once"
    exit 1
fi

print_info "=== Minetest Mapserver Setup ==="

# Download the latest mapserver release
print_info "Fetching latest Mapserver release URL..."
RELEASE_URL=$(curl -s https://api.github.com/repos/minetest-mapserver/mapserver/releases/latest | grep "browser_download_url" | grep "linux_amd64\.tar\.gz" | cut -d '"' -f 4)

if [ -z "$RELEASE_URL" ]; then
    print_error "Failed to fetch Mapserver release URL!"
    exit 1
fi

print_info "Downloading mapserver from $RELEASE_URL..."
wget -qO /tmp/mapserver.tar.gz "$RELEASE_URL"

print_info "Extracting mapserver..."
tar -xzf /tmp/mapserver.tar.gz -C "$WORLD_PATH" mapserver

chmod +x "$WORLD_PATH/mapserver"
rm -f /tmp/mapserver.tar.gz

print_info "Initializing Mapserver for database migration..."
# Stop any running process just in case
sudo systemctl stop luanti-mapserver@${WORLD} 2>/dev/null || true

# Run it once briefly to initialize the database triggers and mapserver.json file
cd "$WORLD_PATH"
timeout 3 ./mapserver || true

# Now modify the mapserver.json layers setting using Python
print_info "Configuring mapserver.json..."
python3 -c "
import json, os
config_path = '$WORLD_PATH/mapserver.json'
if os.path.exists(config_path):
    with open(config_path, 'r') as f:
        data = json.load(f)
    
    if 'layers' not in data:
        data['layers'] = []
    
    # Replace or set the first layer to from: -1, to: 10
    if len(data['layers']) == 0:
        data['layers'].append({
            'id': 1,
            'name': 'Layer 1',
            'from': -1,
            'to': 10
        })
    else:
        for layer in data['layers']:
            layer['from'] = -1
            layer['to'] = 10
    
    with open(config_path, 'w') as f:
        json.dump(data, f, indent=4)
    print('Updated mapserver.json vertical boundaries.')
else:
    print('Warning: mapserver.json not found, configuration skipped.')
"

print_info "Setup complete! Executable is located at: $WORLD_PATH/mapserver"
print_info "You can now run scripts/map/setup-hosting.sh to serve your map."
