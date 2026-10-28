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
        "ORION_LOG_DIR": str(Path(str(state)).parent / "logs"),   # never the real ~/Library/Logs
        "PYTHONNOUSERSITE": "1",
    })
    env.pop("ORION_DENO", None)
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

    def test_app_order_never_has_cookie_strategies(self):
        self.assertTrue(all(x[:1] != ["--cookies-from-browser"] for x in downloader.strategies(True)))
        self.assertEqual(len(downloader.strategies(True)), 3)
        self.assertEqual(downloader.strategies(True, "brave"), [["--cookies-from-browser", "brave"]])
        self.assertEqual(downloader.strategies(False, "brave")[0], ["--cookies-from-browser", "firefox"])

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
        # first pass: the 3 plain metadata attempts only; after -U: succeeds on the first plain one
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


class TestLogin(Base):
    URL = "https://www.youtube.com/watch?v=xxxxxxxxxxx"

    def test_app_never_passes_cookies_without_browser(self):
        for mode in ("fail-age", "fail-bot", "fail-network", "fail-unavailable", "ok", "fail-then-ok"):
            log = self.tmp / f"argv-{mode}.log"
            run_cli(["download", self.URL], mode, self.dl, self.state, argv_log=log)
            self.assertNotIn("--cookies-from-browser", log.read_text(), mode)
            for f in self.state.iterdir():
                f.unlink()

    def test_age_and_bot_and_members_need_login(self):
        for mode, reason in (("fail-age", "age"), ("fail-bot", "bot"), ("fail-members", "members")):
            p, ev = run_cli(["download", self.URL], mode, self.dl, self.state)
            self.assertEqual(ev[-1]["stage"], "needs_login", ev)
            self.assertEqual(ev[-1]["reason"], reason)
            self.assertTrue(ev[-1]["message"])
            self.assertNotIn("tried", ev[-1])
            self.assertNotIn("updating", [e["stage"] for e in ev])
            self.assertNotIn("error", [e["stage"] for e in ev])

    def test_dead_link_is_error_not_login(self):
        p, ev = run_cli(["download", self.URL], "fail-unavailable", self.dl, self.state)
        self.assertEqual(ev[-1]["stage"], "error")
        self.assertNotIn("needs_login", [e["stage"] for e in ev])

    def test_browser_runs_exactly_one_cookie_attempt(self):
        log = self.tmp / "argv.log"
        p, ev = run_cli(["download", self.URL, "--browser", "brave"], "cookie-ok", self.dl, self.state,
                        argv_log=log)
        self.assertEqual(ev[-1]["stage"], "done", ev)
        lines = log.read_text().splitlines()
        self.assertTrue(lines)
        self.assertTrue(all("--cookies-from-browser brave" in l for l in lines), lines)
        self.assertEqual(sum("--dump-json" in l for l in lines), 1)
        self.assertNotIn("-U", log.read_text().split())
        self.assertNotIn("updating", [e["stage"] for e in ev])

    def test_browser_still_login_error_reports_tried(self):
        log = self.tmp / "argv.log"
        p, ev = run_cli(["download", self.URL, "--browser", "firefox"], "fail-age", self.dl, self.state,
                        argv_log=log)
        self.assertEqual(ev[-1]["stage"], "needs_login", ev)
        self.assertEqual(ev[-1]["tried"], "firefox")
        self.assertEqual(len(log.read_text().splitlines()), 1)

    def test_browser_keychain_refusal_is_error_not_login(self):
        # yt-dlp only warns when the Keychain says no, then YouTube asks for a login: the
        # Keychain is the real cause, not a missing YouTube login
        p, ev = run_cli(["download", self.URL, "--browser", "chrome"], "fail-keychain", self.dl, self.state)
        self.assertEqual(ev[-1]["stage"], "error", ev)
        self.assertEqual(ev[-1]["message"], "macOS didn't unlock Chrome's YouTube login. Try again and "
                                            "allow Keychain access when macOS asks.")

    def test_safari_blocked_says_full_disk_access(self):
        p, ev = run_cli(["download", self.URL, "--browser", "safari"], "fail-cookie-blocked", self.dl, self.state)
        self.assertEqual(ev[-1]["stage"], "error")
        self.assertIn("Full Disk Access for Beat Key", ev[-1]["message"])

    def test_missing_cookie_database(self):
        home = self.tmp / "home"
        home.mkdir()
        p, ev = run_cli(["download", self.URL, "--browser", "chrome"], "fail-cookie-missing", self.dl,
                        self.state, extra_env={"HOME": str(home)})
        self.assertEqual(ev[-1]["stage"], "error")
        self.assertEqual(ev[-1]["message"], "Couldn't find Chrome's YouTube login. "
                                            "Log in to YouTube in Chrome, then try again.")

    def test_macos_hiding_the_browser_folder_is_blocked(self):
        # macOS 27 guards the browser's Application Support folder; yt-dlp's os.walk swallows
        # the refusal and reports "could not find ... cookies database"
        home = self.tmp / "home"
        d = home / "Library" / "Application Support" / "Google" / "Chrome"
        d.mkdir(parents=True)
        d.chmod(0)
        try:
            p, ev = run_cli(["download", self.URL, "--browser", "chrome"], "fail-cookie-missing", self.dl,
                            self.state, extra_env={"HOME": str(home)})
        finally:
            d.chmod(0o700)
        self.assertEqual(ev[-1]["stage"], "error")
        self.assertEqual(ev[-1]["message"], "macOS blocked Beat Key from reading Chrome's YouTube login. "
                                            "Allow it in System Settings › Privacy & Security › "
                                            "Files & Folders.")
        self.assertFalse(app_run.cookie_error_message("chrome").lower().count("operation not permitted"))

    def test_harmless_cookie_warning_still_downloads(self):
        p, ev = run_cli(["download", self.URL, "--browser", "brave"], "cookie-warn-ok", self.dl, self.state)
        self.assertEqual(ev[-1]["stage"], "done", ev)

    def test_unsolved_js_challenge_is_blocked_not_region(self):
        for browser in (None, "brave"):
            args = ["download", self.URL] + (["--browser", browser] if browser else [])
            p, ev = run_cli(args, "fail-format", self.dl, self.state)
            self.assertEqual(ev[-1]["stage"], "error", ev)
            self.assertEqual(ev[-1]["message"], "YouTube blocked this download. Try Beat Key › Run Doctor.")
            for f in self.state.iterdir():
                if f.is_file():
                    f.unlink()

    def test_cookie_failure_classifier(self):
        c = downloader.cookie_failure
        self.assertEqual(c(["ERROR: could not find brave cookies database in \"/x\""]), "missing")
        self.assertEqual(c(["ERROR: [Errno 1] Operation not permitted: '/x/Cookies'"]), "blocked")
        self.assertEqual(c(["ERROR: [Errno 13] Permission denied: '/x/Cookies'"]), "blocked")
        self.assertEqual(c(["WARNING: find-generic-password failed"]), "keychain")
        self.assertEqual(c(["WARNING: cannot decrypt v10 cookies: no key found"]), "keychain")
        # harmless warnings and the old over-broad words never count
        self.assertIsNone(c(["WARNING: failed to decrypt cookie (AES-GCM) because the MAC check failed. "
                             "Possibly the key is wrong?"]))
        self.assertIsNone(c(["Extracted 1699 cookies from brave (3 could not be decrypted)"]))
        self.assertIsNone(c(["WARNING: unknown cookie version: \"v12\""]))
        self.assertIsNone(c(["ERROR: [youtube] x: Requested format is not available"]))
        self.assertIsNone(c(["WARNING: keyring something"]))

    def test_error_mapping_uses_ytdlp_wording(self):
        e = downloader.explain_error
        blocked = "YouTube blocked this download. Try Beat Key › Run Doctor."
        self.assertEqual(e(["ERROR: [youtube] x: Requested format is not available. Use --list-formats "
                            "for a list of available formats"]), blocked)
        self.assertEqual(e(["WARNING: Only images are available for download. use --list-formats to see them"]),
                         blocked)
        self.assertEqual(e(["WARNING: [youtube] x: n challenge solving failed: Some formats may be missing."]),
                         blocked)
        self.assertEqual(e(["ERROR: [youtube] x: Video unavailable. This video has been removed by the uploader"]),
                         "That video is unavailable or has been removed.")
        self.assertEqual(e(["ERROR: [youtube] x: The uploader has not made this video available in your country"]),
                         "That video is not available in your country.")
        self.assertEqual(e(["ERROR: [youtube] x: Private video. Sign in if you've been granted access"]),
                         "That video is private and cannot be downloaded.")
        self.assertTrue(e(["ERROR: [youtube] x: Sign in to confirm your age. This video may be inappropriate "
                           "for some users."]).startswith("That video is age-restricted"))
        self.assertTrue(e(["ERROR: [youtube] x: Video unavailable. This video is no longer available due to "
                           "a copyright claim by someone"]).startswith("This video is blocked due to a copyright"))
        self.assertTrue(e(["ERROR: Unable to download webpage: <urlopen error [Errno 8] nodename nor "
                           "servname provided, or not known>"]).startswith("Network error"))
        self.assertTrue(e(["ERROR: Unsupported URL: https://example.com/"]).startswith("That doesn't look like"))
        # "images", "page", "message" contain "age"; none of them is an age restriction
        self.assertFalse(e(["WARNING: Only images are available"]).startswith("That video is age"))
        # a region-locked video is final (no upgrade); a blocked download is not
        self.assertTrue(downloader.is_final_error(["The uploader has not made this video available in your country"]))
        self.assertFalse(downloader.is_final_error(["Requested format is not available"]))

    def test_unknown_browser_is_error(self):
        p, ev = run_cli(["download", self.URL, "--browser", "arc"], "ok", self.dl, self.state)
        self.assertEqual(ev[-1]["stage"], "error")

    def test_reason_classifier(self):
        r = downloader.login_reason
        self.assertEqual(r(["Sign in to confirm your age"]), "age")
        self.assertEqual(r(["This video is age-restricted"]), "age")
        self.assertEqual(r(["Sign in to confirm you\u2019re not a bot"]), "bot")
        self.assertEqual(r(["members-only content"]), "members")
        self.assertIsNone(r(["Private video. Sign in if you've been granted access"]))
        self.assertIsNone(r(["Video unavailable"]))


