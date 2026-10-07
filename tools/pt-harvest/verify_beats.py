"""Second, independent listening pass over the harvested 11 kHz bounces (run on the MBP after
`sv.sh pull`, with any python that has numpy, e.g. tools/train-tempocnn/.venv/bin/python).

Per usable row (ids only, no names):
  beat  audiocheck over 8 windows of 6 s spread over the song: share of windows judged beat / vocal / silent
  mix   same on the full mix (must not be silent)
  resid mix - beat (both printed from sample 0 over the same span, so the difference is roughly what the
        beat lacks: the vocals). It must carry real energy (resid_db well above silence) and be vocal-ish
        (voice-band share above the beat's own) -- a 'beat' that already contains the vocals gives a
        near-silent residual.
  pass  = at least half of the non-silent beat windows judged 'beat' (sub-bass + onset pulse), at most 3 of 8
          'vocal'-looking windows (bass-less intros/breaks look like that too), and, when the mix exists, a
          residual that is not near-silent and more voice-band than the beat. The in-harvest complement probe
          (beat muted -> must sound like vocals) is shown from the DB's beat_check.
usage: verify_beats.py [--db DB] [--audio-dir DIR] [--ids 1,2,..] [--only-new]   (--only-new: rows the v1
       name-only rule would have skipped, old_rule = 0)"""
from __future__ import annotations
import argparse, json, os, sqlite3, sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audiocheck as ac

ROOT = Path(__file__).resolve().parents[2]
GT = ROOT / "docs/research/pt-ground-truth"


def windows(x, n=8, w=6.0):
    L = int(w * ac.SR)
    if len(x) < L * 2:
        return [x]
    starts = [int((len(x) - L) * (i + 0.5) / n) for i in range(n)]
    return [x[s:s + L] for s in starts]


def judge(x, tempo):
    import numpy as np
    vs, fes = [], []
    for seg in windows(x):
        fe = ac.features_x(np.asarray(seg, dtype="float64"), tempo)
        fes.append(fe)
        vs.append(ac.verdict(fe)[0] if fe.get("mean_db") is not None else "silent")
    med = lambda k: float(np.median([f[k] for f in fes if f.get(k) is not None])) if fes else None  # noqa: E731
    return {"beat": vs.count("beat"), "vocal": vs.count("vocal"), "silent": vs.count("silent"),
            "unclear": vs.count("unclear"), "n": len(vs), "sub": round(med("sub"), 3), "voice": round(med("voice"), 3),
            "pulse": round(med("pulse") if tempo else med("pulse_any"), 3)}


def main():
    import numpy as np
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=GT / "pt-ground-truth.sqlite3", type=Path)
    ap.add_argument("--audio-dir", default=GT / "audio11k", type=Path)
    ap.add_argument("--ids")
    ap.add_argument("--only-new", action="store_true")
    a = ap.parse_args()
    con = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True)
    cols = {r[1] for r in con.execute("PRAGMA table_info(sessions)")}
    q = "SELECT id, session_tempo, beat_wav_path, " + ("mix_wav_path" if "mix_wav_path" in cols else "NULL") + \
        ", " + ("old_rule" if "old_rule" in cols else "NULL") + ", " + ("beat_source" if "beat_source" in cols else "NULL") + \
        ", " + ("beat_check" if "beat_check" in cols else "NULL") + \
        " FROM sessions WHERE beat_wav_path IS NOT NULL"
    rows = con.execute(q + " ORDER BY id").fetchall()
    if a.ids:
        keep = {int(i) for i in a.ids.split(",")}
        rows = [r for r in rows if r[0] in keep]
    if a.only_new:
        rows = [r for r in rows if r[4] == 0]
    npass = 0
    for sid, tempo, beat, mix, old, src, chk in rows:
        bp = a.audio_dir / f"{sid:04d}.wav"
        if not bp.exists():
            print(f"#{sid:04d} no 11k beat file"); continue
        xb = ac.load(bp)
        rb = judge(xb, tempo)
        out = {"id": sid, "src": src, "old_rule": old, "beat": rb,
               "complement": (json.loads(chk).get("complement") or {}).get("v") if chk else None}
        ok = rb["vocal"] <= 3 and rb["beat"] >= max(2, (rb["n"] - rb["silent"] + 1) // 2)
        mp = a.audio_dir / f"{sid:04d}_mix.wav"
        if mp.exists():
            xm = ac.load(mp)
            L = min(len(xm), len(xb))
            res = xm[:L] - xb[:L]
            db = lambda v: round(float(20 * np.log10(np.sqrt(np.mean(v * v)) + 1e-12)), 1)  # noqa: E731
            rr = judge(res, tempo)
            out["mix_db"], out["resid_db"], out["beat_db"] = db(xm[:L]), db(res), db(xb[:L])
            out["resid"] = rr
            # vocals present in the mix but absent from the beat: the residual is not near-silent and is
            # more voice-band than the beat itself
            out["resid_ok"] = out["resid_db"] > out["mix_db"] - 30 and rr["voice"] > rb["voice"]
            ok = ok and out["resid_ok"]
        out["pass"] = bool(ok)
        npass += ok
        print(json.dumps(out))
    print(f"verified {npass}/{len(rows)} pass")


if __name__ == "__main__":
    main()
