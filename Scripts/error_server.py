#!/usr/bin/env python3
"""Failure-only local fixture. Never supplies speech or mimics a successful backend."""
from http.server import HTTPServer, BaseHTTPRequestHandler
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        status = 401 if self.path.startswith('/unauthorized') else 503
        self.send_response(status); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(b'{"error":"diagnostic fixture"}')
    def log_message(self,*args): pass
HTTPServer(('127.0.0.1',18882),Handler).serve_forever()
