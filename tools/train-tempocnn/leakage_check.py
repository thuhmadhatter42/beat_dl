#!/usr/bin/env python3
"""Train/test leakage check for a tempo fine-tune run (read-only; no training, no eval of models).

Reads: runs/<run>/split.json, runs/<run>/eval.tsv, the labels CSV, the harvest DB, cached features
(cache/<id>/f1.00.npy). Prints and logs only opaque ids, never names or paths.
Checks (test vs train+val):
  1 identical id / session / artist       2 same session sha1 (DB UNIQUE) / same drive+duration
  3 same bpm + duration (+/-0.05 s)        4 same bpm + key        5 audio fingerprint (mel-band matching)
Fingerprint: z-scored mel bands, one 120-frame query window from the middle of the test track,
slid over the candidate with FFT cross-correlation; score = best mean per-band correlation.
Positive control: beat vs its own mix, same session.

Usage: python3.11 leakage_check.py [--data-root MAIN_CHECKOUT] [--run ft1] [--out runs/leakage-check.log]
Log: tools/train-tempocnn/runs/leakage-check.log (next to this script).
"""
import argparse
import csv
import json
import logging
import sqlite3
import sys
import traceback
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent


def setup_log(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s",
                        handlers=[logging.FileHandler(path, mode="w"), logging.StreamHandler(sys.stdout)])
    sys.excepthook = lambda t, v, tb: logging.error("UNCAUGHT %s", "".join(traceback.format_exception(t, v, tb)))


def sid(tid):
    return int(tid[2:].rstrip("m"))


def zbands(a):
    a = np.asarray(a, np.float32)
    return (a - a.mean(0)) / (a.std(0) + 1e-6)


