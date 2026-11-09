"""Decimal BPM, tuning, MIDI files and the extra input formats. Run with the bundled Python:
bin/python/bin/python3 -m unittest discover -s tests"""
import json
import struct
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import app_run  # noqa: E402
import bpm  # noqa: E402
import midi_analyze  # noqa: E402

try:
    import essentia.standard  # noqa: F401
    HAVE_ESSENTIA = True
except ImportError:
    HAVE_ESSENTIA = False


# ---------------------------------------------------------------- a tiny SMF writer

def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(reversed(out))


def smf(events, tpq=480, extra_tracks=()):
    """events: [(delta_ticks, raw_bytes)] for one track. Returns the file bytes."""
    body = b"".join(vlq(d) + e for d, e in events) + vlq(0) + b"\xFF\x2F\x00"
    tracks = [body] + list(extra_tracks)
    out = b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), tpq)
    for t in tracks:
        out += b"MTrk" + struct.pack(">I", len(t)) + t
    return out


def tempo_event(us):
    return b"\xFF\x51\x03" + us.to_bytes(3, "big")


def notes(pitches, length=480, ch=0):
    ev = []
    for p in pitches:
        ev.append((0, bytes([0x90 | ch, p, 90])))
        ev.append((length, bytes([0x80 | ch, p, 0])))
    return ev


C_MAJOR_SCALE = [60, 62, 64, 65, 67, 69, 71, 72]
# a tune that dwells on the tonic and fifth: C E G C G E, repeated
C_MAJOR_TUNE = [60, 64, 67, 72, 67, 64, 60, 60, 67, 67, 62, 65, 60] * 4


