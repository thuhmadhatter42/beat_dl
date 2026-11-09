import Quartz, time, sys
def ev(t,x,y):
    e=Quartz.CGEventCreateMouseEvent(None,t,(x,y),Quartz.kCGMouseButtonLeft); Quartz.CGEventPost(Quartz.kCGHIDEventTap,e); time.sleep(0.08)
x,y,dy=float(sys.argv[1]),float(sys.argv[2]),float(sys.argv[3])
ev(Quartz.kCGEventLeftMouseDown,x,y)
for i in range(1,21): ev(Quartz.kCGEventLeftMouseDragged,x,y+dy*i/20)
ev(Quartz.kCGEventLeftMouseUp,x,y+dy)
print("dragged")
