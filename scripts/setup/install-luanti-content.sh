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

# Luanti game content setup for Position Tracker
# Usage: ./install-luanti-content.sh

# Get the script directory to find common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common functions
if [ -f "$PROJECT_ROOT/src/lib/common.sh" ]; then
    source "$PROJECT_ROOT/src/lib/common.sh"
else
    echo "[ERROR] Could not find common.sh at $PROJECT_ROOT/src/lib/common.sh"
    exit 1
fi

USER_HOME=$(get_user_home)
PROJECT_ROOT=$(get_project_root)

print_info "Installing Luanti game content..."

# Create directories
mkdir -p ${USER_HOME}/snap/luanti/common/.minetest/games
mkdir -p ${USER_HOME}/snap/luanti/common/.minetest/worlds/myworld
mkdir -p ${USER_HOME}/snap/luanti/common/.minetest/mods

# Clone Minetest Game
if [ ! -d ${USER_HOME}/snap/luanti/common/.minetest/games/minetest_game ]; then
    print_info "Downloading Minetest Game..."
    git clone https://github.com/minetest/minetest_game.git ${USER_HOME}/snap/luanti/common/.minetest/games/minetest_game
else
    print_info "Minetest Game already exists, skipping..."
fi

# Create world configuration
print_info "Creating world configuration..."
echo "gameid = minetest_game" > ${USER_HOME}/snap/luanti/common/.minetest/worlds/myworld/world.mt
echo "backend = sqlite3" >> ${USER_HOME}/snap/luanti/common/.minetest/worlds/myworld/world.mt
echo "load_mod_position_tracker = true" >> ${USER_HOME}/snap/luanti/common/.minetest/worlds/myworld/world.mt

# Copy mod
print_info "Installing or updating position tracker mod..."
mkdir -p ${USER_HOME}/snap/luanti/common/.minetest/mods/position_tracker
cp -r "$PROJECT_ROOT/mod/"* ${USER_HOME}/snap/luanti/common/.minetest/mods/position_tracker/

# Configure mod
print_info "Configuring mod..."
sed -i 's|local SERVER_URL = .*|local SERVER_URL = "http://localhost:5000/position"|' ${USER_HOME}/snap/luanti/common/.minetest/mods/position_tracker/init.lua

# Create minetest.conf
echo "secure.http_mods = position_tracker" > ${USER_HOME}/snap/luanti/common/.minetest/minetest.conf

print_info "Luanti game content setup complete!"
