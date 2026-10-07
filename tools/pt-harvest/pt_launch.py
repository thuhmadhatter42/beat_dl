"""Launch the newest installed Pro Tools via osascript (open -a lands in the wrong
session over ssh), wait for PTSL port 31416. No synthetic input."""
import sys, subprocess, time, pathlib
sys.path.insert(0, str(pathlib.Path.home() / "ProTools SDK" / "stem-bouncer"))
from pt_stems.client import _latest_pt_app, _port_open

app = pathlib.Path(_latest_pt_app()).stem
print("app:", app, flush=True)
if _port_open():
    print("PTSL already open"); sys.exit(0)
r = subprocess.run(["osascript", "-e", f'tell application "{app}" to launch'],
                   capture_output=True, text=True)
print("osascript rc", r.returncode, r.stdout, r.stderr, flush=True)
for i in range(int(sys.argv[1]) if len(sys.argv) > 1 else 40):
    if _port_open():
        print("PTSL port open after", i * 3, "s"); sys.exit(0)
    time.sleep(3)
print("PTSL port NOT open yet"); sys.exit(2)
