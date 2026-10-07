"""Dialog clicker for unattended Pro Tools runs on Sofia. J approved exactly four auto-clicks
(2026-10-06):  UAD -> OK, Session Notes -> No, Missing Files -> OK, Save -> Don't Save.
Nothing else is ever pressed.

How (v2): AppleScript/System Events is -600 over ssh on Sofia, and CGWindowList returns nothing
there, but the Accessibility API itself works (the venv's python binary holds the Accessibility
grant). Every 2 s:
- read Pro Tools' AX windows: title, static texts, buttons (shallow walk);
- skip Edit:/Mix:/Plug-in: windows and anything >= 1000x800;
- a window whose title/text matches a whitelist entry AND has the named button -> press that
  button (AXPress; if AXPress fails, a Quartz click at the button's centre);
- if a dialog exists while another app (Terminal) is frontmost -> activate Pro Tools
  (NSRunningApplication, no click), at most once per 10 s, so screenshots see it;
- any other PT window with OK/Yes/No/Save-style buttons -> logged once as UNKNOWN, a screenshot
  kept on Sofia (~/pt-harvest/shots/), ~/pt-harvest/BLOCKED written. Progress windows (Cancel
  only) are ignored.
Logs carry labels, sizes and coordinates only, never window text (names rule, J 2026-10-06).

usage: dialog_clicker.py [--dry-run] [--once]   (run with ~/pt-harvest/.venv/bin/python)
"""
import datetime, os, re, subprocess, sys, time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
DRY = "--dry-run" in sys.argv
ONCE = "--once" in sys.argv
H = Path.home() / "pt-harvest"
BLOCKED = H / "BLOCKED"

# (label, title-or-text regex, button title regex) — the whole whitelist
KNOWN = [
    ("UAD -> OK", r"\bUAD\b", r"^OK$"),
    ("Session Notes -> No", r"Session\s*Notes", r"^No$"),
    ("Missing Files -> OK", r"Missing\s*Files|files?\s+(are|is)\s+missing|could\s+not\s+be\s+found", r"^OK$"),
    ("Save -> Don't Save", r"save\s+(the\s+)?changes|want\s+to\s+save", r"^Don.?t\s*Save$"),
]
# Dialogs seen in the batch that are NOT on J's list. They stay unpressed (BLOCKED) until J approves:
# the main session then adds the label line to ~/pt-harvest/approved-dialogs.txt (read every scan).
PENDING = [
    ("Missing AAX Plugins -> OK", r"Missing\s+AAX\s+Plug-?ins", r"^OK$"),
]
APPROVED_FILE = H / "approved-dialogs.txt"


def known():
    try:
        ok = {l.strip() for l in APPROVED_FILE.read_text().splitlines() if l.strip()}
    except OSError:
        ok = set()
    return KNOWN + [k for k in PENDING if k[0] in ok]


DIALOG_BTN = re.compile(r"^(OK|Yes|No|Don.?t\s*Save|Continue|Retry|Quit|Save|Open|Done|Skip.*|Ignore|Close|Relink.*|Manually.*)$", re.I)
_last_activate = 0.0
_unknown_seen = set()


def log(m):
    print(f"{datetime.datetime.now().isoformat(timespec='seconds')} {m}", flush=True)


def _ax(el, attr):
    import ApplicationServices as AS
    err, v = AS.AXUIElementCopyAttributeValue(el, attr, None)
    return v if err == 0 else None


def _pt_app():
    from AppKit import NSWorkspace
    import ApplicationServices as AS
    for a in NSWorkspace.sharedWorkspace().runningApplications():
        if str(a.localizedName() or "").startswith("Pro Tools"):
            return AS.AXUIElementCreateApplication(a.processIdentifier())
    return None


def _xy(v, kind):
    import ApplicationServices as AS
    if v is None:
        return None
    ok, val = AS.AXValueGetValue(v, kind, None)
    return val if ok else None


