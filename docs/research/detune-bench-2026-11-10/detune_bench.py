#!/usr/bin/env python3
"""Detune key bench: the 40 GiantSteps Key clips (docs/research/key-bench/audio) at 0 / +7 / +14 / +25 / +50 / -30
cents, through bpm.py's shipping key entry (analyze_full's lines: load_audio_essentia -> hpcp_frames(peaks) ->
key_reading) and through the live path (LiveAnalyzer, boundaries off, one reading per 30 s of audio).

Usage: <analyzer python> detune_bench.py <bpm.py dir> <key-bench dir> <out.json>
Pitch shift: the 44.1 kHz mono is treated as recorded at 44100*r Hz and resampled to 44100 (r = 2^(c/1200)),
so every frequency moves by c cents (tempo moves by the same ratio, like a varispeed).
Also logs, per condition, how often the hpcp_to_pcp12 peak roll is non-zero on the (possibly rebuilt) HPCP."""
import json
import sys
import time
import traceback
from pathlib import Path

import numpy as np

BPM_DIR, BENCH, OUT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
sys.path.insert(0, str(BPM_DIR))
import essentia  # noqa: E402
essentia.log.infoActive = essentia.log.warningActive = False
import essentia.standard as es  # noqa: E402
import bpm  # noqa: E402

