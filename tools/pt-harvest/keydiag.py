"""Key-read check on saved Auto-Tune body crops (Sofia): the voting small-glyph read under 'Key'.
Output is limited to note-like text."""
import os, re, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
from PIL import Image
for p in sys.argv[1:]:
    img = Image.open(hlib.H / p).convert("RGB")
    toks = hlib.ocr(img.resize((img.width * 2, img.height * 2)))
    votes = Counter()
    for dx, dy in ((20, (4, 30)), (28, (4, 30)), (40, (4, 30)), (20, (2, 40)), (40, (2, 40)), (34, (6, 34))):
        raw = hlib._value_under(img, toks, r"Key", 2.0, dy=dy, dx=dx) or ""
        m = re.match(r"^\s*([A-G])\s*([#♯b♭])?", raw)
        if m:
            votes[m[1] + (m[2] or "")] += 1
    print(p.split("/")[-1], dict(votes))
sys.stdout.flush(); os._exit(0)
