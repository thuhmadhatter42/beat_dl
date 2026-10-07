"""Print only the time columns of the first EDL rows of a saved info export (no names)."""
import sys, re
from pathlib import Path
p = Path.home() / "pt-harvest" / "info" / sys.argv[1]
n = 0
for ln in p.read_text().splitlines():
    if re.match(r"^\d+\s*\t\s*\d+\s*\t", ln):
        f = [x.strip() for x in ln.split("\t")]
        print(f[3:6], f[-1]); n += 1
        if n >= int(sys.argv[2] if len(sys.argv) > 2 else 4):
            break
for ln in p.read_text().splitlines()[:9]:
    k = ln.split(":")[0]
    if k in ("SAMPLE RATE", "BIT DEPTH", "SESSION START TIMECODE", "TIMECODE FORMAT"):
        print(ln)
