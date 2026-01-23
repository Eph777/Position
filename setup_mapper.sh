#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
MAPPER_DIR="$HOME/minetest-mapper"
# Standard location for Snap installs
WORLD_PATH="$HOME/snap/luanti/common/.minetest/worlds/myworld"

print_info "=== Minetest Mapper Setup ==="

# Step 1: Install dependencies
print_info "Installing dependencies..."
sudo apt update
sudo apt install -y cmake libgd-dev zlib1g-dev libpng-dev libjpeg-dev libsqlite3-dev libpq-dev libhiredis-dev libleveldb-dev libzstd-dev git build-essential

# Verify cmake installed
if ! command -v cmake &> /dev/null; then
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
# This file defines how blocks are colored.
if [ ! -f "$MAPPER_DIR/colors.txt" ]; then
    print_info "Downloading default colors.txt..."
    wget https://raw.githubusercontent.com/luanti-org/minetestmapper/master/colors.txt -O "$MAPPER_DIR/colors.txt"
fi

print_info "Setup complete! executable is located at: $MAPPER_DIR/minetestmapper"
print_info "You can now run ./render_map.sh to generate your map."
