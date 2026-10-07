#!/usr/bin/env python3
"""Parity: the torch replica vs tempocnn_np.py, on cached bench / label features.

For every track:
  - patches = tempocnn_np.patches(cached bands)                     (same input for both)
  - numpy logits via tempocnn_np's own layers (checked bit-equal to tempocnn_np.predict after softmax)
  - torch logits on CPU and on MPS
  - global BPM (tempocnn_np.aggregate) from torch == ref.json, which features.py wrote by running
    tempocnn_np.tempo(audio) in the analyzer Python (the shipped inference path, end to end)
Exit 1 if any global BPM differs.

Usage: tools/train-tempocnn/.venv/bin/python tools/train-tempocnn/parity.py --bench bpm-bench,key-bench
       ... --labels LABELS.csv
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import model as M  # noqa: E402

tn = common.tempocnn_np


def np_logits(P):
    """tempocnn_np.predict without its last softmax lines (same helpers, same order)."""
    W = tn._weights()
    x = np.asarray(P, dtype=np.float32)
    for i in range(12):
        x = np.maximum(tn._conv_time(x, W[f'conv{i}_w'], W[f'conv{i}_b']), 0)
        mul = (np.float32(1) / np.sqrt(W[f'bn{i}_var'] + W[f'bn{i}_eps'])) * W[f'bn{i}_gamma']
        x = x * mul + (W[f'bn{i}_beta'] - W[f'bn{i}_mean'] * mul)
        if i in tn._POOL_AFTER:
            x = tn._maxpool(x, *tn._POOL_AFTER[i])
    x = np.maximum(x @ np.ascontiguousarray(W['head_w'].T) + W['head_b'], 0)
    return x.mean(axis=(1, 2), dtype=np.float32)


def np_softmax(logits):
    e = np.exp(logits - logits.max(axis=1, keepdims=True))
    return (e / e.sum(axis=1, keepdims=True)).astype(np.float32)


@torch.no_grad()
def torch_logits(m, P, dev, bs=64):
    out = []
    for i in range(0, len(P), bs):
        out.append(m(M.to_torch(P[i:i + bs]).to(dev)).float().cpu().numpy())
    return np.concatenate(out) if out else np.zeros((0, 256), np.float32)


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--labels")
    g.add_argument("--bench")
    a = ap.parse_args()
    tracks = common.tracks_from_args(a.labels, a.bench)
    tn.WEIGHTS, tn._W = common.ORIG_NPZ, None
    devs = [torch.device("cpu")] + ([torch.device("mps")] if torch.backends.mps.is_available() else [])
    models = {d.type: M.load_npz(common.ORIG_NPZ).to(d).eval() for d in devs}
    stats = {d.type: dict(glob_eq=0, patch_eq=0, max_logit=0.0, max_prob=0.0) for d in devs}
    n_patch = 0
    bad = []
    for t in tracks:
        ref = json.loads((common.cache_dir(t["id"]) / "ref.json").read_text())
        P = tn.patches(common.load_bands(t["id"]))
        if len(P) == 0:
            continue
        ln = np_logits(P)
        pn = tn.predict(P)
        assert np.array_equal(np_softmax(ln), pn), "np_logits drifted from tempocnn_np.predict"
        assert tn.aggregate(pn)[0] == ref["global_bpm"], "cached ref != tempocnn_np in this venv"
        n_patch += len(P)
        for d in devs:
            lt = torch_logits(models[d.type], P, d)
            pt = np_softmax(lt)
            s = stats[d.type]
            gt = tn.aggregate(pt)[0]
            s["glob_eq"] += gt == ref["global_bpm"]
            s["patch_eq"] += int((pt.argmax(1) == pn.argmax(1)).sum())
            s["max_logit"] = max(s["max_logit"], float(np.abs(lt - ln).max()))
            s["max_prob"] = max(s["max_prob"], float(np.abs(pt - pn).max()))
            if gt != ref["global_bpm"]:
                bad.append((d.type, t["id"], gt, ref["global_bpm"]))
    print(f"parity on {len(tracks)} tracks, {n_patch} patches (reference: tempocnn_np.tempo in the analyzer Python)")
    for d, s in stats.items():
        print(f"  {d:4s} global BPM equal {s['glob_eq']}/{len(tracks)}  per-patch class equal "
              f"{s['patch_eq']}/{n_patch}  max|logit diff| {s['max_logit']:.3g}  max|prob diff| {s['max_prob']:.3g}")
    for b in bad:
        print("  MISMATCH", *b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
