# PICKUP — beat_dl

## CURRENT STATE — 2026-10-09 23:40

**What this is:** YouTube → MP3 downloader with BPM/key tagging. Bash loop (run.sh) + downloader.py (yt-dlp) + bpm.py (Essentia HPCP + bgate for key, TempoCNN for BPM). Launched by run.command or the `beat` alias. Also called by the Jownloader Brave extension (`~/dev/jownloader/extension`) through a native host that pipes a URL into run.sh. Progress page: `PROGRESS-TRACKER.html` (source `tracker.json`; rebuild with `python3 ~/.claude/skills/progress-tracker/build_tracker.py tracker.json`).

**Git:** main = origin/main = 072cd89 (+ this save's commit), clean. Only branch: main; no worktrees. Studio-E-2 already pulled 072cd89 (J, 2026-10-09 23:34).

**Shipped 2026-10-09 (both pushed, both tested on the MBP):**
- ecf4a4c — the prompt now reads `URL/Beat:`. Drag audio files from Finder onto it → BPM + key per file; the file is NOT renamed, moved or logged. `dropped.py` turns the Terminal-escaped paths into file paths (exit 0 = files, 1 = looked like paths but none is a file → "File not found" / "That's a folder", 2 = not paths → download flow). URLs (http/https) skip it. Tested: mp3/wav/aiff, names with spaces, apostrophe, parentheses, two files in one drop.
- 072cd89 — key names spelled like Auto-Tune's Key menu (J's screenshots): major `C Db D Eb E F F# G Ab A Bb B`, minor `C C# D Eb E F F# G G# A Bb B` (+m). bpm.py `MAJOR_NOTES` / `MINOR_NOTES` + `fmt_key`. Same pitch classes; `tools/train-tempocnn/key_eval.py` and `docs/research/key-bench/bench.py` parse the flat names (round-trip checked, all 24). Downloads are now named e.g. "(142.0 BPM Cm Eb Gm)".
- Not changed: downloader.py's own interactive loop still says "Input URL:" (run.sh never uses it, only calls it with a URL); the daily links log keeps its "Input URL:" format (Jownloader's native/engine.py writes the same format).

**PAUSED 10:30 — J: "save state, we will continue later." Goal (J 01:06): harvest 200 Pro Tools beats with BPM/key, then finish the training.** Plan `docs/superpowers/plans/2026-10-06-pt-bpm-harvest-and-train.md` + `-TOC.md` (§0-§5, §7 done; §6, §8-§11 open).
- Harvest STOPPED 10:04: J took the iLok out of Sofia and Pro Tools showed "missing PACE authorization". Result: 101 sessions done, **78 usable** (14 confirmed, 64 tempo-only, 30 with key, 77 also with a full-mix bounce) = 155 audio files. All are on Sofia `~/pt-harvest/audio/` (NNNN.wav + NNNN_mix.wav, 11k copies in `audio11k/`). Rate ≈ 4.4 min/session, ~3 in 4 usable. 318-session ARCH-1 manifest is at id 101. Dialog clicker killed; Pro Tools left open on the PACE error.
- Resume when the iLok is back in Sofia (~120 more usable rows, ~240 manifest entries left incl. 20 new from ALL MIXES, est. 10-14 h): `ssh js-mac-pro 'bash ~/pt-harvest/ptkill.sh; cd ~/pt-harvest && rm -f BLOCKED STOP && .venv/bin/python pt_launch.py 100 && nohup ./run_batch.sh 200 >> logs/batch.log 2>&1 < /dev/null &'`. Status: `cd ~/pt-harvest && .venv/bin/python harvest.py status`. Pull: `tools/pt-harvest/sv.sh pull <repo>`. Beat check: `tools/pt-harvest/verify_beats.py` (71/78 pass; 4 mixes identical to beat, 3 unsure). Extra auto-clicks the agent added (decline/close only; J may revoke by deleting the line in approved-dialogs.txt): PT Dashboard Cancel, iLok Enable Network Licenses No, PACE Activation required Quit.
- Both agent branches merged (beat finder + training run) 10:55; worktrees removed. DB at id 101 + labels committed.
- TRAINING RESULT on 78 sessions (run A, all rows, artist split 85/30/40): held-out Acc1 75.0% → 87.5% (beats 70→85, mixes 80→90), Acc2 100% both; **bpm-bench Acc1 87.5% → 85.0% (−1 clip)** → per plan rule NOT shipped. Run B (confirmed-only, 28 rows) overfit, bench 80%: discard. Candidates kept in `tools/train-tempocnn/candidates/` (ftA-78sessions.npz, ftB-confirmed-only.npz); evals `tools/train-tempocnn/runs/ftA|ftB/eval.md` (untracked runs dir).
- Beat vs mix, original model, all rows: beats Acc1 61.5% / Acc2 98.7% (n78), mixes 67.5% / 97.4% (n77): vocals don't hurt.
- Key, shipped bpm.py vs harvested key (30 sessions): top-1 78.3%, in top-3 95.0% (beat 80.0/93.3, mix 76.7/96.7).
- Next with J: ship A anyway (better on his music, −1 bench clip)? or wait for iLok → harvest to 200 → retrain.
- Names rule (J 22:45): no song/artist/session/file names anywhere; numbers + hashes only; number→path map only on Sofia `~/pt-harvest/manifest.json`.
- Approved auto-clicks (`~/pt-harvest/approved-dialogs.txt`): UAD OK, Session Notes No, Missing Files OK, Save Don't Save, Missing AAX Plugins OK.
- Open with J: Auto Backup writes files to the source drives (left on; listed in Sofia `~/pt-harvest/source-drive-writes.txt` for trashing later).
- iLok is plugged into Sofia (seen on USB 21:45). J's "Arc-1 / 1-mixes" = `/Volumes/ARCH-1/1 - MIXES` on Sofia (Spotlight on): 5463 .ptx, 770 song folders, 323 valid newest mixes via `pick_latest_ptx()`.
- 5 trial sessions picked (seed 20261006, all 2024+, 5 artists). Song/file names are kept off the record (J, 22:45); the list lives only on Sofia in `~/pt-harvest-trial/discover.json`.
- Sofia scratch: `~/pt-harvest-trial/` (discover.py, discover.json, screenshots).
- Sofia's screen re-locked whenever J closed VNC (macOS re-locks on Screen Sharing disconnect if it was locked at connect). J ran `sudo defaults write /Library/Preferences/com.apple.RemoteManagement RestoreMachineState -bool NO` on Sofia 21:57; read back = 0. Not yet proven by a real VNC disconnect.

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
3. Studio-E-2: has 072cd89 (J, 2026-10-09). Done.
4. Harvester trial: done and grown into the 101-session harvest above (paused on the iLok).
5. Verify RestoreMachineState: after J's next VNC disconnect, check `ioreg -n Root -d1 -a | grep -A1 CGSSessionScreenIsLocked` on Sofia shows nothing.
6. Later, only when J says go: **Orion phase 1** (spec `docs/superpowers/specs/2026-09-12-menubar-key-bpm-listener-design.md`, repo `~/dev/orion`).

**Plan done:** `docs/superpowers/plans/2026-10-06-old-mac-support.md` + `-TOC.md`, all boxes ticked.

**Closed by J 2026-10-06 — never raise again:** Studio-E-2 old `beat` window; the 13:38 "152.0 BPM" file in Studio-E-2 Downloads; the trap 70/140 rule (J halves/doubles by ear); the iMessage watcher (one-off, not doing it).
