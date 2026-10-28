#!/usr/bin/env python3
"""
Orchestrator for the Orion app. The Swift app spawns this and renders its JSON-lines events.

  app_run.py download <url> [--cookies-file <path>]
  app_run.py analyze <file>...

One JSON object per stdout line, flushed. Exit code 0 unless the process itself crashed.
Output matches run.sh: rename "<stem> (<bpm> BPM <k1> <k2> <k3>).<ext>", log entry
"Input URL: <url>\\nDownloaded: <name>\\n\\n" in "<Downloads>/(YY-M-D) Youtube DL LINKS.txt".
The Downloads folder comes from ORION_DOWNLOADS (default ~/Downloads).
ORION_YTDLP = the yt-dlp to use (the app's copy in Application Support). It runs the downloads
and is the only file `-U` ever touches; unset or missing = no upgrade step (never PATH).
ORION_YTDLP_TIMEOUT = seconds allowed per yt-dlp call (default 600).
ORION_DENO = the bundled JavaScript runtime, passed to yt-dlp as --js-runtimes deno:<path>.
Every download writes its yt-dlp stderr to ~/Library/Logs/Beat Key/last-run.log (ORION_LOG_DIR
overrides the folder), overwritten each run.
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


YTDLP_TIMEOUT = 600


def ytdlp_path():
    """The app's yt-dlp (ORION_YTDLP) if it exists, else None."""
    p = os.environ.get("ORION_YTDLP")
    if p and os.path.isfile(p) and os.access(p, os.X_OK):
        return p
    return None


def ytdlp_timeout():
    try:
        return float(os.environ.get("ORION_YTDLP_TIMEOUT") or YTDLP_TIMEOUT)
    except ValueError:
        return YTDLP_TIMEOUT


def _attempt(url, cookies_file=None, raw=None):
    """One run_download pass. Returns (Path | None, message_text). raw (a list) receives yt-dlp's
    raw error lines."""
    out, err = io.StringIO(), io.StringIO()
    path = None
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            path = downloader.run_download(url, silent=True, app_order=True, ytdlp=ytdlp_path(),
                                           timeout=ytdlp_timeout(), cookies_file=cookies_file,
                                           raw_errors=raw)
        except Exception as exc:  # keep the process alive; report as a download error
            err.write(f"Download failed: {exc}\n")
    msg = (err.getvalue() or out.getvalue()).strip()
    return path, msg


def _upgrade_ytdlp():
    """`yt-dlp -U` on ORION_YTDLP only. Returns False (and does nothing) when that is unset or
    missing: never PATH, which could be the copy inside the signed bundle."""
    exe = ytdlp_path()
    if not exe:
        return False
    try:
        subprocess.run([exe, "-U"], capture_output=True, text=True, timeout=180)
    except (subprocess.TimeoutExpired, OSError):
        pass
    return True


LOGIN_MESSAGES = {
    "age": "This video is age-restricted. A YouTube login is needed.",
    "bot": "YouTube wants a login before it will serve this video.",
    "members": "This video is for channel members. A YouTube login is needed.",
}


def needs_login(reason, stale=False):
    """stale = the saved login was used and YouTube no longer takes it: the app deletes it and
    asks for a new one."""
    extra = {"stale": True} if stale else {}
    emit(stage="needs_login", reason=reason, message=LOGIN_MESSAGES[reason], **extra)


def keep_private(path):
    """yt-dlp writes the cookie jar back after a run; keep the file owner-only whatever it did."""
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


# The last download's yt-dlp stderr, overwritten every run, for whoever debugs the next failure.
# ORION_LOG_DIR overrides the folder (tests).
_REDACT = re.compile(r"(?i)\b(cookie|cookies|authorization|sapisid\w*|po_?token|visitor_?data|"
                     r"token|key|sig|signature)(\s*[=:]\s*)([^\s&,;'\"]+)")


