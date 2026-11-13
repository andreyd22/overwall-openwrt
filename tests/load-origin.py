#!/usr/bin/env python3
"""Bounded isolated throughput source. Never binds a public interface."""
import http.server
class Handler(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  self.send_response(200); self.send_header('Content-Length',str(64*1024*1024)); self.end_headers()
  try:
   block=b'x'*65536
   for _ in range(1024): self.wfile.write(block)
  except (BrokenPipeError, ConnectionResetError): pass
 def log_message(self,*args): pass
http.server.ThreadingHTTPServer(('198.18.77.1',18002),Handler).serve_forever()
