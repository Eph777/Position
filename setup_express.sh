#!/bin/bash

WORLD="myworld"

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

./setup.sh
./migrate.sh $WORLD
./setup_mapper.sh $WORLD

echo ""
echo "5. Connect from your Luanti client to:"
echo "   Server IP: $(hostname -I | awk '{print $1}')"
echo "   Port: 30000"
echo ""
print_info "Configuration details saved in: $PROJECT_DIR/.env"
print_info "PostgreSQL User: ${DB_USER}"
print_info "PostgreSQL Password: ${DB_PASS}"
echo ""
print_warning "For security, consider changing these passwords in production!"