# PICKUP — beat_dl

## CURRENT STATE — 2026-10-06 17:00

**What this is:** YouTube → MP3 downloader with BPM/key tagging. Bash loop (run.sh) + downloader.py (yt-dlp) + bpm.py (Essentia HPCP + bgate for key, TempoCNN for BPM). Launched by run.command or the `beat` alias. Also called by the Jownloader Brave extension (`~/dev/jownloader/extension`) through a native host that pipes a URL into run.sh. Progress page: `PROGRESS-TRACKER.html` (source `tracker.json`; rebuild with `python3 ~/.claude/skills/progress-tracker/build_tracker.py tracker.json`).

**Git:** main = origin/main = f5d462b (pushed 2026-10-06 ~16:55), clean.

**J's goal (2026-10-06), DONE:** beat_dl works on anyone's Mac: every dependency ships in `vendor/`, no brew, no pip from the network, no system Python. First launch reads macOS version + chip and installs the build that runs there.

**How it works now (deps.sh `ensure_deps`, every launch):**
- `MACOS=$(sw_vers -productVersion)`; `CPU` from `sysctl hw.optional.arm64` (right even in a Rosetta terminal). Below macOS 10.15 → "❌ beat_dl needs macOS 10.15 or newer" and run.sh exits.
- `bin/.picks` = `macos=… cpu=… ffmpeg=… analyzer=essentia-notf-1`. If it differs (new Mac, macOS update, analyzer bump) → bin/ffmpeg, bin/ffprobe, bin/python are dropped and reinstalled. Bump `ANALYZER_BUILD` in deps.sh whenever the vendored analyzer changes.
- ffmpeg/ffprobe: `vendor/macos-arm64/` 9.0.2 (martin-riedl) on arm64 macOS ≥ 12.0; `vendor/macos-arm64-legacy/` our 7.1.1 minimal static build (minos 11.0, built by `tools/build-old-mac/ffmpeg-arm64.sh`) below 12; `vendor/macos-x86_64/` evermeet 7.1.1 (minos 10.9) on Intel.
- yt-dlp: `vendor/yt-dlp` universal (floor 10.15); self-updates in bin/ weekly + once on a failed download; an update that won't run is rolled back to the vendored copy.
- Analyzer: `vendor/macos-<cpu>/python.tar.gz` (python-build-standalone 3.11.17) + `vendor/macos-<cpu>/wheels/` = OUR essentia wheel (`tools/build-old-mac/essentia.sh`, essentia commit 77a6a954 = dev1110, no TensorFlow/ffmpeg/SDL, static, minos arm64 11.0 / x86_64 10.15, links only libc++/libSystem) + numpy 1.26.4, pyyaml, six. `pip install --no-user --no-index`; `PYTHONNOUSERSITE=1 PIP_CONFIG_FILE=/dev/null`, PYTHONPATH/PYTHONHOME unset.
- bpm.py: when essentia has no TempoCNN/AudioLoader (our build), it decodes with ./bin/ffmpeg (`-c:a mp3` fixed-point decoder → s16 ÷ 32768, matches the old AudioLoader sample for sample) and runs TempoCNN in numpy (`tempocnn_np.py`, weights `models/deeptemp-k16-3.npz`, extractor `tools/build-old-mac/extract-tempocnn-weights.py`). The TF path still works if a TF essentia is present (e.g. brew python on the MBP for the benchmarks).
- Accuracy: our build vs the essentia-tensorflow path on the 80 bench tracks (docs/research/bpm-bench + key-bench audio): BPM 80/80, top-3 keys 80/80, confidences 80/80, both arches. Non-mp3 inputs can differ slightly (old ffmpeg kept encoder padding); beat_dl only writes mp3.
- Why the PyPI wheels were dropped: they needed macOS 13.1 (arm64) / 12.1 (Intel), and their bundled libSDL-1.2 pops "Fatal error! Cannot continue! Failed loading SDL2 library." and hangs on any Mac without Homebrew's SDL2 (MBP and Studio-E-2 only worked because both have brew sdl2-compat).

**Tested 2026-10-06:** forced tiers on the MBP (native, arm64 11.7, x86_64 12.7, x86_64 10.15 under Rosetta, x86_64 10.14 refusal) + real Intel run on Sofia (macOS 12.7.6): every download named "(77.0 BPM D# D#m G#)", key line `D# (76.1%) | D#m (14.0%) | G# (2.8%)` everywhere. Not testable on hardware here: Apple Silicon macOS 11/12, Intel 10.15/11 (minos headers + forced tiers only). The pip-isolation fix came after the Sofia run; verified on the MBP with a `user = true` pip.conf (nothing went to ~/.local).

**Owed / open:**
1. Sofia test litter: moved to Sofia's ~/.Trash by J 2026-10-06 17:05, checked (all 4 paths gone).
2. MBP: today's `~/Downloads/(26-10-6) Youtube DL LINKS.txt` got 12 test lines appended by the tier tests (file is J's, left as is).
3. Studio-E-2 and the MBP pick up f5d462b on their next `git pull` + `beat`: the picks change forces a one-time analyzer reinstall (under a minute).
4. Later, only when J says go: **harvester trial** (iLok + Arc-1 on Sofia; spec `docs/superpowers/specs/2026-09-12-protools-autotune-ground-truth-design.md` §5) and **Orion phase 1** (spec `docs/superpowers/specs/2026-09-12-menubar-key-bpm-listener-design.md`, repo `~/dev/orion`).

**Plan done:** `docs/superpowers/plans/2026-10-06-old-mac-support.md` + `-TOC.md`, all boxes ticked.

**Closed by J 2026-10-06 — never raise again:** Studio-E-2 old `beat` window; the 13:38 "152.0 BPM" file in Studio-E-2 Downloads; the trap 70/140 rule (J halves/doubles by ear); the iMessage watcher (one-off, not doing it).
