# beat_dl

Download YouTube beats as WAVs, auto-tagged with BPM and key.

Tested and working on both Apple Silicon and Intel Macs.

## Setup

**Double-click `install.command`** — it handles everything:
- Installs Homebrew (if not already installed)
- Installs yt-dlp and ffmpeg via Homebrew
- Installs librosa for BPM and key detection
- Makes all scripts executable

> **First time opening a `.command` file?** macOS will block it since it wasn't downloaded from the App Store. Just **right-click → Open** the first time, then it'll work normally after that.

## Usage

**Double-click `run.command`** to start.

Paste a YouTube URL when prompted. After each download:
- Audio is saved as WAV to `~/Downloads`
- BPM is detected by analyzing the loudest 60 seconds of the track
- The top 3 most likely keys are shown with confidence percentages
- The file is automatically renamed with BPM and keys included

**Example output:**
```
Input URL: https://www.youtube.com/watch?v=...
Downloading...
Downloaded: Veeze x Lil Yachty type beat (142.0 BPM Cm D# Gm).wav
Key: Cm (48.3%) | D# (31.2%) | Gm (20.5%)
```

Keep pasting URLs until you're done, then press Enter on a blank line or Ctrl+C to quit.

## YouTube Login Requirement

YouTube now requires a sign-in to download most videos. Before running the tool:

1. Open **Chrome**
2. Go to **youtube.com** and make sure you're logged in
3. Run the tool — it will pull your cookies from Chrome automatically

This works on both Apple Silicon and Intel Macs.

## Files

| File | Description |
|------|-------------|
| `install.command` | Double-click once to install everything |
| `run.command` | Double-click to run |
| `run.sh` | Main loop — called by run.command |
| `downloader.py` | Downloads audio from YouTube as WAV |
| `bpm.py` | Detects BPM and key from an audio file |

The Python scripts also work standalone if you need them:

```bash
python3 downloader.py                  # interactive loop
python3 downloader.py <url>            # single download
python3 bpm.py <file>                  # analyze a file
```
