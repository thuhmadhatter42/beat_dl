#!/usr/bin/env python3
"""
BPM + Key detector.
BPM: Essentia TempoCNN (models/deeptemp-k16-3.pb) on the whole track. Two back ends, same numbers:
     - essentia-tensorflow: essentia.standard.TempoCNN + AudioLoader (today's path)
     - legacy essentia (no TensorFlow, no ffmpeg; old Macs): tempocnn_np.py (numpy port, weights in
       models/deeptemp-k16-3.npz) and decoding through the bundled ffmpeg CLI, set up to give the
       same samples AudioLoader gives (fixed-point mp3 decoder -> s16 -> /32768).
Key: Essentia HPCP (36 bins, spectral whitening, detuning correction) on the whole track,
     correlated against Faraldo's 'bgate' EDM profiles for all 24 keys -> real top-3 with a
     confidence from segment agreement + margin (docs/research/key-detection-research.md).
Fallback without essentia-tensorflow: librosa (tempo on the loudest 60 s; HPSS + CENS
chroma + edma profiles for key). Warnings go to stderr only; stdout is the 4-line contract.
Also reads MIDI files (midi_analyze.py). After the 4 lines it prints "bpm_exact: <0.01 BPM>" and,
when the key is confident, "tuning_cents: <cents vs A=440>".
Usage: python3 bpm.py <filepath>
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
EDMA = ([1.00, 0.29, 0.50, 0.40, 0.60, 0.56, 0.32, 0.80, 0.31, 0.45, 0.42, 0.39],
        [1.00, 0.31, 0.44, 0.58, 0.33, 0.49, 0.29, 0.78, 0.43, 0.29, 0.53, 0.32])

# essentia KeyExtractor front-end defaults (keyextractor.cpp)
KEY_SR, FRAME, HOP, HPCP_SIZE, PCP_THRESHOLD = 44100, 4096, 4096, 36, 0.2
TEMPOCNN_SR = 11025
SEGMENT_SECS = 10


def _warn(msg):
    print(f"Warning: {msg}", file=sys.stderr)


def check_deps():
    try:
        import numpy  # noqa
    except ImportError:
        print("Missing: numpy — install with:  pip3 install numpy --break-system-packages", file=sys.stderr)
        return False
    try:
        import essentia  # noqa
        return True
    except ImportError:
        pass
    try:
        import librosa  # noqa
        return True
    except ImportError:
        print("Missing: essentia-tensorflow (or librosa as fallback) — install with:  "
              "pip3 install essentia-tensorflow --break-system-packages --prefer-binary", file=sys.stderr)
        return False


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
    vs 30% for librosa beat_track (docs/research/bpm-detection-research.md).
    """
    import essentia.standard as es
    if hasattr(es, 'TempoCNN'):
        global_bpm, _local_bpm, _local_prob = es.TempoCNN(graphFilename=str(TEMPOCNN_MODEL))(audio_11k)
    else:                                   # legacy essentia: same network in numpy
        import tempocnn_np
        global_bpm, _local_bpm, _local_prob = tempocnn_np.tempo(audio_11k)
    return round(float(global_bpm), 1)


