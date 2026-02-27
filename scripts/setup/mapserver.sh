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

# Install Minetest Mapserver and its required Luanti mod
# Usage: ./scripts/setup/mapserver.sh

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

USER_HOME=$(get_user_home)
MAPSERVER_DIR="$USER_HOME/minetest-mapserver"
MODS_DIR="$USER_HOME/snap/luanti/common/.minetest/mods"

print_info "=== Minetest Mapserver Setup ==="

# Step 1: Download Mapserver Binary
# Using version v4.8.0 for Linux AMD64
MAPSERVER_URL="https://github.com/minetest-mapserver/mapserver/releases/download/v4.8.0/mapserver_4.8.0_linux_amd64.tar.gz"

if [ ! -d "$MAPSERVER_DIR" ]; then
    print_info "Creating directory $MAPSERVER_DIR..."
    mkdir -p "$MAPSERVER_DIR"
fi

cd "$MAPSERVER_DIR"

if [ ! -f "mapserver" ]; then
    print_info "Downloading Minetest Mapserver..."
    wget -qO mapserver.tar.gz "$MAPSERVER_URL"
    
    if [ $? -eq 0 ]; then
        print_info "Extracting Mapserver..."
        tar -xzf mapserver.tar.gz
        rm mapserver.tar.gz
        chmod +x mapserver
        print_info "Mapserver binary installed successfully."
    else
        print_error "Failed to download Mapserver binary."
        exit 1
    fi
else
    print_info "Mapserver binary already exists at $MAPSERVER_DIR/mapserver"
fi

# Step 2: Install the required Luanti Mapserver Mod
print_info "Installing the required Mapserver Mod..."

mkdir -p "$MODS_DIR"
MOD_DIR="$MODS_DIR/mapserver"

if [ ! -d "$MOD_DIR" ]; then
    print_info "Cloning Mapserver mod..."
    git clone https://github.com/minetest-mapserver/mapserver_mod.git "$MOD_DIR"
    
    if [ $? -eq 0 ]; then
        print_info "Mapserver mod installed successfully."
    else
        print_error "Failed to clone Mapserver mod."
        exit 1
    fi
else
    print_info "Mapserver mod already exists at $MOD_DIR. Pulling latest updates..."
    cd "$MOD_DIR"
    git pull
fi

print_info "Setup complete! Mapserver is ready to be used."
