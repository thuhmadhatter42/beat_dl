# Key baseline on J's keyed beats, 2026-11-05 (MBP, local DB)

The baseline a trained key model has to beat. Plan: docs/plans/2026-11-05-afternoon-push.md §3.

- **Detector:** the shipping path, `bpm.load_audio_essentia` -> `bpm.hpcp_frames` -> `bpm.keys_from_hpcp`
  (essentia 36-bin HPCP, `BGATE` profiles, the same function the app's file analyzer and live listener
  call). Variant: `EDMA` profile on the same HPCP (bpm.py keeps it for the librosa fallback).
- **Data:** local `pt-ground-truth.sqlite3`, 101 rows, the 30 with `key` set (22 `autotune`, 3 `comment`,
  5 `comment+autotune`). Each row scored on its beat bounce and its full-mix bounce (60 files, 0 failed).
  Sofia's 333 rows / 91 keyed not included (Sofia offline).
- **Audio:** the 11 kHz copies (`audio11k/`); no full-rate copies exist on this Mac. The detector resamples
  to 44.1 kHz as the app does. HPCP reads only 25-3500 Hz, below the 5.5 kHz Nyquist of an 11 kHz file.
  Check: 40 full-rate key-bench clips run full-rate vs squeezed through 11025 Hz and back gave the same
  top-1 40/40 and the same top-3 set 40/40. So the 11 kHz copies should give the same answers as full-rate
  bounces. That check ran on bench clips, not on J's own full-rate bounces.
- Scoring: top-1 vs truth (pitch class + mode, enharmonics equal). relative = C <-> Am, fifth = same mode
  +-7 semitones, parallel = C <-> Cm. "In top-3" = truth anywhere in the 3 keys the app shows.
  MIREX = 1 / .5 fifth / .3 relative / .2 parallel / 0.

## Headline (shipping bgate, beat bounces, n = 30)

| | top-1 exact | in top-3 | relative | fifth | parallel | other | MIREX |
|---|---:|---:|---:|---:|---:|---:|---:|
| **all** | **24 (80%)** | **28 (93%)** | 0 | 2 | 0 | 4 | 0.833 |
| autotune (22) | 20 (91%) | 22 (100%) | 0 | 1 | 0 | 1 | 0.932 |
| comment (3) | 1 (33%) | 2 (67%) | 0 | 1 | 0 | 1 | 0.500 |
| comment+autotune (5) | 3 (60%) | 4 (80%) | 0 | 0 | 0 | 2 | 0.600 |

## All four tables

| variant, bounce | n | top-1 exact | in top-3 | relative | fifth | parallel | other | MIREX |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| bgate (shipping), beat | 30 | 24 (80%) | 28 (93%) | 0 | 2 | 0 | 4 | 0.833 |
| bgate (shipping), mix | 30 | 23 (77%) | 29 (97%) | 0 | 3 | 0 | 4 | 0.817 |
| edma, beat | 30 | 22 (73%) | 27 (90%) | 0 | 2 | 2 | 4 | 0.780 |
| edma, mix | 30 | 23 (77%) | 27 (90%) | 0 | 2 | 2 | 3 | 0.813 |

Per key_source for every variant: `summary.md`. Per file: `results.tsv` (ids only).

## The errors (bgate, beat + mix)

| id | source | truth | top-3 shown | category |
|---|---|---|---|---|
| pt0037 / m | comment+autotune | B | Ebm, G#m, B | other (relative minor is #2) |
| pt0039 / m | comment+autotune | Bm | C, Cm, Em (mix: C, Em, Bm) | other (a semitone up: tuning?) |
| pt0043 / m | autotune | G#m | C#m, G#m, Db | fifth (predicts the IV) |
| pt0057 / m | comment | Em | A, Am, Em | other (the IV's key, major) |
| pt0061m | autotune | Gm | Cm, Gm, Bb | fifth (IV), mix only |
| pt0067 / m | autotune | Cm | F, C, Cm | other (the IV's key, major) |
| pt0095 / m | comment | G#m | C#m, Db, Ab | fifth (IV) |

Pattern: 4 of the 6 beats it gets wrong come out a fourth up (the subdominant), in minor or major. The
truth is still #2 or #3 in all of these except pt0095. That is something a trained model could learn.
pt0039 is a semitone off, which may be a detuned beat rather than a profile error.

## Doubts about this measurement

1. **n = 30, 27 minor / 3 major.** bgate leans minor (bpm.py caps major confidence for that reason),
   so this set flatters it. The per-source rows have n = 3 and 5, too few to compare sources.
2. **Auto-Tune labels may not be independent of Beat Key.** If the Auto-Tune key was set from Beat Key's
   own readout, the 22 `autotune` rows (91%) score the detector against itself. The `comment` rows
   (beat maker's key, n = 8 including comment+autotune) score 4/8 top-1. That is the more independent
   number, but n is tiny. Ask J how the Auto-Tune key is usually picked.
3. 11 kHz audio: see the parity check above (bench clips, 40/40). Not checked against J's own full-rate
   bounces (they are on Sofia).

## Re-run (Sofia's 91 keyed rows, after `tools/pt-harvest/sync_from_sofia.sh`)

```sh
tools/pt-harvest/sync_from_sofia.sh            # read-only pull of DB + audio11k; old DB -> archive/
bin/python/bin/python3 tools/train-tempocnn/key_baseline.py \
  --db docs/research/pt-ground-truth/pt-ground-truth.sqlite3 \
  --audio-root docs/research/pt-ground-truth/audio11k \
  --out tools/train-tempocnn/runs/key-baseline-<date> \
  --parity-dir docs/research/key-bench/audio     # optional; or a folder of full-rate PT bounces (sync --full)
```

Run from the main checkout (bin/ and the data are untracked and live only there). Writes `results.tsv`,
`summary.md`, `key_baseline.log`. A bad file is logged and skipped. This run took ~3 min for 60 files + 40
parity clips.

## Tempo retrain on the bigger DB, one command

```sh
tools/train-tempocnn/retrain.sh                 # optional: --db DB --audio-dir DIR
```

`retrain.sh` (new) chains the README's "when the harvest has landed" steps: labels_from_db -> features
--augment -> parity -> train (next free `ft<N>`) -> eval. It makes `.venv` with uv if it is missing,
stops at the first failing step, and logs to `runs/retrain-<stamp>.log`. Checked: `labels_from_db.py` runs on the
local DB (155 labels, 78 beat + 77 mix, 33 artists). Both scripts pass `bash -n`. The training venv does
not exist on this Mac yet, so the first run installs torch. The chain was not run end to end today.
