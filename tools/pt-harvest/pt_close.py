"""Close the open session WITHOUT saving."""
import sys, os, pathlib
sys.path.insert(0, str(pathlib.Path.home() / "ProTools SDK" / "stem-bouncer"))
from pt_stems.client import PtslClient
from pt_stems.dialog_watch import DialogWatch
w = DialogWatch().start()
c = PtslClient(autolaunch=False)
try:
    print(c.send("CId_CloseSession", {"save_on_close": False}, timeout=120), flush=True)
finally:
    w.stop(); print("unknown dialogs:", w.unknown, flush=True); os._exit(0)
