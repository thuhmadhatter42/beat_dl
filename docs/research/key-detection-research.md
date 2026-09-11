# Key detection for bpm.py — research + benchmark (2026-09-11)

Research only; nothing in `bpm.py` was changed. Every accuracy number below is from the benchmark
in `docs/research/key-bench/` (run log: `run-2026-09-11.txt`) unless a paper is cited.
Companion to `bpm-detection-research.md` — same wheel (`essentia-tensorflow`) covers both fixes.

## Recommendation (ranked)

1. **Essentia HPCP front end (KeyExtractor chain, `hpcpSize=36` + detuning correction) + `bgate`
   profiles, ranked in numpy over all 24 keys** — MIREX weighted **85.1 / exact 79.5 %** on the
   39-clip GS+-labelled set vs **55.4 / 43.6 %** for the current code. 0.2 s per 2-min clip,
   0.3–1.9 s for a 4-min mp3/m4a/webm. No torch, no librosa, no numba: `essentia-tensorflow`
   (already required for the BPM fix) decodes the mp3 itself via `MonoLoader`. Gives a real
   top-3 and the raw material for an honest confidence (see below). Method `essnp_bgate_36`.
2. **Same via `es.KeyExtractor(profileType='bgate', hpcpSize=36, averageDetuningCorrection=True)`**
   — 83.6 / 79.5 %, three lines of code, but only exposes the winner + `strength`, so slots 2–3
   and the percentages would be fabricated. Method `ess_bgate_36`. Use only if you refuse the
   ~40 lines of numpy in option 1. At hpcpSize=12 the numpy ranking reproduces KeyExtractor's
   winner 12/12; at 36 the two differ on 4/39 (essentia interpolates the profiles up to 36 bins,
   option 1 folds the HPCP down to 12) — option 1 is the better of the two on those 4.
3. **OpenKeyScan `openkeyscan3.pt` CNN** (Korzeniowski & Widmer 2018 AllConv architecture,
   retrained by rekordcloud, MIT) — 75.1 / 66.7 % here. Its softmax IS well calibrated
   (p ≥ 0.85 → 15/15 correct; p < 0.70 → 5/17), and it is the best top-3 recall (92 %), but
   it lost to essentia on top-1, needs torch (590 MB, **no macOS x86_64 wheel for py3.14** →
   dead on the Intel Mac), and 3.6 s / 4-min track. Gating it in (CNN when p ≥ 0.7 else
   essentia) changed nothing: 85.1 / 79.5 %. Not worth the dependency. Method `cnn_oks3`.
4. **librosa-only fallback: HPSS-harmonic → `chroma_cens` → edma profiles**, 81.0 / 76.9 % —
   but 10.8 s per 4-min track (HPSS) and librosa is exactly the package that will not install on
   Intel + py3.14 (no llvmlite wheel, see BPM doc). Keep only as a documented emergency path.
   Method `lib_edma_cens`.
5. Not viable: `madmom` (sdist only, Cython/numpy-2 build fails), `keyfinder` PyPI 1.1.0
   (sdist from 2019, needs libkeyfinder + libav C build), `pykeyfinder`/`keyfinder-cli` (not on
   PyPI; `brew install libkeyfinder` exists but has no Python binding wheel). 2024–2026
   foundation-model key probes (MERT, MuQ, MARBLE `predict_key.py`) all need torch + 300 MB–1 GB
   weights — disqualified by the Intel constraint before accuracy is even asked; not benchmarked.

**Shipped 2026-09-11:** `bpm.py` now implements option 1 (`detect_keys_essentia`, single essentia decode shared with
TempoCNN). `bench.py bpmpy` runs the shipped code on the same clips: **85.1 / 79.5 %** GS+ (66.2 / 60.0 original labels),
identical to `essnp_bgate_36`; confidence bins measured: shown ≥ 85 → 85 % right (n=20), 70–85 → 75 % (n=16), 40–55 → 2/3.
Fresh-process `bpm.py` on a 3-min 48 kHz mp3: 3.1 s (2-min clip 1.7 s). Note: `librosa.beat.beat_track` segfaults on
py3.14 + numba 0.67 (guvectorize compile), so the librosa BPM fallback uses `librosa.feature.tempo` (same estimate).

