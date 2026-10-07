# Harvest 200 PT sessions with BPM, then fine-tune TempoCNN — plan (2026-10-06 22:45)

J (21:59): "as soon as you do it, get like 200 songs with their BPM for training. And then do the
training. Don't stop until all of this is done." Spec: `docs/superpowers/specs/2026-09-12-protools-
autotune-ground-truth-design.md` (§5 trial, §7 J's decisions). This plan replaces the spec's
one-session-a-day cron with one continuous verified run. The spec's other rules still hold.

## What trial step 1 proved (session 1; its text dump stays on Sofia only)
- `CId_ExportSessionInfoAsText` gives per-track `PLUG-INS:`, `STATE:` (Inactive/Muted/Hidden),
  per-track clip EDL rows, and track `COMMENTS:`.
  - The Beat track's comment was `Dm152` (key + BPM, written by J).
  - The text has **no tempo** and **no folders/buses**.
- Session tempo is visible only in the Edit window: the tempo ruler and the "Tempo 152.0000" field
  in the counter area.
- Clicks over ssh work (Python has Accessibility). Apple Events over ssh return -600, so dialogs are
  handled by pixels: skill `sofia-screen` and `tools/pt-harvest/dialog_clicker.py`. That clicker is
  calibrated only for Missing Files and Session Notes; UAD and Save are still placeholders.
- MBP has 17 GB free. Full bounces stay on Sofia; only 11025 Hz mono copies come to the MBP.

## §1 Calibrate the dialog clicker
Open trial session 2. Capture the UAD dialog (it appears on every open: no UAD
hardware) and, on close, any Save prompt. Fill in their regions and buttons in `dialog_clicker.py`.
Run it in watch mode during every open/close from here on. J approved exactly 4 clicks:
UAD → OK, Session Notes → No, Missing Files → OK, Save → Don't Save. Anything else → stop and report.

## §2 Tempo reader
Read the session tempo with no human in the loop:
- Screenshot the Edit window and crop the counter's "Tempo" field (location found on session 1/2).
- OCR the crop with macOS Vision (`VNRecognizeTextRequest` via pyobjc-framework-Vision) in our own
  venv on Sofia, `~/pt-harvest/.venv`. Never modify stem-bouncer's venv.
- Save every crop as evidence.
- Also crop the tempo ruler. More than one tempo event visible → `tempo_map_flat=0`.
Verify on sessions 1-5 against what is visible on screen.

## §3 Beat audio
Bounce the beat per spec §2.8 / §7.2:
- Solo what feeds `Beat Buss`. In session 1, "Beat Buss" is the output bus of the Beat tracks, not a
  folder, so find it with `CId_GetTrackList` (output/folder fields).
- Offline `CId_ExportMix` to Sofia's internal disk, `~/pt-harvest/audio/<YY-M-D>_<Song>_<Artist>_BEAT.wav`.
- Check it is not silent (mean_volume > −50 dB). Restore solo state. Never save.
- No Beat Buss → skip the session and log it. Silent bounce → `beat_wav_path` NULL + note
  "silent bounce (SSL session?)".
- Make an 11025 Hz mono 16-bit copy for training (ffmpeg on Sofia).

## §4 Labels, one row per session
Write a SQLite STRICT table per spec §4 at `docs/research/pt-ground-truth/pt-ground-truth.sqlite3`,
plus columns `session_tempo REAL`, `beat_comment TEXT`, `bpm_source TEXT`, `bpm_confidence TEXT`.

BPM label rules:
- `confirmed`: session tempo agrees with at least one independent source.
  - Independent sources: the Beat track comment's number, or a producer BPM in the beat's source
    file name (e.g. "152bpm").
  - **Never** use a beat_dl-style "(NN.N BPM Key …)" filename as a source. That is our own
    estimate, and using it would be circular.
- `tempo-only`: session tempo ≠ 120.0000 with no other source. Usable, but flagged.
- `excluded`: session tempo = 120.0000 (PT's default) with no confirmation, or `tempo_map_flat=0`.

Key: parse the Beat comment when present (e.g. `Dm152` → "D minor"), as a bonus column.
Auto-Tune clicking is NOT part of this run (J asked for BPM).

## §5 Sessions 2-5, verified one at a time
Full pipeline per session.
- Go/no-go: row correct, WAV not silent, tempo crop legible and matching the screen.
- Any miss → fix before the next session.

## §6 Batch to 200 usable rows
Sampling:
- From `discover.json`'s 323 valid newest mixes, prefer recent era and spread across artists,
  random within each artist. Use 2022 and earlier only if needed.
- Keep going until 200 rows are `confirmed` or `tempo-only` with a non-silent beat.

Running it:
- Resumable: skip sessions already in the DB; JSONL log `docs/research/pt-ground-truth/logs/harvest-<date>.jsonl`.
- Every session must close without saving, even on error.
- Pro Tools hung > 10 min → screenshot, kill PT, relaunch, log, continue.
- Rsync the 11025 Hz copies to the MBP at `docs/research/pt-ground-truth/audio11k/` (gitignored by *.wav).

## §7 Training harness (parallel with §1-§6)
Build `tools/train-tempocnn/` on the MBP:
- PyTorch replica of deeptemp-k16-3, loaded from `models/deeptemp-k16-3.npz`.
- Proof of parity: identical class outputs to `tempocnn_np.py` on the 80 bench tracks.
- Features: the same essentia mel front end as `tempocnn_np.py`, so train = inference.
- Fine-tune with patches + augmentation (tempo-shift via resampling, as in the TempoCNN paper).
- Export back to `.npz` with the same keys.

## §8 Train + evaluate
- Split by artist: about 150 train, 50 test, with no artist in both.
- Report Acc1 (±4 %) and Acc2 (×2, ×½, ×3, ×⅓ also allowed) for current vs fine-tuned on:
  - (a) the 50 held-out PT beats;
  - (b) the existing benches: `docs/research/bpm-bench` (40-track subset + results.tsv) and the
    key-bench audio.
- Ship only if (a) improves and (b) doesn't drop. Shipping means a new `models/*.npz`,
  `ANALYZER_BUILD` bump in `deps.sh`, push.
- Otherwise report the numbers and keep the current model.

## §9 Report to J
Rows harvested, label sources, accuracy table, shipped or not, and what's left (Auto-Tune key read,
review playlist).

## §10 Full-mix bounces + beat-vs-mix eval (J, 01:08)
- Every usable session also gets a full-mix bounce (vocals + beat, original solo state), saved as `audio/NNNN_mix.wav` with an 11k copy `audio11k/NNNN_mix.wav`. Same labels. Rows done before this change are back-filled.
- J: "just see if adding a vocal changes the results at all. That would double our sample size with a new distinct group."
- Eval reports beat vs mix separately, for the original and the fine-tuned model. Training may use both groups; the split stays by artist, so a session's beat and mix always land on the same side.

## §11 Smart beat finder (J, 01:06)
"You should be able to figure out where the beat bus is." Detect the beat in any session from routing, folder names, excluding vocals, clip shape, and a short probe bounce with a drum check. Re-queue sessions that were skipped for having no beat, and continue onto ALL MIXES (dedupe by hash) until there are 200.