def windows():
    """-> [{'title','texts','buttons':[(title, element)], 'pos', 'size'}] for PT windows."""
    import ApplicationServices as AS
    app = _pt_app()
    if app is None:
        return []
    out = []
    for w in _ax(app, "AXWindows") or []:
        pos = _xy(_ax(w, "AXPosition"), AS.kAXValueCGPointType)
        size = _xy(_ax(w, "AXSize"), AS.kAXValueCGSizeType)
        d = {"title": str(_ax(w, "AXTitle") or ""), "texts": [], "buttons": [], "el": w,
             "pos": (pos.x, pos.y) if pos else (0, 0), "size": (size.width, size.height) if size else (0, 0)}
        stack = [(k, 1) for k in (_ax(w, "AXChildren") or [])]
        while stack:
            el, depth = stack.pop()
            role = _ax(el, "AXRole")
            if role == "AXButton":
                d["buttons"].append((str(_ax(el, "AXTitle") or ""), el))
            elif role == "AXStaticText":
                d["texts"].append(str(_ax(el, "AXValue") or ""))
            if depth < 3 and role in ("AXGroup", "AXScrollArea", "AXSplitGroup", "AXTabGroup", "AXLayoutArea"):
                stack += [(k, depth + 1) for k in (_ax(el, "AXChildren") or [])]
        out.append(d)
    return out


def press(el) -> bool:
    import ApplicationServices as AS
    if AS.AXUIElementPerformAction(el, "AXPress") == 0:
        return True
    import Quartz
    p = _xy(_ax(el, "AXPosition"), AS.kAXValueCGPointType)
    s = _xy(_ax(el, "AXSize"), AS.kAXValueCGSizeType)
    if not (p and s):
        return False
    x, y = p.x + s.width / 2, p.y + s.height / 2
    for t in (Quartz.kCGEventMouseMoved, Quartz.kCGEventLeftMouseDown, Quartz.kCGEventLeftMouseUp):
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, t, (x, y), Quartz.kCGMouseButtonLeft))
        time.sleep(0.08)
    return True


def is_dialog(d) -> bool:
    if d["title"].startswith(("Edit:", "Mix:", "Plug-in:")):
        return False
    w, h = d["size"]
    return not (w >= 1000 and h >= 800)


def scan_once():
    global _last_activate
    import hlib
    dialogs = [d for d in windows() if is_dialog(d)]
    if not dialogs:
        return None
    if not hlib.frontmost().startswith("Pro Tools") and time.time() - _last_activate > 10:
        _last_activate = time.time()
        ok = hlib.bring_pt_forward()
        log(f"Pro Tools window behind another app: activated PT -> frontmost={'PT' if ok else 'other'}")
    for d in dialogs:
        text = d["title"] + "\n" + "\n".join(d["texts"])
        for label, trx, brx in known():
            if not re.search(trx, text, re.I):
                continue
            btn = next((el for t, el in d["buttons"] if re.match(brx, t.strip(), re.I)), None)
            if btn is None:
                continue
            if DRY:
                log(f"{label}: matched (dry-run) dialog {d['size'][0]:.0f}x{d['size'][1]:.0f}")
            else:
                ok = press(btn)
                log(f"{label}: pressed={ok} dialog {d['size'][0]:.0f}x{d['size'][1]:.0f} at {d['pos'][0]:.0f},{d['pos'][1]:.0f}")
                time.sleep(1.5)
            return label
        btnish = [t for t, _ in d["buttons"] if DIALOG_BTN.match(t.strip())]
        if btnish:
            pend = next((lbl for lbl, trx, _ in PENDING if re.search(trx, text, re.I)), "unlisted")
            sig = (round(d["size"][0] / 10), round(d["size"][1] / 10), len(d["buttons"]), pend)
            if sig not in _unknown_seen or not BLOCKED.exists():
                _unknown_seen.add(sig)
                keep = H / "shots" / f"unknown-{datetime.datetime.now():%m%d-%H%M%S}.png"
                keep.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(["screencapture", "-x", str(keep)])
                BLOCKED.write_text(f"{datetime.datetime.now().isoformat(timespec='seconds')} unknown PT dialog [{pend}] "
                                   f"{d['size'][0]:.0f}x{d['size'][1]:.0f} at {d['pos'][0]:.0f},{d['pos'][1]:.0f}, "
                                   f"{len(d['buttons'])} buttons; shot {keep.name}\n")
                log(f"UNKNOWN PT dialog [{pend}] {d['size'][0]:.0f}x{d['size'][1]:.0f} at {d['pos'][0]:.0f},{d['pos'][1]:.0f} "
                    f"({len(btnish)} dialog-style buttons): not pressing; BLOCKED written; shot {keep.name}")
            return "unknown"
    return None


if __name__ == "__main__":
    log(f"dialog_clicker v2 up (dry={DRY}, once={ONCE}, pid={os.getpid()})")
    if not ONCE:
        (H / "clicker.pid").write_text(str(os.getpid()))
    while True:
        try:
            scan_once()
        except Exception as e:
            log(f"err {type(e).__name__}")
        if ONCE:
            break
        time.sleep(2)
    sys.stdout.flush(); os._exit(0)
