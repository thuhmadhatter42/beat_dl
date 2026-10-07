"""Test toolbar OCR + bring-forward on the open session; crops saved to ~/pt-harvest/crops/ (Sofia)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
tag = sys.argv[1]
print("frontmost before:", hlib.frontmost())
if "--forward" in sys.argv:
    print("bring forward ->", hlib.bring_pt_forward(), "frontmost:", hlib.frontmost())
d = hlib.H / "crops"; d.mkdir(exist_ok=True)
img = hlib.screenshot(d / f"full-{tag}.png")
print(hlib.read_toolbar(img))
hlib.crop(img, hlib.TOOLBAR, 1.0).save(d / f"toolbar-{tag}.png")
print("toolbar tokens:", [t[0] for t in hlib.ocr(hlib.crop(img, hlib.TOOLBAR, 2.0))])
sys.stdout.flush(); os._exit(0)
