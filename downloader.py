#!/usr/bin/env python3
"""
YouTube audio downloader — reliable, minimal, no fuss.
Usage: python3 downloader.py
"""

import os
import sys
import json
import shutil
import signal
import subprocess
from pathlib import Path

# ORION_DOWNLOADS overrides the output folder (the Orion app and tests); unset = ~/Downloads.
DOWNLOADS = Path(os.environ.get("ORION_DOWNLOADS") or (Path.home() / "Downloads"))

# Strategies tried silently in order until one works.
_STRATEGIES = [
    ["--cookies-from-browser", "firefox"],
    ["--cookies-from-browser", "safari"],
    ["--cookies-from-browser", "chrome"],
    ["--extractor-args", "youtube:player_client=android"],
    ["--extractor-args", "youtube:player_client=web"],
    [],
]


def strategies(app_order, cookies=True):
    """The strategy list. app_order=True (Beat Key app): non-cookie strategies first, the three
    browser-cookie ones last (cookies=False drops them). False (run.sh / CLI): the original order."""
    if not app_order:
        return list(_STRATEGIES)
    plain = [s for s in _STRATEGIES if s[:1] != ["--cookies-from-browser"]]
    if not cookies:
        return plain
    cookie = [s for s in _STRATEGIES if s[:1] == ["--cookies-from-browser"]]
    return plain + cookie


# ── Dependency check ──────────────────────────────────────────────────────────

def check_deps():
    missing = []
    if not shutil.which("yt-dlp"):
        missing.append(("yt-dlp", "double-click install.command"))
    if not shutil.which("ffmpeg"):
        missing.append(("ffmpeg", "double-click install.command"))
    return missing


# ── yt-dlp subprocess wrapper ─────────────────────────────────────────────────

class YtDlpTimeout(Exception):
    """A yt-dlp call ran past its timeout (app mode only; the CLI never sets one)."""


def _run(*args, exe="yt-dlp", timeout=None):
    if timeout is None:   # run.sh / CLI: exactly as before
        result = subprocess.run(
            [exe] + list(args),
            capture_output=True,
            text=True,
        )
        return result.returncode, result.stdout, result.stderr
    p = subprocess.Popen([exe] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         text=True, start_new_session=True)
    try:
        out, err = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)   # yt-dlp's one-file build forks a child
        except OSError:
            p.kill()
        try:
            p.communicate(timeout=5)
        except Exception:
            pass
        raise YtDlpTimeout()
    return p.returncode, out, err


def fetch_info(url, extra_args=(), exe="yt-dlp", timeout=None):
    code, out, err = _run("--dump-json", "--no-playlist", *extra_args, url, exe=exe, timeout=timeout)
    if code != 0 or not out.strip():
        return None, (out + err).splitlines()
    try:
        return json.loads(out.strip().splitlines()[-1]), []
    except (json.JSONDecodeError, ValueError):
        return None, (out + err).splitlines()


def download_audio(url, fmt_selector, outtmpl, extra_args=(), exe="yt-dlp", timeout=None):
    """
    Download audio. Returns (success, path_or_none, fmt_id, abr, error_lines).
    success=True whenever yt-dlp exits 0, regardless of whether we captured the path.
    """
    cmd_args = [
        "-f", fmt_selector,
        "-o", outtmpl,
        "--no-playlist",
        "--quiet",       # Keeps stdout clean for --print parsing
        "--no-progress",
        "--extract-audio",
        "--audio-format", "mp3",
        "--audio-quality", "0",
        "--print", "after_move:filepath",
        "--print", "%(format_id)s",
        "--print", "%(abr)s",
    ] + list(extra_args) + [url]

    code, out, err = _run(*cmd_args, exe=exe, timeout=timeout)

    if code != 0:
        return False, None, None, 0.0, (out + err).splitlines()

    # Exit 0 = success. Parse --print output from stdout.
    lines = (out or "").strip().splitlines()
    filepath = lines[0].strip() if len(lines) > 0 else None
    fmt_id   = lines[1].strip() if len(lines) > 1 else None
    abr_raw  = lines[2].strip() if len(lines) > 2 else "0"

    try:
        abr = float(abr_raw) if abr_raw not in ("", "NA", "none", "None") else 0.0
    except ValueError:
        abr = 0.0

    # Resolve path: use --print result if it exists, otherwise glob for the file.
    path = None
    if filepath:
        p = Path(filepath)
        if p.exists():
            path = p

    if path is None:
        # --print sometimes doesn't fire (e.g. already-cached, certain extractors).
        # Fall back: find the most recently modified file matching the title stem.
        stem = Path(outtmpl).stem.replace(".%(ext)s", "").replace("%", "")
        # outtmpl looks like /Users/.../Title.%(ext)s — stem is "Title"
        base = Path(outtmpl).parent
        stem_clean = Path(outtmpl).name.replace(".%(ext)s", "")
        matches = sorted(base.glob(f"{stem_clean}.*"), key=lambda p: p.stat().st_mtime, reverse=True)
        if matches:
            path = matches[0]

    return True, path, fmt_id, abr, []


# ── Format analysis ───────────────────────────────────────────────────────────

# ── Error translation ─────────────────────────────────────────────────────────

