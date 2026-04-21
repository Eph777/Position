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

# Start Luanti game server
# Usage: ./start-luanti.sh <world_name> [port] [--service] [--map MAP_PORT]
#   Without --service: Runs in foreground
#   With --service: Creates and starts systemd service
#   With --map PORT: Also starts map rendering and hosting services on specified port

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

# Defaults
WORLD=""
PORT=30000
IS_SERVICE=false
MAP_PORT=""
INTERACTIVE=false
GAME_ID="minetest_game"

# Parse Positional Arguments
# Check if current First argument is existent and NOT a flag
if [[ -n "$1" && "$1" != -* ]]; then
    WORLD="$1"
    shift
fi

# Check if current First argument (was second) is a number (Port)
if [[ -n "$1" && "$1" =~ ^[0-9]+$ ]]; then
    PORT="$1"
    shift
fi

# Parse Flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            echo "Usage: $0 [-i|--interactive] <world_name> [port] [--service] [--map MAP_PORT]"
            echo "  -i, --interactive        Run in interactive mode"
            echo "  <world_name>             Name of the world folder (Required unless interactive)"
            echo "  [port]                   UDP Port for game server (Default: 30000)"
            echo "  --service                Create and start as systemd service"
            echo "  --map PORT               Also start map hosting on TCP PORT"
            exit 0
            ;;
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        --service)
            IS_SERVICE=true
            shift
            ;;
        --game)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: --game requires a game ID argument"
                exit 1
            fi
            GAME_ID="$2"
            shift 2
            ;;
        --map)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: --map requires a port number argument"
                exit 1
            fi
            MAP_PORT="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument '$1'"
            exit 1
            ;;
    esac
done

