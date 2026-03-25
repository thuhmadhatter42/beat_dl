#!/usr/bin/env python3
"""
BPM + Key detector.
Focuses on the loudest 60s of the track for accuracy.
Usage: python3 bpm.py <filepath>
       python3 bpm.py          (prompts for a path)
"""

import sys
from pathlib import Path


def check_deps():
    try:
        import librosa  # noqa
        import numpy    # noqa
        return True
    except ImportError:
        print("Missing: librosa — install with:  pip3 install librosa --break-system-packages")
        return False


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


def detect_bpm(section, sr):
    import librosa
    tempo, _ = librosa.beat.beat_track(y=section, sr=sr)
    try:
        bpm = float(tempo[0]) if hasattr(tempo, '__len__') else float(tempo)
    except Exception:
        bpm = float(tempo)
    return round(bpm, 1)


def detect_keys(section, sr):
    """
    Return top 3 keys with confidence using Krumhansl-Schmuckler profiles.
    Each entry is (key_name, confidence_pct).
    """
    import librosa
    import numpy as np

    NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']

    # Krumhansl-Schmuckler key profiles
    MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
    MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])

    # Compute mean chroma vector from the section
    chroma = librosa.feature.chroma_cqt(y=section, sr=sr)
    mean_chroma = chroma.mean(axis=1)

    # Correlate chroma against all 24 key profiles
    scores = {}
    for i, note in enumerate(NOTE_NAMES):
        major_profile = np.roll(MAJOR, i)
        minor_profile = np.roll(MINOR, i)
        scores[f"{note} Major"] = float(np.corrcoef(mean_chroma, major_profile)[0, 1])
        scores[f"{note} Minor"] = float(np.corrcoef(mean_chroma, minor_profile)[0, 1])

    # Rank and convert to percentage confidence
    ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)
    top3_raw = ranked[:3]

    # Normalize top scores to sum to 100% for display
    total = sum(s for _, s in top3_raw)

    # Format: "C Minor" → "Cm", "D# Major" → "D#"
    def fmt_key(name):
        if "Minor" in name:
            return name.replace(" Minor", "m")
        else:
            return name.replace(" Major", "")

    top3 = [(fmt_key(key), round((s / total) * 100, 1)) for key, s in top3_raw]

    return top3


def analyze(filepath):
    import librosa
    y, sr = librosa.load(str(filepath), mono=True)
    section = get_loud_section(y, sr)
    bpm = detect_bpm(section, sr)
    keys = detect_keys(section, sr)
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

    bpm, keys = analyze(path)

    # Output for bash parsing: BPM on line 1, then each key on its own line
    print(bpm)
    for key, confidence in keys:
        print(f"{key} ({confidence}%)")


if __name__ == "__main__":
    main()
