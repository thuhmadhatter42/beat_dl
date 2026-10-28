import json
import os
import subprocess
import sys
import tempfile
import unittest
import io
import contextlib
import shutil
from unittest import mock
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
STUB_DIR = ROOT / "tests" / "stub"
WAV = ROOT / "tests" / "fixtures" / "click120.wav"

import app_run  # noqa: E402
import downloader  # noqa: E402


def run_cli(args, mode="ok", downloads=None, state=None, argv_log=None, ytdlp="stub", extra_env=None):
    env = dict(os.environ)
    env.pop("ORION_YTDLP", None)
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
    if ytdlp == "stub":
        env["ORION_YTDLP"] = str(STUB_DIR / "yt-dlp")
    elif ytdlp:
        env["ORION_YTDLP"] = str(ytdlp)
    env.update(extra_env or {})
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

    def test_unavailable_stops_before_cookies_and_upgrade(self):
        log = self.tmp / "argv.log"
        p, ev = run_cli(["download", "https://www.youtube.com/watch?v=xxxxxxxxxxx"], "fail-unavailable",
                        self.dl, self.state, argv_log=log)
        self.assertEqual(ev[-1]["stage"], "error")
        self.assertTrue(ev[-1]["message"].startswith("That video is unavailable"), ev[-1])
        argv = log.read_text()
        self.assertNotIn("--cookies-from-browser", argv)
        self.assertNotIn("-U", argv.split())
        self.assertNotIn("updating", [e["stage"] for e in ev])
        self.assertFalse((self.state / "upgraded").exists())

    def test_timeout_is_an_error_event(self):
        p, ev = run_cli(["download", "https://example.com/v"], "hang", self.dl, self.state,
                        extra_env={"ORION_YTDLP_TIMEOUT": "1"})
        self.assertEqual(ev[-1]["stage"], "error")
        self.assertEqual(ev[-1]["message"], "Download timed out.")
        self.assertNotIn("updating", [e["stage"] for e in ev])

    def test_upgrade_only_touches_orion_ytdlp(self):
        # ORION_YTDLP unset: no -U anywhere (PATH has the stub, which would log it)
        log = self.tmp / "argv.log"
        p, ev = run_cli(["download", "https://example.com/v"], "fail-then-ok", self.dl, self.state,
                        argv_log=log, ytdlp=None)
        self.assertEqual(ev[-1]["stage"], "error", ev)
        self.assertNotIn("updating", [e["stage"] for e in ev])
        self.assertNotIn("-U", log.read_text().split())
        self.assertFalse((self.state / "upgraded").exists())
        # ORION_YTDLP set to a missing path: same
        p, ev = run_cli(["download", "https://example.com/v"], "fail-then-ok", self.dl, self.state,
                        ytdlp=self.tmp / "nope")
        self.assertEqual(ev[-1]["stage"], "error")
        self.assertFalse((self.state / "upgraded").exists())

    def test_downloads_run_through_orion_ytdlp(self):
        # a wrapper that logs its own name proves ORION_YTDLP, not PATH, ran the downloads
        wrap = self.tmp / "my-ytdlp"
        wrap.write_text('#!/bin/bash\necho used >> "%s"\nexec "%s" "$@"\n' % (self.tmp / "used.log", STUB_DIR / "yt-dlp"))
        wrap.chmod(0o755)
        p, ev = run_cli(["download", "https://example.com/v"], "ok", self.dl, self.state, ytdlp=wrap)
        self.assertEqual(ev[-1]["stage"], "done", ev)
        self.assertTrue((self.tmp / "used.log").read_text().count("used") >= 2)

    def test_retry_skips_cookie_strategies(self):
        log = self.tmp / "argv.log"
        p, ev = run_cli(["download", "https://example.com/v"], "fail-then-ok", self.dl, self.state, argv_log=log)
        self.assertEqual(ev[-1]["stage"], "done")
        # first pass: 3 plain + 3 cookie metadata attempts; after -U: succeeds on the first plain one
        lines = log.read_text().splitlines()
        i = next(n for n, l in enumerate(lines) if l.split()[:1] == ["-U"])
        self.assertNotIn("--cookies-from-browser", " ".join(lines[i + 1:]))

    def test_cli_downloader_has_no_timeout_or_cookie_stop(self):
        calls = []

        def fake_fetch(url, extra_args=(), exe="yt-dlp", timeout=None):
            calls.append((tuple(extra_args), exe, timeout))
            return None, ["ERROR: Video unavailable"]
        with mock.patch.object(downloader, "fetch_info", fake_fetch), contextlib.redirect_stdout(io.StringIO()):
            downloader.run_download("https://example.com/v", silent=True, ytdlp="/x/y", timeout=5)
        self.assertEqual(len(calls), 6)                       # every strategy still tried, cookies first
        self.assertEqual(calls[0][0], ("--cookies-from-browser", "firefox"))
        self.assertTrue(all(c[1] == "yt-dlp" and c[2] is None for c in calls))

    def test_playlist_url(self):
        log = self.tmp / "argv.log"
        p, ev = run_cli(["download", "https://example.com/watch?v=x&list=PL123"], "ok",
                        self.dl, self.state, argv_log=log)
        self.assertEqual(ev[-1]["stage"], "done")
        lines = log.read_text().splitlines()
        self.assertTrue(lines)
        self.assertTrue(all("--no-playlist" in l for l in lines), lines)


