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

# Common utility functions for Luanti/QGIS scripts
# Source this file in other scripts: source "$(dirname "$0")/../src/lib/common.sh" || source "$(dirname "$0")/../../src/lib/common.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored info message
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Print colored error message
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Print colored warning message
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Get user home directory (handles root and non-root users)
get_user_home() {
    if [ "$EUID" -eq 0 ]; then
        echo "/root"
    else
        echo "$HOME"
    fi
}

# Get current username
get_current_user() {
    if [ "$EUID" -eq 0 ]; then
        echo "root"
    else
        whoami
    fi
}

# Check if a port is in use and optionally kill the process
# Usage: check_port <port> [--kill] [--force]
check_port() {
    local port=$1
    local kill_process=false
    local force=false
    
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --kill) kill_process=true; shift ;;
            --force) force=true; shift ;;
            *) shift ;;
        esac
    done
    
    local port_in_use=$(sudo lsof -i :$port -t 2>/dev/null || true)
    
    if [ -z "$port_in_use" ]; then
        return 0  # Port is free
    fi
    
    print_warning "Port $port is already in use!"
    sudo lsof -i :$port | grep LISTEN || true
    
    if [ "$kill_process" = true ]; then
        if [ "$force" = true ]; then
            print_info "Stopping process on port $port..."
            sudo kill -9 $port_in_use
            sleep 2
            print_info "Process stopped."
            return 0
        else
            echo ""
            read -p "Do you want to kill this process and continue? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_info "Stopping process on port $port..."
                sudo kill -9 $port_in_use
                sleep 2
                print_info "Process stopped."
                return 0
            else
                print_error "Cannot proceed while port $port is in use."
                return 1
            fi
        fi
    fi
    
    return 1  # Port is in use and not killed
}

# Validate required environment variables
# Usage: validate_env VAR1 VAR2 VAR3...
validate_env() {
    local missing=()
    for var in "$@"; do
        if [ -z "${!var}" ]; then
            missing+=("$var")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required environment variables:"
        for var in "${missing[@]}"; do
            echo "  - $var"
        done
        return 1
    fi
    return 0
}

# Get the project root directory (assumes common.sh is in src/lib/)
get_project_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Go up two levels from src/lib/ to get to project root
    echo "$(cd "$script_dir/../.." && pwd)"
}

# Load environment variables from .env file
# Usage: load_env [path_to_env_file]
load_env() {
    local env_file="${1:-.env}"
    if [ -f "$env_file" ]; then
        print_info "Loading environment from $env_file"
        export $(cat "$env_file" | grep -v '^#' | xargs)
        return 0
    else
        print_warning "Environment file $env_file not found"
        return 1
    fi
}

# Check if a command exists
# Usage: command_exists <command_name>
command_exists() {
    command -v "$1" &> /dev/null
}

# Confirm action with user (skippable with --force flag)
# Usage: confirm "Are you sure?" [--force]
confirm() {
    local message="$1"
    local force="${2:-false}"
    
    if [ "$force" = "--force" ]; then
        return 0
    fi
    
    echo ""
    read -p "$message (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Update or append a key=value pair in a file
# Usage: update_config_value <file> <key> <value>
update_config_value() {
    local file=$1
    local key=$2
    local value=$3
    
    if [ ! -f "$file" ]; then
        print_error "File not found: $file"
        return 1
    fi
    
    if grep -q "^${key} *=" "$file"; then
        sed -i.bak "s|^${key} *=.*|${key} = ${value}|" "$file"
    else
        echo "${key} = ${value}" >> "$file"
    fi
}

# Export all functions for use in other scripts
export -f print_info
export -f print_error
export -f print_warning
export -f get_user_home
export -f get_current_user
export -f check_port
export -f validate_env
export -f get_project_root
export -f load_env
export -f command_exists
export -f confirm
export -f update_config_value
