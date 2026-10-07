"""Calibrate audiocheck on bounces in ~/pt-harvest/audio (ids only). Usage:
  calib.py db                 every DB row with a beat wav: 3 windows of 8 s (25/50/75 %)
  calib.py file <rel> [tempo] one file under ~/pt-harvest (3 windows)"""
import json, os, sqlite3, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audiocheck as ac
import hlib
from hlib import H


def run(rel, tempo, tag):
    p = H / rel
    d = hlib.duration_s(p) or 0
    for frac in (0.25, 0.5, 0.75):
        fe = ac.features(p, tempo, start=max(d * frac - 4, 0), dur=8) if d > 10 else ac.features(p, tempo)
        lab = ac.verdict(fe)
        print(tag, frac, lab, json.dumps({k: fe.get(k) for k in ("mean_db", "sub", "low", "voice", "air", "flat",
                                                                   "onset_rate", "pulse", "lowpulse", "pulse_any")}))


if sys.argv[1] == "db":
    con = sqlite3.connect(H / "pt-ground-truth.sqlite3")
    for i, path, tempo in con.execute("SELECT id, beat_wav_path, session_tempo FROM sessions WHERE beat_wav_path IS NOT NULL"):
        run(path, tempo, f"#{i:04d}")
else:
    run(sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else None, "file")
sys.stdout.flush(); os._exit(0)
