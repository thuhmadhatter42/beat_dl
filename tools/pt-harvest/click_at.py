"""One Quartz CGEvent left click at (x, y) screen points. Run on Sofia with the
stem-bouncer venv python. Caller must have confirmed from a screenshot that the
point is on a Pro Tools window/dialog."""
import sys, time, Quartz
x, y = float(sys.argv[1]), float(sys.argv[2])
mv = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, (x, y), Quartz.kCGMouseButtonLeft)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, mv); time.sleep(0.15)
for t in (Quartz.kCGEventLeftMouseDown, Quartz.kCGEventLeftMouseUp):
    ev = Quartz.CGEventCreateMouseEvent(None, t, (x, y), Quartz.kCGMouseButtonLeft)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev); time.sleep(0.06)
print("clicked", x, y)
