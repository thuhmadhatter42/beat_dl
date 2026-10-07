"""OCR a saved crop (path under ~/pt-harvest) and print SHORT tokens only (<=14 chars, no spaces
beyond one) with boxes — enough to tune label/value matching without printing preset/track names."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
from PIL import Image
img = Image.open(hlib.H / sys.argv[1]).convert("RGB")
sc = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0
img = img.resize((int(img.width * sc), int(img.height * sc)), Image.LANCZOS)
for t in hlib.ocr(img):
    s = t[0].strip()
    # only numbers/notes or known plug-in UI words are printed (track/preset names never)
    ui = {"key", "scale", "retune speed", "humanize", "input type", "tracking", "minor", "major", "chromatic",
          "bypass", "mix", "output", "formant", "learn", "auto-tune", "hold", "flex tune", "transpose", "detune",
          "classic", "modern", "auto mode", "graph mode", "auto key", "motion trigger", "toggle", "efx", "motion"}
    ok = s.lower() in ui or re.fullmatch(r"[-+]?[\d.]+\s*(%|dB|Hz|ms)?|[A-G][#b]?\d?", s) is not None
    print(f"{s if ok else '<long>'!r:20s} conf={t[1]:.2f} x={t[2]:.0f} y={t[3]:.0f} w={t[4]:.0f} h={t[5]:.0f}")
sys.stdout.flush(); os._exit(0)
