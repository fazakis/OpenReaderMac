"""Loopback-only HTTP fixture for bounded speech-error handling; no real TTS."""
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        case = request["voice"]
        status, mime = 422, "application/json"
        body = json.dumps({"detail": {"message": "Unsupported characters: U+001B. Use Select screen region.",
                                     "input": "PRIVATE-FIXTURE-INPUT"}}).encode()
        if case == "oversized":
            body = json.dumps({"detail": "x" * 20000}).encode()
        elif case == "html":
            mime, body = "text/html", b"<html>PRIVATE-FIXTURE-INPUT</html>"
        elif case == "unauthorized":
            status = 401
        elif case == "unavailable":
            status = 503
        elif case == "success":
            status = 200
            pcm = b"\x01\x00" * 4800
            if self.path == "/dev/captioned_speech":
                body = json.dumps({"audio": base64.b64encode(pcm).decode(), "audio_format": "audio/pcm", "timestamps": []}).encode()
            else:
                mime, body = "audio/pcm", pcm
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Expected when the client rejects an oversized error response.


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
