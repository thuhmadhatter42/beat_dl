"""List Pro Tools AX windows: kind, size, button count, whitelist match (no titles/text: names rule)."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dialog_clicker as dc
import hlib
print("frontmost:", hlib.frontmost())
for d in dc.windows():
    kind = "edit" if d["title"].startswith("Edit:") else "mix" if d["title"].startswith("Mix:") else \
        "plugin" if d["title"].startswith("Plug-in:") else "other"
    text = d["title"] + "\n" + "\n".join(d["texts"])
    match = [lbl for lbl, trx, _ in dc.KNOWN if re.search(trx, text, re.I)]
    btnish = [t for t, _ in d["buttons"] if dc.DIALOG_BTN.match(t.strip())]
    print(f'{kind:6s} {d["size"][0]:.0f}x{d["size"][1]:.0f} at {d["pos"][0]:.0f},{d["pos"][1]:.0f} '
          f'buttons={len(d["buttons"])} dialog-buttons={btnish if kind == "other" else len(btnish)} match={match}')
sys.stdout.flush(); os._exit(0)