class TestAnalyze(Base):
    def test_unreadable_file_reports_permission(self):
        t = self.tmp / "locked.wav"
        t.write_bytes(b"x")
        t.chmod(0)
        try:
            p, ev = run_cli(["analyze", str(t)], "ok", self.dl, self.state)
        finally:
            t.chmod(0o600)
        self.assertEqual(ev[-1]["stage"], "analyzed")
        self.assertIsNone(ev[-1]["bpm"])
        self.assertEqual(ev[-1].get("error"), "permission")

    def test_plain_failure_has_no_error_flag(self):
        t = self.tmp / "notes.txt"
        t.write_text("not audio")
        p, ev = run_cli(["analyze", str(t)], "ok", self.dl, self.state)
        self.assertNotIn("error", ev[-1])

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


TERMINAL = ("done", "analyzed", "error")


class TestGuards(Base):
    def _run_inproc(self, fn, *args):
        buf = io.StringIO()
        with mock.patch.dict(os.environ, {"ORION_DOWNLOADS": str(self.dl)}), \
                contextlib.redirect_stdout(buf):
            fn(*args)
        return [json.loads(l) for l in buf.getvalue().splitlines() if l.strip()]

    def _fake_download(self):
        f = self.dl / "Test Beat.mp3"
        shutil.copy(WAV, f)
        return mock.patch.object(app_run, "_attempt", return_value=(f, ""))

    def test_rename_failure_still_done(self):
        with self._fake_download(), mock.patch.object(app_run.os, "replace", side_effect=OSError("denied")):
            ev = self._run_inproc(app_run.cmd_download, "https://example.com/v")
        term = [e for e in ev if e["stage"] in TERMINAL]
        self.assertEqual(len(term), 1, ev)
        self.assertEqual(term[0]["stage"], "done")
        self.assertEqual(term[0]["name"], "Test Beat.mp3")
        self.assertEqual(term[0]["bpm"], "120.0")
        self.assertTrue(Path(term[0]["file"]).is_file())

    def test_log_failure_still_done(self):
        with self._fake_download(), mock.patch.object(app_run, "log_path",
                                                      return_value=self.dl / "nodir" / "x" / "log.txt"), \
                mock.patch.object(app_run.Path, "mkdir", side_effect=OSError("denied")):
            ev = self._run_inproc(app_run.cmd_download, "https://example.com/v")
        term = [e for e in ev if e["stage"] in TERMINAL]
        self.assertEqual(len(term), 1, ev)
        self.assertEqual(term[0]["stage"], "done")

    def test_analyze_exception_still_analyzed(self):
        with mock.patch.object(app_run, "analyze_file", side_effect=RuntimeError("boom")):
            ev = self._run_inproc(app_run.cmd_analyze, [str(WAV), str(WAV)])
        term = [e for e in ev if e["stage"] in TERMINAL]
        self.assertEqual(len(term), 2, ev)
        self.assertTrue(all(e["stage"] == "analyzed" and e["bpm"] is None for e in term))

    def test_main_top_level_guard(self):
        with mock.patch.object(app_run, "cmd_download", side_effect=RuntimeError("boom")):
            ev = self._run_inproc(app_run.main, ["app_run.py", "download", "u"])
        self.assertEqual([e["stage"] for e in ev if e["stage"] in TERMINAL], ["error"])


if __name__ == "__main__":
    unittest.main()
