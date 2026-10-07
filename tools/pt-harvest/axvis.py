"""Why does AXPress open no plug-in window? For the open session: open closed folders, then for each
Auto-Tune insert button on a live track print its on-screen frame, the Edit window frame, and the
AX actions of the button and its strip. --scroll i: try AXScrollToVisible on candidate i's strip,
then press. No names printed."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib, harvest
import dialog_clicker as dc
import ApplicationServices as AS
c = hlib.client(); tl = hlib.tracks(c)
closed = [t["name"] for t in tl if t["type"] in ("TType_RoutingFolder", "TType_BasicFolder") and not hlib.attr(t, "is_open")]
if closed:
    print("open folders:", c.status_of("CId_SetTrackOpenState", {"track_names": closed, "enabled": True})[0], len(closed))
    time.sleep(1.5)
by_name = {t["name"]: t for t in tl}
edit = next((d for d in dc.windows() if d["title"].startswith("Edit:")), None)
print("edit frame", edit["pos"], edit["size"])
cands = []
for name, btns in hlib.edit_strips().items():
    t = by_name.get(name)
    live = t and t["type"] == "TType_Audio" and hlib.attr(t, "contains_clips") and not any(
        hlib.attr(t, k) for k in ("is_inactive", "is_muted", "is_hidden"))
    slot, val, b = btns[0]
    p = dc._xy(dc._ax(b, "AXPosition"), AS.kAXValueCGPointType)
    s = dc._xy(dc._ax(b, "AXSize"), AS.kAXValueCGSizeType)
    err, acts = AS.AXUIElementCopyActionNames(b, None)
    par = dc._ax(b, "AXParent"); strip = dc._ax(par, "AXParent") if par else None
    err2, sacts = AS.AXUIElementCopyActionNames(strip, None) if strip else (1, None)
    print(f"live={bool(live)} lead={bool(harvest._LEAD.search(name))} slot={slot} btn@{p.x:.0f},{p.y:.0f} {s.width:.0f}x{s.height:.0f} "
          f"acts={list(acts or [])} strip_acts={list(sacts or [])}")
    if live:
        cands.append((b, strip))
if "--scroll" in sys.argv:
    i = int(sys.argv[sys.argv.index("--scroll") + 1])
    b, strip = cands[i]
    print("scroll:", hlib.scroll_into_view(b))
    time.sleep(1)
    p = dc._xy(dc._ax(b, "AXPosition"), AS.kAXValueCGPointType)
    print("btn now @", p.x, p.y)
    img = hlib.screenshot(hlib.H / "shots" / "axvis.png")
    hlib.crop(img, (int(p.x) - 80, int(p.y) - 30, 300, 80), 3.0).save("/tmp/pth_view/crop-btn.png")
    if "--nopress" not in sys.argv:
        print("press:", AS.AXUIElementPerformAction(b, "AXPress"))
    time.sleep(2.5)
    print("plugin window:", hlib.plugin_window() is not None)
    hlib.close_plugin_window()
if closed and "--keep" not in sys.argv:
    c.status_of("CId_SetTrackOpenState", {"track_names": closed, "enabled": False})
sys.stdout.flush(); os._exit(0)
