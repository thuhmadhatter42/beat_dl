#!/usr/bin/env python3
"""Key-detection baseline: Beat Key's shipping key detector (bpm.py: essentia HPCP -> 'bgate' profiles,
the same keys_from_hpcp the app's analyzer and live listener use) scored against the harvested keys
in the PT ground-truth DB. Also scores the 'edma' profile on the same HPCP frames (the variant bpm.py
keeps for its librosa fallback) so a trained model has two numbers to beat.

Scoring per file, top-1 vs truth (pitch class + mode, enharmonics equal):
  exact | relative (C <-> Am) | fifth (same mode, +-7 semitones) | parallel (C <-> Cm) | other
plus in-top-3 exact (the app shows 3 keys) and the MIREX weighted score (1 / .5 / .3 / .2 / 0).

Audio: rows' `beat_wav_path` (and `mix_wav_path`) are 'audio/NNNN.wav' on Sofia; --audio-root holds
the files by base name (the local 11 kHz copies by default). The detector decodes and resamples to
44.1 kHz exactly as the app does (bpm.load_audio_essentia). Its HPCP reads only 25-3500 Hz, which an
11 kHz file (Nyquist 5.5 kHz) still carries; --parity-dir measures how much the 11 kHz round trip
changes the answer on full-rate files.

Privacy: no file, song or artist names are printed or logged; rows are 'pt0001' (beat) / 'pt0001m' (mix).
Per-file errors are logged and skipped; the run never dies on one bad file.

Run with the analyzer Python (has essentia):
  bin/python/bin/python3 tools/train-tempocnn/key_baseline.py \
      --db docs/research/pt-ground-truth/pt-ground-truth.sqlite3 \
      --audio-root docs/research/pt-ground-truth/audio11k \
      --out tools/train-tempocnn/runs/key-baseline-2026-11-05 [--parity-dir docs/research/key-bench/audio]
Writes <out>/results.tsv, <out>/summary.md, <out>/key_baseline.log.
"""
import argparse
import logging
import os
import sqlite3
import sys
import time
import traceback
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import common  # noqa: E402  (puts the checkout root on sys.path, so `import bpm` works)

NOTES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
FLAT = {"Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#", "Cb": "B", "Fb": "E", "E#": "F", "B#": "C"}
CATS = ("exact", "relative", "fifth", "parallel", "other")
MIREX = {"exact": 1.0, "fifth": 0.5, "relative": 0.3, "parallel": 0.2, "other": 0.0}
log = logging.getLogger("key_baseline")


def norm(s):
    """'Eb minor' / 'D#m' / 'F major' / 'F' -> (pitch class, 'major'|'minor')"""
    s = s.strip()
    minor = s.endswith("minor") or (s.endswith("m") and not s.endswith("major"))
    tonic = s.replace("minor", "").replace("major", "").strip()
    if tonic.endswith("m"):
        tonic = tonic[:-1]
    tonic = FLAT.get(tonic, tonic)
    return NOTES.index(tonic), "minor" if minor else "major"


def category(truth, pred):
    (tp, tm), (pp, pm) = truth, pred
    if (tp, tm) == (pp, pm):
        return "exact"
    if tm != pm and pp == tp:
        return "parallel"
    if tm == "major" and pm == "minor" and pp == (tp + 9) % 12:
        return "relative"
    if tm == "minor" and pm == "major" and pp == (tp + 3) % 12:
        return "relative"
    if tm == pm and (pp - tp) % 12 in (5, 7):
        return "fifth"
    return "other"


def top3_from_scores(scores):
    return [k for k, _ in sorted(scores.items(), key=lambda kv: -kv[1])[:3]]


def detect(bpm, path):
    """-> {'bgate': [top3 (pc, mode)], 'edma': [...]} via the app's own decode + HPCP chain."""
    a_key, _ = bpm.load_audio_essentia(path)
    H = bpm.hpcp_frames(a_key)
    shipped = [norm(k) for k, _ in bpm.keys_from_hpcp(H)]          # exactly what the app shows
    pcp = bpm.hpcp_to_pcp12(H.mean(axis=0))
    return {"bgate": shipped, "edma": top3_from_scores(bpm.key_scores(pcp, bpm.EDMA))}


