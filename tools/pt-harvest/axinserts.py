"""Probe the Edit window AX tree: per track strip, its insert buttons whose value names Auto-Tune.
Prints strip index, the insert slot letter, the Auto-Tune value, and AX attribute names. Never the
track name (it is redacted out of every printed string)."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dialog_clicker as dc
AT = re.compile(r"Auto-?Tune", re.I)
edit = next((d for d in dc.windows() if d["title"].startswith("Edit:")), None)
strips = dc._ax(edit["el"], "AXChildren") or []
n_at = 0
sample_done = False
for i, s in enumerate(strips):
    if dc._ax(s, "AXRole") != "AXGroup":
        continue
    stitle = str(dc._ax(s, "AXTitle") or "")
    def red(x):
        x = str(x)
        return x.replace(stitle, "<track>") if stitle else x
    for g in dc._ax(s, "AXChildren") or []:
        gt = str(dc._ax(g, "AXTitle") or "")
        if "Insert" not in gt:
            continue
        for b in dc._ax(g, "AXChildren") or []:
            vals = {a: dc._ax(b, a) for a in ("AXTitle", "AXValue", "AXDescription", "AXHelp")}
            if not sample_done:
                print("sample insert attrs:", {k: red(v)[:60] for k, v in vals.items() if v})
                acts = dc._ax(b, "AXActionNames") if False else None
                import ApplicationServices as AS
                err, names = AS.AXUIElementCopyActionNames(b, None)
                print("actions:", list(names or []))
                sample_done = True
            hit = [str(v) for v in vals.values() if isinstance(v, str) and AT.search(v)]
            if hit:
                n_at += 1
                if n_at <= 12:
                    print(f"strip {i}: group '{red(gt)[:30]}' button '{red(vals['AXTitle'])[:40]}' value '{red(vals['AXValue'])[:50]}'")
print("Auto-Tune insert buttons:", n_at)
sys.stdout.flush(); os._exit(0)
