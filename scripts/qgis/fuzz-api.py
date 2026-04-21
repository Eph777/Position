#!/usr/bin/env python3
import urllib.request
import urllib.error
import re

print("=======================================")
print("  Luanti Mapserver API Discovery Tool")
print("=======================================\n")

# Base URLs to test
base_urls = [
    "http://192.168.2.14:8080",
    "http://localhost:8080",
    "http://127.0.0.1:8080"
]

found_url = None

for url in base_urls:
    print(f"[*] Probing {url} for Web UI...")
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=3) as response:
            html = response.read().decode('utf-8')
            print(f"   [+] Web UI reached! Parsing javascript configuration...")
            
            # Find Leaflet TileLayer or similar configuration
            # Looking for typical URLs like '/api/tile/{id}/{z}/{x}/{y}'
            
            # Use regex to search for API patterns
            tile_patterns = re.findall(r"['\"](/.*?\{z\}.*?)['\"]", html)
            if tile_patterns:
                print(f"   [SUCCESS] Native Tile Endpoint Discovered in HTML:")
                for tp in tile_patterns:
                    print(f"       -> {tp}")
                found_url = tile_patterns[0]
                break
            else:
                # Often it's loaded dynamically via a config.json or API endpoint
                print("   [~] No inline tile URL found. Checking for /api/config or mapserver.json...")
                config_urls = [f"{url}/api/config", f"{url}/mapserver.json", f"{url}/config.json"]
                for curl in config_urls:
                    try:
                        with urllib.request.urlopen(curl, timeout=2) as cres:
                            config_data = cres.read().decode('utf-8')
                            if 'tile' in config_data or 'url' in config_data:
                                print(f"   [+] Found configuration file: {curl}")
                                print(config_data[:500])  # Print first 500 chars to review
                    except:
                        pass
                break
    except urllib.error.URLError:
        print(f"   [-] Unreachable.")
    except Exception as e:
        print(f"   [-] Error: {str(e)}")

print("\n=======================================")

if not found_url:
    print("\nFallback: Blind-Fuzzing Origin Tile (0,0) across known patterns...\n")
    # If we couldn't parse the JS, let's just hammer the API with possibilities
    # We will test layer 1 and layer 0, zoom 1
    patterns = [
        "/api/tile/{layer}/{x}/{y}/{z}",
        "/api/tile/{layer}/{z}/{x}/{y}",
        "/api/tiles/{layer}/{x}/{y}/{z}",
        "/api/tiles/{layer}/{z}/{x}/{y}",
        "/tiles/{layer}/{z}/{x}/{y}.png",
        "/tiles/{layer}/{x}/{y}/{z}.png",
        "/{layer}/{z}/{x}/{y}.png",
    ]
    
    server = [u for u in base_urls if u != "http://localhost:8080"][0] 
    # Use 192.168.2.14 preferably
    server = "http://192.168.2.14:8080"
    
    for layer in ["0", "1", "base"]:
        for pattern in patterns:
            # We request X:0, Y:0 at Z:1 because the origin almost always exists
            test_path = pattern.replace("{layer}", layer).replace("{z}", "1").replace("{x}", "0").replace("{y}", "0")
            test_url = server + test_path
            
            try:
                with urllib.request.urlopen(test_url, timeout=1) as response:
                    content_type = response.headers.get('Content-Type', '')
                    if 'image' in content_type:
                        print(f"[FOUND IMAGE!] Correct Format is: {pattern} (Layer: {layer})")
                        found_url = pattern
                        break
            except:
                pass
        if found_url:
            break
