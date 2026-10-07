"""Run beatfind on the OPEN session; name-free output (safe_track_name only). Dev/verification aid.
  findprobe.py [--rows]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import beatfind as bf
import hlib

c = hlib.client()
tl = hlib.tracks(c)
sa = hlib.parse_info(hlib.export_info(c, "TLType_Samples"))
sr = float(sa["header"].get("SAMPLE RATE", "48000") or 48000)
outs = hlib.track_outputs(c, tl)
res = bf.find(tl, sa, outs, sr, use_folders="--no-folders" not in sys.argv)
print(" ".join(bf.table(res)))
for r in res.get("rows", []):
    print("  ", r)
if "--rows" in sys.argv:
    beat_ids = {t["id"] for t in res.get("tracks", [])}
    voc = set(res.get("vocal_names", []))
    for t in tl:
        if t["type"] not in ("TType_Audio", "TType_Instrument"):
            continue
        print(f'{hlib.safe_track_name(t["name"]):10s} {t["format"][8:]:6s} clips={int(bf.attr(t, "contains_clips"))} '
              f'inact={int(bf.attr(t, "is_inactive"))} mute={int(bf.attr(t, "is_muted"))} '
              f'{"BEAT" if t["id"] in beat_ids else "VOC " if t["name"] in voc else "-   "}')
sys.stdout.flush(); os._exit(0)
