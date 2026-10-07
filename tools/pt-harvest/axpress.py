"""Press one insert button of one Edit-window strip via AX (AXPress), then list PT windows
(kind/size only). argv: strip index, button title (e.g. 'Insert Assignment B')."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dialog_clicker as dc
import ApplicationServices as AS
idx, title = int(sys.argv[1]), sys.argv[2]
edit = next((d for d in dc.windows() if d["title"].startswith("Edit:")), None)
s = (dc._ax(edit["el"], "AXChildren") or [])[idx]
btn = None
for g in dc._ax(s, "AXChildren") or []:
    for b in dc._ax(g, "AXChildren") or []:
        if str(dc._ax(b, "AXTitle") or "") == title:
            btn = b
print("found", btn is not None, "value", dc._ax(btn, "AXValue") if btn else None)
print("desc tail", repr(str(dc._ax(btn, "AXDescription") or "").split("\n")[-1][-60:]))
if btn is not None and "--press" in sys.argv:
    print("AXPress ->", AS.AXUIElementPerformAction(btn, "AXPress"))
    time.sleep(2)
for d in dc.windows():
    kind = d["title"].split(":")[0] if ":" in d["title"] else "other"
    print(f"  window {kind[:10]} {d['size'][0]:.0f}x{d['size'][1]:.0f} at {d['pos'][0]:.0f},{d['pos'][1]:.0f} buttons={len(d['buttons'])}")
sys.stdout.flush(); os._exit(0)
