"""Step 2.0/2.1: find .ptx under a root, group by song folder, pick newest per song.
Run on the Mac that has the drive. Emits JSON to stdout. Read-only."""
import sys, json, subprocess
from pathlib import Path
sys.path.insert(0, str(Path.home() / "ProTools SDK" / "stem-bouncer"))
from pt_stems.session_picker import pick_latest_ptx, _date_key

root = Path(sys.argv[1])
method = "mdfind"
r = subprocess.run(["mdfind", "-onlyin", str(root), "kMDItemFSName=*.ptx"],
                   capture_output=True, text=True)
files = [l for l in r.stdout.splitlines() if l.strip()]
if not files:
    method = "find-fallback"
    r = subprocess.run(["find", str(root), "-iname", "*.ptx"], capture_output=True, text=True)
    files = [l for l in r.stdout.splitlines() if l.strip()]
files = [f for f in files if "Session File Backups" not in f]
# song folder = <root>/<artist>/<song>/... ; artist = first component
songs = {}
for f in files:
    rel = Path(f).relative_to(root)
    if len(rel.parts) < 3:
        continue
    songs.setdefault((rel.parts[0], rel.parts[1]), []).append(f)
out = {"method": method, "total_ptx": len(files), "song_folders": len(songs), "picked": []}
for (artist, song), _ in sorted(songs.items()):
    p = pick_latest_ptx(root / artist / song)
    if p:
        out["picked"].append({"artist": artist, "song": song, "ptx": str(p), "date": list(_date_key(p.name))})
json.dump(out, sys.stdout)
