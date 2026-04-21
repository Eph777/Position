import urllib.parse
from qgis.core import QgsRasterLayer, QgsProject, QgsCoordinateReferenceSystem, QgsRectangle
from qgis.utils import iface

# =========================================================
# LUANTI MAPSERVER QGIS INTEGRATION SCRIPT
# Execute this strictly in the QGIS Python Console
# =========================================================

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

# Force QGIS to realize this map lives on Spherical Slippy Coordinates
crs = QgsCoordinateReferenceSystem("EPSG:3857")
layer.setCrs(crs)

if layer.isValid():
    QgsProject.instance().addMapLayer(layer)
    print(f"Success! Mapserver layer injected connecting to {PROXY_URL}")
    
    # CRITICAL: Snap QGIS Camera strictly to Minetest Map Bounds
    if iface:
        canvas = iface.mapCanvas()
        
        # We manually snap the camera exactly to (0,0) with a 15km viewport radius
        # If QGIS zooms out further, Mapserver blank tiles will be filtered by the proxy
        # as transparent, preserving the geometry visibility instead of painting White void!
        extent = QgsRectangle(-15000, -15000, 15000, 15000)
        canvas.setExtent(extent)
        canvas.refresh()
        
        print("-> QGIS Camera locked onto Minetest map geometries.")
else:
    print("Error: QGIS failed to validate the layer.")
