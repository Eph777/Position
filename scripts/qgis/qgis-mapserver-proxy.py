#!/usr/bin/env python3
import http.server
import socketserver
import urllib.request
import urllib.error
import re
import sys

# =========================================================
# QGIS <-> LUANTI MAPSERVER TRANSLATOR PROXY
# This script forms a rigid bridge translating QGIS's 
# Spherical Earth logic into Mapserver's Flat Cartesian plane.
# =========================================================

PROXY_PORT = 5050

# Mapserver ONLY correctly receives the world chunks on localhost.
# Never change this unless explicitly tunneling!
MAPSERVER_URL = "http://127.0.0.1:8080"
LAYER_ID = 0

class MapserverProxyHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        match = re.match(r'/tiles/(\d+)/(-?\d+)/(-?\d+)', self.path)
        if match:
            z = int(match.group(1))
            x_qgis = int(match.group(2))
            y_qgis = int(match.group(3))

            # The exact math verified by mapserver source
            tile_center = 2 ** (z - 1)
            x_ms = x_qgis - tile_center
            y_ms = y_qgis - tile_center

            # The exact endpoint structure verified by web/serve.go
            target_url = f"{MAPSERVER_URL}/api/tile/{LAYER_ID}/{x_ms}/{y_ms}/{z}"
            
            try:
                # Ask daemon for chunk mapping
                req = urllib.request.Request(target_url, headers={'User-Agent': 'QGIS-Proxy'})
                with urllib.request.urlopen(req, timeout=5) as response:
                    data = response.read()
                    
                    # 763 bytes is Mapserver's hardcoded "white blank tile" for non-existent map geometries!
                    # We MUST intercept it so QGIS understands it is looking off the edge of the world.
                    if len(data) == 763:
                        # By returning a classic 404, QGIS won't paint a white opaque block. 
                        # It will leave it beautifully transparent inside QGIS!
                        self.send_response(404)
                        self.end_headers()
                        return

                    self.send_response(200)
                    self.send_header('Content-Type', 'image/png')
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.end_headers()
                    self.wfile.write(data)
                    
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
    print(f"      QGIS -> Minetest Translation Proxy Active            ")
    print(f"===========================================================")
    print(f" Mapserver Target:  {MAPSERVER_URL}")
    print(f" Target Layer:      {LAYER_ID}")
    print(f"\n Leave this terminal running while QGIS is open!")
    
    with socketserver.ThreadingTCPServer(("127.0.0.1", PROXY_PORT), MapserverProxyHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down proxy...")
            sys.exit(0)
