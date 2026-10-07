"""Shared bits for the TempoCNN fine-tuning harness. Stdlib + numpy only, so it imports under both the
bundled analyzer Python (essentia, no torch) and the training venv (torch, no essentia).

Privacy rule (J, 2026-10-06): no audio file names in anything printed, logged or committed. Tracks are
known by an opaque id; paths are read from the labels CSV and never echoed.
"""
import csv
import hashlib
import json
import random
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]                       # the beat_dl checkout this harness lives in
CACHE = HERE / "cache"                       # features (gitignored)
RUNS = HERE / "runs"                         # training runs (gitignored)
MODELS = ROOT / "models"
ORIG_NPZ = MODELS / "deeptemp-k16-3.npz"
BPM_MIN, BPM_MAX = 30, 285                   # class i = 30 + i, 256 classes
FACTORS = tuple(round(0.80 + 0.04 * i, 2) for i in range(11))   # 0.80 .. 1.20, Schreiber & Mueller 2018

sys.path.insert(0, str(ROOT))
import tempocnn_np  # noqa: E402  (numpy only at import time)


def _up(rel):
    """ROOT/rel, else the same path in an enclosing checkout (an agent worktree lives inside the main
    checkout, and bin/ + bench audio are gitignored, so they exist only there)."""
    for d in (ROOT, *ROOT.parents):
        if (d / rel).exists():
            return d / rel
    return ROOT / rel


def analyzer_python():
    return _up("bin/python/bin/python3")


BENCHES = {"bpm-bench": "docs/research/bpm-bench", "key-bench": "docs/research/key-bench"}


def bench_tracks(name):
    """bpm-bench: the 40-clip GiantSteps Tempo subset with subset.tsv ground truth.
    key-bench: 40 GiantSteps Key clips, no tempo ground truth (bpm = None).
    Ids are '<bench>-NN' in sorted order; artist = id, so an artist split is a track split."""
    d = _up(BENCHES[name] + "/audio").parent
    truth = {}
    if name == "bpm-bench":
        for line in open(d / "subset.tsv"):
            n, _genre, bpm = line.rstrip("\n").split("\t")
            truth[n] = float(bpm)
    files = sorted((d / "audio").glob("*.mp3"))
    out = []
    for i, f in enumerate(files):
        tid = f"{name}-{i:02d}"
        out.append(dict(id=tid, path=str(f), bpm=truth.get(f.stem), artist=tid))
    return out


def load_labels(csv_path):
    """Labels CSV (header required): id,path,bpm,artist  -- extra columns ignored.
    path: absolute, or relative to the CSV's own directory. bpm: float in 30..285."""
    csv_path = Path(csv_path)
    rows = []
    with open(csv_path, newline="") as f:
        r = csv.DictReader(f)
        missing = {"id", "path", "bpm", "artist"} - set(r.fieldnames or [])
        if missing:
            raise SystemExit(f"labels CSV missing columns: {sorted(missing)}")
        for i, row in enumerate(r, 2):
            p = Path(row["path"])
            p = p if p.is_absolute() else csv_path.parent / p
            bpm = float(row["bpm"])
            if not BPM_MIN <= bpm <= BPM_MAX:
                raise SystemExit(f"labels CSV line {i} (id {row['id']}): bpm {bpm} outside {BPM_MIN}-{BPM_MAX}")
            rows.append(dict(id=row["id"].strip(), path=str(p), bpm=bpm, artist=row["artist"].strip()))
    ids = [r["id"] for r in rows]
    if len(set(ids)) != len(ids):
        raise SystemExit("labels CSV: duplicate ids")
    return rows


def tracks_from_args(labels=None, bench=None):
    if bench:
        return [t for b in bench.split(",") for t in bench_tracks(b)]
    return load_labels(labels)


def path_key(path):
    """Fingerprint of the source file (name hashed, size, mtime) so a cache entry is redone when the
    audio changes, without storing the file name."""
    st = Path(path).stat()
    return hashlib.sha1(f"{Path(path).resolve()}|{st.st_size}|{int(st.st_mtime)}".encode()).hexdigest()


def cache_dir(tid):
    return CACHE / tid


def fname(f):
    return f"f{f:.2f}.npy"


def load_bands(tid, f=1.0, mmap=False):
    return np.load(cache_dir(tid) / fname(f), mmap_mode="r" if mmap else None)


def cache_meta(tid):
    p = cache_dir(tid) / "meta.json"
    return json.loads(p.read_text()) if p.is_file() else None


# ---------------------------------------------------------------- split + metrics

def split_by_artist(tracks, test_frac=0.25, val_frac=0.15, seed=1234):
    """Artists shuffled with a fixed seed; whole artists go to test until ~test_frac of the tracks,
    then whole artists of the rest go to val (early stopping) until ~val_frac of train.
    No artist is on two sides."""
    by = {}
    for t in tracks:
        by.setdefault(t["artist"], []).append(t["id"])
    artists = sorted(by)
    random.Random(seed).shuffle(artists)
    n = len(tracks)
    test, rest = [], []
    for a in artists:
        (test if sum(len(by[x]) for x in test) < test_frac * n else rest).append(a)
    n_rest = sum(len(by[a]) for a in rest)
    val, train = [], []
    for a in rest:
        (val if sum(len(by[x]) for x in val) < val_frac * n_rest else train).append(a)
    ids = lambda al: sorted(i for a in al for i in by[a])   # noqa: E731
    sp = dict(seed=seed, train=ids(train), val=ids(val), test=ids(test))
    assert not (set(train) & set(val) or set(train) & set(test) or set(val) & set(test))
    return sp


def acc1(est, ref, tol=0.04):
    return abs(est - ref) / ref <= tol


def acc2(est, ref, tol=0.04):
    return any(acc1(est, ref * k, tol) for k in (1 / 3, 1 / 2, 1, 2, 3))


def global_bpm(pred):
    """tempocnn_np's own 'majority' vote over per-patch class outputs."""
    return tempocnn_np.aggregate(np.asarray(pred, np.float32))[0]
