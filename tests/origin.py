#!/usr/bin/env python3
"""An isolated WAN fixture; no production endpoints or customer credentials."""
import http.server
import socketserver
import threading

class HTTP(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'overwall-lab-origin')
    def log_message(self, *_):
        pass
class UDP(socketserver.BaseRequestHandler):
    def handle(self):
        data, sock = self.request
        sock.sendto(data, self.client_address)
threading.Thread(target=socketserver.UDPServer(('198.18.77.1', 18001), UDP).serve_forever, daemon=True).start()
http.server.HTTPServer(('198.18.77.1', 18000), HTTP).serve_forever()
