# PICKUP — beat_dl

## CURRENT STATE — 2026-09-12 22:55

**What this is:** YouTube → MP3 downloader with BPM/key tagging. Bash loop (run.sh) + downloader.py (yt-dlp) + bpm.py (Essentia TempoCNN for BPM, Essentia HPCP + bgate for key; librosa only where essentia has no wheel). Launched by run.command or the `beat` alias. Also called by the Jownloader Brave extension (`~/dev/jownloader/extension`) through a native host that pipes a URL into run.sh. Progress page: `PROGRESS-TRACKER.html` (source `tracker.json`; rebuild with `python3 ~/.claude/skills/progress-tracker/build_tracker.py tracker.json`).

**Git:** main = origin/main, tree clean, pushed (last content commit a1046d6).

**2026-09-12 — research and specs only, no code changed:**
- Accuracy stands at 87.5 % BPM Acc1 / 79.5 % key exact (85.1 MIREX) on GiantSteps. Antares Auto-Key publishes no figure (uses zplane TONART V3). Dubspot 2026 200-track test: Mixed In Key 11 89 %, KeyFinder 76 %, Rekordbox 7 69 % — beat_dl lands between KeyFinder and MIK.
- **Pro Tools Auto-Tune ground-truth harvester spec** — `docs/superpowers/specs/2026-09-12-protools-autotune-ground-truth-design.md`. Purpose: turn J's mixed sessions (Arc-1 → `1-mixes`, many artists) into (beat-only WAV, key, BPM) benchmark rows where an ACTIVE Auto-Tune (Pro or EFX, retune ≠ off) on the 3 busiest lead-vocal tracks agrees on Key+Scale. Beat folder is always `Beat Buss`. Bypassed/inactive Auto-Tune = song untuned = no label. Every labelled session's newest full bounce goes into Music.app playlist "PT Ground Truth" for J's ear check. PTSL can't read plugin state → screenshot the plugin window (insert-slot pixel click). First test: `CId_ExportSessionInfoAsText` for plugin list / clip counts / tempo.
- **Orion spec** (menu-bar BPM/key listener) — `docs/superpowers/specs/2026-09-12-menubar-key-bpm-listener-design.md`. Global CoreAudio process tap (Artemis pattern copied, not linked), bundled-Python Essentia helper, loading glyph until confident, panel with relative/fifths/Camelot + Auto-Tune-EFX-style piano roll with note elimination, collapsed persisted history. MacBook only (Sofia = macOS 12.7.6). Repo will be `~/dev/orion`, VERSION 0.1.0. Phase 1 = tap + readout in the bar.

**Next — each gated on J:**
1. **Harvester trial** (5 sessions on Sofia): J plugs the iLok and Arc-1 into Sofia and says go. Session 1 = text export only, then one insert click + one screenshot, verified by eye; sessions 2–5 one at a time. Plan in spec §5.
2. **Orion phase 1**: J says go → superpowers:writing-plans from the spec, create `~/dev/orion`, build tap + menu-bar readout.
3. **Studio-E-2** (user studioe): `git -C "$(dirname "$(alias beat | sed -E "s/.*[='\"]([^'\"]*run\.(sh|command)).*/\1/")")" pull && beat` — first run prints "✓ essentia" or "✓ librosa"; next download gets a "(NN BPM key key key)" name. Hand-rename the one bad file in its ~/Downloads ("Roddy Ricch - The Box _Official Audio_ (Missing: librosa … ).mp3").
4. **iMessage watcher**: spec `docs/superpowers/specs/2026-06-05-imessage-watcher-design.md`, no plan or code yet. Needs `brew install steipete/tap/imsg` + Terminal Automation→Messages + Accessibility.

**Open — only J can answer:**
1. Trap octave: filename carries 70 or 140 as the model hears it. Always double, always halve, or leave? No rule until J says.
