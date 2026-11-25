import argparse
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
import json


class Handler(BaseHTTPRequestHandler):
    devices = set()
    valid_key = "MECHA-DEMO-PRO"

    def log_message(self, *_args):
        pass

    def reply(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 4096:
                raise ValueError
            request = json.loads(self.rfile.read(size))
            key, device = request["license_key"], request["device_id"]
            if not device or not isinstance(device, str):
                raise ValueError
        except (TypeError, KeyError, ValueError):
            self.reply(400, {"ok": False, "code": "invalid_request"})
            return
        if key == "MECHA-DEMO-EXPIRED":
            self.reply(410, {"ok": False, "code": "expired"})
        elif key == "MECHA-DEMO-FULL":
            self.reply(409, {"ok": False, "code": "device_limit"})
        elif key != self.valid_key:
            self.reply(404, {"ok": False, "code": "invalid_key"})
        elif self.path == "/api/licenses/activate":
            if not isinstance(request.get("device_name"), str) or not request["device_name"]:
                self.reply(400, {"ok": False, "code": "invalid_request"})
                return
            if device not in self.devices and len(self.devices) == 30:
                self.reply(409, {"ok": False, "code": "device_limit"})
                return
            self.devices.add(device)
            self.reply(200, {
                "ok": True,
                "plan": "pro",
                "expires_at": (datetime.now(timezone.utc) + timedelta(days=30)).isoformat(),
                "devices_used": len(self.devices),
                "devices_max": 30,
            })
        elif self.path == "/api/licenses/deactivate":
            self.devices.discard(device)
            self.reply(200, {"ok": True})
        else:
            self.reply(404, {"ok": False, "code": "not_found"})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    with HTTPServer(("127.0.0.1", parser.parse_args().port), Handler) as server:
        print(f"http://127.0.0.1:{server.server_port}", flush=True)
        server.serve_forever()
