"""Find scroll bars/areas in the Edit window AX tree; print role, frame, orientation, value and
whether AXValue is settable. --set v: set the vertical scroll bar's value to v (0..1)."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dialog_clicker as dc
import ApplicationServices as AS
edit = next((d for d in dc.windows() if d["title"].startswith("Edit:")), None)
found = []
stack = [(edit["el"], 0)]
while stack:
    el, d = stack.pop()
    role = str(dc._ax(el, "AXRole"))
    if role in ("AXScrollBar", "AXScrollArea", "AXValueIndicator") or "Scroll" in str(dc._ax(el, "AXTitle") or ""):
        p = dc._xy(dc._ax(el, "AXPosition"), AS.kAXValueCGPointType)
        s = dc._xy(dc._ax(el, "AXSize"), AS.kAXValueCGSizeType)
        err, settable = AS.AXUIElementIsAttributeSettable(el, "AXValue", None)
        print(role, f"@{p.x:.0f},{p.y:.0f} {s.width:.0f}x{s.height:.0f}" if p and s else "", "orient", dc._ax(el, "AXOrientation"),
              "value", dc._ax(el, "AXValue"), "settable", settable, "title", str(dc._ax(el, "AXTitle") or "")[:30])
        found.append((role, el, s))
    if d < 4:
        stack += [(k, d + 1) for k in (dc._ax(el, "AXChildren") or [])]
if "--set" in sys.argv:
    v = float(sys.argv[sys.argv.index("--set") + 1])
    vs = [el for role, el, s in found if role == "AXScrollBar" and s and s.height > s.width]
    for el in vs:
        print("set ->", AS.AXUIElementSetAttributeValue(el, "AXValue", v), "now", dc._ax(el, "AXValue"))
sys.stdout.flush(); os._exit(0)
