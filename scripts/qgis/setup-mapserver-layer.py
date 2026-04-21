import urllib.parse
from qgis.core import QgsRasterLayer, QgsProject, QgsCoordinateReferenceSystem

# =========================================================
# LUANTI MAPSERVER QGIS INTEGRATION SCRIPT
# Copy and paste this script directly into the QGIS Python Console
# (Menu: Plugins -> Python Console)
# =========================================================

# 1. Configuration
# We now point QGIS to the LOCAL PYTHON PROXY running on your Mac.
# The Proxy handles the messy translation of web mercator Slippy tiles to Mapserver Coordinates.
PROXY_URL = "http://127.0.0.1:5000/tiles/{z}/{x}/{y}"

# Adjust minimum and maximum zoom depending on your world's size in mapserver.json
Z_MIN = 1
Z_MAX = 13 

# 2. Build the exact XYZ parameters string required by QgsRasterLayer
url_template = PROXY_URL

params = {
    'type': 'xyz',
    'url': url_template,
    'zMin': str(Z_MIN),
    'zMax': str(Z_MAX),
}

# 3. Create the WMS/XYZ Provider Connection string
# QGIS uses URL encoded parameters for the WMS driver configuration.
encoded_url = urllib.parse.urlencode(params)

print(f"Attempting to add Mapserver Tile Server: {url_template}")

# 4. Initialize the Layer
# The driver name for XYZ tiles in QGIS is actually 'wms' (it acts as a generic web tile provider)
layer = QgsRasterLayer(encoded_url, "Luanti Live Map", "wms")

# 5. Handle CRS (Coordinate Reference System)
# Mapserver translates Minetest X/Z coordinates directly into tile mapping.
# Typically, Web Mercator (EPSG:3857) is assumed by QGIS for all XYZ tiles.
# We will set it explicitly.
crs = QgsCoordinateReferenceSystem("EPSG:3857")
layer.setCrs(crs)

# 6. Apply Layer to QGIS Canvas
if layer.isValid():
    QgsProject.instance().addMapLayer(layer)
    print("Success! Luanti Mapserver layer added to QGIS.")
    print("Note: Because Minetest has a non-earth coordinate system, Earth maps (like OpenStreetMap) will not align perfectly natively without a custom CRS matrix.")
else:
    print("Error: QGIS failed to validate the layer. Check your network connection to the server or verify Mapserver is actively serving.")
