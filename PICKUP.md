# PICKUP — beat_dl

## CURRENT STATE — 2026-10-06 15:30

**What this is:** YouTube → MP3 downloader with BPM/key tagging. Bash loop (run.sh) + downloader.py (yt-dlp) + bpm.py (Essentia TempoCNN for BPM, Essentia HPCP + bgate for key). Launched by run.command or the `beat` alias. Also called by the Jownloader Brave extension (`~/dev/jownloader/extension`) through a native host that pipes a URL into run.sh. Progress page: `PROGRESS-TRACKER.html` (source `tracker.json`; rebuild with `python3 ~/.claude/skills/progress-tracker/build_tracker.py tracker.json`).

**Git:** main = origin/main, pushed. Last code commit 570695e (2026-10-06 13:45).

**J's goal (2026-10-06 15:23):** beat_dl must work on ANYONE's Mac. Every dependency ships in the repo (no brew, no pip, no network except yt-dlp's own -U), and first run checks the macOS version + CPU and picks, per component, a build that runs on that Mac. "macOS 14 doesn't support XYZ" must never happen again.

**Everything that ships in `vendor/` now (all installed into gitignored `bin/` by deps.sh `ensure_deps`, with visible progress):**
- `vendor/yt-dlp` — universal yt-dlp_macos. Measured minos: arm64 11.0, x86_64 10.13.
- `vendor/macos-{arm64,x86_64}/{ffmpeg,ffprobe}.zip` — martin-riedl.de static 9.0.2. Measured minos 12.0 both arches → TOO NEW for macOS 11 / Intel 10.15–11.
- `vendor/macos-{arm64,x86_64}/python.tar.gz` — python-build-standalone cpython-3.11.17+20261003 install_only_stripped (sha256 checked against upstream SHA256SUMS). Minos arm64 11.0, x86_64 10.15. Unpacked to `bin/python`; run.sh calls `"$PY"` (= bin/python/bin/python3) for downloader.py and bpm.py.
- `vendor/macos-{arm64,x86_64}/wheels/` — essentia-tensorflow 2.1b6.dev1110 cp311 (split into `.part-aa/.part-ab` at 60 MB for GitHub's 100 MB limit; joined at install), numpy 1.26.4, pyyaml 6.0.3, six 1.17.0. pip installs them with `--no-index`. Measured minos (real Mach-O, wheel tags lie): arm64 13.1 (libtensorflow_framework; libx264/x265/libyaml 13.0), x86_64 12.1.
- **So today it runs on:** Apple Silicon macOS 13.1+, Intel macOS 12.1+. Target: Apple Silicon 11.0+ (all of them), Intel 10.15+ (my default floor, not confirmed by J).

**In flight (2026-10-06 15:28):** one Sonnet agent ("T3 Old-macOS build hunt", worktree isolation, recon only) is finding + measuring older builds: ffmpeg/ffprobe static with arm64 minos ≤ 11.0 and x86_64 ≤ 10.15; essentia-tensorflow versions (dev871/1032/1110/1177/1389) for arm64 11–13.0 and Intel 10.15–12.0, else plain `essentia` wheels (BPM falls back to RhythmExtractor2013, key unchanged); yt-dlp `-U` vs yt-dlp_macos_legacy on old macOS. Its downloads go to `<scratchpad>/oldmac/` (session scratchpad, gone after this session — if the agent's report is lost, rerun the hunt). Grade it after review: `python3 ~/.claude/scripts/agent-grade.py grade last pass|fix|fail "<why>"`; remove its worktree.

**Next (build, after the agent reports):**
1. Vendor the extra tiers as `vendor/macos-<arch>/<component>/<tier>/…` (or similar) with a small manifest listing each build's measured minos.
2. deps.sh first run: read `sw_vers -productVersion` and native CPU (`sysctl -n hw.optional.arm64`, so a Rosetta terminal still gets arm64), pick per component the newest build whose minos ≤ this Mac; record what was picked in `bin/` so later launches skip the work; print one loud line if a component has no build for this Mac.
3. Launch check stays (J 15:23: "I'd rather make sure it works"). It runs once per launch, not per download: `runs` executes yt-dlp/ffmpeg/ffprobe `--version` (~8 s total, mostly yt-dlp's one-file unpack) and reinstalls a missing/broken tool; `have_essentia` checks bin/python. yt-dlp is the only thing that needs updates (weekly `-U` + once on a failed download); ffmpeg/python/essentia never need updating.
4. Test each tier: fresh copy + bare PATH (`env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin bash ./run.sh`) on this MBP; Sofia (Intel, macOS 12.7.6, `~/.claude/scripts/ssh-rc js-mac-pro '…'`) covers the Intel path. Test URL J gave: https://www.youtube.com/watch?v=TL_EX-hDXfo (77.0 BPM D#). Trash every test download.

**Verified 2026-10-06:**
- MBP: fresh copy, no brew on PATH → analyzer setup + download + tag in 42 s ("77.0 BPM D# D#m G#"). Test file trashed. MBP's own `bin/python` not created yet — J was running `beat` at 15:23, which does the one-time setup.
- Studio-E-2 (arm64, macOS 14.1.1, user studioe; ssh key auth now works): git pull → 570695e, analyzer installed, J's test at 13:48 tagged "77.0 BPM D# D#m G#". Test file moved to its ~/.Trash. Root cause there: PyPI's newest essentia wheel needs macOS 15 and the old deps.sh hid pip's failure; plus an orphaned `brew reinstall yt-dlp` was compiling Rust/LLVM from source for an hour at load 20 (gone by 13:46).

**Still open, later (J 15:23: "yes, later"):**
1. **Harvester trial** (5 sessions on Sofia): J plugs the iLok and Arc-1 into Sofia and says go. Spec `docs/superpowers/specs/2026-09-12-protools-autotune-ground-truth-design.md` §5.
2. **Orion phase 1** (menu-bar BPM/key listener): J says go → superpowers:writing-plans from `docs/superpowers/specs/2026-09-12-menubar-key-bpm-listener-design.md`, repo `~/dev/orion`.

**Closed by J 2026-10-06 — never raise again:** Studio-E-2 old `beat` window; the 13:38 "152.0 BPM" file in Studio-E-2 Downloads; the trap 70/140 rule (J halves/doubles by ear, leave the detector as is); the iMessage watcher (one-off, not doing it).
