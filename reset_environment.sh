#!/bin/bash

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_NAME="luanti_db"
DB_USER="luanti"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}!!! WARNING: This will DELETE the database, user, virtual environment, and systemd services. !!!${NC}"
echo -e "${YELLOW}!!! All player data will be lost. !!!${NC}"
read -p "Are you sure you want to continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo -e "${GREEN}[INFO] Stopping services...${NC}"
sudo systemctl stop luanti-tracker-postgresql 2>/dev/null
sudo systemctl stop luanti-map-render 2>/dev/null
sudo systemctl stop luanti-map-server 2>/dev/null
sudo systemctl disable luanti-tracker-postgresql 2>/dev/null
sudo systemctl disable luanti-map-render 2>/dev/null
sudo systemctl disable luanti-map-server 2>/dev/null

echo -e "${GREEN}[INFO] Removing systemd service files...${NC}"
sudo rm /etc/systemd/system/luanti-tracker-postgresql.service 2>/dev/null
sudo rm /etc/systemd/system/luanti-map-render.service 2>/dev/null
sudo rm /etc/systemd/system/luanti-map-server.service 2>/dev/null
sudo systemctl daemon-reload

echo -e "${GREEN}[INFO] Dropping PostgreSQL database and user...${NC}"
sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS ${DB_NAME};
DROP USER IF EXISTS ${DB_USER};
EOF

echo -e "${GREEN}[INFO] Removing virtual environment...${NC}"
rm -rf "$PROJECT_DIR/venv"

echo -e "${GREEN}[INFO] Cleanup complete! You can now run ./setup_postgresql.sh for a fresh install.${NC}"
