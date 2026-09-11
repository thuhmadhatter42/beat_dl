# PICKUP — beat_dl

## CURRENT STATE — 2026-09-11 06:02

**What this is:** YouTube → MP3 downloader with BPM/key tagging. Bash loop (run.sh) + downloader.py (yt-dlp) + bpm.py (Essentia TempoCNN for BPM, Essentia HPCP + bgate for key; librosa only where essentia has no wheel). Launched by run.command or the `beat` alias. Also called by the Jownloader Brave extension (`~/dev/brave_img-downloader/extension`) through a native host that pipes a URL into run.sh.

**Git:** main = origin/main = 80d4b55, tree clean, pushed.

**Landed 2026-09-11:**
- 0c8c57c: BPM 30% → 87.5% Acc1 (40 GiantSteps clips), key 43.6% → 79.5% exact (39 GS+ clips), ~2 s/track. Model `models/deeptemp-k16-3.pb` vendored (CC BY-NC-SA). Research + re-runnable benches in `docs/research/` (datasets git-ignored; `fetch.sh` re-downloads).
- 80d4b55: deps.sh installs ONE analyzer, auto-picked: essentia-tensorflow if it imports on this Mac, else librosa (+ numba repair). Root cause of "no tags at all" since 2026-09-08 was numba lagging numpy 2.5.3.
- librosa's `beat_track` segfaults on py3.14 + numba 0.67 → fallback uses `librosa.feature.tempo`.

**Open — J must answer:**
1. Trap octave: filename carries 70 or 140 as the model hears it. Should it always be doubled (or halved)? No rule until J says.
2. Studio-E-2 (user studioe, NOT Intel): needs the pull. Repo path there unknown — `alias beat` shows it. Command given to J:
   `git -C "$(dirname "$(alias beat | sed -E "s/.*[='\"]([^'\"]*run\.(sh|command)).*/\1/")")" pull && beat`
   First run prints "✓ essentia" (macOS ≥ 15) or "✓ librosa". Then one download should get a "(NN BPM key key key)" name. One old bad file to hand-rename in its ~/Downloads: "Roddy Ricch - The Box _Official Audio_ (Missing: librosa … ).mp3".

**Next:** nothing queued beyond the two open items. iMessage watcher spec (docs/superpowers/specs/2026-06-05-imessage-watcher-design.md) still has no plan/implementation.
