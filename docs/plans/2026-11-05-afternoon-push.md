# Afternoon push — 2026-11-05 13:10 → hard stop 17:00 (state saved by then, J)

Goal (J 13:08): as much progress as possible with what we have, before 17:00. The iLok is NOT in Sofia, so nothing that opens Pro Tools.

## §1 Save state deep (13:10-13:35)
save-state + deep sweep agent (Sonnet, medium, worktree). Merge, grade.

## §2 Tempo retrain on the bigger harvest (agent A, 13:35-16:00)
- Data: Sofia ~/pt-harvest DB pt-ground-truth.sqlite3 (last id 333, usable 243) + its 11k beat wavs; the 2026-10-09 run used 78. Copy to the MBP (rsync via ssh, read-only on Sofia).
- Harness: tools/train-tempocnn (plan docs/superpowers/plans/2026-10-06-pt-bpm-harvest-and-train.md §7-§8). Same artist split rule, same ship rule: ship only if held-out Acc1 improves AND bpm-bench Acc1 does not drop.
- Output: tools/train-tempocnn/runs/<run>/eval.md + candidate .npz; a result table. No ship without the rule passing; nothing replaces the shipped model this afternoon.

## §3 Key accuracy on J's keyed beats (agent A, after §2 or in parallel)
- 91 harvested beats have a key from the Beat comment / filename. Score the current key formula (bpm.py / bgate) on them: exact, relative, fifth, parallel. Report per-error type. This is the baseline the "trained key model" must beat later.
- Output: tools/train-tempocnn/runs/key-baseline-2026-11-05/eval.md.

## §4 "Wrong, it's X" button (agent B, 13:35-16:00)
In-app teach button (j241): saves the analysed clip + J's chosen key to ~/Library/Application Support/Beat Key/teach/ (wav or source path + JSON label), logged in beatkey.log. Swift tests pass. No release.

## §5 Play-to-find-the-key + ⇧⌘A (agent B, if time)
Spec: PICKUP block 2026-11-02 02:08 item 2c. Musical Typing layout, last note = root, space toggles major/minor, sets KeyChoice; ⇧⌘A focused = Send to Auto-Tune.

## §6 Stop + save (16:15-16:55)
16:15 tell agents to wrap; 16:30 merge/grade, remove worktrees; 16:35 save-state; 16:55 verified. Anything unfinished goes into PICKUP verbatim.

Not this afternoon: Auto-Tune key read in the harvest (needs the iLok to test), Waves Tune test (needs J), release (J runs publish).
