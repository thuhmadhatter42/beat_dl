#!/usr/bin/env python3
"""Verify-labels server: one page to confirm BPM + key labels of harvested beats.

Stdlib only. Binds 127.0.0.1. Serves index.html, audio (Range), and a JSON API.
Answers go to verify-labels.sqlite3 next to the ground-truth DB (never the source DB).
Errors (server + page beacons) -> logs/server.log beside this file.

Run:  python3 tools/verify-labels/server.py [--port 8765]
"""
import argparse
import json
import logging
import os
import re
import sqlite3
import sys
import traceback
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = "/Users/jshriver/dev/beat_dl/docs/research/pt-ground-truth"
SRC_DB = os.path.join(DATA, "pt-ground-truth.sqlite3")
AUDIO = os.path.join(DATA, "audio11k")
ANS_DB = os.path.join(DATA, "verify-labels.sqlite3")
LOG_DIR = os.path.join(HERE, "logs")
os.makedirs(LOG_DIR, exist_ok=True)

logging.basicConfig(
    filename=os.path.join(LOG_DIR, "server.log"),
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("verify")


def _excepthook(t, v, tb):
    log.error("uncaught: %s", "".join(traceback.format_exception(t, v, tb)))
    sys.__excepthook__(t, v, tb)


sys.excepthook = _excepthook

ANS_SCHEMA = """
CREATE TABLE IF NOT EXISTS answers (
    id          INTEGER PRIMARY KEY,   -- sessions.id in pt-ground-truth.sqlite3
    bpm_ok      INTEGER,               -- 1 yes, 0 no, NULL unanswered
    bpm_fixed   REAL,                  -- metronome BPM when bpm_ok = 0
    key_ok      INTEGER,               -- 1 yes, 0 no, NULL unanswered / no label
    key_fixed   TEXT,                  -- Auto-Tune spelling: C, Db, ... / Cm, C#m, ...
    phase_ms    REAL,                  -- click grid offset used (ms from file start)
    note        TEXT,
    skipped     INTEGER NOT NULL DEFAULT 0,
    answered_at TEXT NOT NULL          -- local time
) STRICT;
"""


def ans_conn():
    c = sqlite3.connect(ANS_DB, timeout=10)
    c.row_factory = sqlite3.Row
    return c


def init_db():
    with ans_conn() as c:
        c.executescript(ANS_SCHEMA)


def audio_file(rel):
    if not rel:
        return None
    p = os.path.join(AUDIO, os.path.basename(rel))
    return os.path.basename(rel) if os.path.isfile(p) else None


def load_items():
    src = sqlite3.connect(f"file:{SRC_DB}?mode=ro", uri=True)
    src.row_factory = sqlite3.Row
    rows = src.execute(
        "SELECT id,status,bpm,bpm_source,bpm_confidence,key,key_source,autotune_key,"
        "comment_key,comment_bpm,beatdl_estimate,beat_wav_path,mix_wav_path,"
        "beat_duration_s,mix_duration_s FROM sessions ORDER BY id"
    ).fetchall()
    src.close()
    items = []
    for r in rows:
        beat = audio_file(r["beat_wav_path"])
        mix = audio_file(r["mix_wav_path"])
        if not beat and not mix:
            continue
        d = dict(r)
        d["beat_file"] = beat
        d["mix_file"] = mix
        items.append(d)
    return items


ITEMS = []


def answers_map():
    with ans_conn() as c:
        return {r["id"]: dict(r) for r in c.execute("SELECT * FROM answers")}


class H(BaseHTTPRequestHandler):
    server_version = "verify-labels/0.1"

    def log_message(self, fmt, *args):
        pass  # quiet; errors are logged explicitly

    def _json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(b)

    def _err(self, code, msg):
        log.error("%s %s -> %d %s", self.command, self.path, code, msg)
        self._json({"ok": False, "error": msg}, code)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def do_GET(self):
        try:
            path = urlparse(self.path).path
            if path in ("/", "/index.html"):
                return self._file(os.path.join(HERE, "index.html"), "text/html; charset=utf-8")
            if path == "/api/items":
                return self._json({"items": ITEMS, "answers": answers_map()})
            m = re.fullmatch(r"/audio/(\d{4}(?:_mix)?\.wav)", path)
            if m:
                return self._file(os.path.join(AUDIO, m.group(1)), "audio/wav", rng=True)
            if path == "/favicon.ico":
                self.send_response(204)
                self.end_headers()
                return
            return self._err(404, "not found")
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            log.error("GET %s: %s", self.path, traceback.format_exc())
            try:
                self._json({"ok": False, "error": str(e)}, 500)
            except Exception:
                pass

    def do_POST(self):
        try:
            path = urlparse(self.path).path
            if path == "/api/answer":
                return self._save(self._body())
            if path == "/api/delete":
                d = self._body()
                with ans_conn() as c:
                    c.execute("DELETE FROM answers WHERE id=?", (int(d["id"]),))
                return self._json({"ok": True})
            if path == "/api/clientlog":
                d = self._body()
                log.error("CLIENT %s", json.dumps(d)[:4000])
                return self._json({"ok": True})
            return self._err(404, "not found")
        except Exception as e:
            log.error("POST %s: %s", self.path, traceback.format_exc())
            try:
                self._json({"ok": False, "error": str(e)}, 500)
            except Exception:
                pass

    def _save(self, d):
        iid = int(d["id"])
        if iid not in {i["id"] for i in ITEMS}:
            return self._err(400, f"unknown id {iid}")

        def opt_int(v):
            return None if v is None else int(v)

        def opt_float(v):
            return None if v in (None, "") else float(v)

        row = (
            iid,
            opt_int(d.get("bpm_ok")),
            opt_float(d.get("bpm_fixed")),
            opt_int(d.get("key_ok")),
            (d.get("key_fixed") or None),
            opt_float(d.get("phase_ms")),
            (d.get("note") or None),
            1 if d.get("skipped") else 0,
            datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        )
        with ans_conn() as c:
            c.execute(
                "INSERT INTO answers(id,bpm_ok,bpm_fixed,key_ok,key_fixed,phase_ms,note,skipped,answered_at)"
                " VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET bpm_ok=excluded.bpm_ok,"
                " bpm_fixed=excluded.bpm_fixed, key_ok=excluded.key_ok, key_fixed=excluded.key_fixed,"
                " phase_ms=excluded.phase_ms, note=excluded.note, skipped=excluded.skipped,"
                " answered_at=excluded.answered_at",
                row,
            )
            saved = dict(c.execute("SELECT * FROM answers WHERE id=?", (iid,)).fetchone())
        log.info("saved %s", json.dumps(saved))
        return self._json({"ok": True, "answer": saved})

    def _file(self, p, ctype, rng=False):
        if not os.path.isfile(p):
            return self._err(404, f"missing {os.path.basename(p)}")
        size = os.path.getsize(p)
        start, end = 0, size - 1
        partial = False
        h = self.headers.get("Range")
        if rng and h:
            m = re.fullmatch(r"bytes=(\d*)-(\d*)", h.strip())
            if not m:
                return self._err(416, f"bad range {h}")
            if m.group(1):
                start = int(m.group(1))
                if m.group(2):
                    end = min(int(m.group(2)), size - 1)
            else:
                start = max(0, size - int(m.group(2)))
            if start > end:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.end_headers()
                return
            partial = True
        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", ctype)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Cache-Control", "no-store" if ctype.startswith("text/html") else "max-age=3600")
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        with open(p, "rb") as f:
            f.seek(start)
            left = end - start + 1
            while left > 0:
                chunk = f.read(min(65536, left))
                if not chunk:
                    break
                self.wfile.write(chunk)
                left -= len(chunk)


def main():
    global ITEMS
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    a = ap.parse_args()
    init_db()
    ITEMS = load_items()
    log.info("start port=%d items=%d answers_db=%s", a.port, len(ITEMS), ANS_DB)
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), H)
    print(f"verify-labels: http://127.0.0.1:{a.port}/  items={len(ITEMS)}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    log.info("stop")


if __name__ == "__main__":
    main()
