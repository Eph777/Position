import urllib.parse
from qgis.core import QgsRasterLayer, QgsProject, QgsCoordinateReferenceSystem, QgsRectangle
from qgis.utils import iface

# =========================================================
# LUANTI NATIVE MAP TILE VIEWER FOR QGIS
# Execute this inside the QGIS Python Console
# =========================================================

# The Multipass VM IP. Change this if your VM has a different address.
VM_IP = "192.168.2.14"
TILE_PORT = 8080

TILE_URL = f"http://{VM_IP}:{TILE_PORT}/{{z}}/{{x}}/{{y}}.png"

# These should match what the daemon generates. 
# The daemon writes metadata.txt with the actual max_zoom.
Z_MIN = 0
Z_MAX = 8  # Will work even if the daemon uses a different max - QGIS just won't find tiles at unused levels

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
        # Snap to a reasonable view around the origin
        extent = QgsRectangle(-5000, -5000, 5000, 5000)
        canvas.setExtent(extent)
        canvas.refresh()
        print("Camera snapped to origin.")
else:
    print(f"ERROR: Layer failed to validate. URL: {TILE_URL}")
    print("Check that serve-tiles.py is running on the VM and the port is accessible.")
