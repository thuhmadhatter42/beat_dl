#!/usr/bin/env python3
"""Key-detection benchmark harness (GiantSteps subset).

Usage:  ./venv/bin/python bench.py [method ...]      (no args = all methods)
Reads:  audio/*.mp3 + ground_truth.json (from fetch_gs.py)
Writes: results/<method>.json  and prints a MIREX table.

MIREX weighting: correct 1.0, fifth 0.5, relative 0.3, parallel 0.2, other 0.
"""
import sys, json, time, os, glob
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
NOTES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
FLAT2SHARP = {'Db': 'C#', 'Eb': 'D#', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#', 'Cb': 'B', 'Fb': 'E'}


def parse_key(s):
    """'Eb minor' / 'D#m' / 'C' -> (pitch_class, 'minor'|'major')"""
    s = s.strip().replace(' Major', ' major').replace(' Minor', ' minor')
    if ' ' in s:
        tonic, mode = s.split()
    else:
        mode = 'minor' if s.endswith('m') else 'major'
        tonic = s[:-1] if s.endswith('m') else s
    tonic = FLAT2SHARP.get(tonic, tonic)
    return NOTES.index(tonic), mode


def fmt(pc, mode):
    return NOTES[pc] + ('m' if mode == 'minor' else '')


def mirex(pred, gt):
    (pp, pm), (gp, gm) = pred, gt
    if pp == gp and pm == gm:
        return 'correct', 1.0
    if pm == gm and (pp - gp) % 12 in (5, 7):
        return 'fifth', 0.5
    if pm != gm and ((gm == 'major' and pp == (gp + 9) % 12) or (gm == 'minor' and pp == (gp + 3) % 12)):
        return 'relative', 0.3
    if pm != gm and pp == gp:
        return 'parallel', 0.2
    return 'other', 0.0


# ---------------------------------------------------------------- profiles
PROFILES = {
    'krumhansl': (
        [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88],
        [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]),
    'temperley': (  # Temperley 1999 "What's key for key" (as used in essentia)
        [5.0, 2.0, 3.5, 2.0, 4.5, 4.0, 2.0, 4.5, 2.0, 3.5, 1.5, 4.0],
        [5.0, 2.0, 3.5, 4.5, 2.0, 4.0, 2.0, 4.5, 3.5, 2.0, 1.5, 4.0]),
    'shaath': (  # Sha'ath 2011 (KeyFinder)
        [6.6, 2.0, 3.5, 2.3, 4.6, 4.0, 2.5, 5.2, 2.4, 3.7, 2.3, 3.4],
        [6.5, 2.7, 3.5, 5.4, 2.6, 3.5, 2.5, 5.2, 4.0, 2.7, 4.3, 3.2]),
    'edma': (  # Faraldo et al., essentia key.cpp profileTypesWithOther
        [1.00, 0.29, 0.50, 0.40, 0.60, 0.56, 0.32, 0.80, 0.31, 0.45, 0.42, 0.39],
        [1.00, 0.31, 0.44, 0.58, 0.33, 0.49, 0.29, 0.78, 0.43, 0.29, 0.53, 0.32]),
    'bgate': (  # essentia key.cpp
        [1.00, 0.00, 0.42, 0.00, 0.53, 0.37, 0.00, 0.77, 0.00, 0.38, 0.21, 0.30],
        [1.00, 0.00, 0.36, 0.39, 0.00, 0.38, 0.00, 0.74, 0.27, 0.00, 0.42, 0.23]),
}


def profile_scores(mean_chroma, prof):
    maj, mn = (np.array(p, float) for p in PROFILES[prof])
    out = {}
    for i in range(12):
        out[(i, 'major')] = float(np.corrcoef(mean_chroma, np.roll(maj, i))[0, 1])
        out[(i, 'minor')] = float(np.corrcoef(mean_chroma, np.roll(mn, i))[0, 1])
    return out


def top3_from_scores(scores, conf='rescale'):
    ranked = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)
    if conf == 'rescale':  # current bpm.py: top-3 renormalised to 100 (meaningless)
        tot = sum(s for _, s in ranked[:3])
        return [(k, 100 * s / tot) for k, s in ranked[:3]]
    # softmax over z-scored correlations across all 24 keys -> honest-ish probability
    v = np.array([s for _, s in ranked])
    z = (v - v.mean()) / (v.std() + 1e-9)
    p = np.exp(3.0 * z); p /= p.sum()
    return [(k, 100 * float(p[i])) for i, (k, _) in enumerate(ranked[:3])]


# ---------------------------------------------------------------- audio helpers
def load(path, sr=22050):
    import librosa
    y, _ = librosa.load(path, sr=sr, mono=True)
    return y, sr


