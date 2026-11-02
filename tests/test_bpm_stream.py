"""Live listening: bpm.py --stream (raw float32 PCM on stdin, one JSON line per reading).
Run with the bundled Python: bin/python/bin/python3 -m unittest discover -s tests"""
import io
import json
import subprocess
import sys
import unittest
from pathlib import Path

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


def click_drone(secs, sr=SR, bpm_=120.0):
    """The tests/fixtures/make_click.sh signal, synthesized: a 10 ms 1 kHz click every beat over a
    quiet A-minor drone (A3 C4 E4)."""
    t = np.arange(int(secs * sr)) / sr
    period = 60.0 / bpm_
    click = np.where(np.mod(t, period) < 0.01, 0.9 * np.sin(2 * np.pi * 1000 * t), 0.0)
    drone = 0.08 * (np.sin(2 * np.pi * 220 * t) + np.sin(2 * np.pi * 261.63 * t) + np.sin(2 * np.pi * 329.63 * t))
    return (click + drone).astype(np.float32)


def silence(secs, sr=SR):
    return np.zeros(int(secs * sr), np.float32)


def run_stream(audio, *args):
    """Pipe audio through `bpm.py --stream`; returns the parsed events and the exit code."""
    p = subprocess.run([sys.executable, str(ROOT / "bpm.py"), "--stream", *args],
                       input=audio.astype("<f4").tobytes(), capture_output=True, timeout=300)
    events = [json.loads(line) for line in p.stdout.decode().splitlines() if line.strip()]
    return events, p.returncode


@unittest.skipUnless(HAVE_ESSENTIA, "needs the bundled Python")
class TestLiveAnalyzer(unittest.TestCase):
    def feed(self, live, audio, chunk=0.5):
        n = int(chunk * SR)
        out = []
        for i in range(0, len(audio), n):
            out += live.push(audio[i:i + n])
        return out

    def test_key_first_then_bpm_once_the_tempo_window_is_full(self):
        live = bpm.LiveAnalyzer(hop=2.0)
        evs = self.feed(live, click_drone(16))
        readings = [e for e in evs if e["event"] == "reading"]
        self.assertTrue(readings)
        early = readings[0]
        self.assertIsNone(early["bpm"])                      # < 12 s: key only
        self.assertIn("Am", [k for k, _ in early["keys"]])
        last = readings[-1]
        self.assertEqual(round(float(last["bpm"])), 120)
        self.assertAlmostEqual(last["bpm_exact"], 120.0, delta=0.5)
        self.assertIn("Am", [k for k, _ in last["keys"]])

    def test_a_reading_every_hop(self):
        live = bpm.LiveAnalyzer(hop=2.0)
        evs = self.feed(live, click_drone(10))
        # readings from 4 s (the key minimum) every 2 s: 4, 6, 8, 10
        self.assertEqual([e["secs"] for e in evs if e["event"] == "reading"], [4.0, 6.0, 8.0, 10.0])

    def test_gap_resets_after_a_last_reading(self):
        live = bpm.LiveAnalyzer(hop=2.0, gap=3.0)
        evs = self.feed(live, np.concatenate([click_drone(5), silence(4)]))
        kinds = [e["event"] for e in evs]
        self.assertIn("reset", kinds)
        i = kinds.index("reset")
        self.assertEqual(kinds[i - 1], "reading")           # the final word before the reset
        self.assertEqual(evs[i - 1]["secs"], 5.0)
        self.assertEqual(live.heard, 0.0)
        self.assertEqual(live.frames, [])

    def test_short_pause_is_not_a_gap(self):
        live = bpm.LiveAnalyzer(hop=2.0, gap=3.0)
        evs = self.feed(live, np.concatenate([click_drone(5), silence(2), click_drone(3)]))
        self.assertNotIn("reset", [e["event"] for e in evs])
        self.assertEqual(live.heard, 8.0)

    def test_silence_alone_says_nothing(self):
        live = bpm.LiveAnalyzer(hop=2.0, gap=3.0)
        self.assertEqual(self.feed(live, silence(10)), [])

    def test_buffers_stay_bounded(self):
        live = bpm.LiveAnalyzer(hop=4.0, key_window=10.0)
        self.feed(live, click_drone(40))
        self.assertLessEqual(len(live.audio), int(12 * SR))
        self.assertLessEqual(len(live.frames), int(10 * SR / bpm.HOP))

    def test_other_input_rate_is_resampled(self):
        live = bpm.LiveAnalyzer(rate=48000, hop=2.0)
        x = click_drone(6, sr=48000)
        out = []
        for i in range(0, len(x), 24000):
            out += live.push(x[i:i + 24000])
        self.assertTrue([e for e in out if e["event"] == "reading"])
        self.assertAlmostEqual(live.heard, 6.0, delta=0.05)

    def test_level_db(self):
        self.assertLess(bpm.LiveAnalyzer.level_db(silence(1)), -100)
        self.assertAlmostEqual(bpm.LiveAnalyzer.level_db(np.full(100, 0.5, np.float32)), -6.02, places=1)
        self.assertEqual(bpm.LiveAnalyzer.level_db(np.zeros(0, np.float32)), -120.0)


