"""Dump one Edit-window strip's AX children (roles/titles/values, track name redacted). argv: strip index."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dialog_clicker as dc
import ApplicationServices as AS
idx = int(sys.argv[1])
edit = next((d for d in dc.windows() if d["title"].startswith("Edit:")), None)
s = (dc._ax(edit["el"], "AXChildren") or [])[idx]
st = str(dc._ax(s, "AXTitle") or "")
red = lambda x: str(x).replace(st, "<track>") if st else str(x)
print("strip role", dc._ax(s, "AXRole"), "n children", len(dc._ax(s, "AXChildren") or []))


def dump(el, d):
    role = dc._ax(el, "AXRole")
    attrs = {a: dc._ax(el, a) for a in ("AXTitle", "AXValue", "AXDescription", "AXSelected", "AXEnabled")}
    p = dc._xy(dc._ax(el, "AXPosition"), AS.kAXValueCGPointType)
    sz = dc._xy(dc._ax(el, "AXSize"), AS.kAXValueCGSizeType)
    geo = f"@{p.x:.0f},{p.y:.0f} {sz.width:.0f}x{sz.height:.0f}" if p and sz else ""
    shown = {k: red(v)[:40] for k, v in attrs.items() if v is not None and v != ""}
    print("  " * d + f"{role} {geo} {shown}")
    if d < 2:
        for k in dc._ax(el, "AXChildren") or []:
            dump(k, d + 1)


for g in dc._ax(s, "AXChildren") or []:
    if "Insert" in str(dc._ax(g, "AXTitle") or "") or "--all" in sys.argv:
        dump(g, 0)
sys.stdout.flush(); os._exit(0)
