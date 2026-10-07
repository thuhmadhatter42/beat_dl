"""Name-safe screen view for Sofia (J 2026-10-06: no song/artist/file names in transcripts).
Takes a full screenshot (kept only on Sofia, ~/pt-harvest/shots/full-<tag>.png) and writes
viewable derivatives to /tmp/pth_view/:
  thumb-<tag>.png   downscaled to --thumb width (default 640): layout + dialogs, text illegible
  crop-<tag>.png    --crop x,y,w,h at --scale (default 2x) for a region known to hold no names
  --mask x,y,w,h    (repeatable) blacks out a region in every derivative
usage: view.py <tag> [--thumb 640] [--crop x,y,w,h] [--scale 2] [--mask x,y,w,h ...]
Prints the derivative paths only."""
import os, subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw

args = sys.argv[1:]
tag = args.pop(0)


def opt(name, default=None, multi=False):
    vals = []
    while name in args:
        i = args.index(name); vals.append(args[i + 1]); del args[i:i + 2]
    return vals if multi else (vals[-1] if vals else default)


thumb_w = int(opt("--thumb", "480"))
crop = opt("--crop")
scale = float(opt("--scale", "2"))
masks = opt("--mask", multi=True)
full = Path.home() / "pt-harvest" / "shots" / f"full-{tag}.png"
full.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(["screencapture", "-x", str(full)], check=True)
img = Image.open(full).convert("RGB")
if img.size[0] != 1920:
    img = img.resize((1920, int(img.size[1] * 1920 / img.size[0])))
d = ImageDraw.Draw(img)
for m in masks:
    x, y, w, h = map(int, m.split(","))
    d.rectangle([x, y, x + w, y + h], fill=(0, 0, 0))
out = Path("/tmp/pth_view"); out.mkdir(exist_ok=True)
lum = sum(img.resize((16, 9)).convert("L").get_flattened_data()) / 144
print(f"mean_luma {lum:.0f}")
if thumb_w > 0:
    t = img.resize((thumb_w, int(img.size[1] * thumb_w / img.size[0])), Image.LANCZOS)
    t.save(out / f"thumb-{tag}.png"); print(out / f"thumb-{tag}.png")
if crop:
    x, y, w, h = map(int, crop.split(","))
    c = img.crop((x, y, x + w, y + h)).resize((int(w * scale), int(h * scale)), Image.LANCZOS)
    c.save(out / f"crop-{tag}.png"); print(out / f"crop-{tag}.png")
sys.stdout.flush(); os._exit(0)
