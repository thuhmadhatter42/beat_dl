# tools/train-tempocnn — fine-tune deeptemp-k16-3 (plan 2026-10-06 §7, §8)

A PyTorch copy of the shipped TempoCNN, trained on harvested beats and exported back to an `.npz`
that `tempocnn_np.py` loads unchanged. Torch lives only in `.venv/` here; the analyzer that ships
(`bin/python`) never gets it. Nothing in `bpm.py`, `tempocnn_np.py`, `deps.sh` or `models/deeptemp-k16-3.*`
is touched: shipping a fine-tuned model is a separate decision (§8).

No audio file names are printed, logged or committed: tracks are known by an opaque id.

## Files

| file | runs under | does |
|---|---|---|
| `common.py` | both | paths, labels CSV + bench loading, artist split, Acc1/Acc2 |
| `features.py` | analyzer Python | mel bands via the shipped front end (`bpm.load_audio_essentia` → `tempocnn_np.mel_bands`), tempo-shift augmentation, reference BPM via `tempocnn_np.tempo` |
| `model.py` | `.venv` | torch replica, `.npz` load/save (same keys/shapes/dtypes, refuses otherwise) |
| `parity.py` | `.venv` | torch vs `tempocnn_np` on cached features; exit 1 on any global-BPM mismatch |
| `train.py` | `.venv` | split, fine-tune, early stop, export, export check |
| `check_npz.py` | analyzer Python | loads an `.npz` through unmodified `tempocnn_np.py`, prints global BPMs (called by `train.py`) |
| `eval.py` | analyzer Python | original vs fine-tuned, Acc1/Acc2, markdown table |
| `labels_from_db.py` | any python3 | harvest DB (§4) → labels CSV |

Gitignored here: `.venv/` (~640 MB), `cache/` (features), `runs/` (split, logs, eval, smoke models).

## Labels CSV

```
id,path,bpm,artist
pt0001,audio11k/<file>.wav,152,<artist>
```

- `id`: opaque, unique; used for cache dirs and every printed line.
- `path`: absolute, or relative to the CSV's directory. 11025 Hz mono wav expected (any format/rate
  the app can read works; it goes through the same decode + resample as `bpm.py`). Never printed.
- `bpm`: the label, 30–285. A float is fine; the training class is `round(bpm)`.
- `artist`: only used to split (no artist in both train and test). Blank artists are not allowed;
  `labels_from_db.py` gives a blank one its own group.
- Extra columns are ignored.

## Method

- Features: `cache/<id>/f1.00.npy` = the exact float32 bands inference sees. With `--augment`, the
  audio is also resampled to 11025/f Hz and read back at 11025 Hz for f in 0.80, 0.84 … 1.20
  (tempo and pitch × f, label bpm × f, factors leaving 30–285 skipped), stored float16.
- Patches: 256 frames, z-scored by `tempocnn_np.patches` itself, so train = inference.
- Split (seed 1234): whole artists to test until ~25 % of tracks, then whole artists of the rest to
  val (~15 %) for early stopping. Saved in `runs/<name>/split.json` (ids only).
- Training: Adam, lr 3e-5, batch 32, 16 random patches per train track per epoch (random factor,
  random offset). BatchNorm mean/var frozen, gamma/beta and all convs train (`--freeze N` freezes
  the first N blocks). Every epoch the val tracks are scored like inference (all patches, majority
  vote); best val Acc1 wins, val CE breaks ties; stop after 5 epochs without improvement (max 40).
  Epoch 0 is the original model, so a fine-tune that never helps exports the original weights and says so.
- Export check: torch vs numpy logits on the new file, and `check_npz.py` in the analyzer Python
  must give the same global BPM on every val + test track.

## Commands (from the repo root)

One-time setup (`bin/` comes from `source deps.sh; ensure_deps`):

```sh
uv venv -p python3.12 tools/train-tempocnn/.venv
uv pip install -p tools/train-tempocnn/.venv/bin/python -r tools/train-tempocnn/requirements.txt
bin/python/bin/python3 tools/train-tempocnn/features.py --bench bpm-bench,key-bench --augment
tools/train-tempocnn/.venv/bin/python tools/train-tempocnn/parity.py --bench bpm-bench,key-bench
```

When the harvest has landed:

```sh
python3 tools/train-tempocnn/labels_from_db.py            # -> docs/research/pt-ground-truth/labels.csv
bin/python/bin/python3 tools/train-tempocnn/features.py --labels docs/research/pt-ground-truth/labels.csv --augment
tools/train-tempocnn/.venv/bin/python tools/train-tempocnn/parity.py --labels docs/research/pt-ground-truth/labels.csv
tools/train-tempocnn/.venv/bin/python tools/train-tempocnn/train.py --labels docs/research/pt-ground-truth/labels.csv
bin/python/bin/python3 tools/train-tempocnn/eval.py --run ft1 --labels docs/research/pt-ground-truth/labels.csv
```

`train.py` writes `models/deeptemp-k16-3-ft<N>.npz` (next free N; run name `ft<N>`) and exits 1 if
the export check fails. `eval.py` prints the table and saves `runs/ft<N>/eval.md` + `eval.tsv`.

Smoke test (bench only, split by track, NOT a result):

```sh
tools/train-tempocnn/.venv/bin/python tools/train-tempocnn/train.py --bench bpm-bench --run-name smoke \
    --out tools/train-tempocnn/runs/smoke/deeptemp-k16-3-smoke.npz
bin/python/bin/python3 tools/train-tempocnn/eval.py --run smoke
```

## Results so far (2026-10-06, MBP M1 Pro)

- Parity, 80 bench tracks (bpm-bench + key-bench), 1520 patches: global BPM equal 80/80 on CPU and
  MPS, every per-patch class equal; max |logit diff| 1.0e-5 (CPU), 8.8e-6 (MPS).
- Original on bpm-bench via this harness: Acc1 87.5 %, Acc2 100 %, the same as
  `docs/research/bpm-bench/results.tsv` (`tempocnn_deeptemp`).
- Smoke test only (25 train / 5 val / 10 test bench clips): pipeline runs end to end, export check
  passes (layout identical, 50 of 86 arrays changed, 15/15 global BPMs equal through unmodified
  `tempocnn_np.py`). Its accuracy numbers mean nothing.
- key-bench has no tempo ground truth (GiantSteps Key ships keys only), so `eval.py` reports only
  how often the two models agree there.
