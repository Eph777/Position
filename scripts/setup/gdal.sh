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

# Install GDAL dependencies for map tiling
# Usage: ./gdal.sh

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root 2>/dev/null || echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)")
source $PROJECT_ROOT/src/lib/common.sh || { echo "Error: common.sh not found"; exit 1; }

print_info "=== GDAL Setup ==="

# Step 1: Install GDAL
print_info "Installing GDAL packages..."
if command_exists apt; then
    sudo apt update
    sudo apt install -y gdal-bin python3-gdal
else
    print_warning "Apt not found. Please install gdal-bin and python3-gdal manually for your distribution."
fi

# Step 2: Verify installation
if command_exists gdal_translate; then
    print_info "GDAL binary (gdal_translate) verified."
else
    print_error "gdal_translate not found after installation."
    exit 1
fi

if python3 -c "from osgeo import gdal" 2>/dev/null; then
    print_info "GDAL Python bindings verified."
else
    print_error "GDAL Python bindings not found."
    exit 1
fi

# Verifying gdal2tiles.py
if command_exists gdal2tiles.py; then
    print_info "gdal2tiles.py verified."
else
    # Sometimes it's installed as gdal2tiles
    if command_exists gdal2tiles; then
        print_info "gdal2tiles verified (aliased)."
    else
        print_error "gdal2tiles utility not found."
        exit 1
    fi
fi

print_info "GDAL setup complete!"