class TestMidi(unittest.TestCase):
    def analyze(self, data):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "t.mid"
            p.write_bytes(data)
            return midi_analyze.analyze_midi(p)

    def test_tempo_from_set_tempo_event(self):
        # 428,000 us per quarter = 140.19 BPM
        data = smf([(0, tempo_event(428000))] + notes(C_MAJOR_TUNE))
        bpm_r, keys, extras = self.analyze(data)
        self.assertEqual(bpm_r, 140.2)
        self.assertEqual(extras["bpm_exact"], 140.19)

    def test_default_tempo_is_120(self):
        bpm_r, _keys, extras = self.analyze(smf(notes(C_MAJOR_TUNE)))
        self.assertEqual((bpm_r, extras["bpm_exact"]), (120.0, 120.0))

    def test_tempo_in_force_longest_wins(self):
        # 100 BPM for the first 10 quarters, then 90 BPM for the rest of a long piece
        ev = [(0, tempo_event(600000)), (480 * 10, tempo_event(666667))] + notes(C_MAJOR_TUNE)
        bpm_r, _k, extras = self.analyze(smf(ev))
        self.assertEqual(round(extras["bpm_exact"]), 90)

    def test_key_from_note_durations(self):
        _b, keys, _e = self.analyze(smf(notes(C_MAJOR_TUNE)))
        self.assertEqual(len(keys), 3)
        self.assertEqual(keys[0][0], "C")

    def test_key_signature_is_ignored(self):
        # key signature says A major (3 sharps); the notes say C major
        sig = b"\xFF\x59\x02\x03\x00"
        _b, keys, _e = self.analyze(smf([(0, sig)] + notes(C_MAJOR_TUNE)))
        self.assertEqual(keys[0][0], "C")

    def test_minor_key(self):
        a_minor = [69, 72, 76, 81, 76, 72, 69, 69, 76, 76, 71, 74, 69] * 4
        _b, keys, _e = self.analyze(smf(notes(a_minor)))
        self.assertEqual(keys[0][0], "Am")

    def test_drum_channel_ignored(self):
        # C major tune on channel 1, loud chromatic junk on the drum channel (10)
        drums = notes([61, 63, 66, 68, 70] * 20, length=960, ch=9)
        track2 = b"".join(vlq(d) + e for d, e in drums) + vlq(0) + b"\xFF\x2F\x00"
        _b, keys, _e = self.analyze(smf(notes(C_MAJOR_TUNE), extra_tracks=[track2]))
        self.assertEqual(keys[0][0], "C")

    def test_running_status_and_note_on_velocity_zero(self):
        # note-on, then note-on vel 0 as the note-off, with running status (no repeated 0x90)
        ev = []
        for p in C_MAJOR_TUNE:
            ev.append((0, bytes([0x90, p, 90])))
            ev.append((480, bytes([p, 0])))        # running status: note on, velocity 0
        _b, keys, _e = self.analyze(smf(ev))
        self.assertEqual(keys[0][0], "C")

    def test_too_few_notes_gives_zero_confidence(self):
        _b, keys, _e = self.analyze(smf(notes([60, 64])))
        self.assertEqual(keys[0][1], 0.0)

    def test_not_a_midi_file(self):
        with self.assertRaises(midi_analyze.MidiError):
            midi_analyze.parse(b"RIFF....")

    def test_truncated_track_does_not_raise(self):
        data = smf(notes(C_MAJOR_TUNE))
        midi_analyze.parse(data[:-9])

    def test_cli_prints_contract_and_extras(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "t.mid"
            p.write_bytes(smf([(0, tempo_event(428000))] + notes(C_MAJOR_TUNE)))
            out = subprocess.run([sys.executable, str(ROOT / "bpm.py"), str(p)],
                                 capture_output=True, text=True, timeout=60).stdout.splitlines()
        self.assertEqual(out[0], "140.2")
        self.assertTrue(out[1].startswith("C ("))
        self.assertIn("bpm_exact: 140.19", out)

    def test_app_run_analyze_midi(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "t.mid"
            p.write_bytes(smf([(0, tempo_event(428000))] + notes(C_MAJOR_TUNE)))
            extras = {}
            b, keys = app_run.analyze_file(p, extras=extras)
        self.assertEqual(b, "140.2")
        self.assertEqual(keys[0][0], "C")
        self.assertEqual(extras, {"bpm_exact": 140.19})


# ---------------------------------------------------------------- decimal BPM + tuning

def click_track(bpm_value, seconds=40, sr=11025):
    """Kick-like thumps on the beat and a hat on the off-beat, at an exact tempo."""
    n = int(sr * seconds)
    y = np.zeros(n, np.float32)
    k = np.arange(int(0.12 * sr)) / sr
    kick = (np.sin(2 * np.pi * (50 + 80 * np.exp(-k * 40)) * k) * np.exp(-k * 18)).astype(np.float32)
    spb = 60.0 / bpm_value
    i = 0
    while i * spb < seconds - 0.2:
        s = int(round(i * spb * sr))
        seg = kick[:n - s]
        y[s:s + len(seg)] += seg
        i += 1
    return y


class TestDecimalBpm(unittest.TestCase):
    def test_refines_whole_bpm_to_hundredths(self):
        for true in (140.82, 128.37, 93.55):
            got = bpm.refine_bpm(click_track(true), round(true))
            self.assertAlmostEqual(got, true, delta=0.08, msg=f"true {true}")

    def test_whole_bpm_stays_whole(self):
        self.assertAlmostEqual(bpm.refine_bpm(click_track(120.0), 120), 120.0, delta=0.05)

    def test_silence_returns_the_input(self):
        self.assertEqual(bpm.refine_bpm(np.zeros(11025 * 20, np.float32), 100), 100.0)

    def test_too_short_or_zero_bpm(self):
        self.assertEqual(bpm.refine_bpm(np.zeros(100, np.float32), 100), 100.0)
        self.assertEqual(bpm.refine_bpm(click_track(120.0), 0), 0.0)

    def test_search_stays_within_a_bpm_and_a_half(self):
        # the network said 100 but the audio is 120: no pretending, stays near 100 or falls back
        got = bpm.refine_bpm(click_track(120.0), 100)
        self.assertLessEqual(abs(got - 100), 1.5)


def chord_wav(path, cents, seconds=20, sr=44100):
    """A slow C-E-G-A arpeggio with overtones, every pitch `cents` away from A = 440."""
    t = np.arange(int(sr * seconds)) / sr
    f0 = 440 * 2 ** (cents / 1200)
    y = np.zeros_like(t)
    for i, semis in enumerate([-9, -5, -2, 0, -2, -5]):
        on = ((t * 0.8).astype(int) % 6) == i
        f = f0 * 2 ** (semis / 12)
        for h in (1, 2, 3):
            y += np.sin(2 * np.pi * f * h * t) * (0.2 / h) * (0.4 + 0.6 * on)
    y = y / np.abs(y).max() * 0.5
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((y * 32767).astype("<i2").tobytes())


@unittest.skipUnless(HAVE_ESSENTIA, "needs the bundled Python (essentia)")
class TestTuning(unittest.TestCase):
    def measure(self, cents):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "c.wav"
            chord_wav(p, cents)
            a_key, _ = bpm.load_audio_essentia(p)
            peaks = []
            keys = bpm.detect_keys_essentia(a_key, peaks)
            return bpm.detect_tuning(peaks, 90), keys

    def test_in_tune(self):
        c, _k = self.measure(0)
        self.assertLessEqual(abs(c), 4)

    def test_flat_and_sharp(self):
        for true in (-32, -18, 20, 40):
            c, _k = self.measure(true)
            self.assertAlmostEqual(c, true, delta=5, msg=f"true {true}")

    def test_wraps_to_the_nearest_semitone_grid(self):
        c, _k = self.measure(-44)
        self.assertLess(c, 0)
        self.assertAlmostEqual(c, -44, delta=6)

    def test_low_confidence_gives_none(self):
        self.assertIsNone(bpm.detect_tuning([(np.array([440.0], np.float32), np.array([1.0], np.float32))], 49))
        self.assertIsNone(bpm.detect_tuning([], 90))

    def test_hpcp_frames_unchanged_by_peak_capture(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "c.wav"
            chord_wav(p, 0, seconds=6)
            a_key, _ = bpm.load_audio_essentia(p)
            plain = bpm.hpcp_frames(a_key)
            out = []
            self.assertTrue(np.array_equal(plain, bpm.hpcp_frames(a_key, out)))
            self.assertEqual(len(out), len(plain))


# ---------------------------------------------------------------- the app_run contract

class TestExtrasLines(unittest.TestCase):
    def run_with_stdout(self, stdout):
        class P:
            returncode = 0

        P.stdout = stdout
        from unittest import mock
        with mock.patch.object(app_run.subprocess, "run", return_value=P):
            extras = {}
            r = app_run.analyze_file("x.wav", extras=extras)
        return r, extras

    def test_extras_parsed(self):
        out = "140.0\nCm (80.0%)\nEb (10.0%)\nGm (5.0%)\nbpm_exact: 140.82\ntuning_cents: -12.0\n"
        (b, keys), extras = self.run_with_stdout(out)
        self.assertEqual(b, "140.0")
        self.assertEqual(len(keys), 3)
        self.assertEqual(extras, {"bpm_exact": 140.82, "tuning_cents": -12.0})

    def test_old_output_still_parses(self):
        (b, keys), extras = self.run_with_stdout("140.0\nCm (80.0%)\nEb (10.0%)\nGm (5.0%)\n")
        self.assertEqual((b, len(keys), extras), ("140.0", 3, {}))

    def test_junk_extras_ignored(self):
        _r, extras = self.run_with_stdout("1.0\nCm (80%)\nA (1%)\nB (1%)\nbpm_exact: abc\nwhat: 3\n")
        self.assertEqual(extras, {})

    def test_chroma_parsed(self):
        ch = [1.0, 0.0, 0.5, 0.25, 0.0, 0.7, 0.0, 0.9, 0.0, 0.6, 0.0, 0.3]
        out = "140.0\nC (80.0%)\nAm (10.0%)\nG (5.0%)\nchroma: [" + ", ".join(map(str, ch)) + "]\n"
        _r, extras = self.run_with_stdout(out)
        self.assertEqual(extras, {"chroma": ch})

    def test_junk_chroma_ignored(self):
        for bad in ("chroma: [1, 2]", "chroma: nope", "chroma: [\"a\"" + ", 0" * 11 + "]"):
            _r, extras = self.run_with_stdout("1.0\nCm (80%)\nA (1%)\nB (1%)\n" + bad + "\n")
            self.assertEqual(extras, {}, bad)

    @unittest.skipUnless(HAVE_ESSENTIA, "needs the bundled Python (essentia)")
    def test_bpm_py_prints_chroma_and_tuning_app_run_reads_them(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "c.wav"
            chord_wav(p, 20, seconds=14)
            p_out = subprocess.run([sys.executable, str(ROOT / "bpm.py"), str(p)],
                                   capture_output=True, text=True, timeout=120)
        self.assertEqual(p_out.returncode, 0, p_out.stderr)
        (_b, keys), extras = self.run_with_stdout(p_out.stdout)
        self.assertEqual(len(keys), 3)
        self.assertEqual(len(extras.get("chroma", [])), 12)
        self.assertAlmostEqual(extras["tuning_cents"], 20, delta=3)


class TestInputFormats(unittest.TestCase):
    """ffmpeg-decodable containers go through bpm.py unchanged (needs the bundled ffmpeg)."""

    def ffmpeg(self):
        for c in (ROOT / "bin" / "ffmpeg", Path("/Users/jshriver/dev/beat_dl/bin/ffmpeg")):
            if c.is_file():
                return str(c)
        return None

    @unittest.skipUnless(HAVE_ESSENTIA, "needs the bundled Python")
    def test_decode_each_container(self):
        ff = self.ffmpeg()
        if not ff:
            self.skipTest("no ffmpeg")
        src = ROOT / "tests" / "fixtures" / "click120.wav"
        if not src.is_file():
            self.skipTest("run tests/fixtures/make_click.sh first")
        with tempfile.TemporaryDirectory() as d:
            for ext, args in [("flac", []), ("caf", []), ("m4a", ["-c:a", "aac"]), ("aac", ["-c:a", "aac"]),
                              ("ogg", ["-c:a", "libvorbis"]),
                              ("mov", ["-f", "lavfi", "-i", "color=c=black:s=64x64:d=30", "-c:a", "aac", "-c:v", "mpeg4", "-shortest"]),
                              ("mp4", ["-f", "lavfi", "-i", "color=c=black:s=64x64:d=30", "-c:a", "aac", "-c:v", "mpeg4", "-shortest"]),
                              ("m4v", ["-f", "lavfi", "-i", "color=c=black:s=64x64:d=30", "-c:a", "aac", "-c:v", "mpeg4", "-shortest"])]:
                out = Path(d) / f"t.{ext}"
                cmd = [ff, "-v", "error", "-y", "-i", str(src)] + args + [str(out)]
                r = subprocess.run(cmd, capture_output=True, text=True)
                self.assertEqual(r.returncode, 0, f"{ext}: {r.stderr}")
                a_key, a_bpm = bpm.load_audio_essentia(out)
                self.assertGreater(len(a_key), 44100 * 10, ext)


if __name__ == "__main__":
    unittest.main()