print(f"bpm.py = {bpm.__file__}", flush=True)
SHIFTS = (0, 7, 14, 25, 50, -30)
NOTES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
FLAT = {'Db': 'C#', 'Eb': 'D#', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#', 'Cb': 'B', 'Fb': 'E'}


def parse(s):
    s = s.strip()
    if ' ' in s:
        t, m = s.split()[:2]
    else:
        m = 'minor' if s.endswith('m') else 'major'
        t = s[:-1] if s.endswith('m') else s
    if m not in ('major', 'minor'):
        return None
    return NOTES.index(FLAT.get(t, t)), m


def mirex(p, g):
    (pp, pm), (gp, gm) = p, g
    if (pp, pm) == (gp, gm):
        return 1.0
    if pm == gm and (pp - gp) % 12 in (5, 7):
        return 0.5
    if pm != gm and ((gm == 'major' and pp == (gp + 9) % 12) or (gm == 'minor' and pp == (gp + 3) % 12)):
        return 0.3
    if pm != gm and pp == gp:
        return 0.2
    return 0.0


ORIG = {n: parse(v) for n, v in json.load(open(BENCH / 'ground_truth.json')).items()}
GSP = {}
for n, v in json.load(open(BENCH / 'ground_truth_gsplus.json')).items():
    k = parse(' '.join(v.split('|')[0].split()[:2]))
    if k:
        GSP[n] = k


def shift(a, cents):
    if cents == 0:
        return a
    r = 2 ** (cents / 1200)
    return es.Resample(inputSampleRate=44100.0 * r, outputSampleRate=44100.0)(a)


def roll_index(avg):
    p = avg / (avg.max() + 1e-12)
    p[p < bpm.PCP_THRESHOLD] = 0.0
    return int(np.argmax(p)) % 3


def roll_stats(H, peaks):
    """Replicates key_reading's choice of H, then counts non-zero peak rolls (whole + 10 s windows)."""
    t = bpm.estimate_tuning(peaks)
    if t is not None and abs(t) >= bpm.TUNING_RETUNE_CENTS:
        H = bpm.hpcp_from_peaks(peaks, 440.0 * 2 ** (t / 1200))
    whole = roll_index(H.mean(axis=0)) != 0
    fr = int(bpm.SEGMENT_SECS * bpm.KEY_SR / bpm.HOP)
    segs = [roll_index(H[i:i + fr].mean(axis=0)) != 0 for i in range(0, len(H), fr) if len(H[i:i + fr]) >= fr // 2]
    return whole, sum(segs), len(segs)


rows = []
errors = []
t0 = time.time()
for name in sorted(ORIG):
    path = BENCH / 'audio' / f'{name}.mp3'
    try:
        a_key, _ = bpm.load_audio_essentia(path)
    except Exception as e:
        errors.append(f'{name} decode: {e!r}')
        print(f'ERROR {name} decode {e!r}', file=sys.stderr, flush=True)
        continue
    for c in SHIFTS:
        try:
            a = np.ascontiguousarray(shift(a_key, c), dtype=np.float32)
            peaks = []
            H = bpm.hpcp_frames(a, peaks)
            k = bpm.key_reading(H, peaks)                         # analyze_full's key lines
            rw, rs, rn = roll_stats(H, peaks)
            live = bpm.LiveAnalyzer(boundaries=False, hop=30.0)
            lr = []
            step = int(bpm.STREAM_CHUNK_SECS * bpm.KEY_SR)
            for i in range(0, len(a), step):
                lr += [e for e in live.push(a[i:i + step]) if e.get('event') == 'reading']
            lr += [e for e in live.finish() if e.get('event') == 'reading']
            rows.append(dict(track=name, cents=c, keys=k['keys'], tuning=k['tuning_cents'],
                             roll_whole=rw, roll_segs=rs, n_segs=rn,
                             live=[dict(keys=e['keys'], tuning=e['tuning_cents'], secs=e['secs']) for e in lr]))
        except Exception as e:
            errors.append(f'{name} {c:+d}c: {e!r}')
            print(f'ERROR {name} {c:+d}c {e!r}\n{traceback.format_exc()}', file=sys.stderr, flush=True)
    print(f'{name} done ({time.time() - t0:.0f} s)', flush=True)


def equiv(pred, truth, c):
    """+50 c sits exactly between two semitones: truth or truth+1 (same mode) are both right."""
    if pred == truth:
        return True
    return c == 50 and pred == ((truth[0] + 1) % 12, truth[1])


def table(get, label):
    print(f'\n== {label}')
    print(f"{'cents':>6} {'n':>4} {'exact':>7} {'exact≈':>7} {'GS+ex':>7} {'MIREX':>7} {'top3':>7} {'conf1':>7}")
    tot = {}
    for c in SHIFTS:
        items = [x for r in rows if r['cents'] == c for x in get(r)]
        n = len(items)
        if not n:
            print(f'{c:+6d} {0:4d}')
            continue
        ex = sum(parse(p[0][0]) == ORIG[t] for t, p in items)
        eq = sum(equiv(parse(p[0][0]), ORIG[t], c) for t, p in items)
        gi = [(t, p) for t, p in items if t in GSP]
        gx = sum(parse(p[0][0]) == GSP[t] or (c == 50 and parse(p[0][0]) == ((GSP[t][0] + 1) % 12, GSP[t][1])) for t, p in gi)
        mx = sum(max(mirex(parse(p[0][0]), ORIG[t]), mirex(parse(p[0][0]), ((ORIG[t][0] + 1) % 12, ORIG[t][1])) if c == 50 else 0) for t, p in items)
        t3 = sum(any(equiv(parse(k), ORIG[t], c) for k, _ in p) for t, p in items)
        cf = np.mean([p[0][1] for t, p in items])
        print(f'{c:+6d} {n:4d} {100 * ex / n:7.1f} {100 * eq / n:7.1f} {100 * gx / max(len(gi), 1):7.1f} '
              f'{100 * mx / n:7.1f} {100 * t3 / n:7.1f} {cf:7.1f}')
        tot[c] = (n, eq)
    n = sum(v[0] for v in tot.values())
    print(f"{'all':>6} {n:4d} {'':7} {100 * sum(v[1] for v in tot.values()) / max(n, 1):7.1f}   (exact≈ pooled over all shifts)")


print(f'\nrows={len(rows)} errors={len(errors)} secs={time.time() - t0:.0f}')
table(lambda r: [(r['track'], [tuple(k) for k in r['keys']])], 'FILE (key_reading on the whole track)')
table(lambda r: [(r['track'], [tuple(k) for k in e['keys']]) for e in r['live']], 'LIVE (LiveAnalyzer readings, 30 s key window, one per 30 s)')
print('\n== roll activity on the HPCP key_reading scores (peak not on a semitone bin -> hpcp_to_pcp12 rolls)')
for c in SHIFTS:
    rs = [r for r in rows if r['cents'] == c]
    print(f'{c:+6d} whole-track roll non-zero {sum(r["roll_whole"] for r in rs)}/{len(rs)}; '
          f'10 s windows rolled {sum(r["roll_segs"] for r in rs)}/{sum(r["n_segs"] for r in rs)}')
print('\nerrors:', errors or 'none')
json.dump(dict(rows=rows, errors=errors), open(OUT, 'w'), indent=0)
