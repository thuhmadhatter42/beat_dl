#!/usr/bin/env python3
"""Original vs fine-tuned TempoCNN, scored with tempocnn_np.py itself (the shipped inference code, run
under the analyzer Python; only its WEIGHTS path is switched between the two .npz files).

Sets:
  (a) held-out test split of the run (runs/<name>/split.json; truth from the labels CSV)
  (b) bpm-bench: 40 GiantSteps Tempo clips, subset.tsv truth
      key-bench: 40 GiantSteps Key clips; no tempo truth exists for them, so no accuracy, only how
      often the two models give the same BPM (and within 4 %)
Acc1 = |est - ref| / ref <= 4 %.  Acc2 = Acc1 against ref x {1/3, 1/2, 1, 2, 3}.
Output: markdown table (stdout + runs/<name>/eval.md), per-track rows by id only (runs/<name>/eval.tsv).

Usage: bin/python/bin/python3 tools/train-tempocnn/eval.py --run ft1 --labels LABELS.csv
       smoke: ... --run smoke   (split source is the bench; no --labels)
"""
import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402

tn = common.tempocnn_np


def predict_all(npz, ids):
    tn.WEIGHTS, tn._W = Path(npz), None
    out = {}
    for tid in ids:
        P = tn.patches(common.load_bands(tid))
        out[tid] = tn.aggregate(tn.predict(P) if len(P) else np.zeros((0, 256), np.float32))[0]
    tn.WEIGHTS, tn._W = common.ORIG_NPZ, None
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True, help="run name under tools/train-tempocnn/runs/")
    ap.add_argument("--labels", help="labels CSV the run was trained from (not needed for bench smoke runs)")
    ap.add_argument("--model", help="override the fine-tuned .npz (default: the run's)")
    a = ap.parse_args()
    rdir = common.RUNS / a.run
    sp = json.loads((rdir / "split.json").read_text())
    ft = Path(a.model or sp["model"])
    smoke = sp["source"].startswith("bench:")
    src = common.tracks_from_args(a.labels, sp["source"][6:] if smoke else None)
    byid = {t["id"]: t for t in src}
    missing = [i for i in sp["test"] if i not in byid]
    if missing:
        raise SystemExit(f"{len(missing)} test ids not in the labels CSV")
    sets = [("(a) held-out test split", [byid[i] for i in sp["test"]])]
    bb = common.bench_tracks("bpm-bench")
    kb = common.bench_tracks("key-bench")
    sets.append(("(b) bpm-bench", bb))
    ids = sorted({t["id"] for _, ts in sets for t in ts} | {t["id"] for t in kb})
    t0 = time.time()
    est = {"original": predict_all(common.ORIG_NPZ, ids), "fine-tuned": predict_all(ft, ids)}

    title = f"TempoCNN eval, run `{a.run}`" + (" — SMOKE TEST on bench data, not a result" if smoke else "")
    lines = [f"## {title}", "",
             f"Fine-tuned model: `{ft.name}`. Scored by tempocnn_np.py (shipped numpy TempoCNN). "
             f"Acc1 = within 4 %; Acc2 = also x2, x1/2, x3, x1/3.", ""]
    if smoke:
        lines += ["Smoke test: bench tracks split by track; (b) bpm-bench contains the training tracks, "
                  "so its fine-tuned numbers are not a held-out measure.", ""]
    lines += ["| set | n | original Acc1 | fine-tuned Acc1 | original Acc2 | fine-tuned Acc2 |",
              "|---|---:|---:|---:|---:|---:|"]
    rows = []
    for name, ts in sets:
        r = {}
        for mname in est:
            e = [est[mname][t["id"]] for t in ts]
            r[mname] = (100 * np.mean([common.acc1(x, t["bpm"]) for x, t in zip(e, ts)]),
                        100 * np.mean([common.acc2(x, t["bpm"]) for x, t in zip(e, ts)]))
        lines.append(f"| {name} | {len(ts)} | {r['original'][0]:.1f}% | {r['fine-tuned'][0]:.1f}% | "
                     f"{r['original'][1]:.1f}% | {r['fine-tuned'][1]:.1f}% |")
        for t in ts:
            rows.append((name.split()[0], t["id"], t["bpm"], est["original"][t["id"]], est["fine-tuned"][t["id"]]))
    same = np.mean([est["original"][t["id"]] == est["fine-tuned"][t["id"]] for t in kb])
    near = np.mean([common.acc1(est["fine-tuned"][t["id"]], est["original"][t["id"]]) for t in kb])
    lines += ["", f"key-bench ({len(kb)} clips): no tempo ground truth, accuracy skipped. Fine-tuned gives the "
              f"same BPM as the original on {100 * same:.0f}% of clips, within 4 % on {100 * near:.0f}%."]
    for t in kb:
        rows.append(("key-bench", t["id"], "", est["original"][t["id"]], est["fine-tuned"][t["id"]]))
    md = "\n".join(lines) + "\n"
    print(md)
    (rdir / "eval.md").write_text(md)
    with open(rdir / "eval.tsv", "w") as f:
        f.write("set\tid\tref\toriginal\tfine_tuned\n")
        for r in rows:
            f.write("\t".join(str(x) for x in r) + "\n")
    print(f"({time.time() - t0:.0f}s; per-track by id in {rdir.relative_to(common.ROOT)}/eval.tsv)")


if __name__ == "__main__":
    main()
