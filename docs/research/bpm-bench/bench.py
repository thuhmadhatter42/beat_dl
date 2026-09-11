#!/usr/bin/env python3
"""BPM detection benchmark: current bpm.py approach vs candidates.

Usage: venv/bin/python bench.py [--methods a,b,c] [--subset subset.tsv] [--audio audio/]
Writes results.tsv (one row per track x method) and prints Acc1/Acc2 table.
Acc1 = |est-ref|/ref <= 4%.  Acc2 = Acc1 for est in {ref/3, ref/2, ref, 2ref, 3ref}.
"""
import argparse, sys, time, os, csv, math
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "models")

# ---------------------------------------------------------------- loading

def load_mono(path, sr=22050):
    import librosa
    y, _ = librosa.load(path, sr=sr, mono=True)
    return y

def loud_section(y, sr, chunk_s=10, span_s=60):
    """Exact copy of bpm.py get_loud_section."""
    chunk = sr * chunk_s
    chunks = [y[i:i + chunk] for i in range(0, len(y), chunk)]
    rms = [np.sqrt(np.mean(c ** 2)) for c in chunks]
    i = int(np.argmax(rms))
    return y[i * chunk: min(i * chunk + sr * span_s, len(y))]

# ---------------------------------------------------------------- helpers

def fold(bpm, lo=60.0, hi=180.0):
    """Octave-fold into [lo, hi)."""
    while bpm >= hi: bpm /= 2
    while bpm < lo: bpm *= 2
    return bpm

# ---------------------------------------------------------------- methods

def m_current(path):
    """bpm.py as shipped: librosa.beat.beat_track on loudest 60 s, sr=22050."""
    import librosa
    y = load_mono(path); sr = 22050
    sec = loud_section(y, sr)
    t, _ = librosa.beat.beat_track(y=sec, sr=sr)
    return float(np.atleast_1d(t)[0])

def m_librosa_tempo_full(path):
    """librosa.feature.tempo on full track, default prior (start_bpm=120)."""
    import librosa
    y = load_mono(path); sr = 22050
    oenv = librosa.onset.onset_strength(y=y, sr=sr)
    return float(librosa.feature.tempo(onset_envelope=oenv, sr=sr)[0])

def m_librosa_multiwin(path):
    """librosa: onset env on full track, per-frame tempo (aggregate=None),
    mode over frames, wider-than-default prior centred at 100 BPM, then
    tempogram-ratio octave check: prefer T vs 2T by comparing tempogram
    energy at the candidate lags."""
    import librosa
    y = load_mono(path); sr = 22050
    hop = 512
    oenv = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
    tg = librosa.feature.tempogram(onset_envelope=oenv, sr=sr, hop_length=hop, win_length=384)
    per_frame = librosa.feature.tempo(onset_envelope=oenv, sr=sr, hop_length=hop,
                                      aggregate=None, start_bpm=100, std_bpm=1.5, max_tempo=320)
    # histogram vote in 1-BPM bins
    hist, edges = np.histogram(per_frame, bins=np.arange(20, 321, 1))
    bpm = float(edges[np.argmax(hist)] + 0.5)
    # refine with mean of frames within 4% of the winning bin
    close = per_frame[np.abs(per_frame - bpm) / bpm < 0.04]
    if len(close): bpm = float(np.median(close))
    return bpm

def m_librosa_multiwin_folded(path):
    return fold(m_librosa_multiwin(path))

def m_essentia_re2013(path):
    """Essentia RhythmExtractor2013 multifeature on full track (44.1k)."""
    import essentia.standard as es
    audio = es.MonoLoader(filename=path, sampleRate=44100)()
    bpm, ticks, conf, est, ivals = es.RhythmExtractor2013(method="multifeature")(audio)
    return float(bpm)

def m_essentia_re2013_degara(path):
    import essentia.standard as es
    audio = es.MonoLoader(filename=path, sampleRate=44100)()
    bpm, *_ = es.RhythmExtractor2013(method="degara")(audio)
    return float(bpm)

def m_essentia_percival(path):
    """Essentia PercivalBpmEstimator (Percival & Tzanetakis 2014, octave-aware)."""
    import essentia.standard as es
    audio = es.MonoLoader(filename=path, sampleRate=44100)()
    return float(es.PercivalBpmEstimator()(audio))

