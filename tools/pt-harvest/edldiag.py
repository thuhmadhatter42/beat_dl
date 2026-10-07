"""EDL tempo diagnostics for a harvested session N (numbers only)."""
import os, sys, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
n = int(sys.argv[1]); tempo = float(sys.argv[2]) if len(sys.argv) > 2 else None
bb = hlib.parse_info((hlib.H / "info" / f"{n:04d}-bb.txt").read_text())
sa = hlib.parse_info((hlib.H / "info" / f"{n:04d}-samples.txt").read_text())
sr = float(bb["header"]["SAMPLE RATE"])
pts = hlib.edl_points(bb, sa, 4)
print("points", len(pts), "sr", sr, "fit", hlib.edl_tempo(pts, sr))
spb = 60 * sr / (tempo or hlib.edl_tempo(pts, sr)[0])
res = [s - spb * b for b, s in pts]
print("intercept-free residuals (samples) by beat position, using tempo", tempo)
for (b, s), r in list(zip(pts, res))[:: max(1, len(pts) // 25)]:
    print(f"  beat {b:9.3f} sample {s:9d} resid {r:9.1f}")
sys.stdout.flush(); os._exit(0)
