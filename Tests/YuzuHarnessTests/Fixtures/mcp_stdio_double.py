#!/usr/bin/env python3
"""Minimal MCP stdio test server: ping -> pong, optional instructions and trace file."""
import json
import os
import sys

INSTRUCTIONS = os.environ.get("MCP_INSTRUCTIONS", "be brief")
TRACE_FILE = os.environ.get("MCP_TRACE_FILE")


def send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def handle(req):
    method = req.get("method")
    req_id = req.get("id")
    if method == "initialize":
        send(
            {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "test", "version": "1.0"},
                    "instructions": INSTRUCTIONS,
                },
            }
        )
    elif method == "notifications/initialized":
        pass
    elif method == "tools/list":
        send(
            {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "tools": [
                        {
                            "name": "ping",
                            "description": "ping",
                            "inputSchema": {"type": "object", "properties": {}},
                        }
                    ]
                },
            }
        )
    elif method == "tools/call":
        if TRACE_FILE:
            with open(TRACE_FILE, "a", encoding="utf-8") as trace:
                trace.write("tools/call\n")
        send(
            {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": "pong"}],
                    "isError": False,
                },
            }
        )
    elif method == "prompts/list":
        send(
            {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "prompts": [
                        {
                            "name": "hello",
                            "description": "hello prompt",
                        }
                    ]
                },
            }
        )
    elif method == "prompts/get":
        send(
            {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "messages": [
                        {
                            "role": "user",
                            "content": {"type": "text", "text": "wave"},
                        }
                    ]
                },
            }
        )
    elif method == "resources/list":
        send(
            {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "resources": [
                        {
                            "uri": "file://note",
                            "name": "note",
                            "mimeType": "text/plain",
                        }
                    ]
                },
            }
        )
    elif method == "resources/read":
        send(
            {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "contents": [
                        {
                            "uri": "file://note",
                            "mimeType": "text/plain",
                            "text": "note-body",
                        }
                    ]
                },
            }
        )


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    handle(json.loads(line))