def loud60(y, sr):
    """bpm.py: 60 s starting at the loudest 10 s chunk."""
    cs = sr * 10
    chunks = [y[i:i + cs] for i in range(0, len(y), cs)]
    rms = [np.sqrt(np.mean(c ** 2)) for c in chunks]
    st = int(np.argmax(rms)) * cs
    return y[st:min(st + sr * 60, len(y))]


# ---------------------------------------------------------------- methods
def m_current(path):
    """Exactly what bpm.py does today."""
    import librosa
    y, sr = load(path)
    sec = loud60(y, sr)
    c = librosa.feature.chroma_cqt(y=sec, sr=sr).mean(axis=1)
    return top3_from_scores(profile_scores(c, 'krumhansl'), 'rescale')


def _librosa_chroma_variant(path, prof, harmonic=True, cens=False, tuning=True, segment=None, whole=True):
    import librosa
    y, sr = load(path)
    if not whole:
        y = loud60(y, sr)
    if harmonic:
        y = librosa.effects.harmonic(y, margin=4.0)
    tun = librosa.estimate_tuning(y=y, sr=sr) if tuning else 0.0
    if cens:
        C = librosa.feature.chroma_cens(y=y, sr=sr, tuning=tun)
    else:
        C = librosa.feature.chroma_cqt(y=y, sr=sr, tuning=tun, n_chroma=12, bins_per_octave=36)
    if segment:  # vote over fixed windows, sum z-scored correlations
        hop = 512; fr = int(segment * sr / hop)
        acc = None
        for i in range(0, C.shape[1] - fr + 1, fr):
            sc = profile_scores(C[:, i:i + fr].mean(axis=1), prof)
            v = np.array([sc[k] for k in sorted(sc)])
            v = (v - v.mean()) / (v.std() + 1e-9)
            acc = v if acc is None else acc + v
        keys = sorted(sc)
        scores = {k: float(acc[i]) for i, k in enumerate(keys)}
    else:
        scores = profile_scores(C.mean(axis=1), prof)
    return top3_from_scores(scores, 'softmax')


def m_lib_ks_harm(path):        return _librosa_chroma_variant(path, 'krumhansl')
def m_lib_temperley_harm(path): return _librosa_chroma_variant(path, 'temperley')
def m_lib_shaath_harm(path):    return _librosa_chroma_variant(path, 'shaath')
def m_lib_edma_harm(path):      return _librosa_chroma_variant(path, 'edma')
def m_lib_edma_cens(path):      return _librosa_chroma_variant(path, 'edma', cens=True)
def m_lib_edma_seg(path):       return _librosa_chroma_variant(path, 'edma', segment=10)
def m_lib_shaath_noharm(path):  return _librosa_chroma_variant(path, 'shaath', harmonic=False)
def m_lib_bgate_harm(path):     return _librosa_chroma_variant(path, 'bgate')
def m_lib_edma_60(path):        return _librosa_chroma_variant(path, 'edma', whole=False)


def _essentia(path, profile, whole=True, extra=None):
    import essentia.standard as es
    audio = es.MonoLoader(filename=str(path), sampleRate=44100)()
    if not whole:
        audio = loud60(audio, 44100).astype(np.float32)
    kw = dict(profileType=profile, sampleRate=44100)
    if extra: kw.update(extra)
    key, scale, strength = es.KeyExtractor(**kw)(audio)
    pc, mode = parse_key(f'{key} {scale}')
    # KeyExtractor only exposes the winner; fill 2nd/3rd with fifth + relative for the contract
    rel = ((pc + 9) % 12, 'major') if mode == 'minor' else ((pc + 3) % 12, 'minor')
    return [((pc, mode), 100 * float(strength)), (rel, 0.0), (((pc + 7) % 12, mode), 0.0)]


def m_ess_bgate(path):  return _essentia(path, 'bgate')
def m_ess_edma(path):   return _essentia(path, 'edma')
def m_ess_edmm(path):   return _essentia(path, 'edmm')
def m_ess_braw(path):   return _essentia(path, 'braw')
def m_ess_temperley(path): return _essentia(path, 'temperley')
def m_ess_shaath(path): return _essentia(path, 'shaath')
def m_ess_bgate_60(path): return _essentia(path, 'bgate', whole=False)
def m_ess_bgate_hp(path): return _essentia(path, 'bgate', extra=dict(minFrequency=200))


