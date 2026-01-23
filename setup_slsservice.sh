#!/bin/bash

WORLD="$1"

sudo tee /etc/systemd/system/luanti-server.service > /dev/null <<EOF
[Unit]
Description=Luanti Server (Port 30000 default)

[Service]
Type=simple
User=${SERVICE_USER}
ExecStart=/snap/bin/luanti --server --world ~/snap/luanti/common/.minetest/worlds/$WORLD --gameid minetest_game --port 30000
Restart=always

[Install]
WantedBy=multi-user.target
EOF


sudo systemctl daemon-reload
sudo systemctl enable luanti-server
sudo systemctl start luanti-server
sudo systemctl enable luanti-server
sudo systemctl start luanti-server