def table(rows, variant, group_key):
    groups = defaultdict(list)
    for r in rows:
        groups["all"].append(r)
        groups[group_key(r)].append(r)
    out = ["| group | n | top-1 exact | in top-3 | relative | fifth | parallel | other | MIREX |",
           "|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for g in sorted(groups, key=lambda x: (x != "all", x)):
        rs = groups[g]
        n = len(rs)
        c = Counter(category(r["truth"], r[variant][0]) for r in rs)
        t3 = sum(r["truth"] in r[variant] for r in rs)
        mirex = sum(MIREX[category(r["truth"], r[variant][0])] for r in rs) / max(n, 1)
        pct = lambda k: f"{k} ({100 * k / max(n, 1):.0f}%)"  # noqa: E731
        out.append(f"| {g} | {n} | {pct(c['exact'])} | {pct(t3)} | {c['relative']} | {c['fifth']} | "
                   f"{c['parallel']} | {c['other']} | {mirex:.3f} |")
    return "\n".join(out)


def parity(bpm, folder, limit):
    """Full-rate file vs the same file squeezed through 11025 Hz and back: does the top-1 change?"""
    import essentia.standard as es
    files = sorted(p for p in folder.iterdir() if p.suffix.lower() in (".mp3", ".wav", ".flac"))[:limit]
    same1 = same3 = n = 0
    for i, f in enumerate(files):
        try:
            a44, _ = bpm.load_audio_essentia(f)
            down = es.Resample(inputSampleRate=44100, outputSampleRate=11025)(a44)
            up = es.Resample(inputSampleRate=11025, outputSampleRate=44100)(down)
            k_full = [norm(k) for k, _ in bpm.detect_keys_essentia(a44)]
            k_11k = [norm(k) for k, _ in bpm.detect_keys_essentia(up)]
            n += 1
            same1 += k_full[0] == k_11k[0]
            same3 += set(k_full) == set(k_11k)
            log.info("parity-%02d top1_same=%d top3_same=%d", i, k_full[0] == k_11k[0], set(k_full) == set(k_11k))
        except Exception as exc:
            log.error("parity-%02d failed: %s", i, exc)
    return n, same1, same3


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", required=True, type=Path)
    ap.add_argument("--audio-root", required=True, type=Path, help="folder holding NNNN.wav / NNNN_mix.wav by base name")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--no-mix", action="store_true", help="beat bounces only")
    ap.add_argument("--parity-dir", type=Path, help="full-rate audio for the 11 kHz round-trip check")
    ap.add_argument("--parity-limit", type=int, default=40)
    a = ap.parse_args()

    a.out.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s",
                        handlers=[logging.FileHandler(a.out / "key_baseline.log"), logging.StreamHandler()])
    sys.excepthook = lambda t, v, tb: log.critical("crash: %s", "".join(traceback.format_exception(t, v, tb)))
    os.environ["PATH"] = str(common.analyzer_python().parents[2]) + os.pathsep + os.environ.get("PATH", "")
    import essentia
    essentia.log.infoActive = essentia.log.warningActive = False
    import bpm

    con = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True)
    q = ("SELECT id, key, key_source, beat_wav_path, mix_wav_path FROM sessions "
         "WHERE key IS NOT NULL AND key != '' ORDER BY id")
    db_rows = con.execute(q).fetchall()
    log.info("start: %d keyed rows, audio root set, profiles bgate (shipping) + edma", len(db_rows))

    rows, failed = [], []
    t0 = time.time()
    for sid, key, src, beat, mix in db_rows:
        try:
            truth = norm(key)
        except Exception as exc:
            log.error("pt%04d: truth key unparsable (%s)", sid, exc)
            failed.append(f"pt{sid:04d}")
            continue
        for kind, wav, suf in (("beat", beat, ""), ("mix", mix, "m")):
            if not wav or (kind == "mix" and a.no_mix):
                continue
            rid = f"pt{sid:04d}{suf}"
            f = a.audio_root / Path(wav).name
            if not f.is_file():
                log.error("%s: audio missing under audio root", rid)
                failed.append(rid)
                continue
            try:
                d = detect(bpm, f)
            except Exception as exc:
                log.error("%s: detector failed: %s", rid, exc)
                failed.append(rid)
                continue
            rows.append({"id": rid, "kind": kind, "source": src or "?", "truth": truth, **d})
            log.info("%s %s truth=%s bgate=%s (%s) edma=%s (%s)", rid, kind, key,
                     bpm.fmt_key(*d["bgate"][0]), category(truth, d["bgate"][0]),
                     bpm.fmt_key(*d["edma"][0]), category(truth, d["edma"][0]))
    log.info("detected %d files in %.0f s, %d failed", len(rows), time.time() - t0, len(failed))

    fk = lambda k: bpm.fmt_key(*k)  # noqa: E731
    with open(a.out / "results.tsv", "w") as fh:
        fh.write("id\tkind\tkey_source\ttruth\tbgate_top3\tbgate_cat\tedma_top3\tedma_cat\n")
        for r in rows:
            fh.write(f"{r['id']}\t{r['kind']}\t{r['source']}\t{fk(r['truth'])}\t"
                     f"{','.join(map(fk, r['bgate']))}\t{category(r['truth'], r['bgate'][0])}\t"
                     f"{','.join(map(fk, r['edma']))}\t{category(r['truth'], r['edma'][0])}\n")

    md = [f"# Key baseline: {a.db.name}", "",
          f"{len(rows)} files scored, {len(failed)} failed ({', '.join(failed) or 'none'}).", ""]
    for variant, label in (("bgate", "bgate (shipping: bpm.keys_from_hpcp)"), ("edma", "edma (same HPCP, edma profile)")):
        for kind in ("beat", "mix"):
            rs = [r for r in rows if r["kind"] == kind]
            if not rs:
                continue
            md += [f"## {label}, {kind} bounces, by key_source", "", table(rs, variant, lambda r: r["source"]), ""]
    truth_modes = Counter(r["truth"][1] for r in rows if r["kind"] == "beat")
    md += [f"Truth modes (beat rows): {dict(truth_modes)}", ""]
    if a.parity_dir:
        n, s1, s3 = parity(bpm, a.parity_dir, a.parity_limit)
        md += ["## 11 kHz round-trip parity (full-rate vs 44.1k->11025->44.1k, shipping detector)", "",
               f"{n} files: top-1 unchanged {s1}/{n}, top-3 set unchanged {s3}/{n}.", ""]
    (a.out / "summary.md").write_text("\n".join(md))
    print("\n".join(md))
    log.info("done: wrote results.tsv, summary.md")


if __name__ == "__main__":
    main()
