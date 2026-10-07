"""Probe the open Plug-in window's AX tree: buttons (title/value), close button. No track names
printed: the track selector's value is redacted."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dialog_clicker as dc
import ApplicationServices as AS
for d in dc.windows():
    if not d["title"].startswith("Plug-in:"):
        continue
    print("plugin window", d["size"], d["pos"], "title tail", repr(d["title"].split(":", 1)[1][-16:] if "Auto" in d["title"] else "?"))
    cb = dc._ax(d["el"], "AXCloseButton")
    print("close button", cb is not None)
    stack = [(d["el"], 0)]
    while stack:
        el, depth = stack.pop()
        role = dc._ax(el, "AXRole")
        if role in ("AXButton", "AXPopUpButton", "AXCheckBox", "AXTextField", "AXStaticText", "AXMenuButton"):
            t = str(dc._ax(el, "AXTitle") or ""); v = dc._ax(el, "AXValue"); ds = str(dc._ax(el, "AXDescription") or "")
            if "Track" in t or "track" in ds.lower():
                v = "<redacted>"
            print("  " * depth, role, repr(t[:30]), repr(str(v)[:30]) if v is not None else "", repr(ds[:30]))
        if depth < 4:
            stack += [(k, depth + 1) for k in (dc._ax(el, "AXChildren") or [])]
sys.stdout.flush(); os._exit(0)
