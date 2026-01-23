#!/bin/bash

WORLD="$1"

# Configuration
SERVICE_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo ~$SERVICE_USER)
PROJECT_DIR="$USER_HOME/luanti-qgis"
MAP_OUTPUT_DIR="$PROJECT_DIR/map_output"
RENDER_SCRIPT="$PROJECT_DIR/render_map.sh"

# Ensure directories exist and have correct permissions (fixes 200/CHDIR)
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Creating project directory: $PROJECT_DIR"
    mkdir -p "$PROJECT_DIR"
fi
mkdir -p "$MAP_OUTPUT_DIR"

# Ensure the service user owns the directory so it can CHDIR into it
echo "Setting permissions for $SERVICE_USER on $PROJECT_DIR..."
chown -R "$SERVICE_USER:$SERVICE_USER" "$PROJECT_DIR"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}[INFO] Setting up real-time map services...${NC}"

# 1. Start setup
echo "Configuring map services..."

# 3. Create Map Renderer Service
echo "Creating luanti-map-render.service..."
SERVICE_USER=${SUDO_USER:-$(whoami)}
sudo tee /etc/systemd/system/luanti-map-render.service > /dev/null <<EOF
[Unit]
Description=Luanti Map Auto-Renderer (15s Interval)

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=$PROJECT_DIR
ExecStart=/bin/bash $PROJECT_DIR/auto_render_loop.sh $WORLD
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 4. Create HTTP Map Server Service
echo "Creating luanti-map-server.service..."
sudo tee /etc/systemd/system/luanti-map-server.service > /dev/null <<EOF
[Unit]
Description=Luanti Map HTTP Server (Port 8080)

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=$MAP_OUTPUT_DIR
# Use our custom Python script that supports Range requests (No external dependencies needed!)
ExecStart=/usr/bin/python3 $PROJECT_DIR/range_server.py 8080
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 4. Open Firewall Port 8080
echo "Opening port 8080..."
sudo ufw allow 8080/tcp

# 5. Start Services
echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable luanti-map-render
sudo systemctl start luanti-map-render
sudo systemctl enable luanti-map-server
sudo systemctl start luanti-map-server

echo -e "${GREEN}[SUCCESS] Map services started!${NC}"
echo "Map is now hosted at: http://$(hostname -I | awk '{print $1}'):8080/map.png"
