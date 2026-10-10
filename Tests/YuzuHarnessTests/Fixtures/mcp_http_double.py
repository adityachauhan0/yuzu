#!/usr/bin/env python3
"""Streamable-HTTP-style MCP test server with bearer auth."""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

BEARER = os.environ.get("MCP_HTTP_BEARER", "test-token")
AUTH_TRACE = os.environ.get("MCP_HTTP_AUTH_TRACE")


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        auth = self.headers.get("Authorization", "")
        if auth != f"Bearer {BEARER}":
            self.send_response(401)
            self.end_headers()
            return
        if AUTH_TRACE:
            with open(AUTH_TRACE, "a", encoding="utf-8") as trace:
                trace.write(auth + "\n")
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        req = json.loads(body)
        method = req.get("method")
        req_id = req.get("id")
        if method == "notifications/initialized":
            self.send_response(202)
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()
            return
        if method == "initialize":
            result = {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "test", "version": "1.0"},
            }
        elif method == "tools/list":
            result = {
                "tools": [
                    {
                        "name": "ping",
                        "description": "ping",
                        "inputSchema": {"type": "object", "properties": {}},
                    }
                ]
            }
        elif method == "tools/call":
            result = {
                "content": [{"type": "text", "text": "pong"}],
                "isError": False,
            }
        else:
            result = {}
        payload = json.dumps({"jsonrpc": "2.0", "id": req_id, "result": result}).encode(
            "utf-8"
        )
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, _format, *_args):
        pass


def main():
    port = int(os.environ.get("MCP_HTTP_PORT", "0"))
    server = HTTPServer(("127.0.0.1", port), Handler)
    host, bound_port = server.server_address
    print(f"READY {bound_port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
