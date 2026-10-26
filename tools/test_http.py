#!/usr/bin/env python3
"""Integration test for the optional loopback adapter; no external networking."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
requests = []

class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        requests.append(request)
        scenario = request["messages"][-1]["content"]
        code = 200
        headers = {}
        body = {"choices": [{"message": {"content": "Русский / 中文 / English"}}]}
        if scenario == "invalid_json":
            body = b"{broken"
        elif scenario == "bad_shape":
            body = {"choices": "wrong"}
        elif scenario == "tool_only":
            body = {"choices": [{"message": {"tool_calls": [{"function": {"name": "shell.exec"}}]}}]}
        elif scenario == "http_error":
            code = 503
        elif scenario == "redirect":
            code = 302
            headers["Location"] = "http://127.0.0.1:1/not-followed"
        elif scenario == "slow":
            time.sleep(0.3)
        payload = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        for name, value in headers.items():
            self.send_header(name, value)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        try:
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError):
            pass

def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python tools/test_http.py /path/to/godot")
    # Binding rather than probing: a busy port is an explicit test setup failure.
    server = ThreadingHTTPServer(("127.0.0.1", 9931), Fixture)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        env = dict(os.environ)
        env["HTTP_PROXY"] = "http://127.0.0.1:1"
        env["HTTPS_PROXY"] = "http://127.0.0.1:1"
        result = subprocess.run(
            [sys.argv[1], "--headless", "--path", str(ROOT), "--script",
             "res://tests/test_http.gd", "--", "--test-mode"], env=env, timeout=30)
        if result.returncode:
            return result.returncode
        if not requests:
            raise AssertionError("No fixture requests reached the adapter")
        if any(r.get("max_tokens", 0) > 512 for r in requests):
            raise AssertionError("Token budget was not bounded")
        if any("tools" in r or r.get("stream") is not False for r in requests):
            raise AssertionError("Foundation must not enable model tools or streaming")
        print(f"HTTP_FIXTURE_OK: {len(requests)} requests; proxies bypassed; payload bounded")
        return 0
    finally:
        server.shutdown()
        server.server_close()

if __name__ == "__main__":
    raise SystemExit(main())

