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

# Install and compile minetestmapper for map rendering
# Usage: ./mapper.sh <world_name>

# Load common functions
echo $(cd ../../ && pwd) > /root/.proj_root
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

WORLD="$1"

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 <world_name>"
    exit 1
fi

USER_HOME=$(get_user_home)
MAPPER_DIR="$USER_HOME/minetest-mapper"
WORLD_PATH="$USER_HOME/snap/luanti/common/.minetest/worlds/$WORLD"

print_info "=== Minetest Mapper Setup ==="

# Step 1: Install dependencies
print_info "Installing dependencies..."
sudo apt update
sudo apt install -y cmake libgd-dev zlib1g-dev libpng-dev libjpeg-dev libsqlite3-dev libpq-dev libhiredis-dev libleveldb-dev libzstd-dev git build-essential

# Verify cmake installed
if ! command_exists cmake; then
    print_error "cmake could not be installed. Please install it manually."
    exit 1
fi

# Step 2: Clone minetest-mapper
if [ -d "$MAPPER_DIR" ]; then
    print_warning "minetest-mapper directory already exists. Pulling latest changes..."
    cd "$MAPPER_DIR"
    git pull
else
    print_info "Cloning minetestmapper..."
    git clone https://github.com/luanti-org/minetestmapper.git "$MAPPER_DIR"
    cd "$MAPPER_DIR"
fi

# Step 3: Compiling
print_info "Compiling minetestmapper..."
# CRITICAL: Remove cache file if it exists
if [ -f "CMakeCache.txt" ]; then
    rm CMakeCache.txt
fi

cmake . -DENABLE_LEVELDB=1
make -j$(nproc)

# Step 4: Verify installation
if [ -f "$MAPPER_DIR/minetestmapper" ]; then
    print_info "Compilation successful!"
else
    print_error "Compilation failed. Check the errors above."
    exit 1
fi

# Step 5: Copy colors.txt
if [ ! -f "$MAPPER_DIR/colors.txt" ]; then
    print_info "Downloading default colors.txt..."
    wget https://raw.githubusercontent.com/luanti-org/minetestmapper/master/colors.txt -O "$MAPPER_DIR/colors.txt"
fi

print_info "Setup complete! Executable is located at: $MAPPER_DIR/minetestmapper"
print_info "You can now run scripts/map/render.sh to generate your map."
