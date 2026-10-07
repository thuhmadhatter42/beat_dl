"""Pixel-based watcher for exactly four Pro Tools dialogs on Sofia (AppleScript is
-600 over ssh, so SEE the screen): UAD -> OK, Session Notes -> No,
Missing Files -> OK, Save Changes -> Don't Save. Clicks nothing else, ever.

Run on Sofia: ~/ProTools SDK/stem-bouncer/.venv/bin/python dialog_clicker.py [--dry-run] [--once]
Approach reused from ~/xobaloo/stems_work/xo_clicker2.py (not edited): screencapture
region + gray title strip / body signature + Quartz CGEvent click.

CALIBRATION STATUS (honest):
  Missing Files, Session Notes: geometry copied from xo_clicker2 (verified 2026-08-29).
  UAD, Save Changes: button=None until calibrated from a real capture. Detection of
  those two is logged ("UNCALIBRATED, not clicking") but no click is sent. Fill the
  region/button below from a screenshot taken while the dialog is up.
Anything not matching a signature is left alone.
"""
import subprocess, time, datetime, os, sys

DRY = "--dry-run" in sys.argv
ONCE = "--once" in sys.argv
SHOT = "/tmp/pt_dialog_region.png"

# (label, region xywh, title strip in-region, body patch in-region, extra patch or None, button xy or None)
DIALOGS = [
    ("Missing Files -> OK", (949, 305, 660, 210), (10, 2, 640, 18), (30, 50, 300, 80), None, (1558, 498)),
    ("Session Notes -> No", (1046, 233, 470, 425), (10, 2, 460, 18), (30, 60, 200, 120), (30, 370, 200, 40), (1364, 649)),
    # UNCALIBRATED: UAD "plug-ins are disabled because no UAD hardware" sits ~x 810-1020, y 530-610
    ("UAD -> OK", (780, 480, 300, 200), (10, 2, 280, 18), (20, 40, 260, 100), None, None),
    # UNCALIBRATED: Save Changes -> Don't Save
    ("Save Changes -> Don't Save", (700, 300, 520, 300), (10, 2, 500, 18), (20, 40, 400, 100), None, None),
]


def log(m):
    print(f"{datetime.datetime.now().isoformat(timespec='seconds')} {m}", flush=True)


def grab(region):
    r = subprocess.run(["screencapture", "-x", "-R", ",".join(str(v) for v in region), SHOT],
                       capture_output=True)
    if r.returncode != 0 or not os.path.exists(SHOT):
        return None
    from PIL import Image
    return Image.open(SHOT).convert("RGB")


def mean_rgb(img, box):
    data = list(img.crop(box).resize((8, 8)).getdata())
    return tuple(sum(c[i] for c in data) / len(data) for i in range(3))


def grayish(rgb, lo, hi, tol=14):
    m = sum(rgb) / 3
    return lo <= m <= hi and max(abs(c - m) for c in rgb) <= tol


def click(x, y):
    import Quartz
    mv = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, (x, y), Quartz.kCGMouseButtonLeft)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, mv); time.sleep(0.15)
    for t in (Quartz.kCGEventLeftMouseDown, Quartz.kCGEventLeftMouseUp):
        ev = Quartz.CGEventCreateMouseEvent(None, t, (x, y), Quartz.kCGMouseButtonLeft)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev); time.sleep(0.06)


def scan_once():
    """Return list of labels matched (and click calibrated ones unless --dry-run)."""
    hits = []
    for label, region, ts, bp, extra, btn in DIALOGS:
        img = grab(region)
        if img is None:
            continue
        s = img.width / region[2]
        box = lambda r: tuple(int(v * s) for v in (r[0], r[1], r[0] + r[2], r[1] + r[3]))
        t, b = mean_rgb(img, box(ts)), mean_rgb(img, box(bp))
        ok = grayish(t, 225, 250) and grayish(b, 185, 245)
        if ok and extra is not None:
            ok = grayish(mean_rgb(img, box(extra)), 175, 245)
        if not ok:
            continue
        hits.append(label)
        if btn is None:
            log(f"{label}: signature matched but UNCALIBRATED, not clicking")
        elif DRY:
            log(f"{label}: matched (dry-run, would click {btn})")
        else:
            log(f"{label}: clicking {btn} (title={tuple(round(x) for x in t)} body={tuple(round(x) for x in b)})")
            click(*btn)
            time.sleep(2)
        break  # one dialog per pass; rescan
    return hits


if __name__ == "__main__":
    log(f"dialog_clicker up (dry={DRY}, once={ONCE})")
    while True:
        try:
            scan_once()
        except Exception as e:
            log(f"err {type(e).__name__}: {e}")
        if ONCE:
            break
        time.sleep(5)
    os._exit(0)