## Runtime facts (verified on this Mac)

- `/opt/homebrew/bin/python3` 3.14.7; system librosa 0.11.0, numpy 2.5.3. Benchmark venv pinned
  `librosa==0.11.0` (bare `pip install librosa` now gives 1.0.0).
- `essentia` / `essentia-tensorflow` 2.1b6.dev1438: cp314 wheels for macosx_15_0 arm64 **and**
  x86_64 (Intel needs macOS ≥ 15; cp313/cp312 wheels are macosx_13_0 for x86_64). Both wheels
  unpack into the same `essentia/` package; install only `essentia-tensorflow` (superset, has
  `KeyExtractor`, `HPCP`, `SpectralWhitening`, `TempoCNN`). The benchmark ran on the TF wheel.
- torch 2.14 / torchaudio 2.11: arm64 wheels only. essentia mp3/m4a/webm decode works without ffmpeg
  on the Python side (`MonoLoader` uses bundled ffmpeg libs).
- Wall time, warm process, M-series: essentia HPCP36 path 0.19 s per 2-min clip; 4-min mp3 1.4 s,
  m4a 0.3 s, webm 1.9 s. CNN 0.32 s / clip, 3.6 s / 4-min. Cold `import essentia` adds ~0.8 s.

## Evaluation set and the label problem

GiantSteps Key (Knees et al., ISMIR 2015): 604 two-minute Beatport previews, EDM — the standard
key benchmark and the closest free set to beats (minor-heavy, 808/sub bass, loops). No free
hip-hop key set with annotations exists; treat the numbers as "EDM-with-bass", and have J
spot-check 10 of his own beats against Auto-Key 2 before calling it done.

Subset: 40 clips, `random.seed(42)`, stratified 14 major + 26 minor (the full set is 85 % minor;
the over-sampled majors are deliberately the hard cases). Audio from the JKU mirror, md5-verified;
Beatport LOFI URLs are dead. Re-fetch: `bash docs/research/key-bench/fetch.sh`.

**The original GiantSteps labels are wrong often enough to change the ranking.** Faraldo's
revised **GiantSteps+** labels (Zenodo 1095691, with modal detail and confidence) disagree with
the originals on **27 of our 40** clips; 10 of those are mode flips (e.g. 3076768 "A major" →
A minor aeolian, 4873286 "Gb major" → Gb minor dorian, 1356281 "Eb major" → Eb minor). 1652412 is
"Eb other" in GS+ (no key) and is dropped → n = 39. Every method scores 15–20 points higher on
GS+ and the essentia methods overtake the CNN there. `rescore.py` prints both columns; the GS+
column is the one to believe (GS+ is the same author's second pass with per-track confidence and
comments; the originals came from user corrections on Beatport). 95 % CI on 39
clips is roughly ±13 points on exact-match — ranking gaps under ~8 points are not significant.

## Benchmark (39 clips, GS+ labels; MIREX weights correct 1.0 / fifth 0.5 / relative 0.3 / parallel 0.2)

