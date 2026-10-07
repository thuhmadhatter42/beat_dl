"""Open Auto-Tune candidate #i of the open session (same filter as harvest.stage_autotune), crop the
plug-in header's BYPASS button (+ margin, no track selector) to crops/bypass-view-<i>.png, close."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib, harvest
import dialog_clicker as dc
import ApplicationServices as AS
i = int(sys.argv[1]) if len(sys.argv) > 1 else 0
c = hlib.client(); tl = hlib.tracks(c)
by_name = {t["name"]: t for t in tl}
cands = []
for name, btns in hlib.edit_strips().items():
    t = by_name.get(name)
    if t and t["type"] == "TType_Audio" and hlib.attr(t, "contains_clips") and not any(
            hlib.attr(t, k) for k in ("is_inactive", "is_muted", "is_hidden")) and not harvest._NOT_LEAD.search(name):
        cands.append(btns[0])
print("candidates", len(cands))
slot, val, b = cands[i]
hlib.close_plugin_window()
print("press", AS.AXUIElementPerformAction(b, "AXPress"))
time.sleep(2.5)
w = hlib.plugin_window()
if w:
    stack = [(w["el"], 0)]
    while stack:
        el, d = stack.pop()
        if str(dc._ax(el, "AXTitle") or "") == "Effect Bypass":
            p = dc._xy(dc._ax(el, "AXPosition"), AS.kAXValueCGPointType)
            s = dc._xy(dc._ax(el, "AXSize"), AS.kAXValueCGSizeType)
            print("bypass frame", int(p.x), int(p.y), int(s.width), int(s.height))
            img = hlib.screenshot(hlib.H / "shots" / "bypass-full.png")
            px = img.crop((int(p.x) + 2, int(p.y) + 2, int(p.x + s.width) - 2, int(p.y + s.height) - 2)).resize((1, 1)).getpixel((0, 0))
            print("mean rgb", px)
            hlib.crop(img, (int(p.x) - 10, int(p.y) - 6, int(s.width) + 20, int(s.height) + 12), 3.0).save(
                hlib.H / "crops" / f"bypass-view-{i}.png")
        if d < 4:
            stack += [(k, d + 1) for k in (dc._ax(el, "AXChildren") or [])]
print("closed", hlib.close_plugin_window())
sys.stdout.flush(); os._exit(0)
