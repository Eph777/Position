#!/bin/bash

# check_port_and_prompt <PORT>
# Returns 0 if port is free (or freed by user killing process).
# Returns 1 if port remains busy.
check_port_and_prompt() {
    local port=$1
    local pid=$(sudo lsof -i :$port -t 2>/dev/null | head -n 1)

    if [ -z "$pid" ]; then
        return 0 # Port is free
    fi

    echo "Port $port is currently in use by PID $pid:"
    ps -f -p $pid | sed 1d
    
    echo ""
    echo "Do you want to kill this process? (y/N)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        sudo kill -9 $pid 2>/dev/null
        sleep 1
        if sudo lsof -i :$port -t >/dev/null; then
             echo "Failed to kill process or another started."
             return 1
        else
             echo "Process killed. Port $port is now free."
             return 0
        fi
    else
        return 1
    fi
}

# find_free_port <START_PORT>
# Echoes the first free port found >= START_PORT
find_free_port() {
    local start_port=$1
    local port=$start_port
    
    while :; do
        if ! sudo lsof -i :$port -t >/dev/null 2>&1; then
            echo $port
            return 0
        fi
        port=$((port + 1))
        # Safety break default
        if [ $port -gt 65535 ]; then
             echo "Error: No free ports found" >&2
             return 1
        fi
    done
}