| method | weighted | exact | fifth | rel | par | other | top-3 hit | s/clip |
|---|---|---|---|---|---|---|---|---|
| **current** (`chroma_cqt` mean of loudest 60 s, Krumhansl corr) | 55.4 | 43.6 | 15.4 | 5.1 | 12.8 | 23.1 | 74.4 | 0.30 |
| librosa: harmonic + chroma_cqt + Krumhansl, whole track | 74.4 | 66.7 | 12.8 | 2.6 | 2.6 | 15.4 | 87.2 | ~3 |
| librosa: harmonic + chroma_cqt + Temperley | 48.7 | 41.0 | 12.8 | 2.6 | 2.6 | 41.0 | 64.1 | ~3 |
| librosa: harmonic + chroma_cqt + Sha'ath | 76.7 | 69.2 | 12.8 | 0.0 | 5.1 | 12.8 | 89.7 | ~3 |
| librosa: chroma_cqt + Sha'ath, no HPSS | 72.6 | 61.5 | 15.4 | 2.6 | 12.8 | 7.7 | 82.1 | 0.5 |
| librosa: harmonic + chroma_cqt + edma | 80.0 | 76.9 | 5.1 | 0.0 | 2.6 | 15.4 | 89.7 | ~3 |
| librosa: harmonic + chroma_cqt + edma, 10 s segment vote | 80.0 | 76.9 | 5.1 | 0.0 | 2.6 | 15.4 | 89.7 | ~3 |
| librosa: harmonic + chroma_cqt + edma, loudest 60 s only | 62.6 | 56.4 | 7.7 | 2.6 | 7.7 | 25.6 | 82.1 | ~2 |
| librosa: harmonic + chroma_cqt + bgate | 74.1 | 69.2 | 5.1 | 2.6 | 7.7 | 15.4 | 84.6 | ~3 |
| librosa: harmonic + **chroma_cens** + edma | 81.0 | 76.9 | 5.1 | 0.0 | 7.7 | 10.3 | 92.3 | ~3 |
| essentia KeyExtractor temperley | 57.2 | 43.6 | 12.8 | 20.5 | 5.1 | 17.9 | — | 0.20 |
| essentia KeyExtractor shaath | 74.4 | 66.7 | 10.3 | 0.0 | 12.8 | 10.3 | — | 0.17 |
| essentia KeyExtractor edmm | 71.3 | 61.5 | 7.7 | 7.7 | 17.9 | 5.1 | — | 0.16 |
| essentia KeyExtractor edma | 81.0 | 74.4 | 10.3 | 0.0 | 7.7 | 7.7 | — | 0.16 |
| essentia KeyExtractor braw | 83.3 | 76.9 | 7.7 | 5.1 | 5.1 | 5.1 | — | 0.17 |
| essentia KeyExtractor bgate (defaults, hpcp 12) | 82.6 | 76.9 | 7.7 | 2.6 | 5.1 | 7.7 | — | 0.19 |
| essentia KeyExtractor bgate, loudest 60 s only | 74.1 | 66.7 | 5.1 | 7.7 | 12.8 | 7.7 | — | 0.15 |
| essentia KeyExtractor bgate, minFrequency 200 Hz (bass cut) | 69.5 | 61.5 | 5.1 | 7.7 | 15.4 | 10.3 | — | 0.17 |
| essentia KeyExtractor bgate, hpcp 36 + detuning corr. | 83.6 | 79.5 | 2.6 | 2.6 | 10.3 | 5.1 | — | 0.18 |
| essentia KeyExtractor braw, hpcp 36 + detuning corr. | 83.6 | 79.5 | 2.6 | 2.6 | 10.3 | 5.1 | — | 0.17 |
| essentia HPCP12 → numpy bgate (full ranking) | 80.8 | 74.4 | 7.7 | 5.1 | 5.1 | 7.7 | 87.2 | 0.19 |
| essentia HPCP12 → numpy bgate, 10 s segment vote | 83.1 | 76.9 | 7.7 | 2.6 | 7.7 | 5.1 | 87.2 | 0.19 |
| **essentia HPCP36 + detune → numpy bgate (full ranking)** | **85.1** | **79.5** | 7.7 | 2.6 | 5.1 | 5.1 | 92.3 | 0.19 |
| OpenKeyScan CNN `keynet.pt` (Nf=20) | 72.3 | 64.1 | 7.7 | 2.6 | 17.9 | 7.7 | 89.7 | 0.30 |
| OpenKeyScan CNN `openkeyscan3.pt` (Nf=64) | 75.1 | 66.7 | 10.3 | 2.6 | 12.8 | 7.7 | 92.3 | 0.32 |
| CNN if softmax ≥ 0.7 else essentia HPCP36 bgate | 85.1 | 79.5 | — | — | — | — | — | 0.5 |

