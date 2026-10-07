"""Probe: Edit window AX Tempo field + Tempo/Meter tables (rows, numeric cell values only)."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dialog_clicker as dc
NUM = re.compile(r"^[\s\d.:/|]{1,20}$")
edit = next((d for d in dc.windows() if d["title"].startswith("Edit:")), None)


def walk(el, depth=0, maxd=6):
    yield el, depth
    if depth < maxd:
        for k in dc._ax(el, "AXChildren") or []:
            yield from walk(k, depth + 1, maxd)


for el, depth in walk(edit["el"], 0, 2):
    role = dc._ax(el, "AXRole"); title = str(dc._ax(el, "AXTitle") or "")
    if role == "AXTextField" and re.search("Tempo|Meter", title):
        print("field", title[:20], "value", repr(dc._ax(el, "AXValue")))
    if role == "AXTable" and re.search("^(Tempo|Meter)", title):
        rows = dc._ax(el, "AXRows") or []
        print("table", title[:30], "rows", len(rows))
        for r in rows[:8]:
            cells = []
            for c, d in walk(r, 0, 3):
                for a in ("AXValue", "AXTitle", "AXDescription"):
                    v = dc._ax(c, a)
                    if isinstance(v, str) and NUM.match(v) and v.strip():
                        cells.append(v.strip())
            print("   row", cells[:8])
sys.stdout.flush(); os._exit(0)
