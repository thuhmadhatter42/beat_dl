"""Dev aid: can we see Pro Tools' AX windows? (no titles printed)"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ApplicationServices as AS
from AppKit import NSWorkspace
for a in NSWorkspace.sharedWorkspace().runningApplications():
    n = str(a.localizedName() or "")
    if n.startswith("Pro Tools"):
        el = AS.AXUIElementCreateApplication(a.processIdentifier())
        err, wins = AS.AXUIElementCopyAttributeValue(el, "AXWindows", None)
        print("pid", a.processIdentifier(), "hidden", a.isHidden(), "active", a.isActive(),
              "policy", a.activationPolicy(), "AXWindows err", err, "n", len(wins or []))
        err2, kids = AS.AXUIElementCopyAttributeValue(el, "AXChildren", None)
        print("AXChildren err", err2, "n", len(kids or []))
        print("trusted", AS.AXIsProcessTrusted())
sys.stdout.flush(); os._exit(0)
