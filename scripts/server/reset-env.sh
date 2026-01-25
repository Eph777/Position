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

# Reset Luanti environment - removes all data, services, and configurations
# Usage: ./reset-env.sh [--force]

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

WORLDS_DATA_DIR="$PROJECT_ROOT/worlds_data"
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force) FORCE=true; shift ;;
        *) shift ;;
    esac
done

# Confirmation
print_warning "!!! WARNING: This will DELETE ALL DATA including:"
echo -e "${YELLOW} - All World Databases (Player positions, Teams)${NC}"
echo -e "${YELLOW} - All Logs${NC}"
echo -e "${YELLOW} - Systemd Services (luanti-server@*, luanti-tracker-postgresql, etc)${NC}"
echo -e "${YELLOW} - Virtual Environments${NC}"

if [ "$FORCE" = false ]; then
    confirm "Are you sure you want to RESET EVERYTHING?" || {
        print_info "Aborted."
        exit 0
    }
fi

print_info "Stopping and disabling all luanti services..."

# Find all luanti-server@* services
services=$(systemctl list-units --full --all --no-legend --plain | grep -o 'luanti-server@[^ ]*' || true)
for svc in $services; do
    print_info "Stopping $svc..."
    sudo systemctl stop "$svc" 2>/dev/null || true
    sudo systemctl disable "$svc" 2>/dev/null || true
done


# # Stop legacy/global services
# sudo systemctl stop luanti-tracker-postgresql 2>/dev/null
# sudo systemctl stop luanti-map-render 2>/dev/null
# sudo systemctl stop luanti-map-server 2>/dev/null
# sudo systemctl stop luanti-server@* 2>/dev/null
# sudo systemctl disable luanti-tracker-postgresql 2>/dev/null
# sudo systemctl disable luanti-map-render 2>/dev/null
# sudo systemctl disable luanti-map-server 2>/dev/null
# sudo systemctl disable luanti-server@* 2>/dev/null

# pkill -f luanti
# pkill -f python3

# echo -e "${GREEN}[INFO] Removing systemd service files...${NC}"
# sudo rm /etc/systemd/system/luanti-server@*.service 2>/dev/null
# sudo rm /etc/systemd/system/luanti-tracker-postgresql.service 2>/dev/null
# sudo rm /etc/systemd/system/luanti-map-render.service 2>/dev/null
# sudo rm /etc/systemd/system/luanti-map-server.service 2>/dev/null

# sudo systemctl daemon-reload

# Stop legacy/global services
sudo systemctl stop luanti-tracker-postgresql 2>/dev/null || true
sudo systemctl stop luanti-map-render@* 2>/dev/null || true
sudo systemctl stop luanti-map-server@* 2>/dev/null || true
sudo systemctl disable luanti-tracker-postgresql 2>/dev/null || true
sudo systemctl disable luanti-map-render@* 2>/dev/null || true
sudo systemctl disable luanti-map-server@* 2>/dev/null || true

pkill -f luanti || true
pkill -f python3 || true

print_info "Removing systemd service files..."
sudo rm -f /etc/systemd/system/luanti-server@*.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/luanti-tracker-postgresql.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/luanti-map-render@*.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/luanti-map-server@*.service 2>/dev/null || true

sudo systemctl daemon-reload

print_info "Cleaning up data directories..."
# Remove the per-world data (databases, logs, configs)
if [ -d "$WORLDS_DATA_DIR" ]; then
    print_info "Removing $WORLDS_DATA_DIR..."
    rm -rf "$WORLDS_DATA_DIR"
fi

# Remove legacy venv if it exists
if [ -d "$PROJECT_ROOT/venv" ]; then
    print_info "Removing venv..."
    rm -rf "$PROJECT_ROOT/venv"
fi

print_info "Cleaning up Global PostgreSQL (Legacy)..."
# Attempt to drop legacy global DB/User just in case
sudo -u postgres psql <<EOF 2>/dev/null || true
DROP DATABASE IF EXISTS luanti_db;
DROP USER IF EXISTS luanti;
EOF

print_info "Cleanup complete! Environment is reset."
print_info "You can now run './bin/deploy.sh' to start fresh."
