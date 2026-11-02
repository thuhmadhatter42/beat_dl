# PICKUP — beat_dl

## CURRENT STATE — 2026-11-02 01:23

**Beat Key 0.1.28 (test build, NOT notarized) is installed and running on J's MBP since 01:17. 0.1.18 is still the public release.** All SESSION Key features merged (plan docs/plans/session-key-parity.md, §1-§5 ticked, §6 release owed). J's standing order (2026-11-01 20:14): build ALL of it, no "next section?" check-ins.
- Tonight's builds (main, VERSION=0.1.28, all commits local, main far ahead of origin):
  - 0.1.21 (5a9e4ee): new-song detection merged (title watcher Spotify/Brave/Chrome/Safari + audio break detector; eval 6/12 held-out, never split intro→drop).
  - 0.1.22 (c770111): LIVE KEYS WERE WRONG: ScreenCaptureKit only gives 8/16/24/48 kHz; asking 44.1k got 48k read as 44.1k → keys ~1.5 semitones flat, BPM 8 % slow. Now captures 48k + resamples per buffer (SystemAudio.swift). Verified with a probe (scratchpad/sckrate.swift → 48000). Click key 2/3 in the top 3 = THE key for sends (KeyChoice in KeySpelling.swift, cleared by New Song).
  - 0.1.23 (1533925): Live hears only player apps (Spotify, browsers, Music…) when one is open → no mic bleed via Artemis/DAW. Catch: DAW playback not heard while a browser is open.
  - 0.1.24 (d160906): AppLog.swift → ~/Library/Logs/Beat Key/beatkey.log (launch, quit, "PREVIOUS RUN DID NOT QUIT CLEANLY", crash signals + exceptions, engine + Listen state, menu-bar item frame); analyzer stderr → analyzer.log. Menu bar: coloured key AFTER the reading, no stale "Cm 148.5" at launch. c36f9f9: tests never write the user log.
  - 0.1.25: idle = just the key. 0.1.26: Send Key to Waves Tune (WavesTuneSend.swift: writes /Users/Shared/Waves/Plug-In Settings/Waves Tune Real-Time User Presets/Beat Key.xps, all params "R" = load scale only, Scale "Major"/"Natural Minor" root-relative, Root = pitch class; popover button + Reading menu). 0.1.27/0.1.28: popover no longer slides (item one fixed width in every state, popover centred, animates=false); log proved item frame constant through an analyze.
- Test builds: `app/build.sh --no-notarize` (~3 min) then copy app/build/Beat Key.app to /Applications. Notarize only release builds (J 00:49). Desktop has notarized Beat-Key-0.1.25.dmg.
- Tests: swift 235 (1 skipped) pass; python 101 OK (run `bin/python/bin/python3.11 -m unittest discover -s tests`).
- Owed:
  1. Waves Tune live check: preset "Beat Key - Am" written 01:18. Waves Tune RT is open in ARTEMIS (Track 2, window 672, on another desktop, shows C Major). Load preset ▼ → Beat Key; expect scale Natural Minor, root A. If it doesn't load, diff against a preset J saves from the plug-in.
  2. Re-post the MBP test list only when J can answer: Auto-Tune shows sent key / minor stays minor (KeyType guess in AutoTuneSend.swift); Artemis gets it; Pro Tools + Logic tempo/key; live Mac audio key now correct (Stargazing read Fm @137 before the 48k fix); Finder service; title watcher.
  2b. KEY ACCURACY (J 01:56): J PLUGGED THE iLOK INTO SOFIA at 01:58 (licences to verify on Sofia first), then run the PT ground-truth harvest on SOFIA all night (plan docs/superpowers/plans/2026-10-06-pt-bpm-harvest-and-train.md; spec docs/superpowers/specs/2026-09-12-protools-autotune-ground-truth-design.md; 101 sessions done, 78 usable, BPM only; the Auto-Tune KEY read was never run). Main session (Claude itself, NOT a watcher script — J 01:57) checks it EVERY 5 MIN via a self-paced loop: log progress + Sofia screenshot, clears any dialog/hang itself or skips the session; Sofia screen via the sofia-screen skill. Then: in-app "wrong, it's X" button saving clip + label; compare current bgate formula (re-tuned) vs a trained key model on J's beats, ship the winner. Live log 01:32-01:34 showed 4 listen restarts (cause unchecked) and A/Ab/C#m readings on an E minor song.
  3. AAX plugin: PARKED by J ("worry about the AAX later"). J has PACE tools; says it is not several days. Ideas: Auto-Key-style AAX (analyze track, send key), whole app in a plugin, PTSL import of downloaded beat into the session.
  4. Release per app/RELEASING.md after J's tests: notarized build, gh release DMG + appcast.xml, Sofia site copy + beat-key-latest.json, `scp friends-page/index.html js-mac-pro:beatkey/`, FLR GO handoff (handoff/TO-FLR-SITE-2026-11-01-*.md), push main.
  5. Stale worktrees/branches: remove agent-a282dde3df59844ee, agent-a52991578c624e9d2 and the Waves research worktree (`git worktree list`; `git worktree remove -f -f`, `git branch -D`).
  6. FLR site session: icon + licences link + "updates itself" (handoff/TO-FLR-SITE-2026-10-28-beat-key-0.1.18.md); await reply.
  7. Optional: beatkey (8171) in ~/.claude/skills/jshriver-subdomain/references/players.md.
  8. Question for J (2026-10-29, unanswered): both signing keys into the Passwords app? (plan in the 2026-10-29 block below).
