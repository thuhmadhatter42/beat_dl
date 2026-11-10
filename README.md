# beat_dl

Download YouTube beats as MP3s, auto-tagged with BPM and key.

**Three keys, not one.** Key finders disagree: run a beat through Key Finder, Mixed In Key and Auto-Key and you can get three different answers, then try all three by ear. Beat Key gives you its top 3 keys up front, each with a confidence percentage, and puts all three in the filename (`Some Beat (140.0 BPM Cm Eb Gm).mp3`). The right key is in those three on 92% of the GiantSteps+ benchmark.

Tested and working on both Apple Silicon and Intel Macs.

## Beat Key app

Beat Key is the same tool as a normal Mac app. No Terminal, nothing to install first.

1. Download the Beat Key disk image (the `.dmg` file) and double-click it.
2. Drag **Beat Key** onto the **Applications** folder in the window that opens.
3. Open **Beat Key** from Applications. The first time, macOS asks "Are you sure you want to open it?". Click **Open**.
4. Paste a YouTube link and press Return. The MP3 lands in your Downloads folder with the BPM and key in its name, for example `Some Beat (140.0 BPM Cm Eb Gm).mp3`.
5. To read the BPM and key of a file you already have, drop the audio file onto the Beat Key window. The file isn't changed.

If macOS asks whether Beat Key may access your Downloads folder, click **Allow**. Needs macOS 12 or newer, on Apple Silicon or Intel. yt-dlp updates itself weekly, and Beat Key updates itself too (Beat Key > Check for Updates, plus a daily check; Sparkle); there is nothing to maintain. Beat Key is the free product on fourletterrecords.com (download behind a Four Letter Records account). Age-restricted videos ask you to log in to YouTube once, inside Beat Key's own window; it never reads your browser or asks for Full Disk Access. Licences for every bundled part are under Beat Key › Licenses and in `THIRD-PARTY-LICENSES.md`.

### What else Beat Key does

Everything is under the menus or in Settings (Beat Key > Settings, ⌘,). The global shortcuts work in any app and can be changed or turned off in Settings.

