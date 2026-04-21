import urllib.parse
from qgis.core import QgsRasterLayer, QgsProject, QgsCoordinateReferenceSystem, QgsRectangle
from qgis.utils import iface

# =========================================================
# LUANTI NATIVE MAP TILE VIEWER FOR QGIS
# Execute this inside the QGIS Python Console
# =========================================================

# The Multipass VM IP
VM_IP = "192.168.2.14"
TILE_PORT = 8080

TILE_URL = f"http://{VM_IP}:{TILE_PORT}/{{z}}/{{x}}/{{y}}.png"

# Zoom range: tiles go from zoom 5 (overview) to 13 (full detail, 1px=1node)
Z_MIN = 5
Z_MAX = 13

params = {
    'type': 'xyz',
    'url': TILE_URL,
    'zMin': str(Z_MIN),
    'zMax': str(Z_MAX),
}

encoded = urllib.parse.urlencode(params)

# Remove old layer if it exists
for layer in QgsProject.instance().mapLayersByName("Luanti Map"):
    QgsProject.instance().removeMapLayer(layer.id())

layer = QgsRasterLayer(encoded, "Luanti Map", "wms")

if layer.isValid():
    QgsProject.instance().addMapLayer(layer)
    print(f"Layer added: {TILE_URL}")
    
    if iface:
        canvas = iface.mapCanvas()
        # Game (0,0) maps to EPSG:3857 (0,0) which is lat=0 lon=0.
        # Snap camera to a small area around the origin.
        # At zoom 13, one tile = ~4891 meters in EPSG:3857.
        # Our game world is ~512 nodes = ~2 tiles = ~10000 meters.
        extent = QgsRectangle(-20000, -20000, 20000, 20000)
        canvas.setExtent(extent)
        canvas.refresh()
        print("Camera snapped to equator/meridian (game origin).")
        print("If you see nothing, try zooming in/out with the scroll wheel.")
else:
    print(f"ERROR: Layer is invalid. URL: {TILE_URL}")
    print("Check that serve-tiles.py is running on the VM.")
