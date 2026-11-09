"""Detuned audio (orra-parity §1): Spotify pitched +7 / +14 / +50 cents live must show its tuning and
keep the key as sure as at 0 cents, files and live alike (bpm.key_reading). Run with the bundled
Python: bin/python/bin/python3 -m unittest discover -s tests"""
import contextlib
import io
import json
import sys
import tempfile
import unittest
import wave
from pathlib import Path
from unittest import mock

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import bpm  # noqa: E402

try:
    import essentia.standard  # noqa: F401
    HAVE_ESSENTIA = True
except ImportError:
    HAVE_ESSENTIA = False

SR = 44100
DETUNES = (0, 7, 14, 50, -30)
# MIDI notes per chord, 2 s each. C major: I-vi-IV-V. A minor: i-iv-V-i (G# makes it minor, not C).
PROGRESSIONS = {
    "C": ([[48, 60, 64, 67], [45, 57, 60, 64], [41, 57, 60, 65], [43, 59, 62, 67]], 0, "major"),
    "Am": ([[45, 57, 60, 64], [50, 57, 62, 65], [52, 56, 59, 64], [45, 57, 60, 64]], 9, "minor"),
}
SCALES = {"major": (0, 2, 4, 5, 7, 9, 11), "minor": (0, 2, 3, 5, 7, 8, 11)}
NAMES = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']
MINOR_NAMES = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B']


def progression(name, cents, secs=32, sr=SR):
    """Plucked chords (4 harmonics, a little noise), every pitch `cents` away from A = 440."""
    chords = PROGRESSIONS[name][0]
    t = np.arange(int(sr * 2)) / sr
    env = np.minimum(1, t * 20) * np.exp(-t * 0.6)
    out = []
    for i in range(int(secs / 2)):
        y = np.zeros_like(t)
        for n in chords[i % len(chords)]:
            f = 440 * 2 ** ((n - 69) / 12 + cents / 1200)
            for h in (1, 2, 3, 4):
                y += np.sin(2 * np.pi * f * h * t) * (0.25 / h)
        out.append(y * env)
    y = np.concatenate(out)
    y = y + 0.03 * np.abs(y).max() * np.random.default_rng(7).standard_normal(len(y))
    return (y / np.abs(y).max() * 0.5).astype(np.float32)


def write_wav(path, y, sr=SR):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())


def cents_off(measured, true):
    """Distance on the 100-cent tuning circle (+50 and -50 are the same tuning)."""
    return abs((measured - true + 50) % 100 - 50)


def expected_key(name, cents, measured):
    """The key the readout must name: the progression's own, moved a semitone when the tuning came
    out on the other side of the circle (C at +50 = Db at -50: both right, but key and tuning agree)."""
    _chords, tonic, mode = PROGRESSIONS[name]
    pc = (tonic + int(round((cents - measured) / 100))) % 12
    return MINOR_NAMES[pc] + "m" if mode == "minor" else NAMES[pc]


def file_reading(name, cents):
    """The file path: a WAV decoded the way files are, then analyze_full's key readout."""
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "prog.wav"
        write_wav(p, progression(name, cents))
        a_key, _ = bpm.load_audio_essentia(p)
    peaks = []
    k = bpm.key_reading(bpm.hpcp_frames(a_key, peaks), peaks)
    return {"keys": [[n, c] for n, c in k["keys"]], "tuning_cents": k["tuning_cents"], "chroma": k["chroma"]}


def stream_reading(name, cents):
    """The live path: half-second chunks into LiveAnalyzer, its last reading."""
    live = bpm.LiveAnalyzer(hop=1000.0, boundaries=False)
    y = progression(name, cents)
    n = SR // 2
    evs = []
    for i in range(0, len(y), n):
        evs += live.push(y[i:i + n])
    evs += live.finish()
    return [e for e in evs if e["event"] == "reading"][-1]