_CNN = {}
def _cnn(path, ckpt='openkeyscan3.pt', Nf=64):
    import torch, librosa
    sys.path.insert(0, str(HERE / 'openkeyscan-analyzer'))
    from model import KeyNet
    if ckpt not in _CNN:
        m = KeyNet(num_classes=24, in_channels=1, Nf=Nf, p=0.3)
        m.load_state_dict(torch.load(HERE / 'openkeyscan-analyzer' / 'checkpoints' / ckpt, map_location='cpu'))
        m.eval(); _CNN[ckpt] = m
    m = _CNN[ckpt]
    y, sr = librosa.load(path, sr=44100, mono=True)
    C = np.log1p(np.abs(librosa.cqt(y, sr=44100, hop_length=8820, n_bins=105, bins_per_octave=24, fmin=65)))
    x = torch.tensor(C[:, 0:-2], dtype=torch.float32)[None, None]
    with torch.no_grad():
        p = torch.softmax(m(x), dim=1)[0].numpy()
    # camelot index -> (pc, mode): 0=G#m 1=D#m 2=A#m 3=Fm ... ; 12=B 13=F# ...
    minors = [8, 3, 10, 5, 0, 7, 2, 9, 4, 11, 6, 1]
    keys = [(minors[i], 'minor') for i in range(12)] + [((minors[i] + 3) % 12, 'major') for i in range(12)]
    order = np.argsort(-p)[:3]
    return [(keys[i], 100 * float(p[i])) for i in order]


def m_cnn_oks3(path):  return _cnn(path)
def m_cnn_keynet(path): return _cnn(path, 'keynet.pt', Nf=20)


def m_ensemble(path):
    """CNN + essentia bgate: agree -> CNN conf; disagree -> whichever is more confident (bgate strength rescaled)."""
    cnn = m_cnn_oks3(path); ess = m_ess_bgate(path)
    if cnn[0][0] == ess[0][0]:
        return cnn
    return cnn if cnn[0][1] >= 100 * min(1.0, ess[0][1] / 100 * 1.2) else ess


METHODS = {k[2:]: v for k, v in globals().items() if k.startswith('m_')}


def run(method):
    gt = json.load(open(HERE / 'ground_truth.json'))
    fn = METHODS[method]
    rows = []; t0 = time.time()
    for name, lab in sorted(gt.items()):
        path = HERE / 'audio' / f'{name}.mp3'
        t = time.time()
        try:
            top3 = fn(path)
        except Exception as e:
            print(f'  {name}: ERROR {e}', file=sys.stderr); continue
        cat, w = mirex(top3[0][0], parse_key(lab))
        rows.append(dict(track=name, gt=fmt(*parse_key(lab)), pred=fmt(*top3[0][0]), conf=round(top3[0][1], 1),
                         top3=[(fmt(*k), round(c, 1)) for k, c in top3], cat=cat, w=w, secs=round(time.time() - t, 2)))
    n = len(rows)
    summ = dict(method=method, n=n, weighted=100 * sum(r['w'] for r in rows) / n,
                exact=100 * sum(r['cat'] == 'correct' for r in rows) / n,
                fifth=100 * sum(r['cat'] == 'fifth' for r in rows) / n,
                relative=100 * sum(r['cat'] == 'relative' for r in rows) / n,
                parallel=100 * sum(r['cat'] == 'parallel' for r in rows) / n,
                other=100 * sum(r['cat'] == 'other' for r in rows) / n,
                secs_per_track=(time.time() - t0) / n,
                top3_hit=100 * sum(r['gt'] in [k for k, _ in r['top3']] for r in rows) / n)
    (HERE / 'results').mkdir(exist_ok=True)
    json.dump(dict(summary=summ, rows=rows), open(HERE / 'results' / f'{method}.json', 'w'), indent=1)
    return summ


# ---------------------------------------------------------------- essentia HPCP chain + numpy ranking (full top-3)
def essentia_hpcp_frames(path, hpcp_size=12, sr=44100, frame=4096, hop=4096, whole=True):
    """Replicates essentia KeyExtractor's front end frame by frame; returns (n_frames, hpcp_size) array."""
    import essentia.standard as es
    audio = es.MonoLoader(filename=str(path), sampleRate=sr)()
    if not whole:
        audio = loud60(audio, sr).astype(np.float32)
    win = es.Windowing(type='hann', size=frame)
    spec = es.Spectrum(size=frame)
    peaks = es.SpectralPeaks(orderBy='magnitude', magnitudeThreshold=0.0001, minFrequency=25, maxFrequency=3500, maxPeaks=60, sampleRate=sr)
    white = es.SpectralWhitening(maxFrequency=3500, sampleRate=sr)
    hpcp = es.HPCP(bandPreset=False, harmonics=4, maxFrequency=3500, minFrequency=25, nonLinear=False, normalized='none',
                   referenceFrequency=440, sampleRate=sr, size=hpcp_size, weightType='cosine', windowSize=1.0, maxShifted=False)
    out = []
    for fr in es.FrameGenerator(audio, frameSize=frame, hopSize=hop, startFromZero=True):
        s = spec(win(fr)); f, m = peaks(s); m = white(s, f, m); out.append(hpcp(f, m))
    return np.array(out)


