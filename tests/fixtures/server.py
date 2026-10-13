#!/usr/bin/env python3
"""Local endpoints for the spec, so no test ever probes a real site.

Prints the port it is listening on, then serves until killed.
"""
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATUS = {"/ok": 200, "/redirect": 302, "/error": 500, "/slow-error": 500}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/slow"):
            time.sleep(1.5)
        code = STATUS.get(self.path, 404)
        self.send_response(code)
        if code == 302:
            self.send_header("Location", "/ok")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
