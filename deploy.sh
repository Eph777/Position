#!/bin/bash

# Luanti Tactical Team Management - Unified Deployment Script
# This script is a "One-Stop Shop" to deploy the entire stack:
# 1. System Dependencies (PostgreSQL, PostGIS, Python, etc.)
# 2. Database Configuration (User, DB, Schema, Extensions)
# 3. Python Middleware (Flask API + Systemd Service)
# 4. Minetest Mapper (Compilation)
# 5. Map Services (Renderer + HTTP Server Systemd Services)
# 6. Luanti Game Server (Systemd Service)

set -e

# Configuration
WORLD_NAME="tactical_world"
GAME_PORT="30000"
DB_NAME="luanti_db"
DB_USER="luanti"
DB_PASS="postgres123" # CHANGE THIS IN PRODUCTION
PYTHON_VERSION="python3"

# Paths
SERVICE_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo ~$SERVICE_USER)
PROJECT_DIR="$USER_HOME/luanti-qgis"
MAPPER_DIR="$USER_HOME/minetest-mapper"
SNAP_WORLD_DIR="$USER_HOME/snap/luanti/common/.minetest/worlds/$WORLD_NAME"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -eq 0 ]; then
    print_warn "Running as root. Service user determined as: $SERVICE_USER"
else
    # We need sudo for many steps.
    print_warn "This script should be run with sudo for package installation and service creation."
    print_warn "Example: sudo ./deploy.sh"
    read -p "Continue as $USER? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi
fi

print_info "=== Starting Unified Deployment ==="

# ----------------------------------------------------------------------
# 1. System Dependencies
# ----------------------------------------------------------------------
print_info "Step 1: Installing System Dependencies..."
apt update
apt install -y postgresql postgresql-contrib postgis python3 python3-pip python3-venv git snapd lsof \
    cmake libgd-dev zlib1g-dev libpng-dev libjpeg-dev libsqlite3-dev libpq-dev libhiredis-dev libleveldb-dev libzstd-dev build-essential

# Install Luanti via Snap
if ! snap list | grep -q luanti; then
    print_info "Installing Luanti Snap..."
    snap install luanti
else
    print_info "Luanti Snap already installed."
fi

# ----------------------------------------------------------------------
# 2. Project Files Setup
# ----------------------------------------------------------------------
print_info "Step 2: Setting up Project Directory..."
# Ensure we are in the right place or copy files if needed.
# Assumes script is run from inside the source folder, OR we copy it to PROJECT_DIR.
# We will treat the current directory as the source and sync to PROJECT_DIR.