- Facts: Sofia has no Pro Tools / Auto-Tune licence. J: clock times not durations; logs in everything; anything J must read goes in the FINAL message.
- Standing: Sofia never restarted; ssh via ~/.claude/scripts/ssh-rc; trash not rm; no song names in code/logs.

## STATE — 2026-10-29 06:15 (superseded by the block above)

**Beat Key (internal Orion, bundle com.jshriver.orion) 0.1.18 is RELEASED and live.** Free item on fourletterrecords.com behind an FLR account (page https://fourletterrecords.com/beat-key, download /account/download/beat-key; owned by the FLR site session). Repo is AGPL-3.0 since 2026-10-28 (commit f9e0031; ≤0.1.16 were also MIT).
- Git: main = origin/main = c3ff709; orion-v1 pushed. Tag Beat-Key-0.1.18, GitHub release https://github.com/thuhmadhatter42/beat_dl/releases/tag/Beat-Key-0.1.18 (DMG + appcast.xml). DMG sha256 bc1af29832add5847842ef75e3594e03479857cdd7d70e0db8c890c7a4d69c15. Installed MBP /Applications (spctl OK). Sofia runs 0.1.17 (left there after the Sparkle test).
- Icon: golden key plate (app/icon/, source-golden-key.png); macOS 26+ asset catalog (Assets.car via actool, CFBundleIconName=AppIcon) so no grey squircle; Orion.icns kept for macOS 12.
- Updates: Sparkle 2.10.1. Menu: About / Check for Updates… / Run Doctor / Licenses. Daily auto check; Run Doctor ends with an update check. Feed = https://github.com/thuhmadhatter42/beat_dl/releases/latest/download/appcast.xml → EVERY release must attach app/build/appcast.xml. Private EdDSA key: MBP login Keychain (account beat-key) + ~/.config/beat-key/sparkle_ed25519_private (600; never print/commit). Real update test on Sofia passed (0.1.18→0.1.19 test build).
- Release steps: app/RELEASING.md. Build with `DMG_LAYOUT_FROM=<previous dmg> app/build.sh` (no Finder window on J's screen). Site publish: copy DMG to Sofia ~/fourletterrecords/beat-key-releases/Beat-Key-<ver>.dmg (never overwrite), then write ~/fourletterrecords/beat-key-latest.json = {"version": "<ver>"}.
- yt-dlp weekly self-update verified on Sofia (2026.08.19 → 2026.10.26, 18:42).
- **Friends link (J's spin-off, close friends only): https://beatkey.jshriver.com** — email in, no confirmation, 303 to the GitHub DMG of the version in beat-key-latest.json. Code friends-page/ (c3ff709); live on Sofia ~/beatkey/ (serve.py port 8171, tunnel `beatkey` a362a727-085e-4b43-bea8-6c90ef205d05, LaunchAgents com.jshriver.beatkey-{server,tunnel}). Emails logged to Sofia ~/beatkey/downloads.jsonl. Tested end to end (200/400/303); page look not yet screenshotted.
- Owed:
  1. [DONE 2026-10-29 05:15] Sparkle private key backed up to Sofia ~/.config/beat-key/sparkle_ed25519_private (600, sha256 matches MBP copy).
  2. FLR site session: new icon + "Source code and licences" link + "updates itself" line (handoff/TO-FLR-SITE-2026-10-28-beat-key-0.1.18.md); await handoff/FROM-FLR-SITE-*.md reply.
  3. Optional: add beatkey (8171) to ~/.claude/skills/jshriver-subdomain/references/players.md port table.
  4. [DROPPED 2026-10-29] "Launchagent command?" was a dashboard artifact, not J's ask.
  5. Question for J (asked 2026-10-29 06:14, unanswered): put both signing keys in the Passwords app (iCloud, leaves the house)? Plan: write a Passwords CSV import file in the scratchpad (Artemis key = `security find-generic-password -s artemis-license-signing -w`, may raise an Allow box; Beat Key = ~/.config/beat-key/sparkle_ed25519_private), J clicks File > Import once, then delete the CSV. Both keys already in MBP + Sofia login keychains (artemis-license-signing + .backup-20261013-1558; https://sparkle-project.org / beat-key). Artemis/Zeropoint have no self-updater, so no update key; they share the licence key, owned by the Artemis session.
- Ledger: `.superpowers/sdd/2026-10-27-orion-v1/progress.md` (task-17 = Sparkle). UI checks run on Sofia, recorded frames, never J's MBP screen.
- Standing: Sofia never restarted; ssh via ~/.claude/scripts/ssh-rc; trash not rm; no song names in code/logs.

## STATE BEFORE ORION — 2026-10-09 23:40

**What this is:** YouTube → MP3 downloader with BPM/key tagging. Bash loop (run.sh) + downloader.py (yt-dlp) + bpm.py (Essentia HPCP + bgate for key, TempoCNN for BPM). Launched by run.command or the `beat` alias. Also called by the Jownloader Brave extension (`~/dev/jownloader/extension`) through a native host that pipes a URL into run.sh. Progress page: `PROGRESS-TRACKER.html` (source `tracker.json`; rebuild with `python3 ~/.claude/skills/progress-tracker/build_tracker.py tracker.json`).

**Git (as of 2026-10-09; [SUPERSEDED by 2026-10-28] orion-v1 was merged into main and the local branch deleted, see CURRENT STATE):** main = origin/main = 072cd89 (+ this save's commit), clean. Only branch: main; no worktrees then. Studio-E-2 already pulled 072cd89 (J, 2026-10-09 23:34).

**Shipped 2026-10-09 (both pushed, both tested on the MBP):**
- ecf4a4c — the prompt now reads `URL/Beat:`. Drag audio files from Finder onto it → BPM + key per file; the file is NOT renamed, moved or logged. `dropped.py` turns the Terminal-escaped paths into file paths (exit 0 = files, 1 = looked like paths but none is a file → "File not found" / "That's a folder", 2 = not paths → download flow). URLs (http/https) skip it. Tested: mp3/wav/aiff, names with spaces, apostrophe, parentheses, two files in one drop.
- 072cd89 — key names spelled like Auto-Tune's Key menu (J's screenshots): major `C Db D Eb E F F# G Ab A Bb B`, minor `C C# D Eb E F F# G G# A Bb B` (+m). bpm.py `MAJOR_NOTES` / `MINOR_NOTES` + `fmt_key`. Same pitch classes; `tools/train-tempocnn/key_eval.py` and `docs/research/key-bench/bench.py` parse the flat names (round-trip checked, all 24). Downloads are now named e.g. "(142.0 BPM Cm Eb Gm)".
- Not changed: downloader.py's own interactive loop still says "Input URL:" (run.sh never uses it, only calls it with a URL); the daily links log keeps its "Input URL:" format (Jownloader's native/engine.py writes the same format).

**PAUSED 2026-10-09 10:30 (still paused 2026-10-28; the iLok is not in Sofia) — J: "save state, we will continue later." Goal (J 01:06): harvest 200 Pro Tools beats with BPM/key, then finish the training.** Plan `docs/superpowers/plans/2026-10-06-pt-bpm-harvest-and-train.md` + `-TOC.md` (§0-§5, §7 done; §6, §8-§11 open).
- Harvest STOPPED 10:04: J took the iLok out of Sofia and Pro Tools showed "missing PACE authorization". Result: 101 sessions done, **78 usable** (14 confirmed, 64 tempo-only, 30 with key, 77 also with a full-mix bounce) = 155 audio files. All are on Sofia `~/pt-harvest/audio/` (NNNN.wav + NNNN_mix.wav, 11k copies in `audio11k/`). Rate ≈ 4.4 min/session, ~3 in 4 usable. 318-session ARCH-1 manifest is at id 101. Dialog clicker killed; Pro Tools left open on the PACE error.
- Resume when the iLok is back in Sofia (~120 more usable rows, ~240 manifest entries left incl. 20 new from ALL MIXES, est. 10-14 h): `ssh js-mac-pro 'bash ~/pt-harvest/ptkill.sh; cd ~/pt-harvest && rm -f BLOCKED STOP && .venv/bin/python pt_launch.py 100 && nohup ./run_batch.sh 200 >> logs/batch.log 2>&1 < /dev/null &'`. Status: `cd ~/pt-harvest && .venv/bin/python harvest.py status`. Pull: `tools/pt-harvest/sv.sh pull <repo>`. Beat check: `tools/pt-harvest/verify_beats.py` (71/78 pass; 4 mixes identical to beat, 3 unsure). Extra auto-clicks the agent added (decline/close only; J may revoke by deleting the line in approved-dialogs.txt): PT Dashboard Cancel, iLok Enable Network Licenses No, PACE Activation required Quit.
- Both agent branches merged (beat finder + training run) 10:55; worktrees removed. DB at id 101 + labels committed.
- TRAINING RESULT on 78 sessions (run A, all rows, artist split 85/30/40): held-out Acc1 75.0% → 87.5% (beats 70→85, mixes 80→90), Acc2 100% both; **bpm-bench Acc1 87.5% → 85.0% (−1 clip)** → per plan rule NOT shipped. Run B (confirmed-only, 28 rows) overfit, bench 80%: discard. Candidates kept in `tools/train-tempocnn/candidates/` (ftA-78sessions.npz, ftB-confirmed-only.npz); evals `tools/train-tempocnn/runs/ftA|ftB/eval.md` (untracked runs dir).
- Beat vs mix, original model, all rows: beats Acc1 61.5% / Acc2 98.7% (n78), mixes 67.5% / 97.4% (n77): vocals don't hurt.
- Key, shipped bpm.py vs harvested key (30 sessions): top-1 78.3%, in top-3 95.0% (beat 80.0/93.3, mix 76.7/96.7).
- Open, J's call, no ruling as of 2026-10-28: ship A anyway (better on his music, −1 bench clip)? or wait for iLok → harvest to 200 → retrain. Parked behind Beat Key; the CLI analyzer is unchanged.
- Names rule (J 22:45): no song/artist/session/file names anywhere; numbers + hashes only; number→path map only on Sofia `~/pt-harvest/manifest.json`.
- Approved auto-clicks (`~/pt-harvest/approved-dialogs.txt`): UAD OK, Session Notes No, Missing Files OK, Save Don't Save, Missing AAX Plugins OK.
- Open, no ruling as of 2026-10-28: Auto Backup writes files to the source drives (left on; listed in Sofia `~/pt-harvest/source-drive-writes.txt` for trashing later).
- (2026-10-06) iLok was plugged into Sofia (seen on USB 21:45); J took it out 2026-10-09 10:04, see PAUSED above. J's "Arc-1 / 1-mixes" = `/Volumes/ARCH-1/1 - MIXES` on Sofia (Spotlight on): 5463 .ptx, 770 song folders, 323 valid newest mixes via `pick_latest_ptx()`.
- 5 trial sessions picked (seed 20261006, all 2024+, 5 artists). Song/file names are kept off the record (J, 22:45); the list lives only on Sofia in `~/pt-harvest-trial/discover.json`.
- Sofia scratch: `~/pt-harvest-trial/` (discover.py, discover.json, screenshots).
- Sofia's screen re-locked whenever J closed VNC (macOS re-locks on Screen Sharing disconnect if it was locked at connect). J ran `sudo defaults write /Library/Preferences/com.apple.RemoteManagement RestoreMachineState -bool NO` on Sofia 21:57; read back = 0. Not yet proven by a real VNC disconnect.

**J's goal (2026-10-06), DONE (CLI version; Beat Key app floor is macOS 12 since 2026-10-28):** beat_dl works on anyone's Mac: every dependency ships in `vendor/`, no brew, no pip from the network, no system Python. First launch reads macOS version + chip and installs the build that runs there.

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

**Owed / open (as of 2026-10-09; items 1-4 closed, 5 still open, 6 superseded by CURRENT STATE):**
1. [CLOSED 2026-10-06] Sofia test litter: moved to Sofia's ~/.Trash by J 2026-10-06 17:05, checked (all 4 paths gone).
2. [CLOSED, J's file, left as is] MBP `~/Downloads/(26-10-6) Youtube DL LINKS.txt` got 12 test lines from the tier tests.
3. [CLOSED 2026-10-09] Studio-E-2: has 072cd89 (J). Per J 2026-10-28 09:54: nothing on Studio D or E for now.
4. [CLOSED] Harvester trial: done and grown into the 101-session harvest above (paused on the iLok).
5. Verify RestoreMachineState: after J's next VNC disconnect, check `ioreg -n Root -d1 -a | grep -A1 CGSSessionScreenIsLocked` on Sofia shows nothing.
6. [CLOSED 2026-10-28, see CURRENT STATE] Orion = the beat_dl app, public name Beat Key. The listener spec joins it later as feature 2.

**Plan done:** `docs/superpowers/plans/2026-10-06-old-mac-support.md` + `-TOC.md`, all boxes ticked.

**Closed by J 2026-10-06 — never raise again:** Studio-E-2 old `beat` window; the 13:38 "152.0 BPM" file in Studio-E-2 Downloads; the trap 70/140 rule (J halves/doubles by ear); the iMessage watcher (one-off, not doing it).
