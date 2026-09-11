# PICKUP — beat_dl

## CURRENT STATE — 2026-09-11 01:34

**What this is:** YouTube → MP3 downloader with BPM/key tagging. Bash loop (run.sh) + downloader.py (yt-dlp) + bpm.py (Essentia, librosa fallback). Launched by double-clicking run.command or the `beat` alias.

**Git:** main = origin/main = a5c3e94, tree clean.

**Landed 2026-09-10/11:**
- ae70d59: missing librosa no longer bakes its error into the filename.
- a5c3e94: deps.sh — presence check + install every launch; yt-dlp upgrade weekly (stamp `.last-ytdlp-upgrade`) and on download failure with one retry. README updated.

**Landed 2026-09-11 (committed 0c8c57c + follow-up, pushed):** bpm.py key detection replaced — essentia HPCP36 + bgate, real top-3,
agreement+margin confidence (85.1 / 79.5 % GS+ vs 55.4 / 43.6 old; bench: `docs/research/key-bench/bench.py bpmpy`). Single
essentia decode feeds TempoCNN + key (BPM output unchanged). librosa = fallback only; its BPM path now uses
`librosa.feature.tempo` because `beat_track` segfaults here (py3.14 + numba 0.67). deps.sh: numba-import guard
(`pip3 install -U numba` when it lags numpy). README updated. Not committed — J to review/commit.

**Next (in order):**
1. On Studio-E-2 (user studioe): `git -C <beat_dl path> pull` then run `beat`. Confirm it prints "✓ essentia" (or "✓ librosa" if no essentia build) and the next download gets a "(NN BPM key key key)" name. Rename the one bad file in its ~/Downloads ("Roddy Ricch - The Box _Official Audio_ (Missing: librosa … ).mp3").
2. iMessage watcher: invoke superpowers:writing-plans on docs/superpowers/specs/2026-06-05-imessage-watcher-design.md, then implement (watch.command, watcher.sh, process_url.sh factored out of run.sh, BEAT_DL_OUTDIR override in downloader.py, .watch_state.json + watcher.log git-ignored). Test setup: `brew install steipete/tap/imsg`, grant Terminal Automation→Messages + Accessibility.

**Open questions for J:** none.
