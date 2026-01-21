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
    def send_head(self):
        if 'Range' not in self.headers:
            return super().send_head()
            
        try:
            path = self.translate_path(self.path)
            f = open(path, 'rb')
        except OSError:
            self.send_error(404, "File not found")
            return None

        ctype = self.guess_type(path)
        
        # Parse Range header
        # Range: bytes=0-1023
        try:
            range_value = self.headers['Range']
            start, end = range_value.replace('bytes=', '').split('-')
            file_size = os.fstat(f.fileno()).st_size
            start = int(start) if start else 0
            end = int(end) if end else file_size - 1
            
            if start >= file_size:
                self.send_error(416, "Requested Range Not Satisfiable")
                return None
                
            length = end - start + 1
            
            self.send_response(206)
            self.send_header("Content-type", ctype)
            self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
            self.send_header("Content-Length", str(length))
            self.send_header("Last-Modified", self.date_time_string(os.path.getmtime(path)))
            self.send_header("Accept-Ranges", "bytes")
            self.end_headers()
            
            f.seek(start)
            # We return the file object, but wrapper to limit reading
            # SimpleHTTPRequestHandler.copyfile will read until EOF, which is wrong for Range
            # So we must handle the body sending here for Range requests and return None to signal done
            
            self.copyfile_range(f, self.wfile, length)
            f.close()
            return None
            
        except Exception as e:
            self.send_error(500, f"Internal Server Error: {e}")
            if f: f.close()
            return None

    def copyfile_range(self, source, outputfile, length):
        """Copies exactly length bytes from source to outputfile"""
        BUFFER_SIZE = 1024 * 16
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
