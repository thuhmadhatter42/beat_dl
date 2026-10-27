import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
STUB_DIR = ROOT / "tests" / "stub"
WAV = ROOT / "tests" / "fixtures" / "click120.wav"

import app_run  # noqa: E402
import downloader  # noqa: E402


def run_cli(args, mode="ok", downloads=None, state=None, argv_log=None):
    env = dict(os.environ)
    env.update({
        "PATH": f"{STUB_DIR}{os.pathsep}{env.get('PATH', '')}",
        "STUB_MODE": mode,
        "STUB_AUDIO": str(WAV),
        "STUB_STATE": str(state),
        "ORION_DOWNLOADS": str(downloads),
        "PYTHONNOUSERSITE": "1",
    })
    if argv_log:
        env["STUB_ARGV_LOG"] = str(argv_log)
    p = subprocess.run([sys.executable, str(ROOT / "app_run.py")] + args,
                       capture_output=True, text=True, env=env, timeout=300)
    events = [json.loads(l) for l in p.stdout.splitlines() if l.strip()]
    return p, events


class Base(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.tmp = Path(self._t.name)
        self.dl = self.tmp / "dl"
        self.dl.mkdir()
        self.state = self.tmp / "state"
        self.state.mkdir()

    def tearDown(self):
        self._t.cleanup()


class TestPure(unittest.TestCase):
    def test_renamed_name_matches_run_sh(self):
        self.assertEqual(
            app_run.renamed_name("T", "mp3", "142.0", [("Cm", 73), ("Eb", 18), ("Gm", 9)]),
            "T (142.0 BPM Cm Eb Gm).mp3")

    def test_log_line(self):
        self.assertEqual(app_run.log_line("u", "n"), "Input URL: u\nDownloaded: n\n\n")

    def test_cli_default_order_unchanged(self):
        self.assertEqual(downloader.strategies(False)[0], ["--cookies-from-browser", "firefox"])
        self.assertEqual(downloader.strategies(True)[-1][0], "--cookies-from-browser")
        self.assertEqual(downloader.strategies(True)[0][0], "--extractor-args")
        self.assertEqual(sorted(map(tuple, downloader.strategies(True))),
                         sorted(map(tuple, downloader.strategies(False))))

    def test_old_strategy_order_literal(self):
        self.assertEqual(downloader.strategies(False), [
            ["--cookies-from-browser", "firefox"],
            ["--cookies-from-browser", "safari"],
            ["--cookies-from-browser", "chrome"],
            ["--extractor-args", "youtube:player_client=android"],
            ["--extractor-args", "youtube:player_client=web"],
            [],
        ])


class TestDownload(Base):
    def test_download_ok(self):
        p, ev = run_cli(["download", "https://example.com/v"], "ok", self.dl, self.state)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(ev[-1]["stage"], "done")
        self.assertEqual(ev[-1]["bpm"], "120.0")
        self.assertEqual([e["stage"] for e in ev][:2], ["downloading", "analyzing"])
        self.assertIn("renaming", [e["stage"] for e in ev])
        f = Path(ev[-1]["file"])
        self.assertTrue(f.is_file())
        self.assertEqual(f.parent.resolve(), self.dl.resolve())
        self.assertEqual(f.name, ev[-1]["name"])
        self.assertRegex(f.name, r"^Test Beat \(120\.0 BPM \S+ \S+ \S+\)\.mp3$")
        self.assertFalse((self.dl / "Test Beat.mp3").exists())
        self.assertEqual(len(ev[-1]["keys"]), 3)
        d = date.today()
        log = self.dl / f"({d.year % 100}-{d.month}-{d.day}) Youtube DL LINKS.txt"
        self.assertTrue(log.is_file())
        self.assertEqual(log.read_text(), app_run.log_line("https://example.com/v", f.name))

    def test_weird_title(self):
        p, ev = run_cli(["download", "https://example.com/v"], "ok-weird-title", self.dl, self.state)
        self.assertEqual(ev[-1]["stage"], "done", ev)
        self.assertTrue(Path(ev[-1]["file"]).is_file())
        self.assertNotIn("/", ev[-1]["name"])

    def test_network_error(self):
        p, ev = run_cli(["download", "https://example.com/v"], "fail-network", self.dl, self.state)
        self.assertEqual(p.returncode, 0)
        self.assertEqual(ev[-1]["stage"], "error")
        self.assertTrue(ev[-1]["message"].startswith("Network error"), ev[-1])
        self.assertEqual([e["stage"] for e in ev].count("updating"), 1)

    def test_retry_after_upgrade(self):
        p, ev = run_cli(["download", "https://example.com/v"], "fail-then-ok", self.dl, self.state)
        stages = [e["stage"] for e in ev]
        self.assertIn("updating", stages)
        self.assertLess(stages.index("updating"), stages.index("done"))
        self.assertEqual(stages[-1], "done")

    def test_playlist_url(self):
        log = self.tmp / "argv.log"
        p, ev = run_cli(["download", "https://example.com/watch?v=x&list=PL123"], "ok",
                        self.dl, self.state, argv_log=log)
        self.assertEqual(ev[-1]["stage"], "done")
        lines = log.read_text().splitlines()
        self.assertTrue(lines)
        self.assertTrue(all("--no-playlist" in l for l in lines), lines)


class TestAnalyze(Base):
    def test_analyze_text_file(self):
        t = self.tmp / "notes.txt"
        t.write_text("not audio")
        p, ev = run_cli(["analyze", str(t)], "ok", self.dl, self.state)
        self.assertEqual(ev[-1]["stage"], "analyzed")
        self.assertIsNone(ev[-1]["bpm"])
        self.assertEqual(ev[-1]["keys"], [])
        self.assertEqual(ev[-1]["name"], "notes.txt")

    def test_analyze_audio(self):
        p, ev = run_cli(["analyze", str(WAV)], "ok", self.dl, self.state)
        self.assertEqual(ev[-1]["bpm"], "120.0")
        self.assertEqual(len(ev[-1]["keys"]), 3)
        self.assertIsInstance(ev[-1]["keys"][0][1], int)

    def test_analysis_timeout(self):
        self.assertEqual(app_run.analyze_file(WAV, timeout=0.01), (None, []))


if __name__ == "__main__":
    unittest.main()
