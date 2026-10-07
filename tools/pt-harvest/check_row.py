"""Name-free check of one harvested row: DB row, files on Sofia, and that nothing new landed in the
session's own folder on the source drive (counts only)."""
import json, os, sqlite3, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
from hlib import H
n = int(sys.argv[1])
con = sqlite3.connect(H / "pt-ground-truth.sqlite3"); con.row_factory = sqlite3.Row
r = con.execute("SELECT * FROM sessions WHERE id=?", (n,)).fetchone()
print({k: r[k] for k in r.keys() if r[k] is not None and k not in ("ptx_sha1",)})
for p in (H / "audio" / f"{n:04d}.wav", H / "audio11k" / f"{n:04d}.wav"):
    print(p.relative_to(H), p.exists() and f"{p.stat().st_size/1e6:.1f} MB {hlib.duration_s(p)} s")
e = hlib.entry(n)
sess_dir = os.path.dirname(e["ptx"])
recent = 0
for root, dirs, files in os.walk(sess_dir):
    for f in files:
        try:
            if time.time() - os.path.getmtime(os.path.join(root, f)) < float(sys.argv[2] if len(sys.argv) > 2 else 3600):
                recent += 1
                parent = os.path.basename(root)
                known = parent if parent in ("Session File Backups", "Audio Files", "Bounced Files", "WaveCache",
                                             "Clip Groups", "Rendered Files", "Video Files") else \
                    ("<session dir>" if root == sess_dir else "<other dir>")
                print("  modified:", known, os.path.splitext(f)[1] or "<no ext>",
                      time.strftime("%H:%M:%S", time.localtime(os.path.getmtime(os.path.join(root, f)))))
        except OSError:
            pass
print("files modified on the source drive in this session folder in the window:", recent)
sys.stdout.flush(); os._exit(0)
