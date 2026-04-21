#!/usr/bin/env python3
import http.server
import socketserver
import urllib.request
import urllib.error
import re
import socket
import sys

# =========================================================
# QGIS <-> LUANTI MAPSERVER TRANSLATOR PROXY
# =========================================================

PROXY_PORT = 5050

# Automatically detect system's LAN IP
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(("8.8.8.8", 80))
    IP_ADDRESS = s.getsockname()[0]
except Exception:
    IP_ADDRESS = "127.0.0.1"
finally:
    s.close()

# The Fuzzer proved Mapserver uses Layer 0 and port 8080!
MAPSERVER_URL = f"http://{IP_ADDRESS}:8080"
LAYER_ID = 0

# Set to True to inverse the Y-axis if the map is upside-down.
INVERT_Y = False

class MapserverProxyHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        match = re.match(r'/tiles/(\d+)/(-?\d+)/(-?\d+)', self.path)
        if match:
            z = int(match.group(1))
            x_qgis = int(match.group(2))
            y_qgis = int(match.group(3))

            tile_center = 2 ** (z - 1)
            x_ms = x_qgis - tile_center
            
            if INVERT_Y:
                y_ms = tile_center - y_qgis 
            else:
                y_ms = y_qgis - tile_center

            # The proven API format!
            target_url = f"{MAPSERVER_URL}/api/tile/{LAYER_ID}/{x_ms}/{y_ms}/{z}"
            
            try:
                req = urllib.request.Request(target_url, headers={'User-Agent': 'QGIS-Proxy'})
                with urllib.request.urlopen(req, timeout=5) as response:
                    self.send_response(response.getcode())
                    self.send_header('Content-Type', response.headers.get('Content-Type', 'image/png'))
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.end_headers()
                    self.wfile.write(response.read())
            
            except urllib.error.HTTPError as e:
                # 404 means chunk doesn't exist, ignore cleanly
                self.send_response(e.code)
                self.end_headers()
            except Exception as e:
                print(f"[!] Mapserver target URL failed: {target_url} - {str(e)}")
                self.send_response(500)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass # Shush terminal spam

if __name__ == "__main__":
    print(f"===========================================================")
    print(f"      Luanti QGIS Tile Proxy Server Initiated              ")
    print(f"===========================================================")
    print(f" Proxy Address:  http://{IP_ADDRESS}:{PROXY_PORT}/")
    print(f" Target Server:  {MAPSERVER_URL}")
    print(f" Target Layer:   {LAYER_ID}")
    print(f"===========================================================")
    
    with socketserver.ThreadingTCPServer(("0.0.0.0", PROXY_PORT), MapserverProxyHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down proxy...")
            sys.exit(0)
