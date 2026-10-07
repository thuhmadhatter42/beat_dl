#!/usr/bin/env python3
"""Fine-tune deeptemp-k16-3 on labelled beats, export an .npz that tempocnn_np.py loads unchanged.

  1. split by artist (fixed seed): test (~25 %, untouched here), val (~15 % of the rest, early
     stopping), train. No artist on two sides. Saved to runs/<name>/split.json for eval.py.
  2. each epoch: --ppt random 256-frame patches per train track, each from a random tempo-shift factor
     (cached by features.py --augment), label round(bpm * f) - 30, z-scored by tempocnn_np.patches.
  3. Adam at a low LR, BatchNorm statistics frozen; after every epoch the val tracks are scored the
     way inference does (all patches, hop 128, f = 1.0): mean CE + Acc1 of the majority vote.
     Best val Acc1 wins (val CE breaks ties); stop after --patience epochs without improvement. Epoch 0 = the original.
  4. export the best weights (same keys/shapes/dtypes), then prove it: torch == numpy logits on the
     new file, and check_npz.py (analyzer Python, tempocnn_np unchanged) gives the same global BPMs.

Usage (features first, see README):
  tools/train-tempocnn/.venv/bin/python tools/train-tempocnn/train.py --labels LABELS.csv
  smoke test: ... --bench bpm-bench --run-name smoke --out tools/train-tempocnn/runs/smoke/smoke.npz
"""
import argparse
import copy
import json
import random
import re
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import model as M  # noqa: E402
from parity import np_logits  # noqa: E402

tn = common.tempocnn_np
PATCH = tn.PATCH


def next_ft_path():
    ns = [int(m.group(1)) for p in common.MODELS.glob("deeptemp-k16-3-ft*.npz")
          if (m := re.fullmatch(r"deeptemp-k16-3-ft(\d+)\.npz", p.name))]
    return common.MODELS / f"deeptemp-k16-3-ft{max(ns, default=0) + 1}.npz"


def label(bpm, f=1.0):
    return int(np.clip(round(bpm * f), common.BPM_MIN, common.BPM_MAX)) - common.BPM_MIN


class TrainSet:
    def __init__(self, tracks, augment):
        self.items = []                       # (bands per factor dict, bpm)
        for t in tracks:
            meta = common.cache_meta(t["id"])
            if meta is None:
                raise SystemExit(f"no features for id {t['id']}: run features.py first")
            if meta["n_frames"] < PATCH:
                continue
            fs = meta["factors"] if augment else [1.0]
            self.items.append(({f: common.load_bands(t["id"], f, mmap=True) for f in fs}, t["bpm"]))

    def batch(self, rng, n):
        X, y = [], []
        for _ in range(n):
            bands, bpm = self.items[rng.integers(len(self.items))]
            f = list(bands)[rng.integers(len(bands))]
            b = bands[f]
            if len(b) < PATCH:
                f, b = 1.0, bands[1.0]
            o = rng.integers(len(b) - PATCH + 1)
            X.append(tn.patches(np.asarray(b[o:o + PATCH], np.float32))[0])
            y.append(label(bpm, f))
        return M.to_torch(np.stack(X)), torch.tensor(y)


def inference_set(tracks):
    """Per track: all inference patches at f = 1.0 (exactly tempocnn_np.tempo's input)."""
    out = []
    for t in tracks:
        P = tn.patches(common.load_bands(t["id"]))
        if len(P):
            out.append((t, M.to_torch(P)))
    return out


@torch.no_grad()
def score(m, vset, dev):
    m.eval()
    ce, n, a1 = 0.0, 0, 0
    for t, X in vset:
        lg = m(X.to(dev))
        y = torch.full((len(X),), label(t["bpm"]), device=dev)
        ce += float(F.cross_entropy(lg, y, reduction="sum"))
        n += len(X)
        a1 += common.acc1(tn.aggregate(torch.softmax(lg, 1).cpu().numpy())[0], t["bpm"])
    return ce / max(n, 1), a1 / max(len(vset), 1)