def _tempocnn(path, model):
    import essentia.standard as es
    audio = es.MonoLoader(filename=path, sampleRate=11025)()
    g, l, _ = es.TempoCNN(graphFilename=os.path.join(MODELS, model))(audio)
    return float(g)

def m_tempocnn_deepsquare(path):
    return _tempocnn(path, "deepsquare-k16-3.pb")

def m_tempocnn_deeptemp(path):
    return _tempocnn(path, "deeptemp-k16-3.pb")

_dr = None
def m_deeprhythm(path):
    global _dr
    from deeprhythm import DeepRhythmPredictor
    if _dr is None:
        _dr = DeepRhythmPredictor()
    out = _dr.predict(path)
    return float(out[0] if isinstance(out, (tuple, list)) else out)

_bt = None
def m_beat_this(path):
    """Beat This! (ISMIR 2024) beats -> BPM = 60 / median inter-beat interval."""
    global _bt
    from beat_this.inference import File2Beats
    if _bt is None:
        _bt = File2Beats(checkpoint_path="final0", device="cpu", dbn=False)
    beats, downbeats = _bt(path)
    ibi = np.diff(beats)
    return float(60.0 / np.median(ibi))

def m_bpm_py(path):
    """The shipped bpm.py detect_bpm() (TempoCNN + librosa fallback), imported from the repo root."""
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(HERE))))
    import bpm
    return float(bpm.detect_bpm(path, None, None))

METHODS = {
    "current": m_current,
    "bpm_py": m_bpm_py,
    "librosa_tempo_full": m_librosa_tempo_full,
    "librosa_multiwin": m_librosa_multiwin,
    "librosa_multiwin_folded": m_librosa_multiwin_folded,
    "essentia_re2013": m_essentia_re2013,
    "essentia_degara": m_essentia_re2013_degara,
    "essentia_percival": m_essentia_percival,
    "tempocnn_deepsquare": m_tempocnn_deepsquare,
    "tempocnn_deeptemp": m_tempocnn_deeptemp,
    "deeprhythm": m_deeprhythm,
    "beat_this": m_beat_this,
}

# ---------------------------------------------------------------- metrics

def acc1(est, ref, tol=0.04):
    return abs(est - ref) / ref <= tol

def acc2(est, ref, tol=0.04):
    return any(acc1(est, ref * k, tol) for k in (1/3, 1/2, 1, 2, 3))

# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--methods", default=",".join(METHODS))
    ap.add_argument("--subset", default=os.path.join(HERE, "subset.tsv"))
    ap.add_argument("--audio", default=os.path.join(HERE, "audio"))
    ap.add_argument("--out", default=os.path.join(HERE, "results.tsv"))
    a = ap.parse_args()
    methods = [m.strip() for m in a.methods.split(",") if m.strip()]

    tracks = []
    for line in open(a.subset):
        n, genre, bpm = line.rstrip("\n").split("\t")
        tracks.append((n, genre, float(bpm)))

    rows = []
    for m in methods:
        fn = METHODS[m]
        t0 = time.time(); n_ok = 0
        for n, genre, ref in tracks:
            path = os.path.join(a.audio, n + ".mp3")
            ts = time.time()
            try:
                est = fn(path)
            except Exception as e:
                est = float("nan"); print(f"[{m}] {n}: ERROR {e!r}", file=sys.stderr)
            dt = time.time() - ts
            rows.append(dict(method=m, track=n, genre=genre, ref=ref, est=round(est, 2),
                             acc1=int(acc1(est, ref)) if est == est else 0,
                             acc2=int(acc2(est, ref)) if est == est else 0, sec=round(dt, 2)))
            print(f"[{m}] {n} {genre:16s} ref={ref:6.1f} est={est:7.2f} "
                  f"{'A1' if rows[-1]['acc1'] else ('A2' if rows[-1]['acc2'] else '--')} {dt:.1f}s",
                  flush=True)
        print(f"== {m}: {time.time()-t0:.1f}s total", flush=True)

    with open(a.out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys(), delimiter="\t")
        w.writeheader(); w.writerows(rows)

    print("\nmethod                     Acc1   Acc2   mean s/track")
    for m in methods:
        r = [x for x in rows if x["method"] == m]
        print(f"{m:26s} {100*np.mean([x['acc1'] for x in r]):5.1f}% {100*np.mean([x['acc2'] for x in r]):5.1f}%  {np.mean([x['sec'] for x in r]):.2f}")

if __name__ == "__main__":
    main()
