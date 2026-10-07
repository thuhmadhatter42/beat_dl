"""One-step probes for the §1-§5 calibration, name-free output only.
  step.py state                 PTSL up? session open?
  step.py open N                OpenSession for manifest #N (blocks; run under nohup)
  step.py info N                export session info (BarsBeats/Samples/Ticks) to ~/pt-harvest/info/ (Sofia only), print a name-free summary
  step.py tracks                name-free track table
  step.py close                 CloseSession without saving
"""
import json, os, sys, time, traceback
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
from hlib import H

cmd = sys.argv[1]
try:
    if cmd == "state":
        print("ptsl port", hlib._port_open())
        c = hlib.client(); print("session open", hlib.session_open(c))
    elif cmd == "open":
        e = hlib.entry(int(sys.argv[2]))
        c = hlib.client()
        t0 = time.time()
        st, body = c.status_of("CId_OpenSession", {"session_path": e["ptx"], "prompt_for_file_not_found": False},
                               timeout=900)
        print("open", st, f"{time.time()-t0:.0f}s", hlib.redact(body)[:300])
    elif cmd == "info":
        n = int(sys.argv[2]); e = hlib.entry(n)
        c = hlib.client()
        d = H / "info"; d.mkdir(exist_ok=True)
        texts = {}
        prior = c.send("CId_GetMainCounterFormat").get("current_setting")
        print("main counter was", prior)
        for lt in ("TLType_BarsBeats", "TLType_Samples", "TLType_Ticks"):
            st, b = c.status_of("CId_SetMainCounterFormat", {"location_type": lt})
            if st != "Completed":
                print("set counter", lt, st, hlib.redact(b)[:200]); texts[lt] = ""; continue
            texts[lt] = hlib.export_info(c)
            (d / f"{n:04d}-{lt}.txt").write_text(texts[lt])
            print(lt, "chars", len(texts[lt]))
        c.status_of("CId_SetMainCounterFormat", {"location_type": prior or "TLType_BarsBeats"})
        bb = hlib.parse_info(texts["TLType_BarsBeats"])
        sa = hlib.parse_info(texts["TLType_Samples"])
        tk = hlib.parse_info(texts["TLType_Ticks"])
        sr = float(bb["header"].get("SAMPLE RATE", "0") or 0)
        print("sr", sr, "tracks", len(bb["tracks"]), "files", len(bb["files"]))
        print("sample EDL row (ticks):", hlib.redact([x["start"] for x in tk["tracks"][0]["edl"][:3]] if tk["tracks"] else None))
        tempos = hlib.edl_tempos(bb, sa, tk, sr)
        from collections import Counter
        print("edl tempos (n, top5):", len(tempos), Counter(round(t, 2) for t in tempos).most_common(5))
        for t in bb["tracks"]:
            nm = t["name"]
            if t["comment"]:
                print("comment on", hlib.safe_track_name(nm.replace(" (Stereo)", "").replace(" (Mono)", "")),
                      "->", repr(hlib.redact(t["comment"])), hlib.parse_comment(t["comment"]))
        at = [t for t in bb["tracks"] if any("Auto-Tune" in p for p in t["plugins"])]
        print("tracks with Auto-Tune:", len(at), "active (STATE without Inactive):",
              sum(1 for t in at if "Inactive" not in t["state"]),
              "products:", sorted({p for t in at for p in t["plugins"] if "Auto-Tune" in p}))
        print("producer bpms in files:", hlib.producer_bpms(bb["files"]))
        print("markers:", len(bb["markers"]))
    elif cmd == "tracks":
        c = hlib.client()
        for t in hlib.tracks(c):
            a = t.get("track_attributes", {})
            print(f'{t["index"]:3d} {hlib.safe_track_name(t["name"]):12s} {t["type"]:22s} '
                  f'parent={hlib.safe_track_name(t.get("parent_folder_name","")) if t.get("parent_folder_name") else "-":10s} '
                  f'inact={int(hlib.attr(t,"is_inactive"))} hid={int(hlib.attr(t,"is_hidden"))} '
                  f'mute={int(hlib.attr(t,"is_muted"))} solo={int(hlib.attr(t,"is_soloed"))} clips={int(hlib.attr(t,"contains_clips"))} '
                  f'fmt={t.get("format","")}')
    elif cmd == "close":
        c = hlib.client(); print("close", hlib.close_no_save(c))
except BaseException as ex:
    print("ERR", type(ex).__name__, hlib.redact(ex)[:400])
    print(hlib.redact(traceback.format_exc())[-800:])
sys.stdout.flush(); os._exit(0)