Against the original (noisier) labels the same rows read: current 46.8 / 35.0, KeyExtractor
bgate 63.8 / 57.5, HPCP36 bgate numpy 66.2 / 60.0, CNN 62.8 / 52.5 — consistent with published
full-set numbers (bgate 72.4 weighted on the KeyFinder set [Korzeniowski 2018 Table 2]; edmm 72.0
on full GiantSteps [Faraldo 2016 Table 2]; AllConv CNN 74.6 on GiantSteps [Korzeniowski 2018]).
Our subset over-samples the mislabelled majors, hence the lower absolute numbers on the original
labels.

Take-aways the table supports:
- **Whole track, not the loudest 60 s**: −8 to −17 points every time it was tried (both libs).
  Sparse-intro beats need every bar that contains a note.
- **Profiles matter more than chroma type**: Krumhansl/Temperley are pop/classical priors and
  bias to major (Temperley: 20 % relative-key errors). The EDM-derived `bgate`/`braw`/`edma`
  profiles (Faraldo) win on every front end.
- **Keep the bass**: cutting below 200 Hz cost 14 points. 808s carry the tonic in this music.
- Spectral whitening + peak-based HPCP (essentia) beats librosa CQT chroma with the same profile
  by ~3–5 points and is 10× faster; HPSS in librosa buys ~4 points at 3 s/clip.
- 36-bin HPCP + detuning correction: +2.5 weighted, −5 fifth errors here. Faraldo's Table 1
  shows a smaller gain on full GiantSteps (edma 66.8 → 67.3 with `dc` on top of whitening; the
  big `dc` win is on the Beatles set) — treat +2.5 as "helps, within noise".
- Segment voting did not beat a whole-track average; the CNN's calibrated softmax and
  cross-method agreement are the useful confidence signals, not voting.

## Failures of the winner (essentia HPCP36 bgate, GS+ labels; 8 of 39)

| track | GS+ | orig | predicted (top-3) | type | comment |
|---|---|---|---|---|---|
| 1041574 | G# | G# | Cm 62 · Gm 20 · G 10 | other | Ab-major track read as its iii; every method incl. CNN said Cm |
| 1140027 | Gm | C#m | Cm 57 · G 19 · Gm 11 | fifth | truth is 3rd; original label was a tritone away, GS+ likely right |
| 1161234 | C mixolydian | C | Cm 44 · C 15 · Fm 12 | parallel | mixolydian (b7) pulls the minor profile; all methods failed |
| 3397932 | Dm | Bm | F 37 · Am 23 · C 18 | relative | CNN alone got Dm (p = 0.32) |
| 3949799 | Am | A | F 51 · C 18 · Am 8 | other | CNN got Am (p = 0.67); essentia hears the F-C-Am loop as F |
| 4328388 | F \| Fm | Fm | Fm 43 · F 20 · Cm 15 | parallel | GS+ lists both; either answer is defensible |
| 781373 | E | E | A 26 · E 22 · Em 13 | fifth | low confidence; E was 2nd |
| 846900 | E mixolydian | E | A 32 · Am 20 · Em 19 | fifth | mixolydian: b7 (D) makes A major fit; E not in top-3 |

Pattern: modal material (mixolydian / dorian, common in beats built on a two-chord loop) and
major tracks in general: majors 7/12 correct, minors 24/27. Truth is in the top-3 on 36/39
(92 %; 5 of the 8 misses) — the top-3 output contract is genuinely useful here.

## Exact algorithm to implement