@unittest.skipUnless(HAVE_ESSENTIA, "needs the bundled Python (essentia)")
class TestDetunedKey(unittest.TestCase):
    """Tuning within 3 cents and key confidence within 10 points of the 0-cent reading, both paths."""

    readings = {}

    @classmethod
    def setUpClass(cls):
        for name in PROGRESSIONS:
            for c in DETUNES:
                cls.readings[("file", name, c)] = file_reading(name, c)
                cls.readings[("stream", name, c)] = stream_reading(name, c)

    def check(self, path):
        for name in PROGRESSIONS:
            base = self.readings[(path, name, 0)]
            for c in DETUNES:
                r = self.readings[(path, name, c)]
                msg = f"{path} {name} {c:+d} cents: {r['keys']} tuning {r['tuning_cents']}"
                self.assertIsNotNone(r["tuning_cents"], msg)
                self.assertLessEqual(cents_off(r["tuning_cents"], c), 3, msg)
                self.assertEqual(r["keys"][0][0], expected_key(name, c, r["tuning_cents"]), msg)
                self.assertLessEqual(abs(r["keys"][0][1] - base["keys"][0][1]), 10, msg)

    def test_files(self):
        self.check("file")

    def test_live(self):
        self.check("stream")

    def test_live_reading_carries_tuning_and_chroma(self):
        r = self.readings[("stream", "Am", 14)]
        json.dumps(r)                                       # one JSON line, as stream_main prints it
        self.assertIsInstance(r["tuning_cents"], float)
        self.assertEqual(len(r["chroma"]), 12)

    def test_chroma_is_the_scale(self):
        for path in ("file", "stream"):
            for name, (_ch, tonic, mode) in PROGRESSIONS.items():
                ch = np.array(self.readings[(path, name, 14)]["chroma"])
                self.assertEqual(len(ch), 12)
                self.assertTrue(np.all((ch >= 0) & (ch <= 1)))
                self.assertAlmostEqual(float(ch.max()), 1.0, places=3)
                inside = [(tonic + s) % 12 for s in SCALES[mode]]
                outside = [i for i in range(12) if i not in inside]
                self.assertLess(ch[outside].max(), ch[inside].max(), f"{path} {name}")
                self.assertEqual(int(np.argmax(ch)) in inside, True, f"{path} {name}")


@unittest.skipUnless(HAVE_ESSENTIA, "needs the bundled Python (essentia)")
class TestKeyReading(unittest.TestCase):
    def test_sub_bass_does_not_pin_the_tuning(self):
        # a loud 43 Hz kick (-21 cents off the grid) under music 14 cents sharp: the music wins
        music = [(np.array([440 * 2 ** (14 / 1200) * 2 ** (s / 12) for s in (-9, -5, -2, 0, 3)], np.float32),
                  np.full(5, 0.2, np.float32)) for _ in range(50)]
        kick = [(np.array([43.0], np.float32), np.array([50.0], np.float32)) for _ in range(50)]
        peaks = [(np.concatenate([a[0], b[0]]), np.concatenate([a[1], b[1]])) for a, b in zip(music, kick)]
        self.assertAlmostEqual(bpm.estimate_tuning(peaks), 14, delta=0.5)

    def test_no_peaks_no_tuning(self):
        self.assertIsNone(bpm.estimate_tuning([]))
        self.assertIsNone(bpm.estimate_tuning([(np.array([60.0], np.float32), np.array([1.0], np.float32))]))

    def test_empty_frames(self):
        r = bpm.key_reading(np.zeros((0, 36)), [])
        self.assertEqual(r["keys"], bpm.NO_KEYS)
        self.assertIsNone(r["tuning_cents"])
        self.assertEqual(r["chroma"], [0.0] * 12)

    def test_retune_failure_is_logged_and_the_440_reading_stands(self):
        y = progression("Am", 30, secs=12)
        peaks = []
        H = bpm.hpcp_frames(y, peaks)
        err = io.StringIO()
        with mock.patch.object(bpm, "hpcp_from_peaks", side_effect=RuntimeError("boom")), \
                contextlib.redirect_stderr(err):
            r = bpm.key_reading(H, peaks)
        self.assertIn("retuned key skipped: boom", err.getvalue())
        self.assertEqual(r["keys"], bpm.keys_from_hpcp(H))

    def test_rebuilt_hpcp_at_440_is_the_original(self):
        y = progression("C", 0, secs=6)
        peaks = []
        H = bpm.hpcp_frames(y, peaks)
        self.assertTrue(np.allclose(H, bpm.hpcp_from_peaks(peaks, 440.0)))

    def test_in_tune_audio_is_not_rebuilt(self):
        y = progression("C", 0, secs=12)
        peaks = []
        H = bpm.hpcp_frames(y, peaks)
        with mock.patch.object(bpm, "hpcp_from_peaks", side_effect=AssertionError("rebuilt")):
            r = bpm.key_reading(H, peaks)
        self.assertEqual(r["keys"][0][0], "C")


if __name__ == "__main__":
    unittest.main()
