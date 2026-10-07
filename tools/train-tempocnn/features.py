#!/usr/bin/env python3
"""Feature cache for TempoCNN fine-tuning. Runs under the bundled analyzer Python (bin/python/bin/python3,
essentia, no torch), so the front end is the shipped one, byte for byte:

  audio  = bpm.load_audio_essentia(path)[1]        decode -> MonoMixer -> Resample to 11025 Hz
  bands  = tempocnn_np.mel_bands(audio)            essentia FrameCutter(1024, 512) + TensorflowInputTempoCNN
  ref    = tempocnn_np.tempo(audio)                the shipped numpy TempoCNN, for the parity check

Patching + per-patch z-score (tempocnn_np.patches) is applied later, on the cached bands.

Augmentation (--augment): tempo-shift by resampling, as in Schreiber & Mueller 2018. For factor f the
11025 Hz audio is resampled to 11025/f Hz and read back as 11025 Hz, so it plays f times faster (tempo
and pitch x f); the label becomes bpm * f. Factors whose label leaves 30-285 BPM are skipped.

Cache: cache/<id>/f1.00.npy (float32, exact), f<f>.npy (float16, augmented; training only), ref.json,
meta.json. Re-running skips tracks whose source file and settings are unchanged.

Usage:
  bin/python/bin/python3 tools/train-tempocnn/features.py --labels LABELS.csv [--augment] [-j 6]
  bin/python/bin/python3 tools/train-tempocnn/features.py --bench bpm-bench,key-bench [--augment]
"""
import argparse
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402

SR = 11025


def _setup():
    # bpm.decode_ffmpeg wants the bundled ffmpeg (ROOT/bin, else PATH): point PATH at the bin/ next to
    # the analyzer Python so a worktree uses the same ffmpeg the app ships.
    os.environ["PATH"] = str(common.analyzer_python().parents[2]) + os.pathsep + os.environ.get("PATH", "")
    import essentia
    essentia.log.infoActive = False
    essentia.log.warningActive = False


def one(t, augment):
    _setup()
    import essentia.standard as es
    import bpm as bpm_mod
    import tempocnn_np
    d = common.cache_dir(t["id"])
    factors = [1.0]
    if augment and t["bpm"]:
        factors = [f for f in common.FACTORS
                   if common.BPM_MIN <= round(t["bpm"] * f) <= common.BPM_MAX]
        if 1.0 not in factors:
            factors.append(1.0)
    key = common.path_key(t["path"])
    meta = common.cache_meta(t["id"])
    if meta and meta["key"] == key and set(factors) <= set(meta["factors"]):
        return t["id"], "cached", meta
    d.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    audio = bpm_mod.load_audio_essentia(t["path"])[1]
    bands = tempocnn_np.mel_bands(audio)
    np.save(d / common.fname(1.0), bands.astype(np.float32))
    g, local, _ = tempocnn_np.tempo(audio)
    (d / "ref.json").write_text(json.dumps(dict(global_bpm=float(g), local=[float(x) for x in local])))
    for f in factors:
        if f == 1.0:
            continue
        a = es.Resample(inputSampleRate=SR, outputSampleRate=SR / f)(audio)
        np.save(d / common.fname(f), tempocnn_np.mel_bands(a).astype(np.float16))
    meta = dict(key=key, factors=sorted(factors), n_frames=int(len(bands)), secs=round(time.time() - t0, 1))
    (d / "meta.json").write_text(json.dumps(meta))
    return t["id"], "done", meta


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--labels")
    g.add_argument("--bench", help="bpm-bench and/or key-bench, comma-separated")
    ap.add_argument("--augment", action="store_true")
    ap.add_argument("-j", type=int, default=6)
    a = ap.parse_args()
    tracks = common.tracks_from_args(a.labels, a.bench)
    missing = [t["id"] for t in tracks if not Path(t["path"]).is_file()]
    if missing:
        raise SystemExit(f"{len(missing)} audio file(s) missing, ids: {', '.join(missing)}")
    t0 = time.time()
    n_short = 0
    with ProcessPoolExecutor(max_workers=a.j) as ex:
        futs = [ex.submit(one, t, a.augment) for t in tracks]
        for i, fu in enumerate(as_completed(futs), 1):
            tid, how, meta = fu.result()
            n_short += meta["n_frames"] < tempocnn_np_patch()
            print(f"[{i}/{len(tracks)}] {tid} {how} frames={meta['n_frames']} factors={len(meta['factors'])}",
                  flush=True)
    print(f"features: {len(tracks)} tracks in {time.time() - t0:.0f}s; {n_short} under 256 frames (no patch)")


def tempocnn_np_patch():
    return common.tempocnn_np.PATCH


if __name__ == "__main__":
    main()
