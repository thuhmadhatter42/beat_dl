#!/usr/bin/env python3
"""
BPM + Key detector.
BPM: Essentia TempoCNN (models/deeptemp-k16-3.pb) on the whole track. Two back ends, same numbers:
     - essentia-tensorflow: essentia.standard.TempoCNN + AudioLoader (today's path)
     - legacy essentia (no TensorFlow, no ffmpeg; old Macs): tempocnn_np.py (numpy port, weights in
       models/deeptemp-k16-3.npz) and decoding through the bundled ffmpeg CLI, set up to give the
       same samples AudioLoader gives (fixed-point mp3 decoder -> s16 -> /32768).
Key: Essentia HPCP (36 bins, spectral whitening, rebuilt at the track's own A when it is 5+ cents
     off 440: key_reading) on the whole track,
     correlated against Faraldo's 'bgate' EDM profiles for all 24 keys -> real top-3 with a
     confidence from segment agreement + margin (docs/research/key-detection-research.md).
One method, no fallback: a damaged install (essentia or its tempo model missing) is refused at
bring-up with ANALYZER_INCOMPLETE on stderr and exit 2, never a worse BPM from another method.
Warnings go to stderr only; stdout is the 4-line contract.
Also reads MIDI files (midi_analyze.py). After the 4 lines it prints "bpm_exact: <0.01 BPM>" and,
when the key is confident, "tuning_cents: <cents vs A=440>", then "chroma: [12 floats C..B]".
Live listening: `bpm.py --stream` reads raw float32 mono PCM on stdin and prints one JSON
reading per line (LiveAnalyzer, stream_main); the app pipes the mic / system audio in, nothing
is saved. A new song with no pause between is found by BoundaryDetector ({"event":"boundary"});
SIGUSR1 from the app (the player's title changed) forces one.
Usage: python3 bpm.py <filepath>
       python3 bpm.py --stream [--rate 44100] [--hop 2] [--gap 3]
       python3 bpm.py          (prompts for a path)
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TEMPOCNN_MODEL = HERE / "models" / "deeptemp-k16-3.pb"
TEMPOCNN_WEIGHTS = HERE / "models" / "deeptemp-k16-3.npz"
# Note names spelled the way Auto-Tune's Key menu spells them, which differs by scale
MAJOR_NOTES = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']
MINOR_NOTES = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B']

# Key profiles (index 0 = tonic). bgate/edma: Faraldo et al., essentia src/algorithms/tonal/key.cpp
BGATE = ([1.00, 0.00, 0.42, 0.00, 0.53, 0.37, 0.00, 0.77, 0.00, 0.38, 0.21, 0.30],
         [1.00, 0.00, 0.36, 0.39, 0.00, 0.38, 0.00, 0.74, 0.27, 0.00, 0.42, 0.23])
# EDMA is not used by the analyzer; tools/train-tempocnn/key_baseline.py scores against it as a baseline.
EDMA = ([1.00, 0.29, 0.50, 0.40, 0.60, 0.56, 0.32, 0.80, 0.31, 0.45, 0.42, 0.39],
        [1.00, 0.31, 0.44, 0.58, 0.33, 0.49, 0.29, 0.78, 0.43, 0.29, 0.53, 0.32])

# essentia KeyExtractor front-end defaults (keyextractor.cpp)
KEY_SR, FRAME, HOP, HPCP_SIZE, PCP_THRESHOLD = 44100, 4096, 4096, 36, 0.2
TEMPOCNN_SR = 11025
SEGMENT_SECS = 10


# The one refusal, for files (stderr, exit EXIT_INCOMPLETE) and live listening (an "error" event).
# app_run.py reads both, so the app shows this exact sentence.
ANALYZER_INCOMPLETE = "The analyzer is incomplete. Run Doctor."
EXIT_INCOMPLETE = 2


def _warn(msg):
    print(f"Warning: {msg}", file=sys.stderr)


def check_deps():
    try:
        import numpy  # noqa
    except ImportError:
        print("Missing: numpy — install with:  pip3 install numpy --break-system-packages", file=sys.stderr)
        return False
    return True


def _have_essentia():
    try:
        import essentia
        essentia.log.infoActive = False
        essentia.log.warningActive = False
        return True
    except ImportError:
        return False


# ---------------------------------------------------------------- shared key math (numpy only)

def key_scores(pcp12, profile):
    """Correlate a 12-bin pitch-class profile (bin 0 = C) against all 24 keys.
    Returns {(pitch_class, 'major'|'minor'): pearson r}."""
    import numpy as np
    maj, mn = np.array(profile[0]), np.array(profile[1])
    scores = {}
    for i in range(12):
        scores[(i, 'major')] = float(np.nan_to_num(np.corrcoef(pcp12, np.roll(maj, i))[0, 1]))
        scores[(i, 'minor')] = float(np.nan_to_num(np.corrcoef(pcp12, np.roll(mn, i))[0, 1]))
    return scores


def fmt_key(pc, mode):
    if mode == 'minor':
        return MINOR_NOTES[pc] + 'm'
    return MAJOR_NOTES[pc]


def softmax_probs(ranked):
    """Softmax over z-scored correlations across all 24 keys (same as the benchmark harness)."""
    import numpy as np
    v = np.array([s for _, s in ranked])
    z = (v - v.mean()) / (v.std() + 1e-9)
    p = np.exp(3.0 * z)
    return p / p.sum()


def top3_with_confidence(scores, agree):
    """
    Top-1 confidence rule from docs/research/key-detection-research.md (measured on 39 EDM clips,
    monotonic: conf >= 0.90 -> 86 % right, 0.85-0.90 -> 85 %, 0.75-0.85 -> 76 %).
      agree  = share of 10 s windows whose own winner == whole-track winner
      margin = (r1 - r2) / r1
      conf1  = 0.65 + 0.25*agree + 0.08 if margin >= 0.20   (majors capped at 0.85; bgate is minor-biased)
      floor: r1 < 0.5 or agree < 0.4 (atonal / drum-only) -> cap at 0.40
    Remaining mass goes to slots 2-3 in proportion to their softmax, so the 3 lines sum to <= 100.
    """
    ranked = sorted(scores.items(), key=lambda kv: -kv[1])
    r1, r2 = ranked[0][1], ranked[1][1]
    margin = (r1 - r2) / max(r1, 1e-6)
    conf1 = 0.65 + 0.25 * agree + (0.08 if margin >= 0.20 else 0.0)
    if ranked[0][0][1] == 'major':
        conf1 = min(conf1, 0.85)
    if r1 < 0.5 or agree < 0.4:
        conf1 = min(conf1, 0.40)
    p = softmax_probs(ranked)
    rest = 1.0 - conf1
    denom = max(1.0 - p[0], 1e-9)
    out = [(fmt_key(*ranked[0][0]), round(100 * conf1, 1))]
    for i in (1, 2):
        out.append((fmt_key(*ranked[i][0]), round(100 * rest * float(p[i]) / denom, 1)))
    return out


# ---------------------------------------------------------------- essentia path (main)

def _tool(name):
    """ORION_BIN (the Orion app's runtime) if set, then ./bin, else whatever is on PATH."""
    import os
    import shutil
    ob = os.environ.get("ORION_BIN")
    if ob and (Path(ob) / name).is_file():
        return str(Path(ob) / name)
    p = HERE / "bin" / name
    return str(p) if p.is_file() else shutil.which(name)


def decode_ffmpeg(filepath):
    """AudioLoader stand-in for the legacy (ffmpeg-less) essentia build: returns (stereo (n, 2) float32,
    sample rate, channels) exactly as essentia-tensorflow's AudioLoader does. That AudioLoader is
    ffmpeg 2.8, whose default mp3 decoder is the fixed-point one (s16 output -> float / 32768, clipped
    to +-1); `-c:a mp3` picks the same decoder in any newer ffmpeg (bit-identical on all 80 bench
    tracks). Other codecs are decoded to float like AudioLoader does."""
    import json
    import subprocess
    import numpy as np
    ffmpeg, ffprobe = _tool("ffmpeg"), _tool("ffprobe")
    if not ffmpeg or not ffprobe:
        raise RuntimeError("ffmpeg/ffprobe not found (expected in ./bin)")
    info = json.loads(subprocess.run(
        [ffprobe, "-v", "error", "-select_streams", "a:0", "-show_entries",
         "stream=codec_name,sample_rate,channels", "-of", "json", str(filepath)],
        capture_output=True, check=True).stdout)["streams"][0]
    sr, nch = int(info["sample_rate"]), min(int(info["channels"]), 2)
    mp3 = info.get("codec_name") == "mp3"
    cmd = [ffmpeg, "-nostdin", "-v", "error"] + (["-c:a", "mp3"] if mp3 else []) + \
          ["-i", str(filepath), "-map", "0:a:0", "-ac", str(nch), "-f", "s16le" if mp3 else "f32le",
           "-c:a", "pcm_s16le" if mp3 else "pcm_f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    if mp3:
        x = np.frombuffer(raw, np.int16).astype(np.float32) / np.float32(32768)
    else:
        x = np.frombuffer(raw, np.float32).copy()
    x = x.reshape(-1, nch)
    stereo = np.ascontiguousarray(x if nch == 2 else np.repeat(x, 2, axis=1), dtype=np.float32)
    return stereo, float(sr), nch


def load_audio_essentia(filepath):
    """Decode once; return (audio @ 44100 for HPCP, audio @ 11025 for TempoCNN).
    Same chain MonoLoader uses internally (AudioLoader -> MonoMixer -> Resample), so both arrays are
    byte-identical to MonoLoader(sampleRate=...) while decoding the file only once.
    The legacy essentia build has no AudioLoader; decode_ffmpeg gives the same samples."""
    import essentia.standard as es
    if hasattr(es, 'AudioLoader'):
        audio, sr, nch, *_ = es.AudioLoader(filename=str(filepath), computeMD5=False)()
    else:
        audio, sr, nch = decode_ffmpeg(filepath)
    mono = es.MonoMixer()(audio, nch)
    a_key = mono if sr == KEY_SR else es.Resample(inputSampleRate=sr, outputSampleRate=KEY_SR)(mono)
    a_bpm = mono if sr == TEMPOCNN_SR else es.Resample(inputSampleRate=sr, outputSampleRate=TEMPOCNN_SR)(mono)
    return a_key, a_bpm


def detect_bpm_essentia(audio_11k):
    """
    Essentia TempoCNN (deeptemp-k16-3) on the whole track. Benchmarked at 87.5% Acc1
    vs 30% for the old beat_track method (docs/research/bpm-detection-research.md).
    """
    import essentia.standard as es
    if hasattr(es, 'TempoCNN'):
        global_bpm, _local_bpm, _local_prob = es.TempoCNN(graphFilename=str(TEMPOCNN_MODEL))(audio_11k)
    else:                                   # legacy essentia: same network in numpy
        import tempocnn_np
        global_bpm, _local_bpm, _local_prob = tempocnn_np.tempo(audio_11k)
    return round(float(global_bpm), 1)


def _hpcp(reference=440.0):
    """The KeyExtractor HPCP (36 bins, 25 Hz - 3.5 kHz, 4 harmonics) with A at `reference` Hz."""
    import essentia.standard as es
    return es.HPCP(bandPreset=False, harmonics=4, minFrequency=25, maxFrequency=3500,
                   nonLinear=False, normalized='none', referenceFrequency=float(reference),
                   sampleRate=KEY_SR, size=HPCP_SIZE, weightType='cosine', windowSize=1.0,
                   maxShifted=False)


def hpcp_frames(audio_44k, peaks_out=None):
    """essentia KeyExtractor front end, frame by frame: hann -> spectrum -> peaks -> spectral
    whitening -> 36-bin HPCP (bass kept: minFrequency 25 Hz). Returns (n_frames, 36).
    peaks_out (a list) receives each frame's (frequencies, magnitudes, whitened magnitudes): the
    first two feed the tuning estimate, the frequencies + whitened magnitudes rebuild the HPCP at
    another reference (hpcp_from_peaks) without a second pass over the audio."""
    import numpy as np
    import essentia.standard as es
    win = es.Windowing(type='hann', size=FRAME)
    spec = es.Spectrum(size=FRAME)
    peaks = es.SpectralPeaks(orderBy='magnitude', magnitudeThreshold=1e-4, minFrequency=25,
                             maxFrequency=3500, maxPeaks=60, sampleRate=KEY_SR)
    white = es.SpectralWhitening(maxFrequency=3500, sampleRate=KEY_SR)
    hpcp = _hpcp()
    out = []
    for fr in es.FrameGenerator(audio_44k, frameSize=FRAME, hopSize=HOP, startFromZero=True):
        s = spec(win(fr))
        f, m = peaks(s)
        w = white(s, f, m)
        if peaks_out is not None:
            peaks_out.append((f, m, w))
        out.append(hpcp(f, w))
    return np.array(out)


def hpcp_from_peaks(peaks, reference):
    """The same HPCP frames hpcp_frames gave, rebuilt from its peaks_out with A at `reference` Hz
    (whitening does not depend on the reference, so this equals a fresh pass at that reference)."""
    import numpy as np
    hpcp = _hpcp(reference)
    return np.array([hpcp(f, w) for f, _m, w in peaks])


def hpcp_to_pcp12(avg):
    """essentia streaming Key post-processing: normalise, gate, detuning shift, fold 36 -> 12,
    rotate so bin 0 = C (essentia HPCP bin 0 = A)."""
    import numpy as np
    p = avg / (avg.max() + 1e-12)
    p[p < PCP_THRESHOLD] = 0.0
    res = HPCP_SIZE // 12
    i = int(np.argmax(p)) % res                       # put the global peak on a semitone bin
    p = np.roll(p, -i) if i <= res // 2 else np.roll(p, res - i)
    p12 = np.array([np.take(p, range(k * res - res // 2, k * res - res // 2 + res), mode='wrap').sum()
                    for k in range(12)])
    return np.roll(p12, 9)


def detect_keys_essentia(audio_44k, peaks_out=None):
    """Top-3 keys of a whole track (detune-robust: key_reading)."""
    peaks = peaks_out if peaks_out is not None else []
    return key_reading(hpcp_frames(audio_44k, peaks), peaks)["keys"]


NO_KEYS = [('C', 0.0), ('Am', 0.0), ('G', 0.0)]


def keys_from_hpcp(H):
    """Top-3 keys with confidence from HPCP frames (n, 36): the whole-track key plus agreement of
    its 10 s windows. Shared by files and live listening through key_reading."""
    return _keys_and_pcp(H)[0]


def _keys_and_pcp(H):
    """keys_from_hpcp plus the whole-window 12-bin profile (bin 0 = C) the key came from."""
    import numpy as np
    if len(H) == 0 or H.max() == 0:
        return list(NO_KEYS), np.zeros(12)
    pcp = hpcp_to_pcp12(H.mean(axis=0))
    scores = key_scores(pcp, BGATE)
    winner = max(scores, key=scores.get)
    # segment agreement over 10 s windows (a partial last window counts if >= half a window)
    fr = int(SEGMENT_SECS * KEY_SR / HOP)
    wins = []
    for i in range(0, len(H), fr):
        seg = H[i:i + fr]
        if len(seg) < fr // 2 and wins:
            break
        s = key_scores(hpcp_to_pcp12(seg.mean(axis=0)), BGATE)
        wins.append(max(s, key=s.get) == winner)
    agree = float(np.mean(wins)) if wins else 1.0
    return top3_with_confidence(scores, agree), pcp


TUNING_RETUNE_CENTS = 5   # |tuning| at or above which the key's HPCP is rebuilt at the track's A


def key_reading(H, peaks=None):
    """The key readout from HPCP frames H (n, 36) and their peaks (hpcp_frames' peaks_out, or None):
      keys          top-3 [(name, %)], as keys_from_hpcp
      tuning_cents  the audio's tuning against A = 440 (-50..+50, + = sharp), or None when the key
                    is under TUNING_MIN_CONF (atonal / drum-only) or there are no peaks
      chroma        12 floats C..B, 0..1: the profile the key came from (the app's "notes heard")
    Detune-robust: the 440 Hz HPCP grid is 33 cents a bin, so audio 14 or 50 cents off smears over
    two bins and the 10 s windows stop agreeing (J, 2026-11-08: Spotify pitched +7 / +14 / +50 ¢,
    sureness dropped). When the tuning is TUNING_RETUNE_CENTS or more off, the HPCP is rebuilt with
    A at 440 * 2^(c/1200), so the notes sit on their bins again and the key name agrees with the
    tuning's sign (C at +50 ¢ reads C +50, never Db +50). One function for files and live."""
    import numpy as np
    tuning = estimate_tuning(peaks) if peaks else None
    if tuning is not None and abs(tuning) >= TUNING_RETUNE_CENTS and len(peaks) == len(H):
        try:
            H = hpcp_from_peaks(peaks, 440.0 * 2 ** (tuning / 1200))
        except Exception as exc:                   # the 440 Hz reading stands
            _warn(f"retuned key skipped: {exc}")
    keys, pcp = _keys_and_pcp(H)
    top = pcp.max() if len(pcp) else 0.0
    chroma = [round(float(v / top), 3) if top > 0 else 0.0 for v in pcp]
    if keys[0][1] < TUNING_MIN_CONF:
        tuning = None
    return {"keys": keys, "tuning_cents": tuning, "chroma": chroma}


# ---------------------------------------------------------------- decimal BPM and tuning

def refine_bpm(audio_11k, bpm, span=1.5, step=0.01, sr=TEMPOCNN_SR):
    """TempoCNN answers in whole BPM. Look for the tempo within +-span of it that the onset
    envelope's periodicity (first four harmonics) fits best, to 0.01 BPM. Falls back to the whole
    number when the best fit sits on the edge of the search (no clear peak) or there is no audio."""
    import numpy as np
    bpm = float(bpm)
    hop, n_fft = 128, 1024
    if bpm <= 0 or len(audio_11k) < n_fft + 8 * hop:
        return bpm
    x = np.asarray(audio_11k, dtype=np.float32)
    n = 1 + (len(x) - n_fft) // hop
    win = np.hanning(n_fft).astype(np.float32)
    idx = np.arange(n_fft)[None, :] + hop * np.arange(n)[:, None]
    mag = np.abs(np.fft.rfft(x[idx] * win, axis=1))
    logm = np.log1p(100.0 * mag)
    flux = np.maximum(np.diff(logm, axis=0), 0).sum(axis=1)
    env = flux - flux.mean()
    if not np.any(env):
        return bpm
    t = np.arange(len(env)) / (sr / hop)
    cands = bpm + np.arange(-span, span + step / 2, step)
    score = np.zeros(len(cands))
    for c0 in range(0, len(cands), 64):                      # chunked: memory stays small
        f = cands[c0:c0 + 64, None] / 60.0
        for h in (1, 2, 3, 4):
            score[c0:c0 + 64] += np.abs(np.exp(-2j * np.pi * h * f * t[None, :]) @ env)
    best = int(np.argmax(score))
    if best in (0, len(cands) - 1):
        return bpm
    return round(float(cands[best]), 2)


TUNING_MIN_CONF = 50   # key confidence (%) below which a tuning estimate is not offered


def detect_tuning(peaks, conf):
    """Tuning of the track in cents against A = 440 Hz (+ = sharp), folded to the nearest semitone
    grid (-50..+50), from every frame's spectral peaks (estimate_tuning). None when the key
    readout is not confident (atonal / drum-only audio has no tuning to speak of)."""
    if conf < TUNING_MIN_CONF:
        return None
    return estimate_tuning(peaks)


TUNING_MIN_HZ = 200.0   # peaks below this are left out of the tuning estimate


def estimate_tuning(peaks):
    """detect_tuning without the confidence gate: cents against A = 440 (-50..+50) from peaks
    (hpcp_frames' peaks_out), or None when there are none or the math fails (logged).
    Each peak's distance from the 440 Hz semitone grid is a point on a 100-cent circle; the answer
    is their magnitude-weighted circular mean. Peaks under TUNING_MIN_HZ are left out: a 4096-point
    frame's bins are 10.8 Hz wide (90+ cents under 200 Hz), and a loud kick / 808 there pinned
    essentia's TuningFrequency histogram at -21 cents whatever the music's tuning was (measured
    2026-11-08 on 40 GiantSteps tracks pitched 0 / +7 / +14 / +25 / +50 / -30 cents: 82-98 % of
    estimates moved by the true shift +-3 cents, TuningFrequency 32-55 %)."""
    import numpy as np
    if not peaks:
        return None
    try:
        f = np.concatenate([p[0] for p in peaks]).astype(np.float64)
        m = np.concatenate([p[1] for p in peaks]).astype(np.float64)
        keep = (f >= TUNING_MIN_HZ) & (m > 0)
        if not keep.any():
            return None
        dev = 1200 * np.log2(f[keep] / 440.0)
        z = np.sum(m[keep] * np.exp(2j * np.pi * dev / 100))
        if abs(z) == 0:
            return None
        cents = float(np.angle(z) / (2 * np.pi) * 100)     # -50..+50
    except Exception as exc:
        _warn(f"tuning skipped: {exc}")
        return None
    return round(cents, 1)


# ---------------------------------------------------------------- live listening (--stream)

STREAM_CHUNK_SECS = 0.5      # stdin is read, level-checked and HPCP'd in pieces this long
STREAM_MIN_KEY_SECS = 4.0    # a key reading needs this much non-silent audio
STREAM_TEMPO_SECS = 12.0     # TempoCNN's patch is 256 frames at 11025 Hz / hop 512 = 11.9 s


class BoundaryDetector:
    """New song without a pause (J, 2026-11-01: beats back to back with no gap; the level at a
    track change dips no lower than quiet passages inside songs, so level says nothing).
    A boundary needs a DISCONTINUITY, not just change. Every `tick` s it compares the last
    `cur_secs` of audio with the `ref_secs` before them:
      disappeared (0..1): share of the reference's SUSTAINED tonal peaks (per 10.8 Hz bin, 80 Hz -
          4 kHz: its 30th-percentile level stands 6+ dB above the neighbouring bins) that are gone
          now: no longer a peak and not louder (so not merely masked by drums). An intro -> drop
          only ADDS (drums, 808 over strings that keep going): nothing disappears. A new song takes
          the old one's notes and sounds away.
      grid: the reference's pulse (the tempo whose phase is most coherent in the onset envelope)
          either continues ("same") or breaks: "phase" (it slipped by more than `phase_tol` of a
          beat) or "tempo" (the current audio pulses elsewhere). None when either side has no clear
          pulse (a string intro, a breakdown).
      harmonic (0..2): 1 - correlation of the two windows' chroma.
    Candidate = disappeared >= `disappear` AND (the grid broke and harmonic >= `harm_grid`, or
    there is no grid to judge and harmonic >= `harm`). Evidence builds `tick` s per candidate tick
    and drains `leak` times as fast on the others; a boundary is declared at `sustain` s. While it
    builds, the reference is frozen at the moment it began.
    Tuned 2026-11-01 on real back-to-back type beats (7 songs, 12 boundaries: 12 caught, 0 false,
    median 4.4 s late); on the held-out 7 songs it caught 5 of 12 with 1 false (inside a rubato
    piano ballad) and never split an intro -> drop (7 such songs). Precision first: a missed change
    with the same key and tempo costs nothing, a false one throws a good reading away. The player
    title watcher (app) is the sure signal; this is the fallback.
    Pure numpy, ~1 % of one core; nothing is written anywhere."""

    N_FFT, FHOP = 4096, 1024        # 93 ms frames, 23 ms hop at 44.1 kHz
    BPM_LO, BPM_HI, BPM_STEP = 70.0, 180.0, 0.25

    def __init__(self, ref_secs=8.0, cur_secs=3.0, tick=0.5, sustain=3.0, disappear=0.35,
                 harm=0.6, harm_grid=0.3, phase_tol=0.15, grid_min=0.3, leak=2.0):
        import numpy as np
        self.leak = leak
        self.np = np
        self.ref_secs, self.cur_secs, self.tick, self.sustain = ref_secs, cur_secs, tick, sustain
        self.disappear, self.harm, self.harm_grid = disappear, harm, harm_grid
        self.phase_tol, self.grid_min = phase_tol, grid_min
        self.fps = KEY_SR / self.FHOP
        freqs = np.fft.rfftfreq(self.N_FFT, 1.0 / KEY_SR)
        self.flux_bins = freqs <= 8000
        self.spec_bins = (freqs >= 80) & (freqs <= 4000)
        f = freqs[self.spec_bins]
        self.tonal = (f >= 110) & (f <= 3500)                       # chroma range
        self.pc = (np.round(12 * np.log2(f[self.tonal] / 440.0)).astype(int) + 9) % 12   # C = 0
        self.win = np.hanning(self.N_FFT).astype(np.float32)
        self.bpms = np.arange(self.BPM_LO, self.BPM_HI + 1e-9, self.BPM_STEP)
        self._f = self.bpms / 60.0 / self.fps                  # cycles per frame
        self._base = None
        self.reset()

    def reset(self):
        np = self.np
        self.tail = np.zeros(0, np.float32)
        self.spec = []           # per frame: dB spectrum, 80 Hz - 4 kHz
        self.flux = []           # per frame: onset strength
        self.frame_i = 0         # frames since reset (absolute time for the beat phase)
        self.prev = None
        self.since_tick = 0.0
        self.held = 0.0
        self.frozen = None       # the reference while a boundary is being confirmed
        self.last = None         # the last tick's scores

    def _frames(self, x):
        np = self.np
        buf = np.concatenate([self.tail, x])
        n = 0 if len(buf) < self.N_FFT else 1 + (len(buf) - self.N_FFT) // self.FHOP
        if n == 0:
            self.tail = buf
            return
        idx = np.arange(self.N_FFT)[None, :] + self.FHOP * np.arange(n)[:, None]
        mag = np.abs(np.fft.rfft(buf[idx] * self.win, axis=1))
        self.tail = buf[n * self.FHOP:]
        self.spec.extend(20 * np.log10(mag[:, self.spec_bins] + 1e-5))
        logm = np.log1p(100.0 * mag[:, self.flux_bins])
        prev = self.prev if self.prev is not None else logm[0]
        d = np.diff(np.vstack([prev[None, :], logm]), axis=0)
        self.flux.extend(np.maximum(d, 0).sum(axis=1))
        self.prev = logm[-1]
        self.frame_i += n
        keep = int((self.ref_secs + self.cur_secs) * self.fps) + 2
        del self.spec[:-keep]
        del self.flux[:-keep]

    def _phasors(self, o, t0):
        """Coherence (0..1) and complex phasor, per tempo, of the onset envelope o whose first frame
        is frame t0 since the reset (absolute time, so phases of different windows compare)."""
        np = self.np
        if self._base is None or self._base.shape[1] < len(o):
            n = max(int((self.ref_secs + self.cur_secs) * self.fps) + 4, len(o))
            self._base = np.exp(-2j * np.pi * self._f[:, None] * np.arange(n)[None, :])
        z = np.exp(-2j * np.pi * self._f * t0) * (self._base[:, :len(o)] @ (o - o.mean()))
        return np.abs(z) / max(o.sum(), 1e-9), z

    def _chroma(self, m):
        np = self.np
        amp = np.sqrt((10 ** (m[:, self.tonal] / 10)).mean(axis=0))
        return np.bincount(self.pc, weights=amp, minlength=12)

    def _ref_stats(self, P, o, t0):
        """What the reference window holds: its sustained spectrum, chroma and pulse."""
        np = self.np
        ref = np.percentile(P, 30, axis=0)                   # what was there throughout
        prom = ref - np.convolve(ref, np.ones(15) / 15, mode='same')
        c, z = self._phasors(o, t0)
        j = int(np.argmax(c))
        return {"spec": ref, "weight": np.clip(prom - 6, 0, 12) * (ref > ref.max() - 50),
                "chroma": self._chroma(P), "grid": float(c[j]), "j": j, "z": z[j]}

    def scores(self):
        """Scores for the windows buffered now, or None while there is too little history. While a
        boundary is being confirmed the reference stays the one from before it began (frozen), so
        the sustain checks that the old song's parts STAY gone."""
        np = self.np
        ncur = int(self.cur_secs * self.fps)
        nref = int(self.ref_secs * self.fps)
        if len(self.flux) < ncur + int(0.75 * nref):
            return None
        P = np.array(self.spec)
        o = np.array(self.flux)
        o = np.maximum(o - np.convolve(o, np.ones(15) / 15, mode='same'), 0)   # onsets above the local mean
        r = self.frozen or self._ref_stats(P[:-ncur], o[:-ncur], self.frame_i - len(o))
        cur = np.percentile(P[-ncur:], 50, axis=0)
        prom = cur - np.convolve(cur, np.ones(15) / 15, mode='same')
        gone = (prom < 2) & (cur < r["spec"] + 3)            # not a peak any more, and not masked
        disappeared = float((r["weight"] * gone).sum() / max(r["weight"].sum(), 1e-9))
        harmonic = float(1 - np.nan_to_num(np.corrcoef(r["chroma"], self._chroma(P[-ncur:]))[0, 1]))
        c_cur, z_cur = self._phasors(o[-ncur:], self.frame_i - ncur)
        j = r["j"]
        dphase = float(np.angle(z_cur[j] * np.conj(r["z"])) / (2 * np.pi))
        if r["grid"] < self.grid_min or c_cur.max() < self.grid_min:
            grid = None
        elif c_cur[j] < 0.5 * c_cur.max():
            grid = "tempo"
        elif abs(dphase) > self.phase_tol:
            grid = "phase"
        else:
            grid = "same"
        return {"disappeared": round(disappeared, 3), "grid": grid, "harmonic": round(harmonic, 3),
                "bpm_ref": float(self.bpms[j]), "dphase": round(dphase, 3),
                "grid_ref": round(r["grid"], 3), "grid_cur": round(float(c_cur.max()), 3), "_ref": r}

    def candidate(self, s):
        if s is None or s["disappeared"] < self.disappear:
            return False
        if s["grid"] in ("phase", "tempo"):
            return s["harmonic"] >= self.harm_grid
        return s["grid"] is None and s["harmonic"] >= self.harm

    def push(self, x):
        """Feed mono float32 at 44.1 kHz (non-silent audio only). Returns the scores of a boundary
        when one is declared, else None."""
        self._frames(x)
        self.since_tick += len(x) / KEY_SR
        found = None
        while self.since_tick >= self.tick:
            self.since_tick -= self.tick
            s = self.scores()
            if self.candidate(s):
                self.frozen = self.frozen or s["_ref"]
                self.held += self.tick
            else:                                   # leaky: one odd tick doesn't wipe the evidence
                self.held = max(0.0, self.held - self.leak * self.tick)
                if self.held == 0.0:
                    self.frozen = None
            if s is not None:
                s.pop("_ref")
            self.last = s
            if self.held >= self.sustain and found is None:
                found = s
        return found


class LiveAnalyzer:
    """Key + BPM of a live signal (Beat Key's Listen). Mono float32 audio arrives in chunks
    (`push`); nothing is written anywhere. Keeps the last `window` s for TempoCNN and the last
    `key_window` s of HPCP frames for the key, so a reading costs one 12 s TempoCNN pass, never a
    re-read of everything heard. A silence of `gap` s or more is a new song: everything is dropped
    and a "reset" event says so ("start over after a gap"). A new song with NO pause is found by
    BoundaryDetector (or announced by the app, `new_song`, when the player's title changes): the
    same flush, said with a "boundary" event; the key window stays 30 s and rebuilds from scratch.
    Events are dicts, printed as one JSON line each:
      {"event": "reading", "bpm": "128.0" | null, "bpm_exact": 128.02 | null,
       "keys": [["Ebm", 82], ...], "secs": <s of audio behind it>,
       "tuning_cents": -12.0 | null (vs A = 440; null while the key is under 50 %),
       "chroma": [12 floats C..B, 0..1]}   (key_reading: the same readout files get)
      {"event": "reset"}
      {"event": "boundary", "reason": "audio" | "title", "scores": {...} (audio only)}
      {"event": "silence", "db": -61.3}   (the silence rule tripped: `gap` s under `silence_db`;
          db = that chunk's RMS level. Said once per silent run, with the reset if there was one.
          This analyzer is the one judge of silence: the app shows NO SOUND from this event alone.)
      {"event": "sound", "db": -14.2, "after": 4.5}   (the first chunk at or over `silence_db`
          after a "silence"; after = s of silence it ended)"""

    def __init__(self, rate=None, window=STREAM_TEMPO_SECS, hop=2.0, gap=3.0, key_window=30.0,
                 silence_db=-50.0, boundaries=True, keep_after=2.0):
        import numpy as np
        self.np = np
        self.detector = BoundaryDetector() if boundaries else None
        self.keep_after = keep_after             # s of the new song kept after an audio boundary
        self.rate = rate or KEY_SR
        self.window, self.hop, self.gap = max(window, STREAM_TEMPO_SECS), hop, gap
        self.key_window, self.silence_db = key_window, silence_db
        self._resample = None
        if self.rate != KEY_SR:
            import essentia.standard as es
            self._resample = es.Resample(inputSampleRate=self.rate, outputSampleRate=KEY_SR)
        self.silent_run = 0.0                    # s of the current silence; a song flush keeps it
        self.clear()

    def clear(self):
        np = self.np
        self.audio = np.zeros(0, np.float32)     # last `window` s at 44.1 kHz (tempo)
        self.carry = np.zeros(0, np.float32)     # samples not yet framed for HPCP
        self.frames = []                         # HPCP frames, last `key_window` s
        self.peaks = []                          # their spectral peaks (tuning, retuned key)
        self.heard = 0.0                         # s of non-silent audio since the last reset
        self.since_reading = 0.0
        if self.detector is not None:
            self.detector.reset()

    @staticmethod
    def level_db(x):
        import numpy as np
        if len(x) == 0:
            return -120.0
        rms = float(np.sqrt(np.mean(np.square(x, dtype=np.float64))))
        return 20 * float(np.log10(max(rms, 1e-6)))

    def push(self, chunk):
        """Feed mono float32 at `rate`. Returns the events it causes: a reading every `hop` s of
        audio, and one last reading before a reset, so a song's final word is never lost."""
        np = self.np
        x = np.asarray(chunk, dtype=np.float32)
        if self._resample is not None and len(x):
            x = self._resample(x)
        secs = len(x) / KEY_SR
        events = []
        db = self.level_db(x)
        if db < self.silence_db:
            was = self.silent_run
            self.silent_run += secs
            if was < self.gap <= self.silent_run:
                events.append({"event": "silence", "db": round(db, 1)})
            if self.silent_run >= self.gap and self.heard > 0:
                if self.since_reading > 0:
                    r = self.reading()
                    if r:
                        events.append(r)
                self.clear()
                events.append({"event": "reset"})
            return events
        if self.silent_run >= self.gap:
            events.append({"event": "sound", "db": round(db, 1), "after": round(self.silent_run, 1)})
        self.silent_run = 0.0
        found = self.detector.push(x) if self.detector is not None else None
        if found is not None:
            # a new song with no pause: drop the old one, rebuild from the new one's first seconds
            tail = np.concatenate([self.audio, x])[-int(self.keep_after * KEY_SR):]
            self.clear()
            events.append({"event": "boundary", "reason": "audio", "scores": found})
            return events + self._feed(tail)
        return events + self._feed(x)

    def new_song(self, reason="title"):
        """Start over now (the app saw the player's title change): everything heard is dropped."""
        self.clear()
        return [{"event": "boundary", "reason": reason}]

    def _feed(self, x):
        """Non-silent 44.1 kHz audio into the tempo / key buffers; a reading every `hop` s."""
        np = self.np
        secs = len(x) / KEY_SR
        events = []
        self.heard += secs
        self.since_reading += secs
        keep = int(self.window * KEY_SR)
        self.audio = np.concatenate([self.audio, x])[-keep:]
        buf = np.concatenate([self.carry, x])
        n = (len(buf) // FRAME) * FRAME
        if n:
            pk = []
            self.frames.extend(hpcp_frames(buf[:n], pk))
            self.peaks.extend(pk)
            limit = max(1, int(self.key_window * KEY_SR / HOP))
            del self.frames[:-limit]
            del self.peaks[:-limit]
        self.carry = buf[n:]
        if self.since_reading >= self.hop:
            r = self.reading()
            if r:
                events.append(r)
        return events

    def reading(self):
        """The reading for what is buffered now, or None while there is too little to say."""
        np = self.np
        if self.heard < STREAM_MIN_KEY_SECS or not self.frames:
            return None
        self.since_reading = 0.0
        k = key_reading(np.array(self.frames), self.peaks)
        out = {"event": "reading", "bpm": None, "bpm_exact": None,
               "keys": [[name, int(round(p))] for name, p in k["keys"]], "secs": round(self.heard, 1),
               "tuning_cents": k["tuning_cents"], "chroma": k["chroma"]}
        if len(self.audio) >= int(STREAM_TEMPO_SECS * KEY_SR):
            import essentia.standard as es
            a11 = es.Resample(inputSampleRate=KEY_SR, outputSampleRate=TEMPOCNN_SR)(self.audio)
            bpm = detect_bpm_essentia(a11)
            out["bpm"] = str(bpm)
            try:
                out["bpm_exact"] = refine_bpm(a11, bpm)
            except Exception as exc:               # the whole number stands
                _warn(f"decimal BPM skipped: {exc}")
        return out

    def finish(self):
        """End of input: the last reading, if audio came in since the previous one."""
        if self.since_reading > 0:
            r = self.reading()
            return [r] if r else []
        return []


import threading as _threading
_NEW_SONG = _threading.Event()   # set by SIGUSR1 (the app: "new song, start over")


def _listen_for_new_song():
    """SIGUSR1 = new song. Installed first thing in --stream mode (before the slow imports), so a
    signal sent early never hits Python's default action (exit). Main thread only."""
    import signal
    try:
        signal.signal(signal.SIGUSR1, lambda *_: _NEW_SONG.set())
    except (ValueError, AttributeError):        # not the main thread / no SIGUSR1
        pass


def stream_main(argv, inp=None, out=None):
    """`bpm.py --stream [--rate 44100] [--hop 2] [--gap 3] [--window 12] [--key-window 30]
    [--silence-db -50]`: raw little-endian float32 mono PCM on stdin, one JSON event per line on
    stdout ("ready" first). A reader thread drains stdin into a queue so the app's writes never
    block while a reading is computed. When readings fall behind, all queued audio is still fed
    (level and HPCP are cheap) but only the newest reading of the backlog is printed. Ends at EOF."""
    import argparse
    import json
    import queue
    import threading
    import numpy as np
    ap = argparse.ArgumentParser(prog="bpm.py --stream")
    ap.add_argument("--rate", type=int, default=KEY_SR)
    ap.add_argument("--hop", type=float, default=2.0)
    ap.add_argument("--gap", type=float, default=3.0)
    ap.add_argument("--window", type=float, default=STREAM_TEMPO_SECS)
    ap.add_argument("--key-window", type=float, default=30.0)
    ap.add_argument("--silence-db", type=float, default=-50.0)
    a = ap.parse_args(argv)
    inp = inp or sys.stdin.buffer
    out = out or sys.stdout

    def emit(ev):
        out.write(json.dumps(ev) + "\n")
        out.flush()

    if not analyzer_ready():
        emit({"event": "error", "message": ANALYZER_INCOMPLETE})
        return EXIT_INCOMPLETE
    live = LiveAnalyzer(rate=a.rate, window=a.window, hop=a.hop, gap=a.gap,
                        key_window=a.key_window, silence_db=a.silence_db)
    chunk_bytes = max(1, int(a.rate * STREAM_CHUNK_SECS)) * 4
    q = queue.Queue()

    def reader():
        rest = b""
        while True:
            data = inp.read(chunk_bytes)
            if not data:
                break
            data = rest + data
            n = len(data) // 4 * 4
            rest = data[n:]
            if n:
                q.put(np.frombuffer(data[:n], dtype="<f4"))
        q.put(None)

    def push(c):
        if _NEW_SONG.is_set():                     # SIGUSR1: the app saw the player change track
            _NEW_SONG.clear()
            return live.new_song("title") + live.push(c)
        return live.push(c)

    _listen_for_new_song()
    threading.Thread(target=reader, daemon=True).start()
    emit({"event": "ready"})
    done = False
    while not done:
        chunk = q.get()
        if chunk is None:
            break
        evs = push(chunk)
        while not q.empty():                       # behind: drop all but the newest reading
            nxt = q.get()
            if nxt is None:
                done = True
                break
            more = push(nxt)
            if any(e["event"] == "reading" for e in more) and not any(e["event"] == "reset" for e in more):
                evs = [e for e in evs if e["event"] != "reading"]
            evs += more
        for e in evs:
            emit(e)
    for e in live.finish():
        emit(e)
    return 0


# ---------------------------------------------------------------- entry

def _tempocnn_model_present():
    import essentia.standard as es
    return (TEMPOCNN_MODEL if hasattr(es, 'TempoCNN') else TEMPOCNN_WEIGHTS).is_file()


def analyzer_ready():
    """The one bring-up check, for files and live listening alike: essentia imports and the tempo
    model for its back end is on disk. False = a damaged install; callers refuse with
    ANALYZER_INCOMPLETE, there is no other method to fall back to."""
    return _have_essentia() and _tempocnn_model_present()


MIDI_EXTENSIONS = {".mid", ".midi"}


def analyze_full(filepath):
    """-> (bpm rounded to 0.1, top-3 keys, extras). extras: 'bpm_exact' (0.01 BPM), 'chroma' (12
    floats C..B, 0..1, the profile the key came from) and, for audio with a confident key,
    'tuning_cents' (against A = 440, -50..+50). The first two are what the command line and the
    file names use; extras are for the app's readout (key_reading: the same readout live gets)."""
    if Path(filepath).suffix.lower() in MIDI_EXTENSIONS:
        import midi_analyze
        return midi_analyze.analyze_midi(filepath)
    extras = {}
    a_key, a_bpm = load_audio_essentia(filepath)
    peaks = []
    k = key_reading(hpcp_frames(a_key, peaks), peaks)
    keys = k["keys"]
    if k["tuning_cents"] is not None:
        extras["tuning_cents"] = k["tuning_cents"]
    extras["chroma"] = k["chroma"]
    bpm = detect_bpm_essentia(a_bpm)
    try:
        extras["bpm_exact"] = refine_bpm(a_bpm, bpm)
    except Exception as exc:               # the whole number stands
        _warn(f"decimal BPM skipped: {exc}")
    return bpm, keys, extras


def analyze(filepath):
    bpm, keys, _extras = analyze_full(filepath)
    return bpm, keys


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--stream":
        _listen_for_new_song()
    if not check_deps():
        sys.exit(1)

    if len(sys.argv) > 1 and sys.argv[1] == "--stream":
        sys.exit(stream_main(sys.argv[2:]))

    if not analyzer_ready():
        print(ANALYZER_INCOMPLETE, file=sys.stderr)
        sys.exit(EXIT_INCOMPLETE)

    if len(sys.argv) > 1:
        path = Path(sys.argv[1])
    else:
        try:
            raw = input("Audio file path: ").strip().strip("'\"")
        except (EOFError, KeyboardInterrupt):
            print()
            sys.exit(0)
        path = Path(raw)

    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        sys.exit(1)

    bpm, keys, extras = analyze_full(path)

    # Output for bash parsing: BPM on line 1, then each key on its own line; the app's extras
    # ("bpm_exact: 140.82", "tuning_cents: -12.0", "chroma: [1.0, 0.0, ...]") follow, so lines
    # 1-4 stay the contract
    print(bpm)
    for key, confidence in keys:
        print(f"{key} ({confidence}%)")
    for name, value in extras.items():
        if isinstance(value, list):                # chroma: one JSON list on its line
            value = "[" + ", ".join(str(v) for v in value) + "]"
        print(f"{name}: {value}")


if __name__ == "__main__":
    main()
