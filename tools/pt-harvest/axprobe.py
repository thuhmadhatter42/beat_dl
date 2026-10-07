"""Can the Accessibility API see Pro Tools windows over ssh? Prints roles/sizes, no titles."""
import os, sys
from AppKit import NSWorkspace
import ApplicationServices as AS
pt = [a for a in NSWorkspace.sharedWorkspace().runningApplications() if str(a.localizedName() or "").startswith("Pro Tools")]
print("pt apps", len(pt), "trusted", AS.AXIsProcessTrusted())
for a in pt:
    app = AS.AXUIElementCreateApplication(a.processIdentifier())
    err, wins = AS.AXUIElementCopyAttributeValue(app, "AXWindows", None)
    print("AXWindows err", err, "count", None if wins is None else len(wins))
    for w in wins or []:
        e1, role = AS.AXUIElementCopyAttributeValue(w, "AXSubrole", None)
        e2, pos = AS.AXUIElementCopyAttributeValue(w, "AXPosition", None)
        e3, size = AS.AXUIElementCopyAttributeValue(w, "AXSize", None)
        e4, kids = AS.AXUIElementCopyAttributeValue(w, "AXChildren", None)
        btns = []
        for k in kids or []:
            _, r = AS.AXUIElementCopyAttributeValue(k, "AXRole", None)
            if r == "AXButton":
                _, t = AS.AXUIElementCopyAttributeValue(k, "AXTitle", None)
                btns.append(str(t))
        print(" win subrole", role, "pos", pos, "size", size, "buttons", btns[:8])
sys.stdout.flush(); os._exit(0)
