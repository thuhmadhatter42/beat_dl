"""Dev aid: on the OPEN session, compare ways to isolate the Beat Buss members (name-free):
 A) solo only the member AUDIO tracks (not the folder)  B) mute every other live audio track
 C) complement: mute the members instead. Prints audiocheck per probe. Restores state; never saves."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audiocheck as ac
import hlib
from hlib import H

c = hlib.client()
tl = hlib.tracks(c)
info = hlib.parse_info(hlib.export_info(c, "TLType_Samples"))
sr = int(float(info["header"].get("SAMPLE RATE", "48000")))
end = max(int(e["end"]) for t in info["tracks"] for e in t["edl"] if e["end"].isdigit())
f, kids = hlib.beat_tree(tl)
kida = [k["name"] for k in kids if k["type"] == "TType_Audio"]
others = [t["name"] for t in tl if t["type"] == "TType_Audio" and t["name"] not in kida and not hlib.attr(t, "is_muted")]
print("beat audio kids", len(kida), "other live audio", len(others))
src = hlib.pick_source(hlib.export_sources(c)) or hlib.export_sources(c)[0]


def probe(tag):
    a = int(end * 0.5)
    hlib.set_selection_samples(c, a, a + 8 * sr)
    st, _ = hlib.export_mix(c, str(H / "audio"), f"cal-{tag}", sr, src, timeout=600)
    p = H / "audio" / f"cal-{tag}.wav"
    fe = ac.features(p)
    print(tag, st, ac.verdict(fe), json.dumps({k: fe.get(k) for k in ("mean_db", "sub", "voice", "pulse_any")}))
    p.unlink(missing_ok=True)


def mute(names, on):
    if names:
        c.status_of("CId_SetTrackMuteState", {"track_names": names, "enabled": on})


c.status_of("CId_SetTrackSoloState", {"track_names": kida, "enabled": True})
probe("A-solo-kids")
c.status_of("CId_SetTrackSoloState", {"track_names": kida, "enabled": False})
mute(others, True)
probe("B-mute-others")
mute(others, False)
mute(kida, True)
probe("C-complement")
mute(kida, False)
print("solo/mute left on:", sum(1 for t in hlib.tracks(c) if hlib.attr(t, "is_soloed")),
      sum(1 for t in hlib.tracks(c) if hlib.attr(t, "is_muted")))
sys.stdout.flush(); os._exit(0)
