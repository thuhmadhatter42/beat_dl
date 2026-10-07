# PICKUP — beat_dl

## CURRENT STATE — 2026-10-07 10:30

**What this is:** YouTube → MP3 downloader with BPM/key tagging. Bash loop (run.sh) + downloader.py (yt-dlp) + bpm.py (Essentia HPCP + bgate for key, TempoCNN for BPM). Launched by run.command or the `beat` alias. Also called by the Jownloader Brave extension (`~/dev/jownloader/extension`) through a native host that pipes a URL into run.sh. Progress page: `PROGRESS-TRACKER.html` (source `tracker.json`; rebuild with `python3 ~/.claude/skills/progress-tracker/build_tracker.py tracker.json`).

**Git:** main = origin/main, clean. Code commit f5d462b (2026-10-06 ~16:55); later commits are state saves. Harvester trial work lives on branch `worktree-agent-ab8c9d1d63d053d8d` (worktree `.claude/worktrees/agent-ab8c9d1d63d053d8d`, commit 1bc79c0 = `tools/pt-harvest/discover.py` + `docs/research/pt-ground-truth/trial-sessions.md`), not merged yet.

**PAUSED 10:30 — J: "save state, we will continue later." Goal (J 01:06): harvest 200 Pro Tools beats with BPM/key, then finish the training.** Plan `docs/superpowers/plans/2026-10-06-pt-bpm-harvest-and-train.md` + `-TOC.md` (§0-§5, §7 done; §6, §8-§11 open).
- Harvest STOPPED 10:04: J took the iLok out of Sofia and Pro Tools showed "missing PACE authorization". Result: 101 sessions done, **78 usable** (14 confirmed, 64 tempo-only, 30 with key, 77 also with a full-mix bounce) = 155 audio files. All are on Sofia `~/pt-harvest/audio/` (NNNN.wav + NNNN_mix.wav, 11k copies in `audio11k/`). Rate ≈ 4.4 min/session, ~3 in 4 usable. 318-session ARCH-1 manifest is at id 101. Dialog clicker killed; Pro Tools left open on the PACE error.
- Resume when the iLok is back in Sofia: `cd ~/pt-harvest && rm -f BLOCKED STOP && nohup ./run_batch.sh 200 >> logs/batch.log 2>&1 < /dev/null &` (check `~/pt-harvest/run_batch.sh` header first; the smart-beat agent may have changed it). Status: `cd ~/pt-harvest && .venv/bin/python harvest.py status`. Use the `sofia-screen` skill to see/click.
- Agent "T4 Smart beat finder" told to stop + report at 10:30; its branch `worktree-agent-a7e651e7f4159e1b9` (14 commits ahead, last d27a36f 09:01) holds the beat finder, full-mix bounce, ALL MIXES dedupe. **Not merged yet**: merge it, then remove its worktree (`.claude/worktrees/agent-a7e651e7f4159e1b9`).
- Agent "T3 Train on 78 songs" RUNNING since 10:25 (worktree `agent-a56ac5b30fe8476ed`): pulls 11k audio + DB, fine-tunes (all rows; confirmed-only if enough), evals original vs fine-tuned on held-out beats, held-out mixes, bpm-bench; beat-vs-mix on all rows; beat_dl key vs harvested key (30 rows). It must NOT ship. When it reports: show J the tables, then ship only if held-out improves and benches don't drop (new models/*.npz + ANALYZER_BUILD bump in deps.sh + push). Then merge its branch; move nothing big out of the worktree except a kept model.
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
3. Studio-E-2 and the MBP pick up f5d462b on their next `git pull` + `beat`: the picks change forces a one-time analyzer reinstall (under a minute).
4. Harvester trial: J said go 21:42; step 1 running (see RUNNING above). When it reports: review the answers, merge the worktree branch, grade the agent, then trial step 2 only after checking the answers.
5. Verify RestoreMachineState: after J's next VNC disconnect, check `ioreg -n Root -d1 -a | grep -A1 CGSSessionScreenIsLocked` on Sofia shows nothing.
6. Later, only when J says go: **Orion phase 1** (spec `docs/superpowers/specs/2026-09-12-menubar-key-bpm-listener-design.md`, repo `~/dev/orion`).

**Plan done:** `docs/superpowers/plans/2026-10-06-old-mac-support.md` + `-TOC.md`, all boxes ticked.

**Closed by J 2026-10-06 — never raise again:** Studio-E-2 old `beat` window; the 13:38 "152.0 BPM" file in Studio-E-2 Downloads; the trap 70/140 rule (J halves/doubles by ear); the iMessage watcher (one-off, not doing it).
