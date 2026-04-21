#!/usr/bin/env python3
import http.server
import socketserver
import urllib.request
import urllib.error
import re
import math
import sys

# =========================================================
# QGIS <-> LUANTI MAPSERVER TRANSLATOR PROXY
# This script bridges the gap between Web Mercator mathematics
# and Minetest Cartesian mathematics.
# Run this on your Mac alongside QGIS!
# =========================================================

# 1. Configuration
PROXY_PORT = 5000

# Set this to the exact IP/Port of your Luanti server
MAPSERVER_URL = "http://192.168.2.14:8080"
LAYER_ID = 1

# If the map renders perfectly but is upside-down (north is south),
# change this to True to inverse the Cartesian plane Y-axis mapping.
INVERT_Y = False

class MapserverProxyHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        # Match QGIS Tile Requests: /tiles/{z}/{x}/{y}
        match = re.match(r'/tiles/(\d+)/(-?\d+)/(-?\d+)', self.path)
        if match:
            z = int(match.group(1))
            x_qgis = int(match.group(2))
            y_qgis = int(match.group(3))

            # Web Mercator mathematics assumes the world is a giant square.
            # Center of the world coordinates at zoom Z = 2^(Z-1)
            # Example: At zoom 13, center is X:4096, Y:4096
            tile_center = 2 ** (z - 1)

            # Translation Phase
            # We shift the Web Mercator Slippy Map coordinates back to 0,0 Cartesian coordinates
            x_ms = x_qgis - tile_center
            
            if INVERT_Y:
                y_ms = tile_center - y_qgis 
            else:
                y_ms = y_qgis - tile_center

            # Build the official Mapserver request
            target_url = f"{MAPSERVER_URL}/api/tile/{LAYER_ID}/{x_ms}/{y_ms}/{z}"
            
            try:
                # Fetch the tile from your Linux server
                req = urllib.request.Request(target_url, headers={'User-Agent': 'QGIS-Proxy'})
                with urllib.request.urlopen(req, timeout=5) as response:
                    self.send_response(response.getcode())
                    self.send_header('Content-Type', response.headers.get('Content-Type', 'image/png'))
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.send_header('Cache-Control', 'max-age=60')
                    self.end_headers()
                    self.wfile.write(response.read())
            
            except urllib.error.HTTPError as e:
                # If mapserver returns 404 (chunk doesn't exist), just silently pass it to QGIS
                self.send_response(e.code)
                self.end_headers()
            except Exception as e:
                print(f"[!] Target URL failed: {target_url} - {str(e)}")
                self.send_response(500)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    # Mute standard logging so terminal isn't spammed with thousands of tile requests
    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    print(f"===========================================================")
    print(f"      Luanti QGIS Tile Proxy Server Initiated              ")
    print(f"===========================================================")
    print(f" -> Listening locally at:  http://127.0.0.1:{PROXY_PORT}/")
    print(f" -> Translating to:        {MAPSERVER_URL}")
    print(f" -> Y-Axis Inverted:       {INVERT_Y}")
    print(f"===========================================================")
    print("WARNING: Leave this terminal open while using QGIS!\n")
    
    with socketserver.ThreadingTCPServer(("0.0.0.0", PROXY_PORT), MapserverProxyHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down proxy...")
            sys.exit(0)