class TestJsRuntimeAndLog(Base):
    URL = "https://www.youtube.com/watch?v=xxxxxxxxxxx"

    def _deno(self):
        d = self.tmp / "rt" / "deno"
        d.parent.mkdir()
        d.write_text("#!/bin/bash\necho deno 0\n")
        d.chmod(0o755)
        return d

    def test_every_ytdlp_call_gets_the_bundled_deno(self):
        deno = self._deno()
        log = self.tmp / "argv.log"
        p, ev = run_cli(["download", self.URL], "fail-then-ok", self.dl, self.state, argv_log=log,
                        extra_env={"ORION_DENO": str(deno)})
        self.assertEqual(ev[-1]["stage"], "done", ev)
        calls = [l for l in log.read_text().splitlines() if l.split()[:1] != ["-U"]]
        self.assertTrue(calls)
        self.assertTrue(all(f"--js-runtimes deno:{deno}" in l for l in calls), calls)
        log.unlink()
        p, ev = run_cli(["download", self.URL, "--browser", "brave"], "cookie-ok", self.dl, self.state,
                        argv_log=log, extra_env={"ORION_DENO": str(deno)})
        self.assertTrue(all(f"--js-runtimes deno:{deno}" in l and "--cookies-from-browser brave" in l
                            for l in log.read_text().splitlines()))

    def test_no_or_missing_deno_passes_no_flag(self):
        log = self.tmp / "argv.log"
        run_cli(["download", self.URL], "ok", self.dl, self.state, argv_log=log)
        self.assertNotIn("--js-runtimes", log.read_text())
        log.unlink()
        run_cli(["download", self.URL], "ok", self.dl, self.state, argv_log=log,
                extra_env={"ORION_DENO": str(self.tmp / "nope" / "deno")})
        self.assertNotIn("--js-runtimes", log.read_text())

    def test_js_runtime_args(self):
        deno = self._deno()
        self.assertEqual(downloader.js_runtime_args({"ORION_DENO": str(deno)}),
                         ["--js-runtimes", f"deno:{deno}"])
        self.assertEqual(downloader.js_runtime_args({}), [])

    def test_cli_mode_never_gets_the_flag(self):
        calls = []

        def fake_fetch(url, extra_args=(), exe="yt-dlp", timeout=None):
            calls.append(tuple(extra_args))
            return None, ["ERROR: Video unavailable"]
        deno = self._deno()
        with mock.patch.dict(os.environ, {"ORION_DENO": str(deno)}), \
                mock.patch.object(downloader, "fetch_info", fake_fetch), \
                contextlib.redirect_stdout(io.StringIO()):
            downloader.run_download("https://example.com/v", silent=True)
        self.assertTrue(calls)
        self.assertFalse(any("--js-runtimes" in c for c in calls))

    def test_last_run_log_has_ytdlp_stderr_and_is_overwritten(self):
        p, ev = run_cli(["download", self.URL], "fail-format", self.dl, self.state)
        f = self.tmp / "logs" / "last-run.log"
        text = f.read_text()
        self.assertIn("Requested format is not available", text)
        self.assertIn("n challenge solving failed", text)
        self.assertIn("outcome: error: YouTube blocked this download", text)
        p, ev = run_cli(["download", self.URL], "ok", self.dl, self.state)
        text = f.read_text()
        self.assertNotIn("Requested format", text)
        self.assertIn("outcome: done", text)

    def test_last_run_log_redacts_secrets(self):
        line = "WARNING: x Cookie: SAPISID=abc123; token=zzz sig=AOq0 visitor_data=Cgt"
        out = app_run._REDACT.sub(r"\1\2<redacted>", line)
        for secret in ("abc123", "zzz", "AOq0", "Cgt"):
            self.assertNotIn(secret, out)

    def test_last_run_log_failure_never_costs_the_download(self):
        blocker = self.tmp / "file-not-dir"
        blocker.write_text("x")
        p, ev = run_cli(["download", self.URL], "ok", self.dl, self.state,
                        extra_env={"ORION_LOG_DIR": str(blocker / "logs")})
        self.assertEqual(ev[-1]["stage"], "done", ev)


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
