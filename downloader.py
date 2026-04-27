#!/usr/bin/env python3
"""
YouTube audio downloader — reliable, minimal, no fuss.
Usage: python3 downloader.py
"""

import sys
import shutil
from pathlib import Path

import yt_dlp

AUDIO_FORMAT = "wav"  # "wav" or "mp3"

DOWNLOADS = Path.home() / "Downloads"


# ── Dependency check ──────────────────────────────────────────────────────────

def check_deps():
    missing = []
    if not shutil.which("ffmpeg"):
        missing.append(("ffmpeg", "brew install ffmpeg   or   https://ffmpeg.org/download.html"))
    return missing


# ── Error translation ─────────────────────────────────────────────────────────

def explain_error(text, url=""):
    text = text.lower()
    if "private video" in text:
        return "That video is private and cannot be downloaded."
    if "age" in text and ("restrict" in text or "confirm" in text):
        return "That video is age-restricted. Sign in to YouTube in your browser and retry."
    if "not available" in text or "unavailable" in text:
        return "That video is unavailable in your region or has been removed."
    if "urlopen error" in text or "network" in text or "connection" in text:
        return "Network error — check your connection and try again."
    if "no video formats" in text or "requested format" in text:
        return "No downloadable audio format was found for that video."
    if "sign in" in text or "login" in text or "bot" in text:
        return "YouTube is blocking the download. Sign in to YouTube in your browser and retry."
    if "copyright" in text:
        return "This video is blocked due to a copyright claim."
    if url and not url.startswith("http"):
        return "That doesn't look like a valid URL — paste a full https:// link."
    return f"Download failed: {text.strip()}" if text.strip() else "Download failed for an unknown reason."


def safe_name(text):
    for ch in r'\/:*?"<>|[]':
        text = text.replace(ch, "_")
    return text.strip(". ") or "audio"


# ── BPM + key tagging ────────────────────────────────────────────────────────

def tag_with_bpm(path: Path, silent: bool) -> Path:
    """Analyze path, rename to include BPM and top 3 keys, return new path."""
    try:
        from bpm import analyze, check_deps as bpm_check
        if not bpm_check():
            return path
        if not silent:
            print("Analyzing...")
        bpm, keys = analyze(path)
        key_str = " ".join(k for k, _ in keys)
        new_name = f"{path.stem} ({bpm} BPM {key_str}){path.suffix}"
        new_path = path.parent / new_name
        path.rename(new_path)
        if not silent:
            top = keys[0]
            rest = keys[1:]
            key_display = f"{top[0]} ({top[1]}%)" + "".join(f" | {k} ({c}%)" for k, c in rest)
            print(f"Key: {key_display}")
        return new_path
    except Exception:
        return path


# ── Download ──────────────────────────────────────────────────────────────────

def run_download(url, silent=False):
    """
    Download one URL, analyze BPM + key, rename the file.
    Returns the final output Path on success, None on failure.
    If silent=True, only the final filepath is printed to stdout.
    """
    ydl_opts = {
        "format": "bestaudio/best",
        "outtmpl": str(DOWNLOADS / "%(title)s.%(ext)s"),
        "quiet": True,
        "no_warnings": True,
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": AUDIO_FORMAT,
            }
        ],
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            if not silent:
                print("Downloading...")
            info = ydl.extract_info(url, download=True)
            entry = info["entries"][0] if "entries" in info else info
            pre_path = ydl.prepare_filename(entry)
            out_path = Path(pre_path).with_suffix(f".{AUDIO_FORMAT}")

            if not out_path.exists():
                msg = f"Expected file not found: {out_path}"
                print(msg, file=sys.stderr if silent else sys.stdout)
                return None

            final_path = tag_with_bpm(out_path, silent)

            if not silent:
                print(f"Downloaded: {final_path.name}")
            else:
                print(str(final_path))
            return final_path

    except yt_dlp.utils.DownloadError as e:
        msg = explain_error(str(e), url)
        print(msg, file=sys.stderr if silent else sys.stdout)
        return None
    except Exception as e:
        msg = f"Download failed: {e}"
        print(msg, file=sys.stderr if silent else sys.stdout)
        return None


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

    # Interactive mode
    try:
        url = input("Input URL: ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        sys.exit(0)
    if url:
        run_download(url, silent=False)


if __name__ == "__main__":
    main()
