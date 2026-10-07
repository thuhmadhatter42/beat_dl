"""How do Edit-window strip AX titles relate to PTSL track names? Prints templates only
(the matched track name replaced by <NAME>); never a name."""
import os, re, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
import dialog_clicker as dc
c = hlib.client()
names = sorted({t["name"] for t in hlib.tracks(c)}, key=len, reverse=True)
edit = next((d for d in dc.windows() if d["title"].startswith("Edit:")), None)
tmpl = Counter(); unmatched = 0
for s in dc._ax(edit["el"], "AXChildren") or []:
    if dc._ax(s, "AXRole") != "AXGroup":
        continue
    st = str(dc._ax(s, "AXTitle") or "")
    hit = next((nm for nm in names if nm and nm in st), None)
    if hit:
        tmpl[re.sub(r"[A-Za-z]", "a", st.replace(hit, "<NAME>"))[:60]] += 1
    else:
        unmatched += 1
        tmpl["UNMATCHED len=%d" % len(st)] += 1
for k, v in tmpl.most_common(15):
    print(v, repr(k))
sys.stdout.flush(); os._exit(0)
