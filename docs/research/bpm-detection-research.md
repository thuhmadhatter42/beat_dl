# BPM detection for bpm.py — research + benchmark (2026-09-11)

Research only; nothing in `bpm.py` was changed. Every accuracy number below is from the
benchmark in `docs/research/bpm-bench/` (run log: `run-2026-09-11.txt`) unless a paper is cited.

## Recommendation (ranked)

1. **Essentia TempoCNN, `deeptemp-k16-3` model** — 87.5 % Acc1 / 100 % Acc2 on the 40-clip
   set vs. 30 % / 55 % for the current code. ~1.7 s wall per fresh process (import 0.8 s, mp3
   decode 0.8 s, inference 0.1 s). No torch, no numba. `pip install essentia-tensorflow`
   (single wheel, cp314 arm64 + x86_64). Models are CC BY-NC-SA 4.0 (fine for J's own use).
2. **Essentia TempoCNN `deepsquare-k16-3`** — 82.5 % / 97.5 %, same install. Keep as a
   second opinion only if you want a confidence flag; it does not beat deeptemp on its own.
3. **Beat This! (CPU)** — 77.5 % / 95 %, but needs torch (590 MB) and an 81 MB checkpoint
   downloaded at first run; **torch has no macOS x86_64 wheels for Python 3.14** → dead on
   Studio-E-2. Same for DeepRhythm (72.5 % / 100 %, AGPL, torch + nnAudio).
4. Essentia RhythmExtractor2013 / Percival: 45–52 % Acc1 — better than librosa, still
   octave-blind. Not worth it when TempoCNN is in the same wheel.
5. librosa anything: 20–40 % Acc1. Tempogram voting + folding + prior tuning did **not**
   help (see table). Genre-range octave folding on top of *any* method made things worse on
   this set (post-hoc test, fold to ≤150/160/165 BPM: deeptemp 35/40 → 27–29/40).

## Runtime facts (verified on this Mac)

- `/opt/homebrew/bin/python3` = 3.14.7; system librosa 0.11.0, numpy 2.5.3; ffmpeg + yt-dlp present.
- Note: a bare `pip install librosa` today resolves to **librosa 1.0.0**, not 0.11.0.
  The benchmark pinned 0.11.0 to match the shipped code.
- Wheel availability probed with `pip download --only-binary=:all: --platform … --python-version …`:

| package | py3.14 arm64 (this Mac) | py3.14 Intel | py3.13 Intel | notes |
|---|---|---|---|---|
| essentia-tensorflow 2.1b6.dev1438 | yes, macosx_15_0 (99 MB) | yes, macosx_15_0 (122 MB) | dev1389, macosx_14_0 | superset of `essentia`; contains TempoCNN, RhythmExtractor2013, KeyExtractor |
| essentia (no TF) | yes | yes, macosx_15_0 | dev1389, macosx_14_0 | no TempoCNN |
| llvmlite / numba (librosa dep) | yes | **NO wheel at all** (llvmlite 0.49 ships arm64-only for macOS) | 0.45.1, macosx_10_15 | librosa on an Intel Mac with py3.14 will try to compile llvmlite → the exact failure `deps.sh` comments on |
| torch 2.14 | yes (590 MB) | **none** (torch dropped macOS x86_64) | none | kills beat_this, BeatNet, DeepRhythm on Studio-E-2 |
| madmom | build fails (Cython/numpy 2) | — | — | unmaintained; BeatNet imports it → BeatNet dead |
| aubio 0.4.9 | sdist only, build fails | — | — | |
| tempocnn (hendriks73 PyPI) | ResolutionImpossible (needs TF 2.x pins) | — | — | use the Essentia port instead |

**[Next session] Studio-E-2 unknowns to check before shipping**: `sw_vers` and `python3 --version`.
essentia-tensorflow needs macOS ≥ 15 for py3.14, ≥ 14 for py3.13/3.12, ≥ 10.9 for py ≤ 3.11
(dev1110). If it's on py3.14 there, librosa itself is already broken there (no llvmlite wheel) —
PICKUP.md item 1 ("confirm librosa installs on Studio-E-2") is likely to fail for that reason.
Waiting is safe as long as nobody expects BPM tags from Studio-E-2 yet.

## Evaluation set

GiantSteps Tempo (Knees et al., ISMIR 2015), tempo ground truth from `annotations_v2`
(Schreiber & Müller 2018 crowd-corrected). 664 two-minute Beatport clips; the Beatport LOFI
URLs are dead (404), the JKU mirror `https://www.cp.jku.at/datasets/giantsteps/backup/<id>.mp3`
works (md5-verified against the repo). There is no free hip-hop-only tempo set with clean
annotations; GiantSteps has only 2 hip-hop tracks, so the subset over-samples the genres with the
same half-time ambiguity: dubstep (140 with half-time feel), glitch-hop, chill-out (78–101),
reggae-dub (70), breaks, plus dnb/house/techno as controls. 40 clips, 82 MB, `subset.tsv` lists
id / genre / reference BPM.

Re-fetch: `bash docs/research/bpm-bench/fetch.sh` (clones annotations, downloads the 40 mp3s +
the two TempoCNN `.pb` files; ~2 min). Note curl on the MBP cannot resolve `www.cp.jku.at`
through the Tailscale resolver; the script pins the IP with `--resolve`.

## Benchmark (40 clips, Acc1 = ±4 %, Acc2 = also accepts ×⅓ ×½ ×2 ×3)

| method | Acc1 | Acc2 | s/track (warm loop, M-series) |
|---|---|---|---|
| **current** (`beat_track` on loudest 60 s) | 30.0 % | 55.0 % | 0.21 |
| librosa `feature.tempo`, full track, default prior | 40.0 % | 52.5 % | 0.23 |
| librosa per-frame tempo vote, prior 100 BPM ±1.5 oct | 20.0 % | 62.5 % | 0.29 |
| same + fold to 60–180 | 20.0 % | 62.5 % | 0.27 |
| essentia RhythmExtractor2013 multifeature | 45.0 % | 82.5 % | 1.38 |
| essentia RhythmExtractor2013 degara | 52.5 % | 80.0 % | 0.40 |
| essentia PercivalBpmEstimator | 50.0 % | 87.5 % | 0.53 |
| essentia TempoCNN deepsquare-k16-3 | 82.5 % | 97.5 % | 0.92 |
| **essentia TempoCNN deeptemp-k16-3** | **87.5 %** | **100 %** | 0.81 |
| DeepRhythm 0.0.13 (torch, CPU) | 72.5 % | 100 % | 2.67 |
| Beat This! final0 (torch, CPU, no DBN) | 77.5 % | 95.0 % | 2.09 |

Per-genre, deeptemp vs current (Acc1 hits / clips): hip-hop 2/2 vs 0/2 · dubstep 6/6 vs 2/6 ·
glitch-hop 6/6 vs 4/6 · chill-out 2/5 vs 0/5 · reggae-dub 2/2 vs 0/2 · breaks 4/4 vs 1/4 ·
dnb 5/5 vs 1/5 · house 3/3 vs 0/3 · techno 3/3 vs 1/3 · pop-rock 1/3 vs 2/3.

Literature cross-check: Schreiber & Müller 2018 report TempoCNN at 73.0 % Acc1 / 89.3 % Acc2 on
full GiantSteps (v1 annotations) and 74.2 % / 92.1 % on their 7-dataset "Combined" set; Böck
2015 (madmom) 58.9 % / 86.4 % on GiantSteps. Our higher number is the v2 annotations plus a
small, EDM-heavy subset — treat it as "clearly best of what installs", not as a population estimate.
DeepRhythm's README claims 95.9 % Acc1 on its own 953-song set; not reproduced here (72.5 %).

## Failures of the winner (all octave errors)

| track | genre | ref | deeptemp | error |
|---|---|---|---|---|
| 1743969 | pop-rock | 79 | 157 | ×2 |
| 210560 | chill-out | 78 | 158 | ×2 |
| 4091609 | chill-out | 80 | 160 | ×2 |
| 172384 | chill-out | 84 | 168 | ×2 |
| 3151015 | pop-rock | 174 | 87 | ×½ |

Pattern: slow (78–84 BPM) downtempo tracks get doubled. That is exactly J's hip-hop/R&B range,
and it is the one place the annotation convention is arguable (a 80-BPM chill-out track *is*
160 counted double-time). A blanket "fold anything above 150/160 down" fixes those four and
breaks all six 170–175 dnb/house clips (net loss on this set: 35 → 29/40). For J's genre list
(no dnb) the same post-hoc fold on the 25 non-dnb/house/techno/breaks clips only moved deeptemp
from 20/25 to 21/25 — within noise, so **do not add a fold rule** unless J states a convention
(see open question).

## Exact algorithm to implement

```python
# bpm.py — replace detect_bpm(); keep get_loud_section() only for the key detector.
import essentia.standard as es          # from essentia-tensorflow
MODEL = Path(__file__).parent / "models" / "deeptemp-k16-3.pb"   # 1.3 MB, ship in repo

def detect_bpm(filepath):
    audio = es.MonoLoader(filename=str(filepath), sampleRate=11025)()   # TempoCNN wants 11025 Hz
    global_bpm, local_bpm, local_prob = es.TempoCNN(graphFilename=str(MODEL))(audio)
    return round(float(global_bpm), 1)      # integer BPM from the model, printed as "148.0"
```

- Run on the **whole track** (that's what was benchmarked; 2-min clips → 0.1 s inference).
  The loudest-60 s crop is unnecessary for TempoCNN and was part of why the old code failed.
- `TempoCNN(aggregationMethod="majority")` is the default; keep it (constant-tempo beats).
- Optional confidence for the filename/stderr, not line 1: `float(np.mean(local_prob))` and the
  share of patches whose `local_bpm` is within 4 % of `global_bpm`. In the smoke test the two
  hip-hop clips had mean patch prob 0.6–0.85 with one patch voting ×½.
- Optional fractional refinement (not benchmarked, GiantSteps refs are integers anyway):
  `es.RhythmExtractor2013(method="degara")` beat intervals → `60/median(interval)`, accept only
  if within 4 % of the TempoCNN value, else keep the integer.
- Keep librosa only for `detect_keys()`. If librosa is absent (Intel + py3.14 case), Essentia's
  `es.KeyExtractor()` returns (key, scale, strength) and could replace it — separate decision.
- Model file: `curl -o models/deeptemp-k16-3.pb https://essentia.upf.edu/models/tempo/tempocnn/deeptemp-k16-3.pb`
  (1,320,120 bytes). Commit it (CC BY-NC-SA 4.0 — add the attribution line to README). Then bpm.py
  is fully offline.
- Silence essentia's `[ INFO ]` chatter: `essentia.log.infoActive = False` before use, and the
  TF absl warning goes to stderr (run.sh already discards stderr).

## Install lines

```bash
# deps.sh — replaces the librosa-only block. Order matters: essentia-tensorflow first (no numba);
# librosa second and allowed to fail (key detection degrades, BPM still works).
pip3 install essentia-tensorflow --break-system-packages --prefer-binary
pip3 install librosa==0.11.0 --break-system-packages --prefer-binary || echo "librosa unavailable — key detection off"
```

Presence check for `deps.sh`: `python3 -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('essentia') else 1)"`.
Do **not** also install plain `essentia`; both wheels unpack into the same `essentia/` package and
the TF one is a superset. Disk: ~420 MB unpacked (bundles libtensorflow).

## Known failure modes

- Octave doubling on slow (<90 BPM) tracks with busy hi-hats — see table above. Trap at 70/140
  will come out as one or the other with no way to know J's preferred count.
- Model outputs integer BPM (256 classes, 30–286). Beats at 87.5 BPM will read 87 or 88.
- Tempo changes / tempo-less intros: `majority` aggregation copes; a half-speed outro of ≥50 %
  of the track would flip it.
- First run after install: TF graph load adds ~0.5 s; nothing is downloaded at runtime.
- essentia-tensorflow is tagged "pre-release" on PyPI (it has been for years; dev1438 is the
  May 2026 build). Pin the version in deps.sh so a future wheel can't silently change results.

## Open question for J

octave convention: for a trap beat you'd count at 70/140, do you want the filename to say 140
(Beatport/DJ convention, what the benchmark ground truth uses and what TempoCNN leans to) or 70
(how many producers label half-time)? Answer decides whether a `≤ X → halve` rule is added; the
data says leave it out until you say.

## Eval harness

```bash
cd ~/dev/beat_dl/docs/research/bpm-bench
python3 -m venv venv && venv/bin/pip install --prefer-binary "librosa==0.11.0" essentia-tensorflow   # + deeprhythm beat_this for the torch rows
bash fetch.sh                                     # 40 clips + 2 models, ~2 min
venv/bin/python bench.py --methods current,tempocnn_deeptemp,tempocnn_deepsquare   # or omit --methods for all 11
```
Prints per-track lines and the Acc1/Acc2 table; writes `results.tsv`. `bench.py::m_current` is a
byte-for-byte copy of today's `bpm.py` pipeline, so a re-run after the fix can add the new
`detect_bpm` as one more entry in `METHODS` and compare on identical clips.

## Sources

- GiantSteps Tempo dataset + JKU mirror script: https://github.com/GiantSteps/giantsteps-tempo-dataset
- Schreiber & Müller, "A Single-Step Approach to Musical Tempo Estimation Using a CNN", ISMIR 2018 (Table 1 numbers above): https://www.tagtraum.com/download/2018_schreiber_tempo_cnn.pdf
- Schreiber & Müller, crowd-corrected GiantSteps annotations (v2): https://www.tagtraum.com/download/2018_schreiber_tempo_giantsteps.pdf
- Essentia TempoCNN algorithm: https://essentia.upf.edu/reference/std_TempoCNN.html ; models + CC BY-NC-SA 4.0 licence: https://essentia.upf.edu/models.html
- essentia-tensorflow wheels: https://pypi.org/project/essentia-tensorflow/#files ; essentia: https://pypi.org/project/essentia/#files
- llvmlite wheel list (arm64-only for macOS): https://pypi.org/project/llvmlite/#files
- Beat This! (Foscarin, Schlüter, Widmer, ISMIR 2024): https://github.com/CPJKU/beat_this
- DeepRhythm: https://github.com/bleugreen/deeprhythm
- madmom install breakage (Cython / py>3.9): https://github.com/CPJKU/madmom/issues/478 , https://github.com/CPJKU/beat_this/issues/9
- Review of AI tempo estimation (Acc1/Acc2 definitions, octave-error discussion): https://arxiv.org/abs/2401.00209
- librosa.feature.tempo (prior / aggregate params tried): https://librosa.org/doc/main/generated/librosa.feature.tempo.html
