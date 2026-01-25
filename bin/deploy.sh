#!/bin/bash
# Copyright (C) 2026 Ephraim BOURIAHI
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Unified deployment script for Luanti/QGIS
# Usage: 
#   ./deploy.sh                    # Interactive setup
#   ./deploy.sh --auto             # Non-interactive deployment (production)
#   ./deploy.sh --update           # Update existing deployment
#   ./deploy.sh --status           # Check deployment status

set -e  # Exit on error

# Load common functions
PROJECT_ROOT=$(dirname $(pwd -P))
echo $PROJECT_ROOT > /root/.proj_root
source $PROJECT_ROOT/src/lib/common.sh

# Default values
AUTO=false
UPDATE=false
STATUS_ONLY=false
CONFIG_FILE=""
WORLD_NAME="myworld"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto) AUTO=true; shift ;;
        --update) UPDATE=true; shift ;;
        --status) STATUS_ONLY=true; shift ;;
        --warranty)
            echo "    There is NO WARRANTY, to the extent permitted by law.  Except when"
            echo "    otherwise stated in writing the copyright holders and/or other parties"
            echo "    provide the program \"AS IS\" without warranty of any kind, either"
            echo "    expressed or implied, including, but not limited to, the implied"
            echo "    warranties of merchantability and fitness for a particular purpose."
            echo "    The entire risk as to the quality and performance of the program is"
            echo "    with you.  Should the program prove defective, you assume the cost of"
            echo "    all necessary servicing, repair or correction."
            exit 0
            ;;
        --license)
            echo "    This program is free software: you can redistribute it and/or modify"
            echo "    it under the terms of the GNU General Public License as published by"
            echo "    the Free Software Foundation, either version 3 of the License, or"
            echo "    (at your option) any later version."
            echo ""
            echo "    You should have received a copy of the GNU General Public License"
            echo "    along with this program.  If not, see <https://www.gnu.org/licenses/>."
            exit 0
            ;;
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --world) WORLD_NAME="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --auto             Non-interactive deployment"
            echo "  --update           Update existing deployment"
            echo "  --status           Check deployment status
  --warranty         Show warranty information
  --license          Show license information" 
            echo "  --config FILE      Load configuration from FILE"
            echo "  --world NAME       Specify world name (default: myworld)"
            echo "  -h, --help         Show this help message"
            echo ""
            exit 0
            ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Load configuration if provided
if [ -n "$CONFIG_FILE" ]; then
    load_env "$CONFIG_FILE"
fi

# Status check mode
if [ "$STATUS_ONLY" = true ]; then
    print_info "=== Deployment Status ==="
    echo ""
    
    print_info "Services:"
    systemctl status luanti-tracker-postgresql --no-pager | head -n 3 || echo "  luanti-tracker-postgresql: Not found"
    systemctl status luanti-map-render --no-pager | head -n 3 || echo "  luanti-map-render: Not found"
    systemctl status luanti-map-server --no-pager | head -n 3 || echo "  luanti-map-server: Not found"
    
    echo ""
    print_info "Active Ports:"
    sudo lsof -i :5000 || echo "  Port 5000: Not in use"
    sudo lsof -i :8080 || echo "  Port 8080: Not in use"
    
    echo ""
    print_info "Database Status:"
    sudo -u postgres psql -c "\l" | grep luanti_db || echo "  Database luanti_db: Not found"
    
    exit 0
fi

# Banner
print_info "================================================================"
print_info "       Luanti/QGIS - Unified Deployment"
print_info "================================================================"
echo "       Luanti/QGIS  Copyright (C) 2026 Ephraim BOURIAHI"
echo "       This program comes with ABSOLUTELY NO WARRANTY; for details use '$0 --warranty'."
echo "       This is free software, and you are welcome to redistribute it"
echo "       under certain conditions; use '$0 --license' for details."
echo ""

# Update mode
if [ "$UPDATE" = true ]; then
    print_info "=== Update Mode ==="
    
    # Pull latest code
    if [ -d "$PROJECT_ROOT/.git" ]; then
        print_info "Pulling latest code..."
        cd "$PROJECT_ROOT"
        git pull
    fi
    
    # Update Python dependencies
    if [ -d "$PROJECT_ROOT/venv" ]; then
        print_info "Updating Python dependencies..."
        source "$PROJECT_ROOT/venv/bin/activate"
        pip install --upgrade -r requirements.txt
    fi
    
    # Update mod
    USER_HOME=$(get_user_home)
    if [ -d "${USER_HOME}/snap/luanti/common/.minetest/mods/position_tracker" ]; then
        print_info "Updating position tracker mod..."
        cp -r "$PROJECT_ROOT/mod/"* "${USER_HOME}/snap/luanti/common/.minetest/mods/position_tracker/"
    fi
    
    # Restart services
    print_info "Restarting services..."
    sudo systemctl restart luanti-tracker-postgresql 2>/dev/null || true
    sudo systemctl restart luanti-map-render 2>/dev/null || true
    sudo systemctl restart luanti-map-server 2>/dev/null || true
    
    print_info "Update complete!"
    exit 0
fi

# Fresh installation
print_info "Starting fresh installation..."
echo ""

if [ "$AUTO" = false ]; then
    print_warning "This will install and configure:"
    echo "  • PostgreSQL database"
    echo "  • Python Flask server"
    echo "  • Luanti game server"
    echo "  • Map rendering system"
    echo "  • All required systemd services"
    echo ""
    confirm "Do you want to continue?" || exit 0
fi

# Step 1: Run PostgreSQL setup
print_info "=== Step 1/4: PostgreSQL Setup ==="
if [ "$AUTO" = true ]; then
    "$PROJECT_ROOT/scripts/setup/postgresql.sh" --auto
else
    "$PROJECT_ROOT/scripts/setup/postgresql.sh"
fi

# Step 2: Migrate backend
print_info "=== Step 2/4: Backend Migration ==="
"$PROJECT_ROOT/scripts/server/migrate-backend.sh" "$WORLD_NAME" --force

# Step 3: Setup mapper
print_info "=== Step 3/4: Map Renderer Setup ==="
"$PROJECT_ROOT/scripts/setup/mapper.sh" "$WORLD_NAME"

# Step 4: Setup map hosting
print_info "=== Step 4/4: Map Hosting Setup ==="
"$PROJECT_ROOT/scripts/map/setup-hosting.sh" "$WORLD_NAME"

# Final summary
echo ""
print_info "================================================================"
print_info "                    Deployment Complete!"
print_info "================================================================"
echo ""
print_info "Services Status:"
sudo systemctl status luanti-tracker-postgresql --no-pager | head -n 3
echo ""
print_info "Next Steps:"
echo "  1. Start Luanti server:"
echo "     ~/sls $WORLD_NAME 30000"
echo ""
echo "  2. Connect from Luanti client:"
echo "     Server: $(hostname -I | awk '{print $1}')"
echo "     Port: 30000"
echo ""
echo "  3. View map:"
echo "     http://$(hostname -I | awk '{print $1}'):8080/map.png"
echo ""
print_info "Configuration saved in: $PROJECT_ROOT/.env"
echo ""
print_info "To check status: $0 --status"
print_info "To update deployment: $0 --update"
echo ""
print_warning "Remember to change default passwords in production!"
