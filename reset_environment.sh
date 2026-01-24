#!/bin/bash
# Author: Ephraim BOURIAHI
# Date: 2025-01-24

# Luanti Position Tracker - Reset Environment Script
# This script will reset the environment by removing all data, services, and virtual environments

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLDS_DATA_DIR="$PROJECT_DIR/worlds_data"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}!!! WARNING: This will DELETE ALL DATA including: !!!${NC}"
echo -e "${YELLOW} - All World Databases (Player positions, Teams)${NC}"
echo -e "${YELLOW} - All Logs${NC}"
echo -e "${YELLOW} - Systemd Services (luanti-server@*, luanti-tracker-postgresql, etc)${NC}"
echo -e "${YELLOW} - Virtual Environments${NC}"
echo ""
read -p "Are you sure you want to RESET EVERYTHING? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo -e "${GREEN}[INFO] Stopping and disabling all luanti services...${NC}"

# Find all luanti-server@* services
SERVICES=$(systemctl list-units --full --all --no-legend --plain | grep -o 'luanti-server@[^ ]*')
for svc in $SERVICES; do
    echo "Stopping $svc..."
    sudo systemctl stop "$svc" 2>/dev/null
    sudo systemctl disable "$svc" 2>/dev/null
done

# Stop legacy/global services
sudo systemctl stop luanti-tracker-postgresql 2>/dev/null
sudo systemctl stop luanti-map-render 2>/dev/null
sudo systemctl stop luanti-map-server 2>/dev/null
sudo systemctl stop luanti-server@* 2>/dev/null
sudo systemctl disable luanti-tracker-postgresql 2>/dev/null
sudo systemctl disable luanti-map-render 2>/dev/null
sudo systemctl disable luanti-map-server 2>/dev/null
sudo systemctl disable luanti-server@* 2>/dev/null

pkill -f luanti
pkill -f python3

echo -e "${GREEN}[INFO] Removing systemd service files...${NC}"
sudo rm /etc/systemd/system/luanti-server@*.service 2>/dev/null
sudo rm /etc/systemd/system/luanti-tracker-postgresql.service 2>/dev/null
sudo rm /etc/systemd/system/luanti-map-render.service 2>/dev/null
sudo rm /etc/systemd/system/luanti-map-server.service 2>/dev/null

sudo systemctl daemon-reload

echo -e "${GREEN}[INFO] Cleaning up Data Directories...${NC}"
# Remove the per-world data (databases, logs, configs)
if [ -d "$WORLDS_DATA_DIR" ]; then
    echo "Removing $WORLDS_DATA_DIR..."
    rm -rf "$WORLDS_DATA_DIR"
fi

# Remove legacy venv if it exists
if [ -d "$PROJECT_DIR/venv" ]; then
    echo "Removing venv..."
    rm -rf "$PROJECT_DIR/venv"
fi

echo -e "${GREEN}[INFO] Cleaning up Global PostgreSQL (Legacy)...${NC}"
# Attempt to drop legacy global DB/User just in case
sudo -u postgres psql <<EOF 2>/dev/null
DROP DATABASE IF EXISTS luanti_db;
DROP USER IF EXISTS luanti;
EOF

echo -e "${GREEN}[INFO] Cleanup complete! Environment is reset.${NC}"
echo "You can now run './sls <world>' to start fresh."
