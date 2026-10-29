#!/usr/bin/env python3
"""beatkey.jshriver.com: J's friends-only Beat Key download. Email in (no confirmation), logged, then
redirect to the GitHub DMG of the current version (read from the FLR site's beat-key-latest.json)."""
import json, re, time, html
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import parse_qs

HERE = Path(__file__).resolve().parent
LOG = HERE / "downloads.jsonl"
LATEST = Path.home() / "fourletterrecords" / "beat-key-latest.json"
EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

def version():
    try:
        v = json.loads(LATEST.read_text())["version"]
        if re.fullmatch(r"\d+\.\d+\.\d+", v): return v
    except Exception: pass
    return "0.1.18"

def dmg_url(v):
    return f"https://github.com/thuhmadhatter42/beat_dl/releases/download/Beat-Key-{v}/Beat-Key-{v}.dmg"

class H(BaseHTTPRequestHandler):
    def send(self, code, body, ctype="text/html; charset=utf-8", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items(): self.send_header(k, v)
        self.end_headers()
        if isinstance(body, str): body = body.encode()
        self.wfile.write(body)

    def page(self, msg=""):
        t = (HERE / "index.html").read_text()
        return t.replace("{{VERSION}}", version()).replace("{{MSG}}", html.escape(msg))

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/": return self.send(200, self.page())
        if p == "/icon.png": return self.send(200, (HERE / "icon.png").read_bytes(), "image/png")
        self.send(404, "")

    def do_POST(self):
        if self.path.split("?")[0] != "/download": return self.send(404, "")
        n = min(int(self.headers.get("Content-Length") or 0), 2048)
        email = (parse_qs(self.rfile.read(n).decode("utf-8", "replace")).get("email") or [""])[0].strip()[:200]
        if not EMAIL.match(email): return self.send(400, self.page("That email doesn't look right."))
        v = version()
        rec = {"time": time.strftime("%Y-%m-%d %H:%M:%S"), "email": email, "version": v,
               "ip": self.headers.get("CF-Connecting-IP") or self.client_address[0]}
        with LOG.open("a") as f: f.write(json.dumps(rec) + "\n")
        self.send(303, "", extra={"Location": dmg_url(v)})

    def log_message(self, *a): pass

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8171), H).serve_forever()
