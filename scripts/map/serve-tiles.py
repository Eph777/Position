#!/usr/bin/env python3
import http.server
import socketserver
import argparse
import sys

class CORSRequestHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        return super(CORSRequestHandler, self).end_headers()
        
    def log_message(self, format, *args):
        # Mute logging to prevent terminal spam
        pass

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Static Native Tile Server")
    parser.add_argument("--port", type=int, default=8080, help="Port to serve on")
    parser.add_argument("--dir", type=str, default=".", help="Directory of tiles to serve")
    args = parser.parse_args()

    import os
    os.chdir(args.dir)

    print(f"==========================================")
    print(f" Luanti Native Tile Server (XYZ Slippy)   ")
    print(f"==========================================")
    print(f" Serving Directory: {os.path.abspath(args.dir)}")
    print(f" Address: http://0.0.0.0:{args.port}/")
    print(f" Endpoint format for QGIS: http://<IP>:{args.port}/{{z}}/{{x}}/{{y}}.png")
    print(f"==========================================")
    
    with socketserver.ThreadingTCPServer(("0.0.0.0", args.port), CORSRequestHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server...")
            sys.exit(0)