```python
# bpm.py — replace detect_keys(). Whole track in, no loudest-60 s crop, no librosa.
import numpy as np
import essentia
import essentia.standard as es          # from essentia-tensorflow
essentia.log.infoActive = False

NOTES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
# Faraldo 'bgate' profiles, essentia src/algorithms/tonal/key.cpp (index 0 = tonic)
BGATE_MAJ = np.array([1.00, 0.00, 0.42, 0.00, 0.53, 0.37, 0.00, 0.77, 0.00, 0.38, 0.21, 0.30])
BGATE_MIN = np.array([1.00, 0.00, 0.36, 0.39, 0.00, 0.38, 0.00, 0.74, 0.27, 0.00, 0.42, 0.23])
SR, FRAME, HOP, HPCP_SIZE, PCP_THRESHOLD = 44100, 4096, 4096, 36, 0.2

def hpcp_frames(path):
    """essentia KeyExtractor front end, frame by frame (keyextractor.cpp defaults)."""
    audio = es.MonoLoader(filename=str(path), sampleRate=SR)()
    win, spec = es.Windowing(type='hann', size=FRAME), es.Spectrum(size=FRAME)
    peaks = es.SpectralPeaks(orderBy='magnitude', magnitudeThreshold=1e-4, minFrequency=25,
                             maxFrequency=3500, maxPeaks=60, sampleRate=SR)
    white = es.SpectralWhitening(maxFrequency=3500, sampleRate=SR)
    hpcp = es.HPCP(bandPreset=False, harmonics=4, minFrequency=25, maxFrequency=3500,
                   nonLinear=False, normalized='none', referenceFrequency=440, sampleRate=SR,
                   size=HPCP_SIZE, weightType='cosine', windowSize=1.0, maxShifted=False)
    out = []
    for fr in es.FrameGenerator(audio, frameSize=FRAME, hopSize=HOP, startFromZero=True):
        s = spec(win(fr)); f, m = peaks(s); m = white(s, f, m); out.append(hpcp(f, m))
    return np.array(out)

def key_scores(avg):
    """streaming Key post-processing (normalise, gate, detune-shift) + 24-key correlation."""
    p = avg / (avg.max() + 1e-12)
    p[p < PCP_THRESHOLD] = 0.0
    res = HPCP_SIZE // 12                                   # detuning correction: peak onto a semitone bin
    i = int(np.argmax(p)) % res
    p = np.roll(p, -i) if i <= res // 2 else np.roll(p, res - i)
    # fold 36 -> 12 (sum the 3 bins centred on each semitone), then rotate: essentia bin 0 = A
    p12 = np.array([np.take(p, range(i*res - res//2, i*res - res//2 + res), mode='wrap').sum() for i in range(12)])
    p12 = np.roll(p12, 9)
    scores = {}
    for i in range(12):
        scores[(i, 'major')] = float(np.corrcoef(p12, np.roll(BGATE_MAJ, i))[0, 1])
        scores[(i, 'minor')] = float(np.corrcoef(p12, np.roll(BGATE_MIN, i))[0, 1])
    return scores

def detect_keys(path):
    H = hpcp_frames(path)
    scores = key_scores(H.mean(axis=0))
    ranked = sorted(scores.items(), key=lambda kv: -kv[1])
    # confidence: see next section
    ...
```

`bench.py::essentia_hpcp_frames` / `hpcp_to_scores` are the tested versions of these two
functions; the snippet above was run against them and picks the same winner 10/10. Format as today:
`NOTES[pc] + ('m' if mode == 'minor' else '')`.

## Honest confidence

What is measured, per track, that predicts "top-1 is correct" (GS+ labels, n = 39):

| signal | how measured | correct-rate when high | when low |
|---|---|---|---|
| segment agreement `agree` | share of 10 s windows whose own winner == global winner | ≥ 0.90: 13/14 (93 %) | < 0.75: 13/19 (68 %) |
| CNN agreement | CNN top-1 == essentia top-1 | agree: 24/28 (86 %) | disagree: 7/11 (64 %) |
| correlation margin `(r1−r2)/r1` | | ≥ 0.20: 9/10 (90 %) | < 0.20: 22/29 (76 %) — weak |
| essentia `strength` (r1) | mean 0.87 correct vs 0.81 incorrect | too flat to bin | |
| CNN softmax (for the CNN's own answer) | | ≥ 0.85: 15/15 · 0.70–0.85: 6/7 | < 0.70: 5/17 |

The current "top-3 rescaled to 100" is not a confidence; it is always ~35–45 % for the winner.
Also note essentia's `firstToSecondRelativeStrength` output is not the true 1st-vs-2nd gap (it
compares against the running second maximum *within the same mode*) — do not use it.