def hpcp_frames(audio_44k, peaks_out=None):
    """essentia KeyExtractor front end, frame by frame: hann -> spectrum -> peaks -> spectral
    whitening -> 36-bin HPCP (bass kept: minFrequency 25 Hz). Returns (n_frames, 36).
    peaks_out (a list) receives each frame's (frequencies, magnitudes) for the tuning estimate."""
    import numpy as np
    import essentia.standard as es
    win = es.Windowing(type='hann', size=FRAME)
    spec = es.Spectrum(size=FRAME)
    peaks = es.SpectralPeaks(orderBy='magnitude', magnitudeThreshold=1e-4, minFrequency=25,
                             maxFrequency=3500, maxPeaks=60, sampleRate=KEY_SR)
    white = es.SpectralWhitening(maxFrequency=3500, sampleRate=KEY_SR)
    hpcp = es.HPCP(bandPreset=False, harmonics=4, minFrequency=25, maxFrequency=3500,
                   nonLinear=False, normalized='none', referenceFrequency=440, sampleRate=KEY_SR,
                   size=HPCP_SIZE, weightType='cosine', windowSize=1.0, maxShifted=False)
    out = []
    for fr in es.FrameGenerator(audio_44k, frameSize=FRAME, hopSize=HOP, startFromZero=True):
        s = spec(win(fr))
        f, m = peaks(s)
        if peaks_out is not None:
            peaks_out.append((f, m))
        m = white(s, f, m)
        out.append(hpcp(f, m))
    return np.array(out)


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
    import numpy as np
    H = hpcp_frames(audio_44k, peaks_out)
    if len(H) == 0 or H.max() == 0:
        return [('C', 0.0), ('Am', 0.0), ('G', 0.0)]
    scores = key_scores(hpcp_to_pcp12(H.mean(axis=0)), BGATE)
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
    return top3_with_confidence(scores, agree)


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
    grid (-50..+50), from essentia's TuningFrequency over every frame's spectral peaks. None when
    the key readout is not confident (atonal / drum-only audio has no tuning to speak of)."""
    import numpy as np
    import essentia.standard as es
    if conf < TUNING_MIN_CONF or not peaks:
        return None
    f = np.concatenate([p[0] for p in peaks]).astype(np.float32)
    m = np.concatenate([p[1] for p in peaks]).astype(np.float32)
    if len(f) == 0:
        return None
    _hz, cents = es.TuningFrequency()(f, m)       # essentia reports -35..+65
    cents = float(cents)
    return round(cents - 100 if cents > 50 else cents, 1)


# ---------------------------------------------------------------- librosa fallback

def get_loud_section(y, sr):
    """Return 60s of audio starting at the loudest 10s chunk."""
    import numpy as np
    chunk_size = sr * 10
    chunks = [y[i:i + chunk_size] for i in range(0, len(y), chunk_size)]
    rms_scores = [np.sqrt(np.mean(chunk ** 2)) for chunk in chunks]
    loudest_idx = int(np.argmax(rms_scores))
    start = loudest_idx * chunk_size
    end = min(start + sr * 60, len(y))
    return y[start:end]


def detect_bpm_librosa(section, sr):
    """Fallback: librosa tempo on the loudest 60 s (the pre-TempoCNN method).
    librosa.feature.tempo is the same estimate beat_track returns as its first value; beat_track
    itself segfaults on py3.14 + numba 0.67 (numba.guvectorize in librosa/beat.py), so avoid it."""
    import librosa
    tempo = librosa.feature.tempo(y=section, sr=sr)
    try:
        bpm = float(tempo[0]) if hasattr(tempo, '__len__') else float(tempo)
    except Exception:
        bpm = float(tempo)
    return round(bpm, 1)


def detect_keys_librosa(y, sr):
    """Fallback: HPSS harmonic -> chroma_cens (tuning-corrected) -> edma profiles, whole track.
    81.0 weighted / 76.9 % exact on the benchmark (~3 s per 2-min clip). Confidence = softmax."""
    import librosa
    yh = librosa.effects.harmonic(y, margin=4.0)
    tun = librosa.estimate_tuning(y=yh, sr=sr)
    C = librosa.feature.chroma_cens(y=yh, sr=sr, tuning=tun)
    ranked = sorted(key_scores(C.mean(axis=1), EDMA).items(), key=lambda kv: -kv[1])
    p = softmax_probs(ranked)
    return [(fmt_key(*ranked[i][0]), round(100 * float(p[i]), 1)) for i in range(3)]


# ---------------------------------------------------------------- entry

def _tempocnn_model_present():
    import essentia.standard as es
    return (TEMPOCNN_MODEL if hasattr(es, 'TempoCNN') else TEMPOCNN_WEIGHTS).is_file()


MIDI_EXTENSIONS = {".mid", ".midi"}


def analyze_full(filepath):
    """-> (bpm rounded to 0.1, top-3 keys, extras). extras: 'bpm_exact' (0.01 BPM) and, for audio
    with a confident key, 'tuning_cents' (against A = 440, -50..+50). The first two are what the
    command line and the file names use; extras are for the app's readout."""
    if Path(filepath).suffix.lower() in MIDI_EXTENSIONS:
        import midi_analyze
        return midi_analyze.analyze_midi(filepath)
    extras = {}
    if _have_essentia():
        a_key, a_bpm = load_audio_essentia(filepath)
        peaks = []
        keys = detect_keys_essentia(a_key, peaks)
        tuning = detect_tuning(peaks, keys[0][1])
        if tuning is not None:
            extras["tuning_cents"] = tuning
        if _tempocnn_model_present():
            bpm = detect_bpm_essentia(a_bpm)
            try:
                extras["bpm_exact"] = refine_bpm(a_bpm, bpm)
            except Exception as exc:               # the whole number stands
                _warn(f"decimal BPM skipped: {exc}")
            return bpm, keys, extras
        _warn("TempoCNN model missing in models/; BPM via librosa fallback")
        import librosa
        y, sr = librosa.load(str(filepath), mono=True)
        return detect_bpm_librosa(get_loud_section(y, sr), sr), keys, extras
    _warn("essentia-tensorflow not installed; BPM + key via librosa fallback (less accurate) — "
          "pip3 install essentia-tensorflow --break-system-packages --prefer-binary")
    import librosa
    y, sr = librosa.load(str(filepath), mono=True)
    bpm = detect_bpm_librosa(get_loud_section(y, sr), sr)
    return bpm, detect_keys_librosa(y, sr), extras


def analyze(filepath):
    bpm, keys, _extras = analyze_full(filepath)
    return bpm, keys


def main():
    if not check_deps():
        sys.exit(1)

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
    # ("bpm_exact: 140.82", "tuning_cents: -12.0") follow, so lines 1-4 stay the contract
    print(bpm)
    for key, confidence in keys:
        print(f"{key} ({confidence}%)")
    for name, value in extras.items():
        print(f"{name}: {value}")


if __name__ == "__main__":
    main()
