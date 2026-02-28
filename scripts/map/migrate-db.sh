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

# Migrate map.sqlite to include modification tracking for incremental rendering
# Usage: ./migrate-db.sh <world_name>

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

WORLD="$1"

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 <world_name>"
    exit 1
fi

USER_HOME=$(get_user_home)
WORLD_PATH="$USER_HOME/snap/luanti/common/.minetest/worlds/$WORLD"
MAP_DB="$WORLD_PATH/map.sqlite"

if [ ! -f "$MAP_DB" ]; then
    print_error "map.sqlite not found at $MAP_DB"
    exit 1
fi

print_info "Injecting tracking triggers into map.sqlite for world: $WORLD..."

# Check if sqlite3 is installed
if ! command_exists sqlite3; then
    print_error "sqlite3 is not installed. Please install it with: sudo apt-get install sqlite3"
    exit 1
fi

sqlite3 "$MAP_DB" <<EOF
CREATE TABLE IF NOT EXISTS changed_blocks (pos INT PRIMARY KEY, mtime INT);

CREATE TRIGGER IF NOT EXISTS log_block_insert AFTER INSERT ON blocks
BEGIN
    INSERT OR REPLACE INTO changed_blocks(pos, mtime) VALUES (NEW.pos, CAST(strftime('%s', 'now') AS INT));
END;

CREATE TRIGGER IF NOT EXISTS log_block_update AFTER UPDATE ON blocks
BEGIN
    INSERT OR REPLACE INTO changed_blocks(pos, mtime) VALUES (NEW.pos, CAST(strftime('%s', 'now') AS INT));
END;
EOF

if [ $? -eq 0 ]; then
    print_info "Database migrated successfully! Incremental changes will now be tracked."
else
    print_error "Database migration failed."
    exit 1
fi
