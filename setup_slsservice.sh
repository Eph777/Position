#!/bin/bash

# Configuration
WORLD="$1"
PORT="$2"

if [ -z "$WORLD" ] || [ -z "$PORT" ]; then
    echo "Usage: ./setup_slsservice.sh <world_name> <port>"
    exit 1
fi

SERVICE_NAME="luanti-server@${WORLD}"
SLS_SCRIPT="${HOME}/sls"
SERVICE_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo ~$SERVICE_USER)

# Verify sls script exists
if [ ! -f "$SLS_SCRIPT" ]; then
    echo "Error: $SLS_SCRIPT not found. Please ensure sls script is in your home directory."
    exit 1
fi

echo "Creating systemd service: $SERVICE_NAME..."

# Create systemd service file
# We use a template service style or specific name
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Luanti Game Server - World: $WORLD (Port: $PORT)
# Network dependency removed for robustness, but usually fine here
# After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
# Run sls.sh in non-interactive service mode
ExecStart=/bin/bash ${SLS_SCRIPT} "${WORLD}" "${PORT}" --service
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "Enabling and starting service..."
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}
sudo systemctl start ${SERVICE_NAME}

echo "Service $SERVICE_NAME started!"
echo "Check status with: sudo systemctl status $SERVICE_NAME"