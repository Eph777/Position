#!/bin/bash
# Express setup - runs all setup scripts in sequence
# Usage: ./express.sh [world_name]

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../src/lib/common.sh"

WORLD="${1:-myworld}"
PROJECT_ROOT=$(get_project_root)

print_info "=== Luanti Express Setup ==="
print_info "This will run all setup scripts in sequence for world: $WORLD"

# Run PostgreSQL setup
print_info "Step 1/3: Setting up PostgreSQL..."
"$SCRIPT_DIR/postgresql.sh" || exit 1

# Run backend migration
print_info "Step 2/3: Migrating backend..."
"$PROJECT_ROOT/scripts/server/migrate-backend.sh" "$WORLD" --force || exit 1

# Run mapper setup
print_info "Step 3/3: Setting up mapper..."
"$SCRIPT_DIR/mapper.sh" "$WORLD" || exit 1

print_info "Express setup complete!"
echo ""
echo "Connect from your Luanti client to:"
echo "  Server IP: $(hostname -I | awk '{print $1}')"
echo "  Port: 30000"
echo ""
print_warning "For security, consider changing default passwords in production!"
