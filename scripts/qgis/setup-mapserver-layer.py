import urllib.parse
from qgis.core import QgsRasterLayer, QgsProject, QgsCoordinateReferenceSystem, QgsRectangle
from qgis.utils import iface

# =========================================================
# LUANTI NATIVE MAPSERVER QGIS INTEGRATION
# Execute this strictly inside the QGIS Python Console
# =========================================================

# The target is the Multipass VM IP. 
# Our custom static python server exposes standard `.png` tiles.
TILE_SERVER_URL = "http://192.168.2.14:8080/{z}/{x}/{y}.png"
Z_MIN = 6
Z_MAX = 13 

params = {
    'type': 'xyz',
    'url': TILE_SERVER_URL,
    'zMin': str(Z_MIN),
    'zMax': str(Z_MAX),
}

encoded_url = urllib.parse.urlencode(params)
layer = QgsRasterLayer(encoded_url, "Luanti Native Map", "wms")

# Crucially lock it to EPSG:3857 since our Python generator physically 
# projects chunks into Slippy Map grid positions using minetestmapper bounds.
crs = QgsCoordinateReferenceSystem("EPSG:3857")
layer.setCrs(crs)

if layer.isValid():
    QgsProject.instance().addMapLayer(layer)
    print(f"Success! Native layer attached to {TILE_SERVER_URL}")
    
    if iface:
        canvas = iface.mapCanvas()
        
        # Warp the QGIS Camera mathematically onto the Origin chunk of your Minetest World (Tile(0, 0) at Zoom 13)
        # Because we output standard XYZ files, empty space returns 404 natively!
        extent = QgsRectangle(-10000, -10000, 10000, 10000)
        canvas.setExtent(extent)
        canvas.refresh()
        
        print("-> QGIS Camera locked onto Minetest map origin.")
else:
    print("Error: QGIS failed to validate the layer.")
