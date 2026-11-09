# ftC (run ft1) train/test leakage check, 2026-11-09

Verdict: **essentially clean.** One test session (2 rows of 130) has a confirmed near-duplicate in train. Removing it, or every flagged session, leaves held-out Acc1 at 85.9-86.5 % (original 66 %). The +20 points is not leakage. The real weaknesses are small effective n and a 6-artist test set (below).

## How the split was made (common.py `split_by_artist`, train.py, seed 1234)
- Unit = **artist** (a folder hash, `sessions.artist`), not song. Whole artists go to test until about 25 % of rows, then whole artists of the rest go to val (15 %, early stopping), the remainder is train.
- A session's beat row (`ptNNNN`) and mix row (`ptNNNNm`) share the artist, so they land on the same side.
- ftC = `runs/ft1` (split.json: train 293 / val 60 / test 130 rows; artists 30 / 6 / 6). 243 sessions, 483 rows (243 beat, 240 mix).
- Held-out test = 65 sessions from 6 artists (130 rows, beat and mix of each session counted separately).

## Overlap, test vs train+val (`leakage_check.py`, log `runs/leakage-check.log`)
| method | count |
|---|---:|
| same row id on both sides | 0 |
| same session id on both sides | 0 |
| same artist on both sides | 0 |
| session with beat and mix on different sides | 0 |
| same Pro Tools session (`ptx_sha1`, DB UNIQUE) | 0 |
| same bpm + beat duration (+/-0.05 s), different session | 2 test sessions (47, 265) |
| same bpm + key (weak) | 2 |
| audio fingerprint, single 120-frame window, best score >= 0.85 | 1 session (243, 2 rows tied to train session 49) |
| audio confirmed duplicate, 5 windows, >= 0.9 | **1 session (243 vs 49)** |

Name-based matching (strip "mix N", "MASTER", version numbers) was not possible: the DB stores only opaque hashes (artist = sha1 prefix, session = sha1 of path), no names. So metadata and audio stand in for it.

Fingerprint: z-scored mel bands from the cache (the exact features the model sees), a 120-frame query window slid over the candidate with FFT cross-correlation, score = best mean per-band correlation. Unrelated pairs: median 0.24, p99 0.51 (test x train/val, 130 x 353 pairs). Positive control, beat vs its own mix: median 0.70 (vocals change the mel profile), max 1.00.

## The hits (session ids)
- **243 (test) vs 49 (train): confirmed.** beat-beat 1.00, beat-mix 1.00, mix-mix 0.94. Both bpm 137, different artist folders, durations 155.2 s vs 157.3 s: two versions of one song filed under two artists. Both labels "tempo-only".
- 47 (test) vs 193 and 199 (train): same bpm 100 and duration 135.4 s, but audio 0.41-0.60. Not a match, coincidence.
- 265 (test) vs 150 (train): same bpm 150 and duration 154.6 s, audio 0.31-0.63. Not a match.
- Next strongest fingerprint pairs 0.66-0.82 (ids 67/137, 132/325, 161/213, 164/266, 238/280, 264/302): above the unrelated p99 but well under the 1.0 / 0.94 of the true duplicate. Likely shared style or sample, not the same recording. Not confirmed.

## Held-out accuracy without the flagged items (from existing `runs/ft1/eval.tsv`, no model re-run; Acc1 = within 4 %)
| test subset | n rows | original Acc1 | fine-tuned Acc1 |
|---|---:|---:|---:|
| all held-out | 130 | 66.2 % | 86.2 % |
| without confirmed duplicate (243) | 128 | 66.4 % | 85.9 % |
| without metadata-flagged (47, 265) | 126 | 65.9 % | 86.5 % |
| without all flagged | 124 | 66.1 % | 86.3 % |

## What does still make the number fishy (not leakage)
1. **Effective n is 65, not 130.** Beat and mix of a session are the same song and nearly always right or wrong together. One session is worth 1.5 points.
2. **Only 6 test artists**, so one artist's habits can swing the result by several points. Within-test, 9 rows have a near-dup in a different test session, so the data holds repeated songs; dups of the same artist stay on one side, but a cross-artist repeat like 243/49 can still straddle the split. The check found one.
3. Val also moved a lot (55 % -> 78 % Acc1), consistent with the test gain: fine-tuning on this library's style helps on its held-out artists. Val has 2 sessions with a cross-artist train session of same bpm + duration (metadata only, not audio-checked), which only affects early stopping.
4. bpm-bench (public GiantSteps clips) went **down**, 87.5 % -> 82.5 %: the gain is specific to this producer library's sound, it does not transfer. Labels are mostly "tempo-only", not confirmed.
5. Artist folders are not songs. The same song can sit under two artists (243/49), so an artist split can leak; this check rules out any large-scale leak but a 120-frame fingerprint would miss a re-mixed or re-arranged copy.

## Method limits
Duration/bpm matching assumes a duplicate has the same length; a differently trimmed copy would be caught only by the fingerprint. The fingerprint compares 1 window of the middle (5 windows for flagged pairs), so a copy that differs at that point could score low. Both methods agree on one duplicate and no others.

## Re-run
`bin/python/bin/python3.11 tools/train-tempocnn/leakage_check.py` (reads the main checkout's cache, DB and runs/ft1; about 6 minutes). Log: `tools/train-tempocnn/runs/leakage-check.log` (+ `.json`).