Recommended top-1 confidence, no learned model (39 clips is too few to fit one honestly):

```python
agree = mean(window winner == global winner) over 10 s windows       # 0..1
margin = (r1 - r2) / r1
conf1 = 0.65 + 0.25 * agree + (0.08 if margin >= 0.20 else 0.0)    # 0.65..0.98
conf1 = min(conf1, 0.85) if ranked[0][0][1] == 'major' else conf1   # majors 7/12 vs minors 24/27 here: cap majors
```
Then split the remaining mass over slots 2–3 in proportion to their softmax over z-scored
correlations (`bench.top3_from_scores(..., 'softmax')`), so the three lines sum to ≤ 100 and the
second line is small when the winner is clear. Measured on the 39 clips with exactly this rule:
conf1 ≥ 0.90 → 6/7 right (86 %), 0.85–0.90 → 11/13 (85 %), 0.75–0.85 → 13/17 (76 %), < 0.75 →
1/2. Monotonic and roughly on the diagonal — that is the honesty claim; state it as "measured on
39 EDM clips" in the README, not as a calibrated probability. Re-fit the constants after J's own
beats are scored (`combo.py` prints `agree`/`margin`/`r1` per track).

If the CNN is ever added (arm64 only), the best confidence is simply its softmax when it agrees
with essentia, and "disagree → show both, conf ≤ 0.65".

## Install lines

```bash
# deps.sh — same block the BPM fix needs; nothing extra for key detection.
pip3 install "essentia-tensorflow==2.1b6.dev1438" --break-system-packages --prefer-binary
# librosa no longer required by bpm.py once both detect_bpm and detect_keys are on essentia.
```
Presence check: `python3 -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('essentia') else 1)"`.
Intel Mac: same line works on py3.14 only with macOS ≥ 15; on py3.13/3.12 the wheel is
macosx_13_0. Before shipping there, `sw_vers && python3 --version` (open item from the BPM doc).

## Known failure modes

- **Modal loops** (mixolydian / dorian two-chord beats): the b7 or natural 6 pulls the estimate to
  the relative/fifth key. 4 of 8 misses here. Auto-Key 2 also reports scale, not just key; there
  is no cheap fix with 24 major/minor profiles. Mitigation: the truth is in the top-3 92 % of the
  time — keep printing three lines.
- **Major keys**: 5 of 12 majors missed vs 3 of 27 minors (bgate was fitted on a 90 %-minor
  corpus). For hip-hop/trap (overwhelmingly minor) this bias is the right trade; a pop beat in a
  bright major key is the case to spot-check by ear.
- **Sample in another key than the drums/808**: not measurable on GiantSteps. Whole-track
  averaging lets the dominant section win; expect the 808 root to dominate when the sample is quiet.
- **Detuned/out-of-A440 material**: handled by the 36-bin shift only when the detune is < ±50 c
  and consistent; a beat pitched by a whole tone plus cents is fine, a beat that drifts is not.
- **Atonal / drum-only tracks**: no rejection path. Add a floor: if `r1 < 0.5` or `agree < 0.4`,
  print the keys but cap conf at 40 %.
- essentia writes `[ INFO ]` lines to stderr unless `essentia.log.infoActive = False`; run.sh
  already discards stderr, but the four-line stdout contract must stay clean.

## Eval harness