def _shift_pcp(pcp):
    """essentia Key::shiftPcp - detuning correction: rotate so the global peak sits on a semitone bin."""
    res = len(pcp) // 12
    pcp = pcp / (pcp.max() + 1e-12)
    i = int(np.argmax(pcp)) % res
    return np.roll(pcp, -i) if i <= res // 2 else np.roll(pcp, res - i)


def hpcp_to_scores(avg, prof, hpcp_size=12, threshold=0.2, detune=True):
    """essentia streaming Key post-processing then 24-key correlation. Returns {(pc,mode): corr}."""
    p = avg / (avg.max() + 1e-12)
    p[p < threshold] = 0.0
    if hpcp_size > 12 and detune:
        p = _shift_pcp(p)
    if hpcp_size > 12:  # essentia interpolates profiles up; we instead fold the pcp down to 12 bins (sum per semitone)
        res = hpcp_size // 12
        p = np.array([p[(i * res - res // 2) % hpcp_size:(i * res - res // 2) % hpcp_size + res].sum() if (i * res - res // 2) >= 0
                      else np.concatenate([p[(i * res - res // 2) % hpcp_size:], p[:i * res + res - res // 2]]).sum() for i in range(12)])
    p = np.roll(p, 9)  # essentia HPCP bin 0 = A (pc 9); q[c] = p[(c-9)%12]
    return profile_scores(p, prof)


def _ess_np(path, prof='bgate', hpcp_size=12, segment=None, whole=True):
    H = essentia_hpcp_frames(path, hpcp_size, whole=whole)
    if segment:
        fr = int(segment * 44100 / 4096); acc = None
        for i in range(0, len(H) - fr + 1, fr):
            sc = hpcp_to_scores(H[i:i + fr].mean(axis=0), prof, hpcp_size)
            v = np.array([sc[k] for k in sorted(sc)]); v = (v - v.mean()) / (v.std() + 1e-9)
            acc = v if acc is None else acc + v
        scores = {k: float(acc[i]) for i, k in enumerate(sorted(sc))}
    else:
        scores = hpcp_to_scores(H.mean(axis=0), prof, hpcp_size)
    return top3_from_scores(scores, 'softmax')


def m_essnp_bgate(path):     return _ess_np(path, 'bgate')
def m_essnp_edma(path):      return _ess_np(path, 'edma')
def m_essnp_bgate_36(path):  return _ess_np(path, 'bgate', 36)
def m_essnp_bgate_seg(path): return _ess_np(path, 'bgate', segment=10)
def m_ess_bgate_36(path):    return _essentia(path, 'bgate', extra=dict(hpcpSize=36, averageDetuningCorrection=True))
def m_ess_edma_36(path):     return _essentia(path, 'edma', extra=dict(hpcpSize=36, averageDetuningCorrection=True))
def m_ess_braw_36(path):     return _essentia(path, 'braw', extra=dict(hpcpSize=36, averageDetuningCorrection=True))

METHODS = {k[2:]: v for k, v in globals().items() if k.startswith('m_')}


# ---------------------------------------------------------------- the shipped bpm.py (added after the fix landed)
def m_bpmpy(path):
    """Exactly what bpm.py ships now: detect_keys_essentia on the whole track (essentia decode)."""
    sys.path.insert(0, str(HERE.parents[2]))
    import bpm
    if not bpm._have_essentia():
        raise RuntimeError('essentia missing')
    a_key, _ = bpm.load_audio_essentia(path)
    return [(parse_key(k), c) for k, c in bpm.detect_keys_essentia(a_key)]

METHODS = {k[2:]: v for k, v in globals().items() if k.startswith('m_')}


if __name__ == '__main__':
    names = sys.argv[1:] or list(METHODS)
    print(f"{'method':22} {'weighted':>8} {'exact':>6} {'fifth':>6} {'rel':>6} {'par':>6} {'other':>6} {'top3':>6} {'s/trk':>6}")
    for m in names:
        s = run(m)
        print(f"{m:22} {s['weighted']:8.1f} {s['exact']:6.1f} {s['fifth']:6.1f} {s['relative']:6.1f} {s['parallel']:6.1f} {s['other']:6.1f} {s['top3_hit']:6.1f} {s['secs_per_track']:6.2f}", flush=True)
