#!/usr/bin/env python3
"""Write the labels CSV for train.py / features.py from the harvest DB (plan §4).

Takes rows with a BPM, a beat bounce, and bpm_confidence 'confirmed' or 'tempo-only' (or only
'confirmed' with --confirmed-only); 'excluded' and NULL never. The 11025 Hz copy is looked up in
--audio-dir by the bounce's file stem (an exact stem match, else the one file whose stem starts
with it). Paths are written relative to the CSV and never printed; only counts are.

Usage: python3 tools/train-tempocnn/labels_from_db.py \
         [--db docs/research/pt-ground-truth/pt-ground-truth.sqlite3] \
         [--audio-dir docs/research/pt-ground-truth/audio11k] \
         [--out docs/research/pt-ground-truth/labels.csv] [--confirmed-only]
"""
import argparse
import csv
import os
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GT = ROOT / "docs/research/pt-ground-truth"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=GT / "pt-ground-truth.sqlite3", type=Path)
    ap.add_argument("--audio-dir", default=GT / "audio11k", type=Path)
    ap.add_argument("--out", default=GT / "labels.csv", type=Path)
    ap.add_argument("--confirmed-only", action="store_true")
    a = ap.parse_args()
    con = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True)
    cols = {r[1] for r in con.execute("PRAGMA table_info(sessions)")}
    ok = ("'confirmed'",) if a.confirmed_only else ("'confirmed'", "'tempo-only'")
    where = "bpm IS NOT NULL AND beat_wav_path IS NOT NULL"
    if "bpm_confidence" in cols:
        where += f" AND bpm_confidence IN ({','.join(ok)})"
    rows = con.execute(f"SELECT id, bpm, artist, beat_wav_path FROM sessions WHERE {where} ORDER BY id").fetchall()
    wavs = list(a.audio_dir.glob("*.wav")) if a.audio_dir.is_dir() else []
    out, no_audio, no_artist = [], 0, 0
    for sid, bpm, artist, beat in rows:
        stem = Path(beat).stem
        hit = [w for w in wavs if w.stem == stem] or [w for w in wavs if w.stem.startswith(stem)]
        if len(hit) != 1:
            no_audio += 1
            continue
        if not artist:
            no_artist += 1
            artist = f"unknown-{sid}"           # its own group: never shared across the split
        out.append(dict(id=f"pt{sid:04d}", path=os.path.relpath(hit[0], a.out.parent),
                        bpm=f"{float(bpm):g}", artist=artist))
    a.out.parent.mkdir(parents=True, exist_ok=True)
    with open(a.out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["id", "path", "bpm", "artist"])
        w.writeheader()
        w.writerows(out)
    print(f"labels: {len(out)} rows written ({len({r['artist'] for r in out})} artists); "
          f"{len(rows)} usable DB rows, {no_audio} without a unique 11 kHz file, {no_artist} without artist")


if __name__ == "__main__":
    main()
