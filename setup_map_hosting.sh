#!/bin/bash

# Configuration
USER_HOME=$(eval echo ~$SUDO_USER)
if [ -z "$SUDO_USER" ]; then
    USER_HOME="$HOME"
fi
PROJECT_DIR="$USER_HOME/luanti-qgis"
MAP_OUTPUT_DIR="$PROJECT_DIR/map_output"
RENDER_SCRIPT="$PROJECT_DIR/render_map.sh"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}[INFO] Setting up real-time map services...${NC}"

# 1. Start setup
echo "Configuring map services..."

# 2. Create the Render Loop Script
cat > "$PROJECT_DIR/auto_render_loop.sh" <<EOF
#!/bin/bash
while true; do
    echo "Starting render..."
    $RENDER_SCRIPT
    echo "Sleeping 15s..."
    sleep 15
done
EOF
chmod +x "$PROJECT_DIR/auto_render_loop.sh"

# 3. Create Map Renderer Service
echo "Creating luanti-map-render.service..."
SERVICE_USER=${SUDO_USER:-$(whoami)}
sudo tee /etc/systemd/system/luanti-map-render.service > /dev/null <<EOF
[Unit]
Description=Luanti Map Auto-Renderer (15s Interval)
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=$PROJECT_DIR
ExecStart=/bin/bash $PROJECT_DIR/auto_render_loop.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 4. Create HTTP Map Server Service
echo "Creating luanti-map-server.service..."
sudo tee /etc/systemd/system/luanti-map-server.service > /dev/null <<EOF
[Unit]
Description=Luanti Map HTTP Server (Port 8080)
After=network.target

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
