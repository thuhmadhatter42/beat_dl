"""A damaged analyzer says so: no backup tempo method. bpm.py in file mode refuses (exit 2, one line
on stderr naming Doctor, nothing on stdout) when essentia or its tempo model is missing; app_run.py
turns that into the app's one error event and leaves the file alone.
Run with the bundled Python: bin/python/bin/python3 -m unittest discover -s tests"""
import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
WAV = ROOT / "tests" / "fixtures" / "click120.wav"

import app_run  # noqa: E402

MESSAGE = "The analyzer is incomplete. Run Doctor."

# bpm.py's file mode with both tempo model paths pointed at a file that does not exist
_NO_MODEL = (
    "import sys; sys.path.insert(0, {root!r}); import bpm; "
    "bpm.TEMPOCNN_MODEL = bpm.TEMPOCNN_WEIGHTS = bpm.HERE / 'models' / 'no-such-model'; "
    "sys.argv = ['bpm.py', {wav!r}]; bpm.main()"
)
_NO_ESSENTIA = (
    "import sys; sys.path.insert(0, {root!r}); import bpm; "
    "bpm._have_essentia = lambda: False; "
    "sys.argv = ['bpm.py', {wav!r}]; bpm.main()"
)


def run_bpm(template):
    code = template.format(root=str(ROOT), wav=str(WAV))
    return subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, timeout=120)


class TestBpmRefuses(unittest.TestCase):
    def test_missing_model_exits_nonzero_names_doctor_prints_no_bpm(self):
        p = run_bpm(_NO_MODEL)
        self.assertNotEqual(p.returncode, 0, (p.stdout, p.stderr))
        self.assertEqual(p.stdout, "", "no BPM line, from any method")
        self.assertEqual(p.stderr.strip(), MESSAGE)

    def test_no_essentia_exits_nonzero_names_doctor_prints_no_bpm(self):
        p = run_bpm(_NO_ESSENTIA)
        self.assertNotEqual(p.returncode, 0, (p.stdout, p.stderr))
        self.assertEqual(p.stdout, "")
        self.assertEqual(p.stderr.strip(), MESSAGE)

    def test_the_analyzer_has_no_second_method(self):
        text = (ROOT / "bpm.py").read_text().lower()
        self.assertNotIn("librosa", text)


class TestAppRunReportsIt(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.tmp = Path(self._t.name)
        self.f = self.tmp / "Test Beat.mp3"
        shutil.copy(WAV, self.f)
        self.refused = subprocess.CompletedProcess([], 2, stdout="", stderr=MESSAGE + "\n")

    def tearDown(self):
        self._t.cleanup()

    def _run(self, fn, *args):
        out, err = io.StringIO(), io.StringIO()
        env = {"ORION_DOWNLOADS": str(self.tmp), "ORION_LOG_DIR": str(self.tmp / "logs")}
        with mock.patch.dict(os.environ, env), \
                mock.patch.object(app_run.subprocess, "run", return_value=self.refused), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            fn(*args)
        return [json.loads(l) for l in out.getvalue().splitlines() if l.strip()], err.getvalue()

    def test_analyze_reports_the_error_once_and_leaves_the_file(self):
        ev, err = self._run(app_run.cmd_analyze, [str(self.f), str(self.f)])
        term = [e for e in ev if e["stage"] in ("analyzed", "error")]
        self.assertEqual([e["stage"] for e in term], ["error"], ev)
        self.assertEqual(term[0]["message"], MESSAGE)
        self.assertIn("Run Doctor", err)
        self.assertTrue(self.f.is_file())

    def test_download_does_not_rename_and_reports_the_error(self):
        with mock.patch.object(app_run, "_attempt", return_value=(self.f, "")):
            ev, err = self._run(app_run.cmd_download, "https://example.com/v")
        term = [e for e in ev if e["stage"] in ("done", "analyzed", "error")]
        self.assertEqual([e["stage"] for e in term], ["error"], ev)
        self.assertEqual(term[0]["message"], MESSAGE)
        self.assertNotIn("renaming", [e["stage"] for e in ev])
        self.assertEqual(sorted(p.name for p in self.tmp.glob("*.mp3")), ["Test Beat.mp3"])
        self.assertIn("Run Doctor", err)

    def test_other_analyzer_failures_are_unchanged(self):
        self.refused = subprocess.CompletedProcess([], 1, stdout="", stderr="ValueError: bad file\n")
        ev, _ = self._run(app_run.cmd_analyze, [str(self.f)])
        self.assertEqual(ev[-1]["stage"], "analyzed")
        self.assertIsNone(ev[-1]["bpm"])


if __name__ == "__main__":
    unittest.main()