def tones(secs, freqs, amp=0.08, sr=SR):
    """A sustained chord (strings / pad stand-in): each note with two quieter harmonics."""
    t = np.arange(int(secs * sr)) / sr
    x = np.zeros_like(t)
    for f in freqs:
        x += amp * (np.sin(2 * np.pi * f * t) + 0.4 * np.sin(4 * np.pi * f * t) + 0.2 * np.sin(6 * np.pi * f * t))
    return x


def clicks(secs, bpm_, offset=0.0, amp=0.9, freq=1000.0, sr=SR):
    """A 10 ms click every beat, the first at `offset` s (the beat grid's phase)."""
    t = np.arange(int(secs * sr)) / sr
    period = 60.0 / bpm_
    on = np.mod(t - offset, period) < 0.01
    return np.where(on, amp * np.sin(2 * np.pi * freq * t), 0.0)


def kick808(secs, bpm_, note=55.0, sr=SR):
    """On-grid kicks with a decaying 808 tone (drums + bass entering at a drop)."""
    t = np.arange(int(secs * sr)) / sr
    tb = np.mod(t, 60.0 / bpm_)
    return 0.5 * np.exp(-tb * 6) * np.sin(2 * np.pi * note * t)


A_MINOR = (220.0, 261.63, 329.63)
FS_MAJOR = (185.0, 233.08, 277.18)


@unittest.skipUnless(HAVE_ESSENTIA, "needs the bundled Python")
class TestNewSong(unittest.TestCase):
    """New song with no pause (BoundaryDetector), and the drop that must NOT split a song."""

    def feed(self, live, audio, chunk=0.5):
        n = int(chunk * SR)
        out = []
        for i in range(0, len(audio), n):
            out += live.push(audio[i:i + n].astype(np.float32))
        return out

    def test_other_chord_and_off_grid_beat_is_a_new_song(self):
        a = tones(20, A_MINOR) + clicks(20, 120, 0.0)
        b = tones(16, FS_MAJOR) + clicks(16, 120, 0.25)   # other notes, the beat half a beat off
        live = bpm.LiveAnalyzer(hop=2.0)
        evs = self.feed(live, np.concatenate([a, b]))
        kinds = [e["event"] for e in evs]
        self.assertIn("boundary", kinds, evs)
        i = kinds.index("boundary")
        self.assertEqual(evs[i]["reason"], "audio")
        self.assertEqual(kinds.count("boundary"), 1)
        # found within 8 s of the change: readings before it are at most 28 s of audio
        self.assertLessEqual(max(e["secs"] for e in evs[:i] if e["event"] == "reading"), 28.0)
        after = [e for e in evs[i + 1:] if e["event"] == "reading"]
        self.assertTrue(after)
        self.assertLess(after[0]["secs"], 10)                # rebuilt from scratch
        self.assertEqual(after[-1]["keys"][0][0], "F#")      # the old chord no longer counts

    def test_drums_and_808_entering_over_the_same_chord_is_the_same_song(self):
        intro = tones(16, A_MINOR)                            # strings alone
        drop = tones(20, A_MINOR) + clicks(20, 120, 0.0) + kick808(20, 120)
        live = bpm.LiveAnalyzer(hop=2.0)
        evs = self.feed(live, np.concatenate([intro, drop]))
        self.assertNotIn("boundary", [e["event"] for e in evs])
        self.assertAlmostEqual(live.heard, 36.0, delta=0.1)

    def test_one_steady_song_has_no_boundary(self):
        live = bpm.LiveAnalyzer(hop=4.0)
        self.assertNotIn("boundary", [e["event"] for e in self.feed(live, click_drone(40))])

    def test_new_song_flushes_now(self):
        live = bpm.LiveAnalyzer(hop=2.0)
        self.feed(live, click_drone(8))
        self.assertEqual(live.new_song(), [{"event": "boundary", "reason": "title"}])
        self.assertEqual(live.heard, 0.0)
        self.assertEqual(live.frames, [])
        self.assertEqual(len(live.audio), 0)

    def test_detector_off(self):
        a = tones(20, A_MINOR) + clicks(20, 120, 0.0)
        b = tones(16, FS_MAJOR) + clicks(16, 120, 0.25)
        live = bpm.LiveAnalyzer(hop=2.0, boundaries=False)
        self.assertNotIn("boundary", [e["event"] for e in self.feed(live, np.concatenate([a, b]))])


