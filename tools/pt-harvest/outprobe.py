"""Dev aid: main-output signal path id per track of the open session, grouped (name-free)."""
import collections, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
c = hlib.client()
tl = hlib.tracks(c)
st, b = c.status_of("CId_GetTrackMainOutputAssignments", {"track_ids": [t["id"] for t in tl]})
print("status", st, "keys", list(b.keys()) if isinstance(b, dict) else type(b))
ids = (b or {}).get("signalpath_ids") or []
print("n ids", len(ids), "n tracks", len(tl))
if len(ids) == len(tl):
    g = collections.defaultdict(list)
    for t, i in zip(tl, ids):
        g[i].append(f'{hlib.safe_track_name(t["name"])}:{t["type"][6:]}')
    for i, m in g.items():
        print(i, len(m), m[:12])
for t in tl[:3]:
    st, b = c.status_of("CId_GetTrackMainOutputAssignments", {"track_ids": [t["id"]]})
    print(t["type"], st, b)
sys.stdout.flush(); os._exit(0)
