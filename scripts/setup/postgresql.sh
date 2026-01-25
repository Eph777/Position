#!/bin/bash
# PostgreSQL setup for Luanti Position Tracker
# Usage: ./postgresql.sh [--auto]

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../src/lib/common.sh"

# Parse arguments
AUTO=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto) AUTO=true; shift ;;
        *) shift ;;
    esac
done

# Configuration
DB_NAME="luanti_db"
DB_USER="luanti"
DB_PASS="postgres123"
PYTHON_VERSION="python3"

USER_HOME=$(get_user_home)
CURRENT_USER=$(get_current_user)
PROJECT_ROOT=$(get_project_root)

print_info "=== Luanti Position Tracker - PostgreSQL Setup ==="
echo ""
print_warning "This script will:"
echo "  1. Update system packages"
echo "  2. Install PostgreSQL, Python, and dependencies"
echo "  3. Configure PostgreSQL database"
echo "  4. Set up Python Flask server"
echo "  5. Install Luanti server and game content"
echo "  6. Configure systemd service"
echo "  7. Set up firewall"
echo ""

if [ "$AUTO" = false ]; then
    confirm "Do you want to continue?" || exit 0
fi

# Step 1: Update system
print_info "Step 1/9: Updating system packages..."
sudo apt update
sudo apt upgrade -y

# Step 2: Install required packages
print_info "Step 2/9: Installing PostgreSQL, PostGIS, Python, Git, and Snap..."
sudo apt install -y postgresql postgresql-contrib postgis python3 python3-pip python3-venv git snapd lsof

# Step 3: Install Luanti via Snap
print_info "Step 3/9: Installing Luanti via Snap..."
sudo snap install luanti

# Step 4: Configure PostgreSQL
print_info "Step 4/9: Configuring PostgreSQL..."

# Configure authentication method
print_info "Configuring PostgreSQL authentication..."
PG_HBA_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;')
PG_CONF_FILE=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW config_file;')
print_info "PostgreSQL pg_hba.conf file: $PG_HBA_CONF"
print_info "PostgreSQL postgresql.conf file: $PG_CONF_FILE"

# Backup original pg_hba.conf
sudo cp "$PG_HBA_CONF" "${PG_HBA_CONF}.backup"

# Update pg_hba.conf to use scram-sha-256 authentication for local connections
sudo sed -i 's/^local\s\+all\s\+all\s\+\(peer\|md5\).*/local   all             all                                     scram-sha-256/' "$PG_HBA_CONF"

# Allow remote connections
if ! grep -q "host    all             all             0.0.0.0/0               scram-sha-256" "$PG_HBA_CONF"; then
    echo "host    all             all             0.0.0.0/0               scram-sha-256" | sudo tee -a "$PG_HBA_CONF"
fi

# Configure postgresql.conf to listen on all addresses
print_info "Configuring postgresql.conf to listen on all addresses..."
sudo cp "$PG_CONF_FILE" "${PG_CONF_FILE}.backup"
if grep -q "^listen_addresses" "$PG_CONF_FILE"; then
    sudo sed -i "s/^listen_addresses = .*/listen_addresses = '*'/" "$PG_CONF_FILE"
else
    echo "listen_addresses = '*'" | sudo tee -a "$PG_CONF_FILE"
fi

# Reload PostgreSQL to apply changes
sudo systemctl restart postgresql
sudo systemctl reload postgresql

print_info "PostgreSQL authentication configured!"

# Create database and user
print_info "Creating database and user..."

# Stop service to ensure no active DB connections prevent the drop
sudo systemctl stop luanti-tracker-postgresql 2>/dev/null || true

sudo -u postgres psql <<EOF
-- Ensure password is hashed with SCRAM-SHA-256 to match pg_hba.conf
SET password_encryption = 'scram-sha-256';

-- Force kill all active connections to the database to allow dropping
SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.datname = '${DB_NAME}'
  AND pid <> pg_backend_pid();

DROP DATABASE IF EXISTS ${DB_NAME};
DROP USER IF EXISTS ${DB_USER};
CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';
CREATE DATABASE ${DB_NAME};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
\c ${DB_NAME}
CREATE EXTENSION IF NOT EXISTS postgis;
GRANT ALL ON SCHEMA public TO ${DB_USER};

-- Fix permissions for tables possibly created by root in previous runs
ALTER TABLE IF EXISTS player_traces OWNER TO ${DB_USER};
ALTER TABLE IF EXISTS player_traces_archive OWNER TO ${DB_USER};
ALTER VIEW IF EXISTS view_live_positions OWNER TO ${DB_USER};
ALTER SEQUENCE IF EXISTS player_traces_id_seq OWNER TO ${DB_USER};
ALTER SEQUENCE IF EXISTS player_traces_archive_id_seq OWNER TO ${DB_USER};
EOF

print_info "PostgreSQL configuration complete!"

# Step 5: Set up Python application
print_info "Step 5/9: Setting up Python application..."

cd "$PROJECT_ROOT"

# Create virtual environment
print_info "Creating Python virtual environment..."
$PYTHON_VERSION -m venv venv
source venv/bin/activate

# Install dependencies
print_info "Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Create .env file
print_info "Creating .env configuration file..."
cat > .env <<EOF
DB_HOST=localhost
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
DB_PORT=5432
EOF

# Import database schema
print_info "Importing database schema..."
PGPASSWORD=${DB_PASS} psql -U ${DB_USER} -d ${DB_NAME} -f schema.sql

print_info "Python application setup complete!"

# Step 6: Install Luanti game content
print_info "Step 6/9: Installing Luanti game content..."