def best_corr(q, c):
    """q (Tq,B) z-scored; c (Tc,B) z-scored. best over lags of mean-over-bands normalised correlation."""
    Tq, Tc = len(q), len(c)
    if Tc < Tq:
        return 0.0
    n = 1 << int(np.ceil(np.log2(Tc + Tq)))
    F = np.fft.rfft(c, n, axis=0)
    G = np.fft.rfft(q[::-1], n, axis=0)
    cc = np.fft.irfft(F * G, n, axis=0)[Tq - 1:Tc]          # (lags,B) raw dot products
    # local std normalisation of candidate window per band
    cs = np.cumsum(np.vstack([np.zeros((1, c.shape[1])), c]), 0)
    cs2 = np.cumsum(np.vstack([np.zeros((1, c.shape[1])), c * c]), 0)
    m = (cs[Tq:] - cs[:-Tq]) / Tq
    v = np.maximum((cs2[Tq:] - cs2[:-Tq]) / Tq - m * m, 1e-2)   # floor: silent windows must not blow up
    r = (cc / Tq - q.mean(0) * m) / (np.sqrt(v) * (q.std(0) + 1e-6))
    return float(np.clip(r.mean(1), -1, 1).max())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-root", default="/Users/jshriver/dev/beat_dl", type=Path)
    ap.add_argument("--run", default="ft1")
    ap.add_argument("--out", default=HERE / "runs/leakage-check.log", type=Path)
    ap.add_argument("--thr", type=float, default=0.85)
    a = ap.parse_args()
    setup_log(a.out)
    T = a.data_root / "tools/train-tempocnn"
    GT = a.data_root / "docs/research/pt-ground-truth"
    sp = json.loads((T / f"runs/{a.run}/split.json").read_text())
    train, val, test = sp["train"], sp["val"], sp["test"]
    logging.info("run %s seed %s train/val/test rows %d/%d/%d", a.run, sp["seed"], len(train), len(val), len(test))

    labels = {}
    with open(GT / "labels.csv", newline="") as f:
        for r in csv.DictReader(f):
            labels[r["id"]] = r
    missing = [i for i in train + val + test if i not in labels]
    if missing:
        logging.error("ids in split.json but not in labels.csv: %d (first: %s)", len(missing), missing[:5])
    con = sqlite3.connect(f"file:{GT / 'pt-ground-truth.sqlite3'}?mode=ro", uri=True)
    db = {r[0]: r for r in con.execute(
        "select id, ptx_sha1, artist, bpm, key, beat_duration_s, mix_duration_s, drive from sessions")}

    side = {i: "test" for i in test}
    side.update({i: "train" for i in train}); side.update({i: "val" for i in val})
    pool = train + val
    res = {}

    # 1 identical id / session / artist
    res["row id on both sides"] = len(set(test) & set(pool))
    ts, ps = {sid(i) for i in test}, {sid(i) for i in pool}
    res["session id on both sides"] = len(ts & ps)
    ta = {labels[i]["artist"] for i in test}; pa = {labels[i]["artist"] for i in pool}
    res["artist on both sides"] = len(ta & pa)
    logging.info("test artists %d, train+val artists %d", len(ta), len(pa))
    # beat and mix of a session together?
    split_pairs = sum(1 for s in ts if (f"pt{s:04d}" in side) and (f"pt{s:04d}m" in side)
                      and side[f"pt{s:04d}"] != side[f"pt{s:04d}m"])
    res["sessions with beat and mix on different sides"] = split_pairs
    # 2 same ptx sha1 (DB UNIQUE) / same drive + duration
    sha = {s: db[s][1] for s in ts | ps if s in db}
    res["same ptx_sha1"] = len({sha[s] for s in ts if s in sha} & {sha[s] for s in ps if s in sha})
    # 3 same bpm + duration
    near3, near4, pairs3 = set(), set(), []
    for s in ts:
        for p in ps:
            d1, d2 = db[s], db[p]
            if d1[5] and d2[5] and abs(d1[5] - d2[5]) <= 0.05 and abs((d1[3] or 0) - (d2[3] or 0)) < 0.5:
                near3.add(s); pairs3.append((s, p))
            if d1[3] and d2[3] and abs(d1[3] - d2[3]) < 0.5 and d1[4] and d1[4] == d2[4]:
                near4.add(s)
    res["test sessions with a train/val session of same bpm + beat duration (+/-0.05 s)"] = len(near3)
    res["test sessions with a train/val session of same bpm + key (weak, many coincidences)"] = len(near4)
    logging.info("pairs same bpm+duration: %s", pairs3[:20])

    # 5 fingerprints
    QW = 120
    feats = {}
    for i in set(test) | set(pool):
        p = T / "cache" / i / "f1.00.npy"
        try:
            feats[i] = zbands(np.load(p))
        except Exception:
            logging.error("cannot load features for %s (%s)", i, p.parent.name)
    def query(i):
        z = feats[i]; m = len(z) // 2
        return z[max(0, m - QW // 2): max(0, m - QW // 2) + QW]
    # positive control: beat vs own mix, test sessions
    ctrl = [best_corr(query(f"pt{s:04d}"), feats[f"pt{s:04d}m"]) for s in sorted(ts)
            if f"pt{s:04d}" in feats and f"pt{s:04d}m" in feats]
    logging.info("positive control beat-vs-own-mix: n=%d min %.2f median %.2f max %.2f", len(ctrl), min(ctrl), np.median(ctrl), max(ctrl))
    # negative control: test vs test of different artist
    hits = []   # (test id, pool id, score)
    allscores = []
    for i in sorted(test):
        if i not in feats:
            continue
        q = query(i); best = (0.0, None)
        for p in pool:
            if p not in feats:
                continue
            sc = best_corr(q, feats[p])
            allscores.append(sc)
            if sc > best[0]:
                best = (sc, p)
        hits.append((i, best[1], best[0]))
        logging.info("fp %s best vs train/val: %s %.3f", i, best[1], best[0])
    allscores = np.array(allscores)
    logging.info("fp score dist test x pool: median %.3f p99 %.3f max %.3f", np.median(allscores), np.percentile(allscores, 99), allscores.max())
    logging.info('TOP10 %s', [(h[0], h[1], round(h[2], 3)) for h in sorted(hits, key=lambda h: -h[2])[:10]])
    flagged = [h for h in hits if h[2] >= a.thr]
    res[f"test rows whose best fingerprint match in train/val >= {a.thr}"] = len(flagged)
    res["  of which sessions"] = len({sid(h[0]) for h in flagged})
    # also: within-test cross-session duplicates (info: shows whether dup behaviour exists in data at all)
    tl = sorted(test); within = 0
    for i in tl:
        if i not in feats: continue
        q = query(i)
        for j in tl:
            if sid(j) == sid(i) or j not in feats: continue
            if best_corr(q, feats[j]) >= a.thr: within += 1; break
    res["(info) test rows with a near-dup in a DIFFERENT test session"] = within

    # pair check, 5 query windows (10..90 % of the track), all beat/mix kind combinations
    def multi(i, j):
        if i not in feats or j not in feats:
            return None
        z = feats[i]; out = []
        for fr in (0.1, 0.3, 0.5, 0.7, 0.9):
            st = int(fr * max(1, len(z) - QW)); out.append(best_corr(z[st:st + QW], feats[j]))
        return round(max(out), 3)
    cand = set(pairs3) | {(sid(h[0]), sid(h[1])) for h in sorted(hits, key=lambda h: -h[2])[:10] if h[1]}
    pair_scores = {}
    for s_, p_ in sorted(cand):
        r = {}
        for ka, sa in (("beat", f"pt{s_:04d}"), ("mix", f"pt{s_:04d}m")):
            for kb, sb in (("beat", f"pt{p_:04d}"), ("mix", f"pt{p_:04d}m")):
                r[f"{ka}-{kb}"] = multi(sa, sb)
        pair_scores[(s_, p_)] = r
        logging.info("PAIR test session %d vs train/val session %d (same artist: %s, pool side %s): %s", s_, p_,
                     db[s_][2] == db[p_][2], side.get(f"pt{p_:04d}"), r)
    dup_audio = {s_ for (s_, p_), r in pair_scores.items() if max(v for v in r.values() if v is not None) >= 0.9}
    res["test sessions confirmed duplicated in train/val by audio (multi-window >= 0.9)"] = len(dup_audio)
    # val vs train, same metadata test (affects early stopping only)
    vs = {sid(i) for i in val}; trs = {sid(i) for i in train}
    vt = {(v_, t_) for v_ in vs for t_ in trs if db[v_][5] and db[t_][5] and abs(db[v_][5] - db[t_][5]) <= 0.05 and abs((db[v_][3] or 0) - (db[t_][3] or 0)) < 0.5 and db[v_][2] != db[t_][2]}
    res["(info) val sessions with a cross-artist train session of same bpm + duration"] = len({v_ for v_, _ in vt})
    for k, v in res.items():
        logging.info("RESULT %s = %s", k, v)
    # eval subset
    ev = {}
    for line in open(T / f"runs/{a.run}/eval.tsv"):
        c = line.rstrip("\n").split("\t")
        if c[0] == "(a)":
            ev[c[1]] = (float(c[2]), float(c[3]), float(c[4]))
    bad_sessions = {sid(h[0]) for h in flagged} | near3 | dup_audio
    def acc(ids, col):
        ids = list(ids)
        return (sum(abs(ev[i][col] - ev[i][0]) / ev[i][0] <= 0.04 for i in ids) / max(1, len(ids)), len(ids))
    allt = [i for i in ev]; clean = [i for i in ev if sid(i) not in bad_sessions]
    clean_audio = [i for i in ev if sid(i) not in dup_audio]
    clean_meta = [i for i in ev if sid(i) not in near3]
    for name, ids in (("all test", allt), ("clean test (excl. metadata+fp+audio flags)", clean), ("test excl. audio-confirmed dups only", clean_audio), ("test excl. metadata flags only", clean_meta)):
        logging.info("RESULT %s: n=%d original Acc1 %.1f%% fine-tuned Acc1 %.1f%%", name, len(ids), 100 * acc(ids, 1)[0], 100 * acc(ids, 2)[0])
    json.dump(dict(results=res, flagged=flagged, controls=ctrl), open(a.out.with_suffix(".json"), "w"), default=float)


if __name__ == "__main__":
    main()
