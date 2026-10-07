"""Name-free probe of the open session's CId_GetTrackList fields (dev aid for beatfind.py).
Prints field names/types and values only for non-name fields; names are shown as safe_track_name."""
import collections, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib

NAMEISH = ("name", "parent_folder_name", "id", "parent_folder_id")
c = hlib.client()
tl = hlib.tracks(c)
print("tracks", len(tl))


def walk(d, p=""):
    for k, v in d.items():
        if isinstance(v, dict):
            walk(v, p + k + ".")
        elif isinstance(v, list):
            print(p + k, "list", len(v), [type(x).__name__ for x in v[:2]])
        else:
            print(p + k, type(v).__name__, "-" if k in NAMEISH else v)


if tl:
    walk(tl[0])
print(collections.Counter(x["type"] for x in tl))
print(collections.Counter(x.get("format") for x in tl))
keys = collections.Counter(k for x in tl for k in x)
print(keys)
if "--rows" in sys.argv:
    for t in tl:
        print(t.get("index"), hlib.safe_track_name(t["name"]), t["type"], t.get("format"),
              "parent=" + (hlib.safe_track_name(t.get("parent_folder_name", "")) if t.get("parent_folder_name") else "-"),
              {k: v for k, v in (t.get("track_attributes") or {}).items() if v not in ("TAState_None", False, None)})
sys.stdout.flush(); os._exit(0)
