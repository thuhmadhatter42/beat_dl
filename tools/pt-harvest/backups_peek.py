"""Read-only: for manifest #N's session folder, count .ptx in 'Session File Backups' and show
their modification dates (no names). Used to see whether PT's auto-backup rotation deletes old ones."""
import os, sys, time
from collections import Counter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
for a in sys.argv[1:]:
    e = hlib.entry(int(a))
    sd = os.path.join(os.path.dirname(e["ptx"]), "Session File Backups")
    if not os.path.isdir(sd):
        print(f"#{int(a):04d}: no backups folder"); continue
    ms = sorted(os.path.getmtime(os.path.join(sd, f)) for f in os.listdir(sd) if f.endswith(".ptx"))
    days = Counter(time.strftime("%Y-%m-%d", time.localtime(m)) for m in ms)
    print(f"#{int(a):04d}: {len(ms)} backups; by day {sorted(days.items())}")
sys.stdout.flush(); os._exit(0)
