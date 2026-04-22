#!/usr/bin/env python3
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

import os
import http.server
import socketserver
import sys
import argparse

class CORSRequestHandler(http.server.SimpleHTTPRequestHandler):
    """
    HTTP Request Handler with CORS headers support.
    Needed for web-based GIS clients and cross-origin access.
    """
    def guess_type(self, path):
        # Explicitly handle PNG tiles to ensure QGIS/browsers recognize them correctly
        if path.lower().endswith(".png"):
            return "image/png"
        return super().guess_type(path)

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Range')
        # Add Cache-Control to prevent stale tiles
        self.send_header('Cache-Control', 'no-cache, must-revalidate')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

def start_server(directory, port):
    if not os.path.isdir(directory):
        print(f"❌ Error: Directory '{directory}' does not exist.")
        sys.exit(1)

    os.chdir(directory)
    
    # Binds to "" (0.0.0.0) to expose it to the external network
    try:
        # Allow port reuse to prevent "Address already in use" errors on restarts
        socketserver.TCPServer.allow_reuse_address = True
        with socketserver.TCPServer(("", port), CORSRequestHandler) as httpd:
            print(f"\n✅ Remote Tile Server is live!")
            print(f"📁 Serving content from: {directory}")
            print(f"🌐 Reachable at: http://<YOUR_SERVER_IP_ADDRESS>:{port}/{{z}}/{{x}}/{{y}}.png")
            print(f"  2. **Add Map Background (XYZ Tiles)**:")
            print(f"   - In Browser Panel, right-click **XYZ Tiles**")
            print(f"   - New Connection Name: `Luanti Map`")
            print(f"   - URL: `http://<server-ip>:8080/{{z}}/{{x}}/{{y}}.png`")
            print(f"   - **Crucial**: If the map looks inverted or doesn't show up, try `http://<server-ip>:8080/{{z}}/{{x}}/{{-y}}.png` (some GDAL versions use the TMS Y-axis convention).")
            print(f"   - Add to map")
            print(f"🛑 Press Ctrl+C to stop.")
            
            try:
                httpd.serve_forever()
            except KeyboardInterrupt:
                print("\nShutting down server.")
                httpd.server_close()
    except OSError as e:
        print(f"❌ Error starting server: {e}")
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Serve Luanti XYZ tiles with CORS support.")
    parser.add_argument("directory", help="The directory containing the XYZ tiles")
    parser.add_argument("-p", "--port", type=int, default=8080, help="Port to host the server on (default: 8080)")
    args = parser.parse_args()

    start_server(args.directory, args.port)