@unittest.skipUnless(HAVE_ESSENTIA, "needs the bundled Python")
class TestStreamCli(unittest.TestCase):
    def test_sigusr1_is_a_new_song(self):
        import signal
        import time
        p = subprocess.Popen([sys.executable, str(ROOT / "bpm.py"), "--stream", "--hop", "2"],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.assertEqual(json.loads(p.stdout.readline()), {"event": "ready"})
        p.stdin.write(click_drone(6).astype("<f4").tobytes())
        p.stdin.flush()
        time.sleep(1.0)
        p.send_signal(signal.SIGUSR1)
        time.sleep(0.3)
        p.stdin.write(click_drone(5).astype("<f4").tobytes())
        p.stdin.close()
        events = [json.loads(line) for line in p.stdout.read().decode().splitlines() if line.strip()]
        p.stdout.close()
        self.assertEqual(p.wait(timeout=120), 0)
        kinds = [e["event"] for e in events]
        self.assertIn({"event": "boundary", "reason": "title"}, events)
        i = kinds.index("boundary")
        self.assertTrue(all(e["secs"] <= 5.0 for e in events[i + 1:] if e["event"] == "reading"), events)

    def test_stdin_to_json_lines(self):
        audio = np.concatenate([click_drone(16), silence(4)])
        events, code = run_stream(audio, "--hop", "2", "--gap", "3")
        self.assertEqual(code, 0)
        self.assertEqual(events[0], {"event": "ready"})
        kinds = [e["event"] for e in events]
        self.assertIn("reading", kinds)
        self.assertEqual(kinds[-1], "reset")
        with_bpm = [e for e in events if e["event"] == "reading" and e["bpm"]]
        self.assertTrue(with_bpm, events)
        self.assertEqual(round(float(with_bpm[-1]["bpm"])), 120)
        self.assertIn("Am", [k for k, _ in with_bpm[-1]["keys"]])
        for e in events:
            if e["event"] == "reading":
                self.assertEqual(len(e["keys"]), 3)
                self.assertTrue(all(isinstance(p, int) for _, p in e["keys"]))

    def test_eof_gives_the_last_reading(self):
        events, code = run_stream(click_drone(5), "--hop", "10")
        self.assertEqual(code, 0)
        self.assertEqual([e["event"] for e in events], ["ready", "reading"])
        self.assertEqual(events[1]["secs"], 5.0)

    def test_odd_byte_count_is_tolerated(self):
        raw = click_drone(5).astype("<f4").tobytes() + b"\x00\x01"
        p = subprocess.run([sys.executable, str(ROOT / "bpm.py"), "--stream"], input=raw,
                           capture_output=True, timeout=120)
        self.assertEqual(p.returncode, 0)

    def test_in_process_driver(self):
        out = io.StringIO()
        code = bpm.stream_main(["--hop", "2"], inp=io.BytesIO(click_drone(6).astype("<f4").tobytes()), out=out)
        self.assertEqual(code, 0)
        kinds = [json.loads(line)["event"] for line in out.getvalue().splitlines()]
        self.assertEqual(kinds[0], "ready")
        self.assertIn("reading", kinds)


if __name__ == "__main__":
    unittest.main()