def explain_error(lines, url=""):
    text = " ".join(lines).lower()
    if "private video" in text:
        return "That video is private and cannot be downloaded."
    if "age" in text and ("restrict" in text or "confirm" in text):
        return "That video is age-restricted. Open YouTube in Firefox and sign in, then retry."
    if "not available" in text or "unavailable" in text:
        return "That video is unavailable in your region or has been removed."
    if "urlopen error" in text or "network" in text or "connection" in text:
        return "Network error — check your connection and try again."
    if "no video formats" in text or "requested format" in text:
        return "No downloadable audio format was found for that video."
    if "sign in" in text or "login" in text or "bot" in text:
        return "YouTube is blocking the download. Open YouTube in Firefox, sign in, then retry."
    if "copyright" in text:
        return "This video is blocked due to a copyright claim."
    if url and not url.startswith("http"):
        return "That doesn't look like a valid URL — paste a full https:// link."
    if lines:
        for line in reversed(lines):
            line = line.strip()
            if line and "github.com" not in line and "yt-dlp -U" not in line:
                return f"Download failed: {line}"
    return "Download failed for an unknown reason."


_FINAL_MESSAGES = (
    "That video is private and cannot be downloaded.",
    "That video is unavailable in your region or has been removed.",
    "That doesn't look like a valid URL — paste a full https:// link.",
)


def is_final_error(lines, url=""):
    """True when the error says the link itself is dead (private / unavailable / removed /
    invalid): no other strategy, cookies or yt-dlp upgrade can fix it."""
    return explain_error(lines, url) in _FINAL_MESSAGES


TIMEOUT_MESSAGE = "Download timed out."


def safe_name(text):
    for ch in r'\/:*?"<>|[]':
        text = text.replace(ch, "_")
    return text.strip(". ") or "audio"


# ── Main ──────────────────────────────────────────────────────────────────────

def run_download(url, silent=False, app_order=False, ytdlp=None, timeout=None, cookies=True):
    """
    Download one URL. Returns the output Path on success, None on failure.
    If silent=True, errors go to stderr and only the filepath is printed to stdout
    (for use when called from a shell script).

    The last three arguments are for the Beat Key app (app_order=True) and are ignored otherwise:
    ytdlp = the yt-dlp executable, timeout = seconds per yt-dlp call (a timeout is reported as
    "Download timed out."), cookies=False = skip the browser-cookie strategies. In app mode a
    link that is private / unavailable / removed / invalid stops before the cookie strategies.
    """
    info = None
    meta_err = []
    working_extra = None
    exe = "yt-dlp"
    if app_order:
        exe = ytdlp or "yt-dlp"
    else:
        timeout = None
        cookies = True
    order = strategies(app_order, cookies)
    kw = {"exe": exe, "timeout": timeout}

    def _fail(msg):
        print(msg, file=sys.stderr) if silent else print(msg)
        return None

    for extra in order:
        if app_order and extra[:1] == ["--cookies-from-browser"] and meta_err \
                and is_final_error(meta_err, url):
            break   # the plain attempts say the link is dead: cookies cannot help
        try:
            info, meta_err = fetch_info(url, extra_args=extra, **kw)
        except YtDlpTimeout:
            return _fail(TIMEOUT_MESSAGE)
        except Exception as exc:
            meta_err = [str(exc)]
            info = None
        if info:
            working_extra = extra
            break

    if not info:
        msg = explain_error(meta_err, url)
        if silent:
            print(msg, file=sys.stderr)
        else:
            print(msg)
        return None

    title = safe_name(info.get("title") or "audio")
    if not silent:
        print("Downloading...")
    baseline_tmpl = str(DOWNLOADS / f"{title}.%(ext)s")
    last_err = []

    strategies_to_try = [working_extra] + [s for s in order if s != working_extra]

    success = False
    bl_path = None

    for extra in strategies_to_try:
        try:
            success, bl_path, _, _, last_err = download_audio(
                url, "bestaudio/best", baseline_tmpl, extra_args=extra, **kw
            )
        except YtDlpTimeout:
            return _fail(TIMEOUT_MESSAGE)
        except Exception as exc:
            last_err = [str(exc)]
            success = False
        if success:
            break

    if not success:
        msg = explain_error(last_err, url)
        if silent:
            print(msg, file=sys.stderr)
        else:
            print(msg)
        return None

    if silent:
        # Print only the filepath so the caller can capture it
        print(str(bl_path) if bl_path else "")
    else:
        if bl_path:
            print(f"Downloaded: {bl_path.name}")
        else:
            print(f"Downloaded to: {DOWNLOADS}")

    return bl_path


def main():
    missing = check_deps()
    if missing:
        print("Missing required tools:\n")
        for name, hint in missing:
            print(f"  {name}")
            print(f"    Install: {hint}\n")
        sys.exit(1)

    # Called with a URL argument — single-shot mode for scripts
    if len(sys.argv) > 1:
        url = sys.argv[1].strip()
        result = run_download(url, silent=True)
        sys.exit(0 if result else 1)

    # Interactive loop mode
    while True:
        try:
            url = input("\nInput URL: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not url:
            break
        run_download(url, silent=False)


if __name__ == "__main__":
    main()