# Create directories
mkdir -p ${USER_HOME}/snap/luanti/common/.minetest/games
mkdir -p ${USER_HOME}/snap/luanti/common/.minetest/worlds/myworld
mkdir -p ${USER_HOME}/snap/luanti/common/.minetest/mods

# Clone Minetest Game
if [ ! -d ${USER_HOME}/snap/luanti/common/.minetest/games/minetest_game ]; then
    print_info "Downloading Minetest Game..."
    git clone https://github.com/minetest/minetest_game.git ${USER_HOME}/snap/luanti/common/.minetest/games/minetest_game
else
    print_info "Minetest Game already exists, skipping..."
fi

# Create world configuration
print_info "Creating world configuration..."
echo "gameid = minetest_game" > ${USER_HOME}/snap/luanti/common/.minetest/worlds/myworld/world.mt
echo "backend = sqlite3" >> ${USER_HOME}/snap/luanti/common/.minetest/worlds/myworld/world.mt
echo "load_mod_position_tracker = true" >> ${USER_HOME}/snap/luanti/common/.minetest/worlds/myworld/world.mt

# Copy mod
print_info "Installing or updating position tracker mod..."
mkdir -p ${USER_HOME}/snap/luanti/common/.minetest/mods/position_tracker
cp -r "$PROJECT_ROOT/mod/"* ${USER_HOME}/snap/luanti/common/.minetest/mods/position_tracker/

# Configure mod
print_info "Configuring mod..."
sed -i 's|local SERVER_URL = .*|local SERVER_URL = "http://localhost:5000/position"|' ${USER_HOME}/snap/luanti/common/.minetest/mods/position_tracker/init.lua

# Create minetest.conf
echo "secure.http_mods = position_tracker" > ${USER_HOME}/snap/luanti/common/.minetest/minetest.conf

print_info "Luanti setup complete!"

# Step 7: Check for port conflicts and create systemd service
print_info "Step 7/9: Checking for port conflicts..."

# Check if port 5000 is in use
if ! check_port 5000; then
    # Check if it's the MySQL tracker service
    if systemctl is-active --quiet luanti-tracker; then
        print_warning "Found MySQL tracker service running on port 5000."
        if [ "$AUTO" = true ]; then
            print_info "Auto mode: Stopping MySQL tracker service..."
            sudo systemctl stop luanti-tracker
            sudo systemctl disable luanti-tracker
        else
            if confirm "Do you want to stop the MySQL service and continue with PostgreSQL?"; then
                print_info "Stopping MySQL tracker service..."
                sudo systemctl stop luanti-tracker
                sudo systemctl disable luanti-tracker
                print_info "MySQL service stopped."
            else
                print_error "Cannot proceed while port 5000 is in use."
                exit 1
            fi
        fi
    else
        # Unknown process on port 5000
        if [ "$AUTO" = true ]; then
            check_port 5000 --kill --force || exit 1
        else
            check_port 5000 --kill || exit 1
        fi
    fi
fi

print_info "Creating systemd service..."

sudo tee /etc/systemd/system/luanti-tracker-postgresql.service > /dev/null <<EOF
[Unit]
Description=Luanti Player Position Tracker (PostgreSQL)
After=network.target postgresql.service

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=$PROJECT_ROOT
Environment="PATH=$PROJECT_ROOT/venv/bin"
EnvironmentFile=$PROJECT_ROOT/.env
ExecStart=$PROJECT_ROOT/venv/bin/python3 $PROJECT_ROOT/src/server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable luanti-tracker-postgresql
sudo systemctl start luanti-tracker-postgresql

print_info "Systemd service created and started!"

# Step 8: Configure firewall
print_info "Step 8/9: Configuring firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 5000/tcp
sudo ufw allow 5432/tcp
sudo ufw allow 30000/udp
sudo ufw allow 30001/udp
sudo ufw allow 30002/udp
sudo ufw allow 30003/udp
sudo ufw allow 30004/udp
sudo ufw allow 30005/udp
sudo ufw allow 30006/udp
sudo ufw allow 30007/udp
sudo ufw allow 30008/udp
sudo ufw allow 30009/udp
sudo ufw --force enable

print_info "Firewall configured!"

# Step 9: Create Luanti server start script
print_info "Step 9/9: Creating Luanti server start script..."
cp "$PROJECT_ROOT/scripts/server/start-luanti.sh" "${USER_HOME}/sls"
chmod +x "${USER_HOME}/sls"

print_info "Luanti server start script created!"

# Final status check
echo ""
print_info "=== Setup Complete! ==="
echo ""
print_info "Checking service status..."
sudo systemctl status luanti-tracker-postgresql --no-pager | head -n 10

echo ""
print_info "=== Next Steps ==="
echo ""
echo "1. Test the Flask server:"
echo "   curl http://localhost:5000/"
echo ""
echo "2. Test position logging:"
echo "   curl -X POST http://localhost:5000/position \\"
echo "     -H \"Content-Type: application/json\" \\"
echo "     -d '{\"player\":\"test\",\"pos\":{\"x\":1,\"y\":2,\"z\":3}}'"
echo ""
echo "3. Verify data in PostgreSQL:"
echo "   PGPASSWORD=${DB_PASS} psql -U ${DB_USER} -d ${DB_NAME} -c \"SELECT * FROM player_traces;\""
echo ""
echo "4. Start Luanti server:"
echo "   ~/sls myworld 30000"
echo ""
echo "5. Connect from your Luanti client to:"
echo "   Server IP: $(hostname -I | awk '{print $1}')"
echo "   Port: 30000"
echo ""
print_info "Configuration details saved in: $PROJECT_ROOT/.env"
print_info "PostgreSQL User: ${DB_USER}"
print_info "PostgreSQL Password: ${DB_PASS}"
echo ""
print_warning "For security, consider changing these passwords in production!"