mkdir -p "$PROJECT_DIR"
# Copy all files from current dir to PROJECT_DIR (excluding .git or large dirs if needed, but simple cp is fine for now)
# We assume the user ran git clone and is inside the repo.
cp -r ./* "$PROJECT_DIR/"
chown -R "$SERVICE_USER:$SERVICE_USER" "$PROJECT_DIR"

cd "$PROJECT_DIR"

# Python Venv
print_info "Setting up Python Environment..."
sudo -u "$SERVICE_USER" $PYTHON_VERSION -m venv venv
sudo -u "$SERVICE_USER" ./venv/bin/pip install --upgrade pip
sudo -u "$SERVICE_USER" ./venv/bin/pip install -r requirements.txt

# Create .env
cat > .env <<EOF
DB_HOST=localhost
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
DB_PORT=5432
EOF

# ----------------------------------------------------------------------
# 3. PostgreSQL Configuration
# ----------------------------------------------------------------------
print_info "Step 3: Configuring PostgreSQL..."

# Setup DB/User
sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS ${DB_NAME};
DROP USER IF EXISTS ${DB_USER};
CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';
CREATE DATABASE ${DB_NAME};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
\c ${DB_NAME}
CREATE EXTENSION IF NOT EXISTS postgis;
GRANT ALL ON SCHEMA public TO ${DB_USER};
EOF

# Run Schema (as service user/db user)
print_info "Applying Database Schema..."
PGPASSWORD=${DB_PASS} psql -h localhost -U ${DB_USER} -d ${DB_NAME} -f schema.sql

# Configure pg_hba.conf/postgresql.conf (simplified for robustness)
PG_HBA=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;')
PG_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW config_file;')

# Allow listen *
if ! grep -q "listen_addresses = '*'" "$PG_CONF"; then
    echo "listen_addresses = '*'" >> "$PG_CONF"
fi
# Allow generic password auth (scram-sha-256 or md5 depending on PG version, keeping it simple)
# We won't aggressively sed pg_hba.conf here to avoid breaking existing setups, 
# assuming 'md5' or 'scram-sha-256' default is sufficient for local loopback.
# But for external access (QGIS), add host all all 0.0.0.0/0 scram-sha-256
if ! grep -q "0.0.0.0/0" "$PG_HBA"; then
    echo "host    all             all             0.0.0.0/0               scram-sha-256" >> "$PG_HBA"
fi

systemctl restart postgresql

# ----------------------------------------------------------------------
# 4. Minetest Mapper Compilation
# ----------------------------------------------------------------------
print_info "Step 4: Building Minetest Mapper..."
if [ ! -d "$MAPPER_DIR" ]; then
    sudo -u "$SERVICE_USER" git clone https://github.com/luanti-org/minetestmapper.git "$MAPPER_DIR"
fi

cd "$MAPPER_DIR"
# Clean build
rm -f CMakeCache.txt
cmake . -DENABLE_LEVELDB=1
make -j$(nproc)
# Download colors
if [ ! -f "colors.txt" ]; then
    wget https://raw.githubusercontent.com/luanti-org/minetestmapper/master/colors.txt
fi
chown -R "$SERVICE_USER:$SERVICE_USER" "$MAPPER_DIR"

# ----------------------------------------------------------------------
# 5. Luanti Game Content & Configuration
# ----------------------------------------------------------------------
print_info "Step 5: Configuring Luanti World..."
# Directories
sudo -u "$SERVICE_USER" mkdir -p "$SNAP_WORLD_DIR"
MODS_DIR="$USER_HOME/snap/luanti/common/.minetest/mods"
GAME_DIR="$USER_HOME/snap/luanti/common/.minetest/games"
sudo -u "$SERVICE_USER" mkdir -p "$MODS_DIR"
sudo -u "$SERVICE_USER" mkdir -p "$GAME_DIR"

# Install Minetest Game
if [ ! -d "$GAME_DIR/minetest_game" ]; then
    sudo -u "$SERVICE_USER" git clone https://github.com/minetest/minetest_game.git "$GAME_DIR/minetest_game"
fi

# Install Mod
print_info "Installing Position Tracker Mod..."
sudo -u "$SERVICE_USER" mkdir -p "$MODS_DIR/position_tracker"
sudo -u "$SERVICE_USER" cp -r "$PROJECT_DIR/mod/"* "$MODS_DIR/position_tracker/"

# Config files
world_mt="$SNAP_WORLD_DIR/world.mt"
echo "gameid = minetest_game" > "$world_mt"
echo "backend = sqlite3" >> "$world_mt"
echo "load_mod_position_tracker = true" >> "$world_mt"
chown "$SERVICE_USER:$SERVICE_USER" "$world_mt"

minetest_conf="$USER_HOME/snap/luanti/common/.minetest/minetest.conf"
echo "secure.http_mods = position_tracker" > "$minetest_conf"
chown "$SERVICE_USER:$SERVICE_USER" "$minetest_conf"

# ----------------------------------------------------------------------
# 6. Service Installation
# ----------------------------------------------------------------------
print_info "Step 6: Installing Systemd Services..."

# A. Middleware Service
cat > /etc/systemd/system/luanti-middleware.service <<EOF
[Unit]
Description=Luanti Middleware API
After=network.target postgresql.service

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 $PROJECT_DIR/server.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# B. Map Renderer Service
cat > /etc/systemd/system/luanti-map-render.service <<EOF
[Unit]
Description=Luanti Map Renderer
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=$PROJECT_DIR
ExecStart=/bin/bash $PROJECT_DIR/auto_render_loop.sh $WORLD_NAME
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# C. Map Web Server Service
cat > /etc/systemd/system/luanti-map-server.service <<EOF
[Unit]
Description=Luanti Map Web Server
After=network.target luanti-map-render.service

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=$PROJECT_DIR/map_output
ExecStart=/usr/bin/python3 $PROJECT_DIR/range_server.py 8080
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# D. Game Server Service
cat > /etc/systemd/system/luanti-game.service <<EOF
[Unit]
Description=Luanti Game Server
After=network.target luanti-middleware.service

[Service]
Type=simple
User=${SERVICE_USER}
ExecStart=/snap/bin/luanti --server --world $SNAP_WORLD_DIR --gameid minetest_game --port $GAME_PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable & Start All
systemctl daemon-reload
services="luanti-middleware luanti-game luanti-map-render luanti-map-server"
for s in $services; do
    print_info "Starting $s..."
    systemctl enable "$s"
    systemctl restart "$s"
done

# ----------------------------------------------------------------------
# 7. Final Firewall & Info
# ----------------------------------------------------------------------
print_info "Step 7: Finalizing..."
ufw allow 5000/tcp  # Middleware
ufw allow 8080/tcp  # Map
ufw allow 5432/tcp  # DB
ufw allow ${GAME_PORT}/udp # Game
ufw allow OpenSSH
# ufw enable # Commented out to avoid locking user out if ssh isn't allowed properly, safest to let user do it.

ip_addr=$(hostname -I | awk '{print $1}')
print_info "=== DEPLOYMENT COMPLETE ==="
print_info "Game Server:   $ip_addr:$GAME_PORT"
print_info "Map Server:    http://$ip_addr:8080/map.png"
print_info "Middleware:    http://$ip_addr:5000"
print_info "DB Connection: $ip_addr:5432 ($DB_USER / $DB_PASS)"
print_info ""
print_info "Services have been started automatically."
print_info "To check status: systemctl status luanti-game"
