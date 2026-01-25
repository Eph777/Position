#!/bin/bash
# Setup map hosting services (renderer + HTTP server)
# Usage: ./setup-hosting.sh <world_name>

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

WORLD="$1"

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 <world_name>"
    exit 1
fi

# Configuration
SERVICE_USER=$(get_current_user)
USER_HOME=$(get_user_home)
PROJECT_ROOT=$(get_project_root)
MAP_OUTPUT_DIR="$PROJECT_ROOT/map_output"

# Ensure directories exist and have correct permissions
if [ ! -d "$PROJECT_ROOT" ]; then
    print_info "Creating project directory: $PROJECT_ROOT"
    mkdir -p "$PROJECT_ROOT"
fi
mkdir -p "$MAP_OUTPUT_DIR"

# Ensure the service user owns the directory
print_info "Setting permissions for $SERVICE_USER on $PROJECT_ROOT..."
sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$PROJECT_ROOT"

print_info "Setting up real-time map services..."

# Create Map Renderer Service
print_info "Creating luanti-map-render.service..."
sudo tee /etc/systemd/system/luanti-map-render.service > /dev/null <<EOF
[Unit]
Description=Luanti Map Auto-Renderer (15s Interval)

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=$PROJECT_ROOT
ExecStart=/bin/bash $PROJECT_ROOT/scripts/map/auto-render.sh $WORLD
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Create HTTP Map Server Service
print_info "Creating luanti-map-server.service..."
sudo tee /etc/systemd/system/luanti-map-server.service > /dev/null <<EOF
[Unit]
Description=Luanti Map HTTP Server (Port 8080)

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=$MAP_OUTPUT_DIR
ExecStart=/usr/bin/python3 $PROJECT_ROOT/src/range_server.py 8080
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Open Firewall Port 8080
print_info "Opening port 8080..."
sudo ufw allow 8080/tcp

# Start Services
print_info "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable luanti-map-render
sudo systemctl start luanti-map-render
sudo systemctl enable luanti-map-server
sudo systemctl start luanti-map-server

print_info "Map services started successfully!"
echo "Map is now hosted at: http://$(hostname -I | awk '{print $1}'):8080/map.png"
