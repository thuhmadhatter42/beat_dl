#!/usr/bin/env python3
"""
Orchestrator for the Orion app. The Swift app spawns this and renders its JSON-lines events.

  app_run.py download <url>
  app_run.py analyze <file>...

One JSON object per stdout line, flushed. Exit code 0 unless the process itself crashed.
Output matches run.sh: rename "<stem> (<bpm> BPM <k1> <k2> <k3>).<ext>", log entry
"Input URL: <url>\\nDownloaded: <name>\\n\\n" in "<Downloads>/(YY-M-D) Youtube DL LINKS.txt".
The Downloads folder comes from ORION_DOWNLOADS (default ~/Downloads).
"""

import contextlib
import io
import json
import os
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import downloader  # noqa: E402

_KEY_RE = re.compile(r"^(.*?)\s*\((\d+(?:\.\d+)?)%\)\s*$")


def emit(**event):
    sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def downloads_dir():
    return Path(os.environ.get("ORION_DOWNLOADS") or (Path.home() / "Downloads"))


def log_path():
    d = date.today()
    return downloads_dir() / f"({d.year % 100}-{d.month}-{d.day}) Youtube DL LINKS.txt"


def renamed_name(stem, ext, bpm, keys):
    ks = " ".join(k for k, _ in keys)
    return f"{stem} ({bpm} BPM {ks}).{ext}"


def log_line(url, name):
    return f"Input URL: {url}\nDownloaded: {name}\n\n"


def analyze_file(path, timeout=120):
    """Run bpm.py on a file. Returns (bpm_string | None, [(key, percent_int), ...])."""
    try:
        p = subprocess.run([sys.executable, str(HERE / "bpm.py"), str(path)],
                           capture_output=True, text=True, timeout=timeout)
    except (subprocess.TimeoutExpired, OSError):
        return None, []
    if p.returncode != 0:
        return None, []
    lines = p.stdout.splitlines()
    if not lines:
        return None, []
    bpm = lines[0].strip()
    try:
        float(bpm)
    except ValueError:
        return None, []
    keys = []
    for line in lines[1:4]:
        m = _KEY_RE.match(line.strip())
        if m:
            keys.append((m.group(1), int(round(float(m.group(2))))))
    return bpm, keys


def _attempt(url):
    """One run_download pass. Returns (Path | None, message_text)."""
    out, err = io.StringIO(), io.StringIO()
    path = None
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            path = downloader.run_download(url, silent=True, app_order=True)
        except Exception as exc:  # keep the process alive; report as a download error
            err.write(f"Download failed: {exc}\n")
    msg = (err.getvalue() or out.getvalue()).strip()
    return path, msg


def _upgrade_ytdlp():
    try:
        subprocess.run(["yt-dlp", "-U"], capture_output=True, text=True, timeout=180)
    except (subprocess.TimeoutExpired, OSError):
        pass


def cmd_download(url):
    emit(stage="downloading")
    path, msg = _attempt(url)
    if not path:
        emit(stage="updating")
        _upgrade_ytdlp()
        emit(stage="downloading")
        path, msg = _attempt(url)
    if not path:
        emit(stage="error", message=msg or "Download failed for an unknown reason.")
        return

    emit(stage="analyzing")
    try:
        bpm, keys = analyze_file(path)
    except Exception:
        bpm, keys = None, []
    final = path
    if bpm:
        try:
            emit(stage="renaming")
            new = path.with_name(renamed_name(path.stem, path.suffix.lstrip("."), bpm, keys))
            os.replace(path, new)
            final = new
        except Exception:
            # Rename failed: keep the original file and its analysis.
            final = path
            if not final.exists():
                emit(stage="error", message="Could not rename the downloaded file.")
                return
    else:
        keys = []

    try:
        downloads_dir().mkdir(parents=True, exist_ok=True)
        with open(log_path(), "a", encoding="utf-8") as f:
            f.write(log_line(url, final.name))
    except Exception:
        pass  # a log failure must not lose the done event
    emit(stage="done", file=str(final), name=final.name, bpm=bpm or None,
         keys=[[k, p] for k, p in keys])


def cmd_analyze(files):
    for raw in files:
        path = Path(raw).expanduser()
        emit(stage="analyzing")
        try:
            bpm, keys = analyze_file(path)
        except Exception:
            bpm, keys = None, []
        try:
            full = str(path.resolve())
        except Exception:
            full = str(path)
        emit(stage="analyzed", file=full, name=path.name,
             bpm=bpm or None, keys=[[k, p] for k, p in keys])


def main(argv):
    try:
        return _main(argv)
    except BaseException as exc:  # last resort: the app always gets a terminal event
        if isinstance(exc, KeyboardInterrupt):
            raise
        emit(stage="error", message=f"Unexpected error: {exc}")
        return 0


def _main(argv):
    if len(argv) >= 3 and argv[1] == "download":
        cmd_download(argv[2].strip())
    elif len(argv) >= 3 and argv[1] == "analyze":
        cmd_analyze(argv[2:])
    else:
        emit(stage="error", message="usage: app_run.py download <url> | analyze <file>...")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
