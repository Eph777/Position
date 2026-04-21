import urllib.parse
import socket
from qgis.core import QgsRasterLayer, QgsProject, QgsCoordinateReferenceSystem

# =========================================================
# LUANTI MAPSERVER QGIS INTEGRATION SCRIPT
# Copy and paste this script directly into the QGIS Python Console
# =========================================================

# Dynamically lookup IP so the user doesn't have to change it!
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(("8.8.8.8", 80))
    IP_ADDRESS = s.getsockname()[0]
except Exception:
    IP_ADDRESS = "127.0.0.1"
finally:
    s.close()

PROXY_URL = f"http://{IP_ADDRESS}:5050/tiles/{{z}}/{{x}}/{{y}}"

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
else:
    print("Error: QGIS failed to validate the layer.")
