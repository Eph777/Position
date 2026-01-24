#!/bin/bash
# scripts/setup_env.sh

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$PROJECT_DIR/venv"

echo "--- Setting up Python Virtual Environment ---"

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

echo "Installing/Updating dependencies..."
pip install --upgrade pip
pip install -r "$PROJECT_DIR/requirements.txt"
# Explicitly ensure critical packages are here
pip install fastapi uvicorn asyncpg bcrypt python-multipart

echo "Python environment ready."
