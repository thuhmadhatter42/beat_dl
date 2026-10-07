"""For a harvested session N: track count and the structural (name-safe) track names in its info
export; any name containing 'beat'/'inst'/'music' is shown letter-masked except those words."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
n = int(sys.argv[1])
p = hlib.H / "info" / f"{n:04d}-bb.txt"
if not p.exists():
    print("no info file"); sys.stdout.flush(); os._exit(0)
bb = hlib.parse_info(p.read_text())
names = [re.sub(r"\s*\((Stereo|Mono)\)$", "", t["name"]) for t in bb["tracks"]]
print("tracks", len(names), "with clips", sum(1 for t in bb["tracks"] if t["edl"]))
print("structural:", sorted({nm for nm in names if hlib.safe_track_name(nm) != "<t>"}))
for nm in names:
    if re.search(r"beat|inst|music|bus", nm, re.I) and hlib.safe_track_name(nm) == "<t>":
        print("  masked:", re.sub(r"(?i)(?!beat|inst|music|bus)[a-z]", "a", nm)[:40])
sys.stdout.flush(); os._exit(0)
