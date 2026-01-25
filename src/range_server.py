#!/usr/bin/env python3
import os
import sys
from http.server import SimpleHTTPRequestHandler, HTTPServer
import mimetypes

class RangeRequestHandler(SimpleHTTPRequestHandler):
    """
    Adds support for HTTP 'Range' requests to SimpleHTTPRequestHandler
    Needed for QGIS /vsicurl/ to work correctly.
    """
    def end_headers(self):
        # QGIS/GDAL checks this header to determine if it can use /vsicurl/
        self.send_header('Accept-Ranges', 'bytes')
        # Add Cache-Control to prevent stale maps
        self.send_header('Cache-Control', 'no-cache, must-revalidate')
        super().end_headers()

    def send_head(self):
        if 'Range' not in self.headers:
            return super().send_head()
            
        try:
            path = self.translate_path(self.path)
            if not os.path.exists(path) or not os.path.isfile(path):
                self.send_error(404, "File not found")
                return None
                
            f = open(path, 'rb')
        except OSError:
            self.send_error(404, "File not found")
            return None

        ctype = self.guess_type(path)
        
        try:
            file_size = os.fstat(f.fileno()).st_size
            range_header = self.headers['Range']
            # Regex to parse "bytes=0-1023" type headers
            # We support simple "bytes=start-end"
            if not range_header.startswith('bytes='):
                f.close()
                return super().send_head()
                
            range_value = range_header.replace('bytes=', '')
            start_str, end_str = range_value.split('-')
            
            start = int(start_str) if start_str else 0
            end = int(end_str) if end_str else file_size - 1
            
            if start >= file_size:
                self.send_error(416, "Requested Range Not Satisfiable")
                f.close()
                return None
                
            length = end - start + 1
            
            self.send_response(206)
            self.send_header("Content-type", ctype)
            self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
            self.send_header("Content-Length", str(length))
            self.send_header("Last-Modified", self.date_time_string(os.path.getmtime(path)))
            self.end_headers() # This calls our overridden end_headers() adding Accept-Ranges
            
            f.seek(start)
            self.copyfile_range(f, self.wfile, length)
            f.close()
            return None
            
        except Exception as e:
            self.send_error(500, f"Internal Server Error: {e}")
            if f: f.close()
            return None

    def copyfile_range(self, source, outputfile, length):
        """Copies exactly length bytes from source to outputfile"""
        BUFFER_SIZE = 1024 * 64
        bytes_to_read = length
        while bytes_to_read > 0:
            chunk_size = min(BUFFER_SIZE, bytes_to_read)
            data = source.read(chunk_size)
            if not data:
                break
            outputfile.write(data)
            bytes_to_read -= len(data)

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    print(f"Starting Range-Capable HTTP Server on port {port}...")
    server_address = ('', port)
    httpd = HTTPServer(server_address, RangeRequestHandler)
    httpd.serve_forever()
