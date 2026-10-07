"""Show, letter-masked, the context around every 'bpm' in session N's file and clip names, so the
beat_dl-pattern exclusion can be checked without printing a name ('a' = any letter)."""
import os, re, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
n = int(sys.argv[1])
bb = hlib.parse_info((hlib.H / "info" / f"{n:04d}-bb.txt").read_text())
names = list(bb["files"]) + [e["clip"] for t in bb["tracks"] for e in t["edl"]]
ctx = Counter()
for nm in names:
    for m in re.finditer(r"bpm", nm, re.I):
        s = nm[max(0, m.start() - 12): m.end() + 12]
        ctx[re.sub(r"[A-Za-z]", "a", s) + ("  [beat_dl-excluded]" if hlib._BEATDL.search(nm) else "")] += 1
for k, v in ctx.most_common(20):
    print(v, repr(k))
print("producer_bpms over all names:", hlib.producer_bpms(names))
sys.stdout.flush(); os._exit(0)
