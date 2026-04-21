#!/usr/bin/env python3
import http.server
import socketserver
import urllib.request
import urllib.error
import re
import sys

# =========================================================
# QGIS <-> LUANTI MAPSERVER TRANSLATOR PROXY
# =========================================================

PROXY_PORT = 5050

# Mapserver operates on the user's localhost via SSH tunnel!
MAPSERVER_URL = "http://127.0.0.1:8080"
LAYER_ID = 0
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
            y_ms = tile_center - y_qgis if INVERT_Y else y_qgis - tile_center

            # The exact API endpoint
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
                self.send_response(e.code)
                self.end_headers()
            except Exception as e:
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
    print(f" Proxy Address:  http://127.0.0.1:{PROXY_PORT}/")
    print(f" Target Server:  {MAPSERVER_URL}")
    print(f" Target Layer:   {LAYER_ID}")
    print(f"===========================================================")
    
    with socketserver.ThreadingTCPServer(("127.0.0.1", PROXY_PORT), MapserverProxyHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down proxy...")
            sys.exit(0)