def last_run_log_path():
    d = os.environ.get("ORION_LOG_DIR")
    base = Path(d) if d else Path.home() / "Library" / "Logs" / "Beat Key"
    return base / "last-run.log"


def write_last_run_log(url, cookies_file, outcome):
    try:
        lines = [f"Beat Key last run  {date.today().isoformat()}",
                 f"url: {url}", f"login: {'saved YouTube login' if cookies_file else '-'}", f"outcome: {outcome}", ""]
        for argv, code, err in downloader.RUN_LOG:
            lines.append(f"$ {' '.join(argv)}")
            lines.append(f"exit: {'timeout' if code is None else code}")
            lines.extend(_REDACT.sub(r"\1\2<redacted>", l) for l in err.splitlines())
            lines.append("")
        p = last_run_log_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    except Exception:
        pass  # the log must never cost a download


def cmd_download(url, cookies_file=None):
    downloader.RUN_LOG.clear()
    outcome = ["crashed"]
    try:
        _cmd_download(url, cookies_file, outcome)
    finally:
        if cookies_file:
            keep_private(cookies_file)
        write_last_run_log(url, cookies_file, outcome[0])


def _cmd_download(url, cookies_file, outcome):
    emit(stage="downloading")
    raw = []
    path, msg = _attempt(url, cookies_file=cookies_file, raw=raw)
    if not path:
        reason = downloader.login_reason(raw)
        if cookies_file and (reason or downloader.cookies_stale(raw)):
            # the saved login did not get past YouTube: the app throws it away and asks again
            outcome[0] = "needs_login: saved login no longer works"
            needs_login(reason or "age", stale=True)
            return
        if reason:
            outcome[0] = f"needs_login: {reason}"
            needs_login(reason)
            return
    if not cookies_file:
        # A dead link (private / unavailable / removed / invalid) or a timeout: an upgrade will
        # not help and a retry would only repeat the wait. Report it.
        hopeless = msg == downloader.TIMEOUT_MESSAGE or msg in downloader._FINAL_MESSAGES
        if not path and not hopeless and ytdlp_path():
            emit(stage="updating")
            if _upgrade_ytdlp():
                emit(stage="downloading")
                raw = []
                path, msg = _attempt(url, raw=raw)
                if not path:
                    reason = downloader.login_reason(raw)
                    if reason:
                        outcome[0] = f"needs_login: {reason}"
                        needs_login(reason)
                        return
    if not path:
        msg = msg or "Download failed for an unknown reason."
        outcome[0] = f"error: {msg}"
        emit(stage="error", message=msg)
        return
    outcome[0] = "downloaded"

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
    outcome[0] = "done"
    emit(stage="done", file=str(final), name=final.name, bpm=bpm or None,
         keys=[[k, p] for k, p in keys])


def read_error(path):
    """'permission' when macOS refuses to let us read the file (EPERM/EACCES), else None."""
    try:
        with open(path, "rb") as f:
            f.read(1)
    except PermissionError:
        return "permission"
    except OSError:
        return None
    return None


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
        extra = {}
        if not bpm and read_error(path):
            extra["error"] = "permission"
        emit(stage="analyzed", file=full, name=path.name,
             bpm=bpm or None, keys=[[k, p] for k, p in keys], **extra)


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
        cookies_file = None
        if "--cookies-file" in argv[3:]:
            i = argv.index("--cookies-file", 3)
            cookies_file = argv[i + 1] if i + 1 < len(argv) else ""
            if not cookies_file or not os.path.isfile(cookies_file):
                # the saved login is gone: ask for one again rather than run without it
                needs_login("age", stale=True)
                return 0
        cmd_download(argv[2].strip(), cookies_file)
    elif len(argv) >= 3 and argv[1] == "analyze":
        cmd_analyze(argv[2:])
    else:
        emit(stage="error", message="usage: app_run.py download <url> [--cookies-file <path>] | analyze <file>...")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
