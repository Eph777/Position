"""
World Manager Module
Safely executes commands to manage Luanti worlds
"""

import subprocess
import re
import os
from typing import Dict, List, Optional, Tuple

# Path to project root
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
START_SCRIPT = os.path.join(PROJECT_ROOT, "scripts", "server", "start-luanti.sh")


def validate_world_name(world_name: str) -> bool:
    """
    Validate world name - only alphanumeric and underscores allowed
    
    Args:
        world_name: World name to validate
        
    Returns:
        True if valid, False otherwise
    """
    if not world_name or len(world_name) > 50:
        return False
    return bool(re.match(r'^[a-zA-Z0-9_]+$', world_name))


def validate_port(port: int) -> bool:
    """
    Validate port number - must be in range 1024-65535
    
    Args:
        port: Port number to validate
        
    Returns:
        True if valid, False otherwise
    """
    return isinstance(port, int) and 1024 <= port <= 65535


def start_world(world_name: str, port: int = 30000, map_port: Optional[int] = None, 
                enable_service: bool = True) -> Tuple[bool, str]:
    """
    Start a Luanti world
    
    Args:
        world_name: Name of the world to start
        port: Game server port (default: 30000)
        map_port: Map server port (optional)
        enable_service: Whether to run as service (default: True)
        
    Returns:
        Tuple of (success: bool, message: str)
    """
    # Validate inputs
    if not validate_world_name(world_name):
        return False, f"Invalid world name: {world_name}"
    
    if not validate_port(port):
        return False, f"Invalid port: {port}"
    
    if map_port and not validate_port(map_port):
        return False, f"Invalid map port: {map_port}"
    
    # Check if script exists
    if not os.path.exists(START_SCRIPT):
        return False, f"Start script not found: {START_SCRIPT}"
    
    # Create .proj_root file for scripts to read PROJECT_ROOT
    proj_root_file = os.path.expanduser("~/.proj_root")
    try:
        with open(proj_root_file, 'w') as f:
            f.write(PROJECT_ROOT)
    except Exception as e:
        return False, f"Failed to create .proj_root file: {str(e)}"
    
    # Build command
    cmd = [START_SCRIPT, world_name, str(port)]
    
    if enable_service:
        cmd.append("--service")
    
    if map_port:
        cmd.extend(["--map", str(map_port)])
    
    # Execute command
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=60,
            check=False
        )
        
        if result.returncode == 0:
            services = []
            if enable_service:
                services.append(f"luanti-server@{world_name}")
            if map_port:
                services.extend([
                    f"luanti-map-render@{world_name}",
                    f"luanti-map-server@{world_name}"
                ])
            
            return True, f"World '{world_name}' started successfully"
        else:
            return False, f"Failed to start world: {result.stderr or result.stdout}"
            
    except subprocess.TimeoutExpired:
        return False, "Command timed out after 60 seconds"
    except Exception as e:
        return False, f"Error starting world: {str(e)}"


def stop_world(world_name: str) -> Tuple[bool, str]:
    """
    Stop a Luanti world and its associated services
    
    Args:
        world_name: Name of the world to stop
        
    Returns:
        Tuple of (success: bool, message: str)
    """
    if not validate_world_name(world_name):
        return False, f"Invalid world name: {world_name}"
    
    services = [
        f"luanti-server@{world_name}",
        f"luanti-map-render@{world_name}",
        f"luanti-map-server@{world_name}"
    ]
    
    stopped_services = []
    errors = []
    
    for service in services:
        try:
            result = subprocess.run(
                ["sudo", "systemctl", "stop", service],
                capture_output=True,
                text=True,
                timeout=30
            )
            if result.returncode == 0:
                stopped_services.append(service)
            else:
                # Service might not exist, that's okay
                pass
        except Exception as e:
            errors.append(f"{service}: {str(e)}")
    
    if stopped_services:
        return True, f"Stopped services: {', '.join(stopped_services)}"
    elif errors:
        return False, f"Errors: {', '.join(errors)}"
    else:
        return True, f"No active services found for world '{world_name}'"


def get_world_status(world_name: str) -> Dict:
    """
    Get status of a world's services
    
    Args:
        world_name: Name of the world
        
    Returns:
        Dictionary with service statuses
    """
    if not validate_world_name(world_name):
        return {"error": "Invalid world name"}
    
    services = {
        "game_server": f"luanti-server@{world_name}",
        "map_renderer": f"luanti-map-render@{world_name}",
        "map_server": f"luanti-map-server@{world_name}"
    }
    
    status = {"world": world_name}
    
    for key, service in services.items():
        try:
            result = subprocess.run(
                ["systemctl", "is-active", service],
                capture_output=True,
                text=True,
                timeout=5
            )
            status[key] = result.stdout.strip()  # "active", "inactive", "failed", etc.
        except Exception:
            status[key] = "unknown"
    
    return status


def list_running_worlds() -> List[Dict]:
    """
    List all running Luanti worlds
    
    Returns:
        List of dictionaries with world information
    """
    worlds = []
    
    try:
        # Get all luanti-server services
        result = subprocess.run(
            ["systemctl", "list-units", "--type=service", "--state=running", "luanti-server@*", "--no-pager"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        # Parse output to extract world names
        for line in result.stdout.split('\n'):
            match = re.search(r'luanti-server@(\w+)\.service', line)
            if match:
                world_name = match.group(1)
                status = get_world_status(world_name)
                worlds.append(status)
                
    except Exception as e:
        print(f"Error listing worlds: {e}")
    
    return worlds
