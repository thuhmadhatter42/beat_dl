"""Dev aid (calibration): on the OPEN session, probe-bounce 8 s at 3 spots with (a) the vocal folders
soloed, (b) the beat folder soloed, (c) nothing soloed (full mix), and print audiocheck features.
Never saves; restores solo state. Probes land in ~/pt-harvest/audio/cal-*.wav (Sofia only)."""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audiocheck as ac
import hlib
from hlib import H

c = hlib.client()
tl = hlib.tracks(c)
sr = int(float(c.send("CId_GetSessionSampleRate").get("sample_rate", "SR_48000").split("_")[-1])) \
    if False else None
info = hlib.parse_info(hlib.export_info(c, "TLType_Samples"))
sr = int(float(info["header"].get("SAMPLE RATE", "48000")))
end = 0
for t in info["tracks"]:
    for e in t["edl"]:
        try:
            end = max(end, int(e["end"]))
        except ValueError:
            pass
voc = [t["name"] for t in tl if t["type"].endswith("Folder") and re.search(r"vocal|vox", t["name"], re.I)]
beat = [t["name"] for t in tl if t["type"].endswith("Folder") and hlib.is_beat_buss(t["name"])]
src = hlib.pick_source(hlib.export_sources(c)) or hlib.export_sources(c)[0]
prior = [t["name"] for t in tl if hlib.attr(t, "is_soloed")]
print("vocal folders", len(voc), "beat folders", len(beat), "prior solos", len(prior))
tempo = float(sys.argv[1]) if len(sys.argv) > 1 else None
for p in prior:
    hlib.solo(c, p, False)
try:
    for tag, names in (("vocal", voc), ("beat", beat), ("mix", [])):
        if tag != "mix" and not names:
            continue
        for nm in names:
            hlib.solo(c, nm, True)
        for frac in (0.3, 0.5, 0.7):
            a = int(end * frac)
            hlib.set_selection_samples(c, a, a + 8 * sr)
            st, _ = hlib.export_mix(c, str(H / "audio"), f"cal-{tag}", sr, src, timeout=600)
            p = H / "audio" / f"cal-{tag}.wav"
            fe = ac.features(p, tempo)
            print(tag, frac, st, ac.verdict(fe), json.dumps({k: fe.get(k) for k in ("mean_db", "sub", "low", "voice", "air", "flat", "onset_rate", "pulse", "lowpulse", "pulse_any")}))
            p.unlink(missing_ok=True)
        for nm in names:
            hlib.solo(c, nm, False)
finally:
    for p in prior:
        hlib.solo(c, p, True)
sys.stdout.flush(); os._exit(0)
