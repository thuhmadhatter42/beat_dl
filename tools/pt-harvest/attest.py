"""Test the Auto-Tune read on the open session: every Auto-Tune insert on the Edit window strips
(up to argv[1], default 4). Prints strip index, slot, product and the read (no track names)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
lim = int(sys.argv[1]) if len(sys.argv) > 1 else 4
strips = hlib.edit_strips()
print("strips with Auto-Tune:", len(strips))
for i, (name, btns) in enumerate(list(strips.items())[:lim]):
    slot, val, b = btns[0]
    r = hlib.read_autotune(b, hlib.H / "crops" / f"attest-{i}.png")
    print(i, "slot", slot, {k: v for k, v in r.items()})
print("plugin window closed:", hlib.plugin_window() is None)
sys.stdout.flush(); os._exit(0)