if [[ "$INTERACTIVE" == true ]]; then
    # interactive personalization
    echo "--- Server Configuration ---"


    GAMES_DIR="/root/snap/luanti/common/.minetest/games"
    existing_games=()
    if [ -d "$GAMES_DIR" ]; then
        for g in "$GAMES_DIR"/*; do
            if [ -d "$g" ]; then
                existing_games+=("$(basename "$g")")
            fi
        done
    fi
    
    


    while true; do
        echo "[0] download a new game"
        for i in "${!existing_games[@]}"; do
            echo "[$((i + 1))] ${existing_games[$i]}"
        done

        read -p "game choice : " -r G_CHOICE

        if [[ "$G_CHOICE" =~ ^[0-9]+$ ]]; then
            if [[ "$G_CHOICE" -eq 0 ]]; then
                # download a new game
                read -p "game download link : " -r G_LINK
                if [[ -n "$G_LINK" ]]; then
                    if install_game_from_zip "$G_LINK"; then
                        existing_games=()
                        if [ -d "$GAMES_DIR" ]; then
                            for g in "$GAMES_DIR"/*; do
                                if [ -d "$g" ]; then
                                    existing_games+=("$(basename "$g")")
                                fi
                            done
                        fi
                    fi
                else
                    print_error "Link cannot be empty."
                fi
            else

                G_INDEX=$((G_CHOICE - 1))
                if [[ "$G_INDEX" -lt 0 ]] || [[ "$G_INDEX" -ge "${#existing_games[@]}" ]]; then
                    print_error "Invalid selection."
                else
                    GAME_ID="${existing_games[$G_INDEX]}"
                    break
                fi
            fi
        else
            print_error "Invalid choice: please enter a number."
        fi
    done

    
    

    WORLDS_DIR="/root/snap/luanti/common/.minetest/worlds"
    existing_worlds=()
    if [ -d "$WORLDS_DIR" ]; then
        for w in "$WORLDS_DIR"/*; do
            if [ -d "$w" ]; then
                existing_worlds+=("$(basename "$w")")
            fi
        done
    fi

    echo "[0] create a new world"
    for i in "${!existing_worlds[@]}"; do
        echo "[$((i + 1))] ${existing_worlds[$i]}"
    done
    
    while true; do
        read -p "world choice : " -r W_CHOICE
        if [[ "$W_CHOICE" =~ ^[0-9]+$ ]]; then
            if [[ "$W_CHOICE" -eq 0 ]]; then
                read -p "new world name : " -r NEW_WORLD
                if [[ -n "$NEW_WORLD" ]]; then
                    WORLD="$NEW_WORLD"
                    break
                else
                    print_error "Name cannot be empty."
                fi
            else
                W_INDEX=$((W_CHOICE - 1))
                if [[ "$W_INDEX" -lt 0 ]] || [[ "$W_INDEX" -ge "${#existing_worlds[@]}" ]]; then
                    print_error "Invalid selection."
                else
                    WORLD="${existing_worlds[$W_INDEX]}"
                    break
                fi
            fi
        else
            print_error "Invalid choice: please enter a number."
        fi
    done

    read -p "game server port (default: $PORT) : " -r
    if [[ -n "$REPLY" ]]; then PORT="$REPLY"; fi

    read -p "map hosting port (default: ${MAP_PORT:-none}) : " -r
    if [[ -n "$REPLY" ]]; then MAP_PORT="$REPLY"; fi

    curr_svc="n"
    if [ "$IS_SERVICE" = true ]; then curr_svc="y"; fi
    read -p "run as systemd service? (y/n) (default: $curr_svc) : " -n 1 -r
    echo
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        IS_SERVICE=true
    elif [[ "$REPLY" =~ ^[Nn]$ ]]; then
        IS_SERVICE=false
    fi
    echo
fi

sudo ufw allow "$PORT/udp"

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 [-i|--interactive] <world_name> [port] [--service] [--map MAP_PORT]"
    echo "  With -i, --interactive:  Prompts for configuration interactively"
    echo "  Without --service: Runs in foreground"
    echo "  With --service: Creates and starts systemd service"
    echo "  With --map PORT: Also starts Mapserver hosting on specified port"
    exit 1
fi

USER_HOME=$(get_user_home)
CURRENT_USER=$(get_current_user)
WORLD_PATH="$USER_HOME/snap/luanti/common/.minetest/worlds/$WORLD"
WORLD_MT="$WORLD_PATH/world.mt"

# Create world directory if it doesn't exist
if [ ! -d "$WORLD_PATH" ]; then
    print_info "Creating world directory: $WORLD"
    mkdir -p "$WORLD_PATH"
fi

# Create worldmods directory if it doesn't exist
MODS_DIR="$USER_HOME/snap/luanti/common/.minetest/mods"
if [ ! -d "$MODS_DIR" ]; then
    mkdir -p "$MODS_DIR"
fi

# Create mod_archives directory if it doesn't exist
MOD_ARCHIVES_DIR="$USER_HOME/snap/luanti/common/.minetest/mod_archives"
if [ ! -d "$MOD_ARCHIVES_DIR" ]; then
    mkdir -p "$MOD_ARCHIVES_DIR"
fi

# Create or verify world.mt file
if [ ! -f "$WORLD_MT" ]; then
    print_info "Creating world.mt configuration file..."
    cat > "$WORLD_MT" <<EOF
gameid = ${GAME_ID}
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
EOF
    print_info "World configuration created."
else
    print_info "World $WORLD exists."
fi

# Interactive Mod Installation
if [[ "$INTERACTIVE" == true ]]; then
    echo
    echo "--- Mod Installation ---"
    while true; do
        read -p "Would you like to install a mod? (y/n) ==> " -n 1 -r
        echo
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            break
        fi
        
        local_zips=()
        for f in "$MOD_ARCHIVES_DIR"/*.zip; do
            [ -e "$f" ] && local_zips+=("$f")
        done
        
        installed_mods=()
        for d in "$MODS_DIR"/*; do
            [ -d "$d" ] && installed_mods+=("$(basename "$d")")
        done
        
        echo "[0] add mod by URL"
        zip_count=${#local_zips[@]}
        for i in "${!local_zips[@]}"; do
            echo "[$((i + 1))] [ZIP] $(basename "${local_zips[$i]}")"
        done
        for i in "${!installed_mods[@]}"; do
            mod_name="${installed_mods[$i]}"
            status_tag="[INSTALLED]"
            if grep -q "^load_mod_${mod_name}[ =]*true" "$WORLD_MT" 2>/dev/null; then
                status_tag="[INSTALLED] [ENABLED]"
            fi
            echo "[$((i + 1 + zip_count))] $status_tag $mod_name"
        done
        
        read -p "your choice : " -r CHOICE
        
        if [[ ! "$CHOICE" =~ ^[0-9]+$ ]]; then
            print_error "Invalid choice: please enter a number."
            continue
        fi

        total_choices=$((zip_count + ${#installed_mods[@]}))
        if [[ "$CHOICE" -gt "$total_choices" ]]; then
            print_error "Invalid selection."
            continue
        fi

        TEMP_ZIP=$(mktemp)
        DOWNLOAD_SUCCESS=false
        IS_GIT=false

        if [[ "$CHOICE" -eq 0 ]]; then
            echo "Please provide the direct .zip download link or .git repository URL of the mod:"
            read -p "URL ==> " -r MOD_INPUT
            
            if [[ -z "$MOD_INPUT" ]]; then
                print_error "No URL provided."
                rm -f "$TEMP_ZIP"
                continue
            fi
            
            if [[ "$MOD_INPUT" == *.git ]] || [[ "$MOD_INPUT" == git@* ]]; then
                print_info "Cloning mod repository..."
                MOD_EXTRACT_DIR=$(mktemp -d)
                if git clone -q "$MOD_INPUT" "$MOD_EXTRACT_DIR/repo"; then
                    DOWNLOAD_SUCCESS=true
                    IS_GIT=true
                else
                    print_error "Failed to clone the mod repository."
                    rm -rf "$MOD_EXTRACT_DIR"
                fi
            else
                print_info "Downloading mod from URL..."
                if curl -sL "$MOD_INPUT" -o "$TEMP_ZIP"; then
                    DOWNLOAD_SUCCESS=true
                else
                    print_error "Failed to download the mod."
                fi
            fi
        elif [[ "$CHOICE" -le "$zip_count" ]]; then
            FILE_INDEX=$((CHOICE - 1))
            LOCAL_FILE="${local_zips[$FILE_INDEX]}"
            print_info "Using local mod archive: $(basename "$LOCAL_FILE")"
            cp "$LOCAL_FILE" "$TEMP_ZIP"
            DOWNLOAD_SUCCESS=true
        else
            MOD_INDEX=$((CHOICE - 1 - zip_count))
            SELECTED_MOD_DIR="${installed_mods[$MOD_INDEX]}"
            
            if [ -f "$MODS_DIR/$SELECTED_MOD_DIR/mod.conf" ] && grep -q -E "^[[:space:]]*name[[:space:]]*=" "$MODS_DIR/$SELECTED_MOD_DIR/mod.conf"; then
                SELECTED_MOD=$(grep -E "^[[:space:]]*name[[:space:]]*=" "$MODS_DIR/$SELECTED_MOD_DIR/mod.conf" | cut -d'=' -f2 | tr -d "[:space:]\"'" | head -n 1)
            else
                SELECTED_MOD="$SELECTED_MOD_DIR"
            fi
            
            if grep -q "^load_mod_${SELECTED_MOD}[ =]" "$WORLD_MT"; then
                read -p "Mod '$SELECTED_MOD' is already configured in world.mt. Overwrite and activate? (y/n) " -n 1 -r
                echo
                if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
                    rm -f "$TEMP_ZIP"
                    echo
                    continue
                fi
                grep -v "^load_mod_${SELECTED_MOD}[ =]" "$WORLD_MT" > "${WORLD_MT}.tmp" && mv "${WORLD_MT}.tmp" "$WORLD_MT"
            fi
            
            echo "load_mod_${SELECTED_MOD} = true" >> "$WORLD_MT"
            print_info "Activated installed mod '$SELECTED_MOD' in world.mt"
            
            if [ -f "$MODS_DIR/$SELECTED_MOD_DIR/mod.conf" ]; then
                DEPENDS=$(grep -i -E '^[ \t]*depends[ \t]*=' "$MODS_DIR/$SELECTED_MOD_DIR/mod.conf" | cut -d'=' -f2- | xargs)
                if [ -n "$DEPENDS" ]; then
                    print_warning "This mod depends on other mods: $DEPENDS"
                    print_warning "Please ensure they are installed before starting the server."
                fi
            fi
            
            rm -f "$TEMP_ZIP"
            echo
            continue
        fi

        if [[ "$DOWNLOAD_SUCCESS" == true ]]; then
            if [[ "$IS_GIT" != true ]]; then
                MOD_EXTRACT_DIR=$(mktemp -d)
                if ! unzip -q "$TEMP_ZIP" -d "$MOD_EXTRACT_DIR"; then
                    print_error "Failed to extract the mod zip."
                    rm -rf "$MOD_EXTRACT_DIR"
                    rm -f "$TEMP_ZIP"
                    echo
                    continue
                fi
            fi
            
            # Find the actual mod directory inside (often nested)
            if [[ "$IS_GIT" == true ]]; then
                MOD_ROOT_DIR="$MOD_EXTRACT_DIR/repo"
            else
                MOD_ROOT_DIR=$(find "$MOD_EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
            fi
            
            if [[ -n "$MOD_ROOT_DIR" ]]; then
                # Search for mod.conf to get the real name
                if [ -f "$MOD_ROOT_DIR/mod.conf" ] && grep -q -E "^[[:space:]]*name[[:space:]]*=" "$MOD_ROOT_DIR/mod.conf"; then
                    CLEAN_MOD_NAME=$(grep -E "^[[:space:]]*name[[:space:]]*=" "$MOD_ROOT_DIR/mod.conf" | cut -d'=' -f2 | tr -d "[:space:]\"'" | head -n 1)
                else
                    if [[ "$IS_GIT" == true ]]; then
                        rm -rf "$MOD_ROOT_DIR/.git"
                        MOD_NAME=$(basename -s .git "$MOD_INPUT")
                    else
                        MOD_NAME=$(basename "$MOD_ROOT_DIR")
                    fi
                    
                    # Remove trailing -master or version tags commonly found in downloaded zips
                    CLEAN_MOD_NAME=$(echo "$MOD_NAME" | sed -E 's/-[0-9a-fA-F]+$|-master$//')
                fi
                
                TARGET_MOD_DIR="$MODS_DIR/$CLEAN_MOD_NAME"
                
                if [ -d "$TARGET_MOD_DIR" ]; then
                    read -p "Mod '$CLEAN_MOD_NAME' files already exist. Overwrite? (y/n) " -n 1 -r
                    echo
                    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                        print_warning "Overwriting..."
                        rm -rf "$TARGET_MOD_DIR"
                        mv "$MOD_ROOT_DIR" "$TARGET_MOD_DIR"
                        print_info "Installed mod to $TARGET_MOD_DIR"
                    else
                        print_info "Skipped overwriting mod files."
                    fi
                else
                    mv "$MOD_ROOT_DIR" "$TARGET_MOD_DIR"
                    print_info "Installed mod to $TARGET_MOD_DIR"
                fi
                
                # Ensure mod is enabled in world.mt
                if grep -q "^load_mod_${CLEAN_MOD_NAME}[ =]" "$WORLD_MT"; then
                    read -p "Mod '$CLEAN_MOD_NAME' is already configured in world.mt. Overwrite and activate? (y/n) " -n 1 -r
                    echo
                    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                        grep -v "^load_mod_${CLEAN_MOD_NAME}[ =]" "$WORLD_MT" > "${WORLD_MT}.tmp" && mv "${WORLD_MT}.tmp" "$WORLD_MT"
                        echo "load_mod_${CLEAN_MOD_NAME} = true" >> "$WORLD_MT"
                        print_info "Enabled mod '$CLEAN_MOD_NAME' in world.mt"
                    else
                        print_info "Skipped enabling mod in world.mt."
                    fi
                else
                    echo "load_mod_${CLEAN_MOD_NAME} = true" >> "$WORLD_MT"
                    print_info "Enabled mod '$CLEAN_MOD_NAME' in world.mt"
                fi
                
                if [ -f "$TARGET_MOD_DIR/mod.conf" ]; then
                    DEPENDS=$(grep -i -E '^[ \t]*depends[ \t]*=' "$TARGET_MOD_DIR/mod.conf" | cut -d'=' -f2- | xargs)
                    if [ -n "$DEPENDS" ]; then
                        print_warning "This recently installed mod depends on other mods: $DEPENDS"
                        print_warning "Please ensure they are installed before starting the server."
                    fi
                fi
            else
                print_error "Could not find a valid mod directory."
            fi
            
            rm -rf "$MOD_EXTRACT_DIR"
        fi
        rm -f "$TEMP_ZIP"
        echo
    done
fi

# Check port availability
if [ "$IS_SERVICE" = true ]; then
    check_port "$PORT" --kill --force || exit 1
else
    check_port "$PORT" --kill || exit 1
fi

# Setup map services if --map is specified
if [ -n "$MAP_PORT" ]; then

    check_port "$MAP_PORT" --kill || exit 1

    print_info "Setting up Python Native Map Generators on port $MAP_PORT..."
    
    DAEMON_SERVICE="luanti-map-daemon@${WORLD}"
    SERVER_SERVICE="luanti-map-server@${WORLD}"
    
    TILES_DIR="${WORLD_PATH}/tiles"
    mkdir -p "$TILES_DIR"
    
    # Check if minetest-mapper exists
    if [ ! -f "$USER_HOME/minetest-mapper/minetestmapper" ]; then
        print_error "minetest-mapper not installed! Run scripts/setup/mapper.sh first."
        exit 1
    fi
    
    print_info "Creating systemd Background Daemon..."
    sudo tee "/etc/systemd/system/${DAEMON_SERVICE}.service" > /dev/null <<EOF
[Unit]
Description=Luanti Map Incremental Generator - ${WORLD}
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${PROJECT_ROOT}
ExecStart=/usr/bin/python3 ${PROJECT_ROOT}/scripts/map/luanti-map-daemon.py --daemon --world ${WORLD_PATH} --mapper ${USER_HOME}/minetest-mapper/minetestmapper --colors ${USER_HOME}/minetest-mapper/colors.txt --output ${TILES_DIR}
Restart=always
RestartSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=luanti-map-daemon-${WORLD}

[Install]
WantedBy=multi-user.target
EOF

    print_info "Creating systemd static Tile Server..."
    sudo tee "/etc/systemd/system/${SERVER_SERVICE}.service" > /dev/null <<EOF
[Unit]
Description=Luanti Static Tile Server - ${WORLD}
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${PROJECT_ROOT}
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 -u ${PROJECT_ROOT}/scripts/map/serve-tiles.py --port ${MAP_PORT} --dir ${TILES_DIR}
Restart=always
RestartSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=luanti-map-server-${WORLD}

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "${DAEMON_SERVICE}" "${SERVER_SERVICE}"
    sudo systemctl start "${DAEMON_SERVICE}" "${SERVER_SERVICE}"
    
    # Ensure mapserver mod is disabled natively so it stops collecting garbage data in sqlite
    if grep -q "^load_mod_mapserver[ =]*true" "$WORLD_MT"; then
        print_info "Deactivating deprecated mapserver mod in world.mt..."
        grep -v "^load_mod_mapserver[ =]" "$WORLD_MT" > "${WORLD_MT}.tmp" && mv "${WORLD_MT}.tmp" "$WORLD_MT"
        echo "load_mod_mapserver = false" >> "$WORLD_MT"
    fi
    
    # Verify services are running
    sleep 2
    if systemctl is-active --quiet "${SERVER_SERVICE}"; then
        print_info "Map services started successfully!"
        print_info "Map base URL: http://$(hostname -I | awk '{print $1}'):$MAP_PORT/"
        print_info "QGIS XYZ Tile URL: http://$(hostname -I | awk '{print $1}'):$MAP_PORT/{z}/{x}/{y}.png"
    else
        print_warning "Map services may not have started correctly. Check with:"
        echo "  sudo systemctl status ${SERVER_SERVICE}"
    fi
    echo ""
fi

# Service mode: Create and start systemd service
if [ "$IS_SERVICE" = true ]; then
    print_info "Setting up Luanti server as systemd service..."
    
    SERVICE_NAME="luanti-server@${WORLD}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    
    print_info "Creating systemd service: ${SERVICE_NAME}"
    
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Luanti Game Server - ${WORLD} (Port ${PORT})
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${USER_HOME}
ExecStart=/snap/bin/luanti --server --world ${WORLD_PATH} --gameid ${GAME_ID} --port ${PORT}
Restart=always
RestartSec=10

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=luanti-${WORLD}

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    print_info "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    
    # Enable service
    print_info "Enabling ${SERVICE_NAME}..."
    sudo systemctl enable "${SERVICE_NAME}"
    
    # Start service
    print_info "Starting ${SERVICE_NAME}..."
    sudo systemctl start "${SERVICE_NAME}"
    
    # Show status
    echo ""
    print_info "Service started successfully!"
    print_info "Status:"
    sudo systemctl status "${SERVICE_NAME}" --no-pager | head -n 10
    
    echo ""
    print_info "Service Management Commands:"
    echo "  Stop:    sudo systemctl stop ${SERVICE_NAME}"
    echo "  Restart: sudo systemctl restart ${SERVICE_NAME}"
    echo "  Status:  sudo systemctl status ${SERVICE_NAME}"
    echo "  Logs:    sudo journalctl -u ${SERVICE_NAME} -f"
    
else
    # Foreground mode: Run luanti directly
    print_info "Running Luanti server in foreground mode..."
    print_info "World: $WORLD"
    print_info "Port: $PORT"
    print_info "Press Ctrl+C to stop the server"
    echo ""
    
    /snap/bin/luanti --server --world "$WORLD_PATH" --gameid "$GAME_ID" --port "$PORT"
fi