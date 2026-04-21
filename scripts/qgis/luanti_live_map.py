import urllib.parse
import urllib.request
import urllib.error
import http.server
import socketserver
import threading
import re
import socket
from qgis.core import QgsRasterLayer, QgsProject, QgsCoordinateReferenceSystem, QgsRectangle, QgsMessageLog, Qgis
from qgis.utils import iface

# =========================================================
# THE ULTIMATE LUANTI MAPSERVER <-> QGIS ALL-IN-ONE BRIDGE
# =========================================================
# This powerful standalone script sets up a background Daemon proxy,
# auto-detects the exact location of your Minetest world chunks, 
# injects the XYZ Map Layer, and physically snaps your QGIS camera 
# precisely directly over your populated base. No more getting 
# lost in the infinite white void of Web Mercator!
# =========================================================

PROXY_PORT = 5050
MAPSERVER_URL = "http://192.168.2.14:8080" # The user's active Multipass Ubuntu VM
Z_MIN = 1
Z_MAX = 13
LAYER_ID = 0

# -----------------------------------------------------
# 1. Background Math Translation Daemon 
# -----------------------------------------------------
class MapserverProxyHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        match = re.match(r'/tiles/(\d+)/(-?\d+)/(-?\d+)', self.path)
        if match:
            z = int(match.group(1))
            x_qgis = int(match.group(2))
            y_qgis = int(match.group(3))

            # The exact math map coordinates mapping equator to game origin
            tile_center = 2 ** (z - 1)
            x_ms = x_qgis - tile_center
            y_ms = y_qgis - tile_center

            target_url = f"{MAPSERVER_URL}/api/tile/{LAYER_ID}/{x_ms}/{y_ms}/{z}"
            
            try:
                req = urllib.request.Request(target_url, headers={'User-Agent': 'QGIS-Py-Proxy'})
                with urllib.request.urlopen(req, timeout=3) as response:
                    data = response.read()
                    
                    # 763 bytes is the Mapserver's hardcoded "white blank tile" for missing game chunks!
                    # Passing this to QGIS draws solid white squares over the whole map. Filtering it to 404
                    # makes QGIS cleanly transparent around the edges of the active world.
                    if len(data) == 763:
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
        pass

def start_proxy_daemon():
    # If a proxy is already running from a previous run, do nothing
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    is_running = sock.connect_ex(("127.0.0.1", PROXY_PORT)) == 0
    sock.close()
    
    if not is_running:
        httpd = socketserver.ThreadingTCPServer(("127.0.0.1", PROXY_PORT), MapserverProxyHandler)
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        QgsMessageLog.logMessage("Luanti Local Translation Proxy Started!", "LuantiMap", Qgis.Info)
    else:
        QgsMessageLog.logMessage("Luanti Local Translation Proxy already running.", "LuantiMap", Qgis.Info)

# -----------------------------------------------------
# 2. Mapserver Data Radar (Geo-Locator)
# -----------------------------------------------------
def find_populated_chunk():
    """ Radars outwards from game origin (0,0) to find the first real chunk that ISN'T white void. """
    search_radius = 5  # Max chunks to check around origin (-5 to +5 x/y)
    QgsMessageLog.logMessage(f"Deploying Radar to locate your Minetest Base...", "LuantiMap", Qgis.Info)
    
    for r in range(search_radius + 1):
        for x in range(-r, r + 1):
            for y in range(-r, r + 1):
                if abs(x) != r and abs(y) != r: continue
                # We check zoom 6 (zoomed out) which groups thousands of blocks, 
                # so a tiny search radius actually sweeps a massive area of the map!
                test_url = f"{MAPSERVER_URL}/api/tile/{LAYER_ID}/{x}/{y}/6"
                try:
                    with urllib.request.urlopen(test_url, timeout=1) as resp:
                        if len(resp.read()) > 900: # Not the 763 blank byte preset!
                            QgsMessageLog.logMessage(f"Target Acquired! Game Chunk density found at Tile {x},{y}", "LuantiMap", Qgis.Success)
                            return x, y
                except:
                    pass
                    
    # If local sweeping fails, fallback to 0,0
    QgsMessageLog.logMessage(f"Radar did not find data near origin. Defaulting to 0,0.", "LuantiMap", Qgis.Warning)
    return 0, 0

# -----------------------------------------------------
# 3. Layer Orchestration & Warping
# -----------------------------------------------------
def deploy_map_system():
    # 1. Fire up background mathematical translation thread
    start_proxy_daemon()
    
    # 2. Check if Layer already exists to prevent duplicates
    active_layers = QgsProject.instance().mapLayersByName("Luanti Live Map")
    if active_layers:
        QgsProject.instance().removeMapLayer(active_layers[0].id())
        
    PROXY_URL = f"http://127.0.0.1:{PROXY_PORT}/tiles/{{z}}/{{x}}/{{y}}"
    params = {'type': 'xyz', 'url': PROXY_URL, 'zMin': str(Z_MIN), 'zMax': str(Z_MAX)}
    encoded_url = urllib.parse.urlencode(params)
    
    layer = QgsRasterLayer(encoded_url, "Luanti Live Map", "wms")
    layer.setCrs(QgsCoordinateReferenceSystem("EPSG:3857"))
    
    if layer.isValid():
        QgsProject.instance().addMapLayer(layer)
        
        # 3. Geo-Locate physical chunk data
        active_tile_x, active_tile_y = find_populated_chunk()
        
        if iface:
            canvas = iface.mapCanvas()
            
            # 4. Warp Camera Math
            # Calculate the EPSG:3857 coordinate for this particular physical chunk so we zoom PERFECTLY onto it
            # In Slippy mercator, Zoom 6 tiles cover ~626km each.
            base_resolution_z6 = 626172.0 
            
            # Minetest X coordinates align seamlessly with Web Mercator. 
            # We snap the exact meter bounds:
            center_x = active_tile_x * base_resolution_z6
            center_y = -active_tile_y * base_resolution_z6 # Invert Y for physical plotting
            
            padding = base_resolution_z6 / 2
            extent = QgsRectangle(center_x-padding, center_y-padding, center_x+padding, center_y+padding)
            
            canvas.setExtent(extent)
            canvas.refresh()
            QgsMessageLog.logMessage("Camera successfully warped onto Game Target.", "LuantiMap", Qgis.Success)
            
    else:
        QgsMessageLog.logMessage("Catastrophe! QGIS failed to validate the XYZ layer.", "LuantiMap", Qgis.Critical)

# Execute the System!
deploy_map_system()