def verify_export(npz, tracks, dev):
    """The exported file, read back two ways, must reproduce the trained torch model."""
    m = M.load_npz(npz).to(dev).eval()
    tn.WEIGHTS, tn._W = Path(npz), None
    max_d, glob = 0.0, {}
    with torch.no_grad():
        for t, X in inference_set(tracks):
            lt = m(X.to(dev)).cpu().numpy()
            ln = np_logits(np.transpose(X.numpy(), (0, 2, 3, 1)))
            max_d = max(max_d, float(np.abs(lt - ln).max()))
            glob[t["id"]] = tn.aggregate(tn.predict(np.transpose(X.numpy(), (0, 2, 3, 1))))[0]
    tn.WEIGHTS, tn._W = common.ORIG_NPZ, None
    r = subprocess.run([str(common.analyzer_python()), str(Path(__file__).parent / "check_npz.py"),
                        str(npz), *glob], capture_output=True, text=True)
    if r.returncode:
        raise SystemExit("check_npz.py failed:\n" + r.stderr[-2000:])
    chk = json.loads(r.stdout)
    eq = sum(chk["global_bpm"][k] == v for k, v in glob.items())
    return dict(max_logit_diff_torch_vs_numpy=max_d, same_layout=chk["same_layout"],
                arrays_changed=chk["arrays_changed"], n_arrays=chk["n_arrays"],
                analyzer_global_bpm_equal=f"{eq}/{len(glob)}")


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--labels")
    g.add_argument("--bench", help="smoke test only: bench tracks, artist = track")
    ap.add_argument("--out", help="default models/deeptemp-k16-3-ft<N>.npz (next free N)")
    ap.add_argument("--run-name")
    ap.add_argument("--seed", type=int, default=1234)
    ap.add_argument("--test-frac", type=float, default=0.25)
    ap.add_argument("--val-frac", type=float, default=0.15)
    ap.add_argument("--lr", type=float, default=3e-5)
    ap.add_argument("--wd", type=float, default=0.0)
    ap.add_argument("--epochs", type=int, default=40)
    ap.add_argument("--patience", type=int, default=5)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--ppt", type=int, default=16, help="patches per train track per epoch")
    ap.add_argument("--freeze", type=int, default=0, help="freeze the first N conv blocks")
    ap.add_argument("--no-augment", action="store_true")
    a = ap.parse_args()

    tracks = [t for t in common.tracks_from_args(a.labels, a.bench) if t["bpm"]]
    out = Path(a.out).resolve() if a.out else next_ft_path()
    name = a.run_name or out.stem.replace("deeptemp-k16-3-", "")
    rdir = common.RUNS / name
    rdir.mkdir(parents=True, exist_ok=True)
    log = open(rdir / "train.log", "a")

    def say(*s):
        line = " ".join(str(x) for x in s)
        print(line, flush=True)
        log.write(line + "\n")
        log.flush()

    sp = common.split_by_artist(tracks, a.test_frac, a.val_frac, a.seed)
    sp.update(source=("bench:" + a.bench) if a.bench else "labels", model=str(out))
    (rdir / "split.json").write_text(json.dumps(sp, indent=1))
    byid = {t["id"]: t for t in tracks}
    tr = [byid[i] for i in sp["train"]]
    va = [byid[i] for i in sp["val"]]
    n_art = lambda ts: len({t["artist"] for t in ts})   # noqa: E731
    say(f"== run {name} {time.strftime('%Y-%m-%d %H:%M')}  tracks train/val/test "
        f"{len(tr)}/{len(va)}/{len(sp['test'])}  artists {n_art(tr)}/{n_art(va)}/"
        f"{n_art([byid[i] for i in sp['test']])}  seed {a.seed}")

    torch.manual_seed(a.seed)
    rng = np.random.default_rng(a.seed)
    random.seed(a.seed)
    dev = M.device()
    m = M.load_npz(common.ORIG_NPZ).to(dev)
    for i in range(a.freeze):
        for p in list(m.convs[i].parameters()) + list(m.bns[i].parameters()):
            p.requires_grad_(False)
    opt = torch.optim.Adam([p for p in m.parameters() if p.requires_grad], lr=a.lr, weight_decay=a.wd)
    ts = TrainSet(tr, not a.no_augment)
    vset = inference_set(va)
    steps = max(1, len(ts.items) * a.ppt // a.batch)

    best_ce, best_acc = score(m, vset, dev)
    best_ep, best_state = 0, copy.deepcopy(m.state_dict())
    hist = [dict(epoch=0, train_ce=None, val_ce=best_ce, val_acc1=best_acc)]
    say(f"device {dev}  lr {a.lr}  steps/epoch {steps}  epoch 0 (original): val CE {best_ce:.4f} "
        f"Acc1 {100 * best_acc:.1f}%")
    for ep in range(1, a.epochs + 1):
        m.train()
        t0, tl = time.time(), 0.0
        for _ in range(steps):
            X, y = ts.batch(rng, a.batch)
            loss = F.cross_entropy(m(X.to(dev)), y.to(dev))
            opt.zero_grad()
            loss.backward()
            opt.step()
            tl += loss.item()
        ce, acc = score(m, vset, dev)
        hist.append(dict(epoch=ep, train_ce=tl / steps, val_ce=ce, val_acc1=acc))
        mark = ""
        if (acc, -ce) > (best_acc, -best_ce):     # val Acc1 first, val CE breaks ties
            best_ce, best_acc, best_ep, best_state = ce, acc, ep, copy.deepcopy(m.state_dict())
            mark = " *"
        say(f"epoch {ep:3d}  train CE {tl / steps:.4f}  val CE {ce:.4f}  val Acc1 {100 * acc:5.1f}%  "
            f"{time.time() - t0:.0f}s{mark}")
        if ep - best_ep >= a.patience:
            say(f"early stop: no val improvement for {a.patience} epochs")
            break
    (rdir / "history.json").write_text(json.dumps(hist, indent=1))
    if best_ep == 0:
        say("WARNING: no epoch beat the original on val; exported weights = the original")
    m.load_state_dict(best_state)
    M.save_npz(m, out, like=common.ORIG_NPZ)
    say(f"best epoch {best_ep}: val CE {best_ce:.4f} Acc1 {100 * best_acc:.1f}%  -> {out.relative_to(common.ROOT) if out.is_relative_to(common.ROOT) else out}")
    chk = verify_export(out, va + [byid[i] for i in sp["test"]], dev)
    (rdir / "export-check.json").write_text(json.dumps(chk, indent=1))
    say("export check:", json.dumps(chk))
    ok = chk["same_layout"] and chk["analyzer_global_bpm_equal"].split("/")[0] == chk["analyzer_global_bpm_equal"].split("/")[1]
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
