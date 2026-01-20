#!/bin/bash

# Luanti Position Tracker - Automated MySQL Setup Script
# This script automates the entire server setup process for MySQL

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Determine if running as root
if [ "$EUID" -eq 0 ]; then
    print_warning "Running as root user."
    USER_HOME="/root"
    CURRENT_USER="root"
else
    USER_HOME="$HOME"
    CURRENT_USER=$(whoami)
fi

# Configuration
DB_NAME="luanti_db"
DB_USER="luanti"
DB_PASS="luanti123"
DB_ROOT_PASS="mysql_root_123"
PROJECT_DIR="${USER_HOME}/Position"
PYTHON_VERSION="python3"

print_info "=== Luanti Position Tracker - MySQL Setup ==="
echo ""
print_warning "This script will:"
echo "  1. Update system packages"
echo "  2. Install MySQL, Python, and dependencies"
echo "  3. Configure MySQL database"
echo "  4. Set up Python Flask server"
echo "  5. Install Luanti server and game content"
echo "  6. Configure systemd service"
echo "  7. Set up firewall"
echo ""
read -p "Do you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Setup cancelled."
    exit 0
fi

# Step 1: Update system
print_info "Step 1/9: Updating system packages..."
sudo apt update
sudo apt upgrade -y

# Step 2: Install required packages
print_info "Step 2/9: Installing MySQL, Python, Git, and Snap..."
sudo apt install -y mysql-server python3 python3-pip python3-venv git snapd

# Step 3: Install Luanti via Snap
print_info "Step 3/9: Installing Luanti via Snap..."
sudo snap install luanti

# Step 4: Configure MySQL
print_info "Step 4/9: Configuring MySQL..."

# Set MySQL root password (non-interactive)
print_info "Setting MySQL root password..."
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_ROOT_PASS}';"

# Create database and user
print_info "Creating database and user..."
sudo mysql -u root -p${DB_ROOT_PASS} <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

print_info "MySQL configuration complete!"

# Step 5: Set up Python application
print_info "Step 5/9: Setting up Python application..."

if [ ! -d "$PROJECT_DIR" ]; then
    print_error "Project directory $PROJECT_DIR not found!"
    print_info "Please upload your Position folder to $PROJECT_DIR and run this script again."
    exit 1
fi

cd "$PROJECT_DIR"

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
DB_PORT=3306
EOF

# Import database schema
print_info "Importing database schema..."
mysql -u ${DB_USER} -p${DB_PASS} ${DB_NAME} < schema.sql

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
print_info "Installing position tracker mod..."
cp -r "$PROJECT_DIR/mod" ${USER_HOME}/snap/luanti/common/.minetest/mods/position_tracker

# Configure mod
print_info "Configuring mod..."
sed -i 's|local SERVER_URL = .*|local SERVER_URL = "http://localhost:5000/position"|' ${USER_HOME}/snap/luanti/common/.minetest/mods/position_tracker/init.lua

# Create minetest.conf
echo "secure.http_mods = position_tracker" > ${USER_HOME}/snap/luanti/common/.minetest/minetest.conf

print_info "Luanti setup complete!"

# Step 7: Create systemd service
print_info "Step 7/9: Creating systemd service..."

sudo tee /etc/systemd/system/luanti-tracker.service > /dev/null <<EOF
[Unit]
Description=Luanti Player Position Tracker
After=network.target mysql.service

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$PROJECT_DIR/venv/bin"
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=$PROJECT_DIR/venv/bin/python3 $PROJECT_DIR/server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable luanti-tracker
sudo systemctl start luanti-tracker

print_info "Systemd service created and started!"

# Step 8: Configure firewall
print_info "Step 8/9: Configuring firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 5000/tcp
sudo ufw allow 30000/udp
sudo ufw --force enable

print_info "Firewall configured!"

# Step 9: Create Luanti server start script
print_info "Step 9/9: Creating Luanti server start script..."

cat > ${USER_HOME}/start-luanti-server.sh <<'EOF'
#!/bin/bash
/snap/bin/luanti --server --world ~/snap/luanti/common/.minetest/worlds/myworld --gameid minetest_game --port 30000
EOF

chmod +x ${USER_HOME}/start-luanti-server.sh

print_info "Luanti server start script created!"

# Final status check
echo ""
print_info "=== Setup Complete! ==="
echo ""
print_info "Checking service status..."
sudo systemctl status luanti-tracker --no-pager | head -n 10

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
echo "3. Verify data in MySQL:"
echo "   mysql -u ${DB_USER} -p${DB_PASS} ${DB_NAME} -e \"SELECT * FROM player_traces;\""
echo ""
echo "4. Start Luanti server:"
echo "   ~/start-luanti-server.sh"
echo ""
echo "5. Connect from your Luanti client to:"
echo "   Server IP: $(hostname -I | awk '{print $1}')"
echo "   Port: 30000"
echo ""
print_info "Configuration details saved in: $PROJECT_DIR/.env"
print_info "MySQL User: ${DB_USER}"
print_info "MySQL Password: ${DB_PASS}"
print_info "MySQL Root Password: ${DB_ROOT_PASS}"
echo ""
print_warning "For security, consider changing these passwords in production!"
