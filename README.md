# beat_dl

Download YouTube beats as MP3s, auto-tagged with BPM and key.

Tested and working on both Apple Silicon and Intel Macs.

## Setup

**Double-click `run.command`.** On first launch it installs anything missing (Homebrew, yt-dlp, ffmpeg, essentia-tensorflow, librosa as fallback) and then starts. `install.command` still exists if you want to install without starting the app.

Every launch re-checks that the tools are present (instant, no network). yt-dlp is the only one that goes stale, so it's upgraded once a week, and again automatically if a download fails.

> **First time opening a `.command` file?** macOS will block it since it wasn't downloaded from the App Store. Just **right-click → Open** the first time, then it'll work normally after that.

## Usage

**Double-click `run.command`** to start.

Paste a YouTube URL when prompted. After each download:
- Audio is saved as MP3 to `~/Downloads`
- BPM is detected on the whole track with Essentia's TempoCNN neural net (`models/deeptemp-k16-3.pb`, ships in the repo, runs offline; 87.5% exact-tempo accuracy on the benchmark in `docs/research/` vs 30% for the old librosa method). If essentia-tensorflow is missing it falls back to librosa.
- Key is detected on the whole track with Essentia's HPCP chroma (36-bin, spectral whitening, detuning correction) scored against Faraldo's EDM `bgate` profiles for all 24 keys — 85.1 MIREX-weighted / 79.5% exact on the GiantSteps+ benchmark in `docs/research/` vs 55.4 / 43.6% for the old librosa Krumhansl method. The top 3 keys are printed with a confidence percentage: the first is from segment agreement + score margin (measured on 39 EDM clips with this exact code: ≥ 85% shown → 85% right, 70–85% → 75%; not a calibrated probability), the other two share what's left. Truth is in the top 3 on 92% of the benchmark.
- librosa is fallback-only now (used for BPM and key only if essentia-tensorflow is missing); deps.sh still installs it and repairs a numba/numpy mismatch that would break its import
- The file is automatically renamed with BPM and keys included
- Each successful download is appended to `~/Downloads/(YY-M-D) Youtube DL LINKS.txt` as an `Input URL` / `Downloaded` entry

For example, downloads on May 12, 2026 are logged to:

```text
~/Downloads/(26-5-12) Youtube DL LINKS.txt
```

The link log looks like this:

```text
Input URL: https://www.youtube.com/watch?v=...
Downloaded: Veeze x Lil Yachty type beat (142.0 BPM Cm D# Gm).mp3

Input URL: https://www.youtube.com/watch?v=...
Downloaded: Another Beat Name (95.0 BPM Am C Em).mp3
```

**Example output:**
```
Input URL: https://www.youtube.com/watch?v=...
Downloading...
Downloaded: Veeze x Lil Yachty type beat (142.0 BPM Cm D# Gm).mp3
Key: Cm (90.0%) | D# (4.1%) | Gm (2.7%)
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
| `install.command` | Install deps without starting the app (optional) |
| `deps.sh` | Dependency check/install, used by both launchers |
| `run.command` | Double-click to run |
| `run.sh` | Main loop — called by run.command |
| `downloader.py` | Downloads audio from YouTube as MP3 |
| `bpm.py` | Detects BPM and key from an audio file |

The Python scripts also work standalone if you need them:

```bash
python3 downloader.py                  # interactive loop
python3 downloader.py <url>            # single download
python3 bpm.py <file>                  # analyze a file
```