- **Live listening.** Reading > Start Listening (⌃⌥⌘K) reads the BPM and key of whatever is playing, as it plays, and keeps refining. It listens to the Mac's sound (macOS 13 or newer; when a player app such as Spotify, Music or a browser is open it hears only the players, so a DAW or microphone bleed does not skew the key), the default input, or a microphone or interface you pick, one channel or all. It starts over after 2, 3, 5 or 10 seconds of silence (your choice). Nothing is recorded or saved.
- **Menu-bar readout.** The coloured key and BPM (for example `Ebm 128`) sit in the menu bar; no key is shown until the reading has locked. Click it to start or stop listening, analyze a file, or open Settings.
- **Confidence lights and shapes.** Green octagon = locked, amber triangle = unsure, red circle = listening or analyzing. The shape means colour is never the only signal. View > High Contrast Readout (also in Settings) makes the display brighter.
- **Decimal BPM, half and double.** The BPM shows with two decimals (`140.82`). Reading > Half / Double Tempo, or clicking the BPM on the display, cycles between the reading, double and half.
- **Advanced Mode.** View > Advanced Mode (⌥⌘A, or Settings > Display, off by default) widens the window with the Camelot code and relative key, a key wheel (click a key to choose it), the notes heard, a chord strip (click to hear, drag a chord into a DAW as a .mid) and a MATCH TO row (−6 to +6).
- **Tuning.** The display shows how many cents sharp or flat the track sits against a reference pitch. Reading > Reference Pitch: A = 432, 436, 438, 440, 442, 444, 450, or Custom (400 to 480 Hz).
- **Files.** MP3, WAV, AIFF, FLAC, M4A, AAC, OGG, CAF, MP4, M4V, MOV and MIDI (.mid). For video the audio track is read. The file isn't changed.
- **Analyze a File.** File > Analyze a File… (⌃⌥⌘F, global), drop files on the window or the Dock icon, Open With, or in Finder right-click > Services > Analyze with Beat Key.
- **Recent readings.** File > Recent Readings puts an earlier reading back on the display. Clear Menu empties it.
- **Send to DAW.** Reading > Send to DAW (⌃⌥⌘S) sends the decimal BPM and top key to the DAW you used last; Send to All DAWs (⌃⌥⌘D) sends to every open one. What each gets:
  - Ableton Live 12: tempo and key. Live 11: tempo only. Through a small Remote Script Beat Key offers to install (then pick BeatKey as a Control Surface once, in Live > Settings > Link, Tempo & MIDI).
  - REAPER: tempo (REAPER has no project key). Bitwig Studio: tempo (no project key). Each through a script Beat Key offers to install (REAPER: a ReaScript you start once; Bitwig: a controller you add once).
  - Pro Tools, Logic Pro, Studio One: tempo and key, typed into the DAW's own tempo and key controls through Accessibility. If a value can't be confirmed, nothing is sent (Export MIDI makes a file for any DAW).
  - FL Studio, Reason, Cubase: a MIDI file with tempo and key to import (they can't be told a tempo from outside).
- **Analyze Selection.** Reading > Analyze Selection (no shortcut by default; give it one in Settings › Shortcuts, works in any app) reads the clip you have selected in Pro Tools, Ableton Live or REAPER. Other DAWs: export the clip and drop it on Beat Key.
- **Choose the key.** The top 3 keys are clickable: click key 2 or 3 and that becomes THE key for every send (New Song clears it).
- **Send to Auto-Tune.** One button (Reading > Send to Auto-Tune, ⌃⌥⌘A) hands the chosen key and your reference pitch to Auto-Tune Pro, in any open instance with Auto Key Detection on, and also writes a Waves Tune preset. Waves Tune does not change by itself: load the "Beat Key" preset in the plug-in (as of 0.1.31). Antares doesn't document the hand-off, so tell us if a version doesn't pick it up.
- **Export MIDI Tempo/Key file.** File > Export MIDI Tempo/Key File… (⌃⌥⌘E) saves a small `.mid` with the tempo and key, for any DAW.
- **Open at login.** Settings > General > Open at Login.
- **Log.** `~/Library/Logs/Beat Key/beatkey.log` records launches, quits and crashes (analyzer output in `analyzer.log`); send it with a bug report.

Permissions macOS may ask for, each only when you use the feature:

- **Microphone**: listening to a microphone or audio interface.
- **Screen & System Audio Recording**: listening to everything the Mac plays. Beat Key takes only the sound; it doesn't capture or keep your screen.
- **Accessibility**: Send to DAW for Pro Tools, Logic Pro and Studio One (Beat Key fills in their tempo and key controls). Without it, Beat Key asks once and sends nothing.

The sections below are for the command-line version.

## Setup

**Double-click `run.command`.** On first launch it installs anything missing (yt-dlp, ffmpeg and ffprobe ship inside the repo in `vendor/` — no Homebrew, no downloads — and so does the BPM/key analyzer: a standalone Python 3.11 with Essentia, unpacked into `bin/python` on first launch, offline, about a minute) and then starts. `install.command` still exists if you want to install without starting the app.

Every launch re-checks that the tools are present (instant, no network). yt-dlp is the only one that goes stale, so it's upgraded once a week, and again automatically if a download fails.

> **First time opening a `.command` file?** macOS will block it since it wasn't downloaded from the App Store. Just **right-click → Open** the first time, then it'll work normally after that.

## Usage

**Double-click `run.command`** to start.

Paste a YouTube URL when prompted. After each download:
- Audio is saved as MP3 to `~/Downloads`
- BPM is detected on the whole track with Essentia's TempoCNN neural net (weights in `models/deeptemp-k16-3.npz`, run in numpy by `tempocnn_np.py`, offline; 87.5% exact-tempo accuracy on the benchmark in `docs/research/` vs 30% for the old librosa method). Same numbers as Essentia's TensorFlow TempoCNN on all 80 bench tracks.
- Key is detected on the whole track with Essentia's HPCP chroma (36-bin, spectral whitening, detuning correction) scored against Faraldo's EDM `bgate` profiles for all 24 keys — 85.1 MIREX-weighted / 79.5% exact on the GiantSteps+ benchmark in `docs/research/` vs 55.4 / 43.6% for the old librosa Krumhansl method. The top 3 keys are printed with a confidence percentage: the first is from segment agreement + score margin (measured on 39 EDM clips with this exact code: ≥ 85% shown → 85% right, 70–85% → 75%; not a calibrated probability), the other two share what's left. Truth is in the top 3 on 92% of the benchmark.
- The analyzer never touches the system Python, pip or `~/.local`: everything runs from `bin/python`. Essentia is our own build (`tools/build-old-mac/essentia.sh`) without TensorFlow, ffmpeg or SDL.
- **The command-line version runs on every Apple Silicon Mac (macOS 11+) and Intel Macs on macOS 10.15+** (the Beat Key app needs macOS 12+). First launch checks the macOS version and chip and installs the build of each tool that runs there; after a macOS update it switches by itself. ffmpeg: arm64 9.0.2 on macOS 12+, our arm64 7.1.1 build on macOS 11 (`tools/build-old-mac/ffmpeg-arm64.sh`), evermeet 7.1.1 on Intel.
- The file is automatically renamed with BPM and keys included
- Each successful download is appended to `~/Downloads/(YY-M-D) Youtube DL LINKS.txt` as an `Input URL` / `Downloaded` entry

For example, downloads on May 12, 2026 are logged to:

```text
~/Downloads/(26-5-12) Youtube DL LINKS.txt
```

The link log looks like this:

```text
Input URL: https://www.youtube.com/watch?v=...
Downloaded: Some Beat (142.0 BPM Cm Eb Gm).mp3

Input URL: https://www.youtube.com/watch?v=...
Downloaded: Another Beat (95.0 BPM Am C Em).mp3
```

**Example output:**
```
URL/Beat: https://www.youtube.com/watch?v=...
Downloading...
Downloaded: Some Beat (142.0 BPM Cm Eb Gm).mp3
Key: Cm (90.0%) | Eb (4.1%) | Gm (2.7%)
```

**Drop a beat instead:** drag one or more audio files from Finder onto the `URL/Beat:` prompt and press Enter. You get the BPM and key; the file isn't renamed, moved or logged.
```
URL/Beat: /Users/you/Desktop/My\ Beat.wav
My Beat.wav
Analyzing...
BPM: 140.0
Key: Cm (90.0%) | Eb (4.1%) | Gm (2.7%)
```

Keep pasting URLs or dropping beats until you're done, then press Enter on a blank line or Ctrl+C to quit.

## YouTube Login Requirement (command-line version; the Beat Key app handles this itself, see above)

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
| `dropped.py` | Turns files dragged onto the `URL/Beat:` prompt into paths |

The Python scripts also work standalone if you need them:

```bash
python3 downloader.py                  # interactive loop
python3 downloader.py <url>            # single download
bin/python/bin/python3 bpm.py <file>   # analyze a file
```

## License

GNU Affero General Public License v3.0 (AGPL-3.0); see `LICENSE`. Beat Key includes Essentia (AGPL-3.0), so the whole project uses the same licence. The bundled tempo model (TempoCNN) is CC BY-NC-SA 4.0, so Beat Key is free and may not be sold. Third-party licences: `THIRD-PARTY-LICENSES.md`.
