"""Explore the Edit window AX tree for insert slots holding a plug-in matching argv[1] (default
'Auto-Tune'). Prints roles, attribute NAMES and the matched plug-in text only (never track names)."""
import os, re, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dialog_clicker as dc
pat = re.compile(sys.argv[1] if len(sys.argv) > 1 else "Auto-?Tune", re.I)
edit = next((d for d in dc.windows() if d["title"].startswith("Edit:")), None)
if not edit:
    print("no Edit window"); sys.stdout.flush(); os._exit(0)
roles = Counter(); hits = []
stack = [(edit["el"], 0, "")]
seen = 0
while stack:
    el, depth, path = stack.pop()
    seen += 1
    role = dc._ax(el, "AXRole")
    roles[str(role)] += 1
    vals = {a: dc._ax(el, a) for a in ("AXTitle", "AXDescription", "AXValue", "AXHelp", "AXRoleDescription")}
    txt = " | ".join(f"{k}={v}" for k, v in vals.items() if isinstance(v, str) and v)
    if pat.search(txt):
        m = [f"{k}~{pat.search(v)[0]}" for k, v in vals.items() if isinstance(v, str) and pat.search(v)]
        hits.append((depth, str(role), path, m, [k for k, v in vals.items() if isinstance(v, str) and v]))
    if depth < 12:
        kids = dc._ax(el, "AXChildren") or []
        stack += [(k, depth + 1, f"{path}/{str(role)[2:6]}{i}") for i, k in enumerate(kids)]
print("elements", seen, "roles", roles.most_common(12))
print("hits", len(hits))
for h in hits[:15]:
    print(h)
sys.stdout.flush(); os._exit(0)
