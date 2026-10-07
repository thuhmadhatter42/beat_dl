#!/usr/bin/env python3
"""beat_dl's key detector (bpm.py, as shipped) vs the harvested key, beat bounce and full-mix bounce.

Runs under the analyzer Python (essentia). Needs the FULL-RATE wavs (the key detector wants 44.1 kHz;
the 11 kHz copies are for TempoCNN), so they are read from --full-dir, a scratch folder holding the
rows' `audio/<file>` bounces. File names are never printed; rows are 'pt0001' / 'pt0001m' ids.
Score: exact top-1 and in-top-3 on (pitch class, mode); enharmonic spellings are equal.

Usage: bin/python/bin/python3 tools/train-tempocnn/key_eval.py --full-dir DIR [--db DB] [--out TSV]
"""
import argparse
import os
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402

FLAT = {"Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#", "Cb": "B", "Fb": "E", "E#": "F", "B#": "C"}
NOTES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']


def norm(s):
    """'Eb minor' / 'D#m' / 'F major' / 'F' -> (pitch class, 'major'|'minor')"""
    s = s.strip()
    minor = s.endswith("m") or s.endswith("minor")
    tonic = s.replace("minor", "").replace("major", "").rstrip("m").strip()
    tonic = FLAT.get(tonic, tonic)
    return NOTES.index(tonic), "minor" if minor else "major"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--full-dir", required=True, type=Path)
    ap.add_argument("--db", default=common.ROOT.parents[2] / "docs/research/pt-ground-truth/pt-ground-truth.sqlite3", type=Path)
    ap.add_argument("--out", type=Path)
    a = ap.parse_args()
    os.environ["PATH"] = str(common.analyzer_python().parents[2]) + os.pathsep + os.environ.get("PATH", "")
    import essentia
    essentia.log.infoActive = essentia.log.warningActive = False
    import bpm

    con = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True)
    rows = con.execute("SELECT id, key, beat_wav_path, mix_wav_path FROM sessions WHERE key IS NOT NULL "
                       "AND bpm_confidence IN ('confirmed','tempo-only') AND beat_wav_path IS NOT NULL ORDER BY id").fetchall()
    res = []
    for sid, key, beat, mix in rows:
        truth = norm(key)
        for kind, wav, suf in (("beat", beat, ""), ("mix", mix, "m")):
            if not wav:
                continue
            f = a.full_dir / Path(wav).name
            if not f.is_file():
                print(f"pt{sid:04d}{suf}: full-rate file missing", file=sys.stderr)
                continue
            a_key, _ = bpm.load_audio_essentia(f)
            top3 = [norm(k) for k, _ in bpm.detect_keys_essentia(a_key)]
            res.append((f"pt{sid:04d}{suf}", kind, truth, top3))
            print(f"pt{sid:04d}{suf} {kind} done", flush=True)
    print("\n| group | n | top-1 exact | in top-3 |\n|---|---:|---:|---:|")
    for g in ("beat", "mix", "both"):
        r = [x for x in res if g == "both" or x[1] == g]
        n = len(r)
        t1 = sum(x[3][0] == x[2] for x in r)
        t3 = sum(x[2] in x[3] for x in r)
        print(f"| {g} | {n} | {t1} ({100 * t1 / max(n, 1):.1f}%) | {t3} ({100 * t3 / max(n, 1):.1f}%) |")
    if a.out:
        with open(a.out, "w") as f:
            f.write("id\tkind\ttop1_ok\ttop3_ok\n")
            for i, k, t, p in res:
                f.write(f"{i}\t{k}\t{int(p[0] == t)}\t{int(t in p)}\n")


if __name__ == "__main__":
    main()