```bash
cd ~/dev/beat_dl/docs/research/key-bench
python3 -m venv venv && venv/bin/pip install --prefer-binary "librosa==0.11.0" essentia-tensorflow scikit-learn
bash fetch.sh                        # annotations + GS+ labels + 40 mp3s (md5-verified) + OpenKeyScan repo, ~2 min
venv/bin/pip install --prefer-binary torch torchaudio   # only for the cnn_* / ensemble rows (arm64 only)
venv/bin/python bench.py current essnp_bgate_36 ess_bgate_36     # or no args = all 33 methods (~25 min: librosa HPSS rows are slow)
venv/bin/python rescore.py           # table against original AND GS+ labels from results/*.json
venv/bin/python calib.py essnp_bgate_36 cnn_oks3                 # confidence bins
venv/bin/python combo.py             # per-track raw r1/r2/margin/agree + CNN p -> combo_raw.json
```
`bench.py::m_current` reproduces today's `bpm.py` byte-for-byte (loudest 60 s → `chroma_cqt` → Krumhansl
→ top-3 rescaled). After the fix, add the new `detect_keys` as one more `m_*` entry and re-run on
the identical clips. The audio dir is 55 MB and git-ignored; `fetch.sh` is idempotent.

## Sources

- GiantSteps Key dataset + JKU mirror: https://github.com/GiantSteps/giantsteps-key-dataset (Knees et al., ISMIR 2015)
- GiantSteps+ revised key labels (Faraldo 2017): https://zenodo.org/records/1095691
- Faraldo, Gómez, Jordà, Herrera, "Key Estimation in Electronic Dance Music", ECIR 2016 — Table 1/2 (edma/edmm, spectral whitening, detuning correction; edmm 72.0 weighted on GiantSteps): https://repositori.upf.edu/server/api/core/bitstreams/7a5f186a-b66f-47fe-8ae4-8fc2a8f9a395/content
- Faraldo, Jordà, Herrera, "A Multi-Profile Method for Key Estimation in EDM", AES 2017; reference code (bgate/braw params): https://github.com/angelfaraldo/edmkey
- Korzeniowski & Widmer, "Genre-Agnostic Key Classification with CNNs", ISMIR 2018 — Table 2 (AllConv 74.6 weighted GiantSteps; bgate 72.4 vs AllConv 76.1 on KeyFinder set): https://ismir2018.ircam.fr/doc/pdfs/7_Paper.pdf
- Essentia KeyExtractor params: https://essentia.upf.edu/reference/std_KeyExtractor.html ; profile tables + strength math: https://github.com/MTG/essentia/blob/master/src/algorithms/tonal/key.cpp ; front-end chain: https://github.com/MTG/essentia/blob/master/src/algorithms/extractor/keyextractor.cpp
- essentia / essentia-tensorflow wheels: https://pypi.org/project/essentia/#files , https://pypi.org/project/essentia-tensorflow/#files
- OpenKeyScan analyzer (MIT; `openkeyscan3.pt`, self-reported 79.0 weighted on GiantSteps, not reproduced here: 75.1 on our GS+ subset / 62.8 on original labels): https://github.com/rekordcloud/openkeyscan-analyzer
- libkeyfinder (GPL-3, C++/fftw, no py3.14 binding): https://github.com/mixxxdj/libkeyfinder ; PyPI `keyfinder` 1.1.0 sdist only: https://pypi.org/project/keyfinder/
- madmom PyPI (sdist only): https://pypi.org/project/madmom/
- Mixed In Key 11 vs KeyFinder vs Rekordbox vs Beatport, 200 tracks by ear (MIK 178/200, KeyFinder 152/200; half credit for relative): https://blog.dubspot.com/dubspot-lab-report-mixed-in-key-vs-beatport
- Auto-Key 2 = zplane TONART v3 (pitch-class-profile matching, EDM mode, tuning detection): https://licensing.zplane.de/technology , https://pluginreviewlab.com/best-key-detection-plugins/
- MuQ (2025) foundation-model key probe numbers on GiantSteps: https://arxiv.org/abs/2501.01108
