import urllib.parse
from qgis.core import QgsRasterLayer, QgsProject, QgsCoordinateReferenceSystem, QgsRectangle
from qgis.utils import iface

# =========================================================
# LUANTI MAPSERVER QGIS INTEGRATION SCRIPT
# Copy and paste this script directly into the QGIS Python Console
# =========================================================

# The Proxy listens on localhost (127.0.0.1) on port 5050
PROXY_URL = "http://127.0.0.1:5050/tiles/{z}/{x}/{y}"

Z_MIN = 1
Z_MAX = 13 

params = {
    'type': 'xyz',
    'url': PROXY_URL,
    'zMin': str(Z_MIN),
    'zMax': str(Z_MAX),
}

encoded_url = urllib.parse.urlencode(params)

layer = QgsRasterLayer(encoded_url, "Luanti Live Map", "wms")

crs = QgsCoordinateReferenceSystem("EPSG:3857")
layer.setCrs(crs)

if layer.isValid():
    QgsProject.instance().addMapLayer(layer)
    print(f"Success! Proxy mapped to ({PROXY_URL})")
    
    # MAGIC FIX: Snap QGIS Camera exactly to the Equator (0,0) where the map lives!
    # Because XYZ maps cover the whole Earth, if you aren't at the exact center, everything is blank!
    if iface:
        canvas = iface.mapCanvas()
        # Create a tiny bounding box at point (0,0) exactly
        extent = QgsRectangle(-15000, -15000, 15000, 15000)
        canvas.setExtent(extent)
        canvas.refresh()
        print("-> Camera snapped directly to your Game World!")
else:
    print("Error: QGIS failed to validate the layer.")
