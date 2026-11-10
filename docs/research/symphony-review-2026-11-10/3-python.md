# Symphony review 3: Python (beat_dl, worktree agent-ac50719d3289288ea)

Standard: ~/.claude/skills/code-symphony/SKILL.md. Read-only; nothing in the repo changed.
All paths below are relative to the worktree root. "Layer history" = git log -S / git show on the named lines.

## Coverage table

| File | Lines | Read fully | Verdict |
|---|---:|---|---|
| bpm.py | 949 | yes | 9 findings (1, 2, 9, 10, 13, 14, 18, 19, 24); marble rate high (5 of 6 hunt categories) |
| downloader.py | 398 | yes | findings 3, 8, 9, 19; rate high |
| app_run.py | 376 | yes | findings 3, 7, 8; rate medium |
| tempocnn_np.py | 135 | yes | duplicate constants only (14), otherwise clean |
| midi_analyze.py | 147 | yes | 1 finding (13: NO_KEYS literal) |
| dropped.py | 53 | yes | clean |
| tools/pt-harvest/harvest.py | 1016 | yes | findings 4, 6, 9, 11, 25; rate high |
| tools/pt-harvest/hlib.py | 728 | yes | findings 12, 17, 19, 20, 22, 24 |
| tools/pt-harvest/beatfind.py | 310 | yes | findings 4, 22 |
| tools/pt-harvest/dialog_clicker.py | 280 | yes | findings 9, 21 |
| tools/pt-harvest/audiocheck.py | 150 | yes | findings 12, 17 |
| tools/pt-harvest/verify_beats.py | 99 | yes | 1 note (22; documented as a deliberate second pass) |
| tools/pt-harvest/manifest.py, manifest_ext.py, manifest_mtime.py | 53, 98, 112 | yes | 1 finding (5) |
| tools/pt-harvest/step.py | 74 | yes | 1 finding (20) |
| tools/pt-harvest dev probes: attest axcheck axinserts axplugin axpress axprobe axscroll axstrip axtempo axtree axvis backups_peek bpmctx bypass_view calib check_row click_at discover drag edldiag edlpeek findprobe infonames keydiag lt_probe ocrdump ocrtest outprobe pt_close pt_launch pt_open_export soloprobe stripnames tlprobe treeshape view vocprobe wins (.py) | 8-110 each | yes | minor items only (20), otherwise clean |
| tools/train-tempocnn/common.py | 152 | yes | findings 14, 16 |
| tools/train-tempocnn/features.py, model.py, parity.py, check_npz.py, eval.py | 109, 115, 101, 37, 106 | yes | duplicate constants only (14) |
| tools/train-tempocnn/train.py | 220 | yes | clean apart from shared constants |
| tools/train-tempocnn/labels_from_db.py | 68 | yes | clean apart from GT path (16) |
| tools/train-tempocnn/key_baseline.py | 210 | yes | findings 13, 15 |
| tools/train-tempocnn/key_eval.py | 76 | yes | findings 13, 16 |
| tools/train-tempocnn/leakage_check.py | 214 | yes | finding 16 and a tolerance note |
| tools/verify-labels/server.py | 272 | yes | finding 16 only; error logging present in every handler |
| docs/research/key-bench/bench.py | 326 | yes | finding 23 (and 13) |
| docs/research/key-bench/calib.py, combo.py, fetch_gs.py, rescore.py | 13, 20, 19, 28 | yes | clean (research one-offs) |

NOT claimed and not read (outside the section list): docs/research/bpm-bench/bench.py (203), tools/build-old-mac/extract-tempocnn-weights.py (222), app/tools/textures.py, app/Sources/Orion/Resources/BeatKeyAbleton.py, friends-page/serve.py, the .sh files in tools/pt-harvest. Nothing in the files marked "yes" was only skimmed.

## Findings (most damaging first)

### Stacks

1. [Next session] bpm.py:259-265 + bpm.py:320-322 (constant at bpm.py:304) - two mechanisms correct the same detune for the key. hpcp_to_pcp12 rolls the global peak onto a semitone bin ("i = int(np.argmax(p)) % res ... p = np.roll(p, -i)"), and key_reading rebuilds the whole HPCP at the track's own A ("H = hpcp_from_peaks(peaks, 440.0 * 2 ** (tuning / 1200))"). The roll still runs on the rebuilt HPCP, and is the only corrector when |tuning| < 5 cents.
   Layer history (oldest to newest): (a) 0c8c57c 2026-09-11 brought hpcp_to_pcp12 with the Key::shiftPcp roll (tracker calls it "detuning correction"); (b) add716a added essentia TuningFrequency as a display-only number (detect_tuning); (c) e20b9ce 2026-11-08 "Live tuning + detune-robust key" replaced TuningFrequency with estimate_tuning and added the HPCP rebuild because (a) did not keep +14/+50 cent audio confident (bpm.py:314-317: "J, 2026-11-08 ... sureness dropped"). (c) was added after (a) to cure what (a) left: compensation. Whether the roll is now a no-op after the rebuild is UNPROVEN (not measured; recon only).
   Source fix: one detune mechanism. Keep the rebuild at the estimated A, delete the roll from hpcp_to_pcp12, and prove with the existing 0/+7/+14/+25/+50/-30 cent bench that top-1 does not move.

2. [Next session] bpm.py:894-903 vs bpm.py:808 - BPM/key analysis has several paths with different failure policies. File mode: essentia+TempoCNN; essentia present, model missing -> `_warn("TempoCNN model missing in models/; BPM via librosa fallback")` and a librosa BPM; no essentia -> librosa BPM and keys. Stream mode: `if not _have_essentia() or not _tempocnn_model_present(): emit error ... Run Doctor`. The same missing model is a silent substitute for files and a loud refusal live. A further fork inside the first: bpm.py:188 `hasattr(es,'AudioLoader')` and bpm.py:204 `hasattr(es,'TempoCNN')` pick the TF vs numpy back end (this one is deliberate: 2af7598 "legacy back end ... same output as TF path", claimed bit-identical on 80 bench tracks).
   Layer history: 58c71ba initial, librosa only; 0c8c57c added essentia and kept librosa as fallback; 2af7598 numpy back end; 13e200a live mode with the strict policy. No librosa reference exists in app/ or any build script (git grep outside docs/tests/bpm.py), so the librosa path looks CLI-only; not proven unreachable in the app.
   Source fix: Doctor/bring-up checks the analyzer once and refuses on mismatch; delete the librosa BPM+key paths and get_loud_section from bpm.py (archive/ if the CLI needs them) so there is one analyzer.

3. [Next session] downloader.py:302-312, 330-346 and app_run.py:254-265 - three nested retry layers over the same yt-dlp failure. Layer 1: fetch_info walks every strategy until one returns JSON. Layer 2: download_audio walks every strategy again (working one first). Layer 3: on failure app_run runs `yt-dlp -U` and repeats the whole thing (_attempt -> run_download -> layers 1 and 2). A dead network costs up to 6 x 2 x 2 yt-dlp calls at up to 600 s each (app_run.py:125).
   Layer history: 58c71ba initial (layers 1+2); 258fac6 2026-10-27 app order + _upgrade_ytdlp retry (layer 3); b9fe774 2026-10-27 removed browser-cookie strategies for the app but left both loops; 76de036 2026-10-28 added message-driven short-circuits (app_run.py:253).
   Source fix: one attempt per strategy that does metadata and download together; upgrade yt-dlp once at bring-up (Doctor), not as a retry after failure.

4. [Next session] tools/pt-harvest/beatfind.py:25-29 + harvest.py:385-402, 457-481, 943-945 - the beat finder is a stack of versions, each added to repair the previous one's misses: v3 vocal ancestry by folder names only; v4 v1 Beat/Instrumental tracks first; v5 alt_sets 8d46498; v6 silent complement accepted when probes are vocal-free 0e0703c; v7 retry with "mute-others" when solo prints silence d27a36f. In harvest.listen the outcome is modes (solo, mute-others) x sources (5) x fractions (0.5, 0.25) as nested retries, wrapped in primary + alt candidate sets, and batch() re-queues old rows by magic finder-version numbers (`(r[2] or 0) < 5`, `< 7`). The legacy rule (beatfind.py:229-251), v2 name/stem scoring, group voting (140-162) and the ear check are four owners of "which tracks are the beat".
   Source fix: one finder, one verdict (the ears) on one candidate list built once; re-queue by `finder_version < FINDER_VERSION` only; no per-version numbers in batch().

5. [Next session] tools/pt-harvest/manifest.py:30, manifest_ext.py:71, manifest_mtime.py:88 - three manifest builders, each carrying its own copy of sha(), fsha(), round_robin(), ROOTS. Layer history: manifest.py 8b9e02a (with discover.py's picker); manifest_ext.py af254d0 (second drive); manifest_mtime.py 2ca81cd 2026-11-02, whose docstring says "447 of 770 ARCH-1 song folders had none, so the whole folder was dropped" - proven compensation for discover.py's file-name picker, which is still wired in and still drops folders.
   Source fix: one builder, one picker (newest .ptx by mtime, variant names ranked lower) over a list of drives; delete the name-based picker.

### Tolerance branches

6. [Next session] tools/pt-harvest/harvest.py:651 vs SCHEMA (43-97) and save() (833-841) - `rec["beat_comments_raw"] = json.dumps(...)` has no column. save() builds its row only from PRAGMA table_info, the additive migration (104-106) only adds columns present in SCHEMA, and the log_jsonl key list (842-847) omits it; grep finds the name once in the whole tool. The value is dropped silently on every row. c4135d1's message says "every raw Beat comment kept in beat_comments_raw". UNPROVEN on Sofia's live DB (a column could have been added by hand there); in this repo it cannot be stored.
   Source fix: save() raises on any rec key that is not a column (or the key joins SCHEMA); no silent `{k: rec.get(k) for k in COLS}` projection.

7. [Next session] app_run.py:81-84, 284-298 with tempocnn_np.py:112 - a clip under ~12 s makes TempoCNN return 0.0 (documented as what essentia-tensorflow returns too); bpm.py prints "0.0"; analyze_file accepts it (float("0.0") is valid) and `if bpm:` is true for the string "0.0", so the file is renamed "<stem> (0.0 BPM <k1> <k2> <k3>)". If no key line parses, keys is [] and the name becomes "(120.0 BPM )". Whether the Swift side filters 0.0 is unproven.
   Source fix: bpm.py prints no BPM line and exits non-zero when it cannot measure (one sentinel, owned by bpm.py); app_run never renames without a BPM and three keys.

8. [Next session] downloader.py:44-53 vs 205-210 and app_run.py:253-254 - the same yt-dlp phrases ("sign in to confirm your age", "not a bot") are matched in two tables (login_reason, explain_error), and app_run drives control flow from the human message text (`msg == downloader.TIMEOUT_MESSAGE or msg in downloader._FINAL_MESSAGES`, a private tuple) although is_final_error(raw_lines) exists. Layers: 58c71ba explain_error; b9fe774 login_reason (second copy of the age/bot phrases); 76de036 more explain_error phrases.
   Source fix: one classifier returning a code (age, bot, members, private, unavailable, region, invalid, blocked, network, timeout); messages are looked up from the code; app_run branches on the code only.

9. [Someday] bpm.py:405-408, 323-324, 756-757, 891-892; app_run.py:153-154, 278-280, 330-332, 348-354; harvest.py:533-534, 749-750; dialog_clicker.py:273-276; hlib.py:354-355 - `except Exception` blocks that substitute None/pass/warning and continue (estimate_tuning, retuned key, decimal BPM twice, run_download crash -> message string, analysis crash -> bpm None, mix_resid_db, source_writes, the clicker scan loop logs only the exception class, track_outputs -> None). Most are logged, but bpm.py:405 and bpm.py:323 return a plausible lesser answer (the 440 reading stands) instead of refusing, so a repeating failure just means every file has no tuning.
   Source fix: decide per call: programmer errors refuse at bring-up; data errors get a narrow `except (OSError, ValueError)`; no `except Exception` around math.

10. [Someday] bpm.py:652 and bpm.py:844-856 - LiveAnalyzer clamps `--window` silently (`max(window, STREAM_TEMPO_SECS)`), and stream_main drops all queued readings except the newest when behind (no log, no event). Source fix: refuse a window under 12 s at argparse; emit a "dropped N readings" event so a persistent backlog is visible.

11. [Someday] tools/pt-harvest/harvest.py:662-682, hlib.py:263 - tempo comes from three sources in a fallback chain (AX field -> AX table -> OCR) with agreement tolerances 0.001, 0.0005, 0.004, 0.01 and no stated source for any; mismatches only add a free-text note. Source fix: AX field is the reading; OCR and EDL are cross-checks that set a "tempo-disputed" status using one named tolerance.

12. [Someday] tools/pt-harvest/audiocheck.py:34 - `subprocess.run(cmd, capture_output=True).stdout` ignores ffmpeg's exit code; a failed decode gives an empty array that features_x reports as mean_db None (reads as silent). Same pattern: hlib.py mean_db (285-289) and duration_s (379-385). Source fix: check=True; the harvest row becomes "error-decode", not "silent".

### Second clocks / duplicate truth

13. [Next session] Key names and spelling are typed out many times: bpm.py:33-34 (MAJOR_NOTES/MINOR_NOTES, Auto-Tune spelling), bpm.py:274 NO_KEYS and midi_analyze.py:133 (literal copy `[('C', 0.0), ('Am', 0.0), ('G', 0.0)]`), key-bench bench.py:15-16, key_baseline.py:41-42, key_eval.py:20-21 (NOTES + FLAT, sharp-only), hlib.py:704 key_label ("D minor" style), and three different norm() parsers (key_baseline.py:48, key_eval.py:24, bench.py:19) with different edge handling. Swift duplicates (grep only): app/Sources/Orion/KeySpelling.swift:11-12, AutoTuneSend.swift:21, DAWSend/AXRoutes.swift:15-16, MidiExport.swift:18, Harmony.swift. Spelling is settled; it is typed 6 times in Python and 5 in Swift.
    Source fix: one key-name module in Python (bpm.py exports fmt_key plus a parse_key; midi_analyze, harvest and the tools import it); Swift keeps one table behind KeySpelling.

14. [Next session] Tempo constants are copied into training code: TEMPOCNN_SR 11025 (bpm.py:44) vs features.py:35 SR = 11025 vs hlib.py:375 `"-ar", "11025"`; class offset 30 (tempocnn_np.py:28 BPM_OFFSET) vs common.py:22 `BPM_MIN, BPM_MAX = 30, 285`; pool table tempocnn_np.py:29 `_POOL_AFTER` vs model.py:20 `POOL_AFTER`; Acc1 tolerance 0.04 (common.py:142, eval.py:72 text, leakage_check.py:204 literal). If the shipped model changes these drift silently; parity.py proves equality for one model only.
    Source fix: tempocnn_np exports SR, BPM_OFFSET, N_CLASSES, POOL_AFTER; training imports them; hlib.to_11k reads bpm.TEMPOCNN_SR.

15. [Next session] tools/train-tempocnn/key_baseline.py:80-84 vs bpm.py:307-330 - detect() hand-builds the key chain (`H = bpm.hpcp_frames(a_key)`; `shipped = ... bpm.keys_from_hpcp(H)`) without peaks, so it bypasses key_reading, i.e. the e20b9ce retune. Its comment says "exactly what the app shows" and its summary labels the row "bgate (shipping: bpm.keys_from_hpcp)". key_baseline.py was written in aa56b94 (2026-11-05), before e20b9ce (2026-11-08); key_eval.py:58 and key-bench bench.py:316 call detect_keys_essentia, which does go through key_reading. Two harnesses now measure two different detectors under the word "shipping".
    Source fix: every harness calls one entry (bpm.key_reading or analyze_full) and no harness rebuilds the chain.

16. [Someday] Five derivations of the ground-truth folder: labels_from_db.py:20-21 and verify_beats.py:24-25 (ROOT/docs/...), key_eval.py:36 (`common.ROOT.parents[2] / "docs/research/..."`, right only inside a worktree at .claude/worktrees/x, wrong in the main checkout), leakage_check.py:66 (default "/Users/jshriver/dev/beat_dl"), verify-labels/server.py:23 (hardcoded "/Users/jshriver/dev/beat_dl/docs/research/pt-ground-truth"). Plus common.py:29-35 `_up()` walks up through every parent directory to find bin/ or bench audio, a tolerance search that can pick any enclosing tree.
    Source fix: one GT path constant in common.py (env override), all five import it; `_up` replaced by an explicit --data-root.

17. [Someday] Three ffmpeg resolution rules: hlib.py:286,374,380 hardcode "/usr/local/bin/ffmpeg|ffprobe"; audiocheck.py:27 picks "/usr/local/bin/ffmpeg if it exists else which"; bpm.py:140-148 `_tool()` uses ORION_BIN -> ./bin -> PATH. Source fix: one resolver.

18. [Someday] Defaults duplicated across the Python/Swift line: gap 3.0 (bpm.py:645, 797; Swift LiveSession.swift:239 `defaultGap = 3.0`), KEY_SR 44100 (bpm.py:43; Swift LiveSession.swift:286 `sampleRate = 44100`, passed as --rate, so Python's default is redundant). Downloads dir: downloader.py:16 (computed at import) vs app_run.py:51-52 (same expression, computed at call).

### More than one owner / dead paths

19. [Someday] Dead or superseded but present: bpm.py:367-376 detect_tuning (only tests/test_bpm_extras.py call it; replaced by estimate_tuning + key_reading in e20b9ce); bpm.py get_loud_section/detect_*_librosa (see 2); hlib.py:389-390 RULERS (unused) and TOOLBAR/read_toolbar/_right_of (only ocrtest.py; harvest.stage_screen has its own tempo-field OCR, harvest.py:155-165); hlib.py:298-313 beat_tree and is_beat_buss (v1; only vocprobe/soloprobe); hlib.py:63-65 is_beat_track (no caller); downloader.py:177-178 (`stem`, `base` computed, unused) and the empty "Format analysis" header (188); download_audio's fmt_id/abr always discarded (downloader.py:337). Source fix: delete (git keeps them).

20. [Someday] Dev probes: tools/pt-harvest/step.py:46 calls `hlib.edl_tempos`, which has never existed in git history (`git log -S "def edl_tempos" -- tools/pt-harvest/hlib.py` is empty; step.py has called it since 8b9e02a), so `step.py info` always dies into its catch-all `ERR AttributeError`. axinserts.py:27 and vocprobe.py:12-13 hold `... if False else None` dead code. view.py:42 and axvis.py:41 write to /tmp/pth_view (axvis never creates it). treeshape.py:6 puts argv into a shell string. Eight probes repeat `next((d for d in dc.windows() if d["title"].startswith("Edit:")), None)`, which hlib.py also repeats four times (lines 461, 543, 578, 605 area). hlib.py and dialog_clicker.py import each other lazily (dialog_clicker.py:204 `import hlib`, hlib.py:458 `import dialog_clicker as dc`). Source fix: one `edit_window()` helper in one AX module; delete probes that existed only for calibration.

21. [Someday] tools/pt-harvest/dialog_clicker.py:31-42, 115-118, 221-231 - "may the clicker press this" has four mechanisms: KNOWN (approved in code), PENDING (approved by a label in approved-dialogs.txt), LICENSE_RULES (same file gate, separate scan), and the Dashboard special case hardcoded inline with its own button heuristic. Source fix: one table (label, window match, button, approved) and one scan loop; the file only flips `approved`.

22. [Someday] tools/pt-harvest/beatfind.py:80-83 vs hlib.py:14,72-74 - attr() and its state set duplicated; beatfind.py:231-234 and :245 re-type hlib.is_beat_buss and is_beat_track as raw regexes, so "what is a Beat Buss" has two definitions. verify_beats.py repeats harvest.mix_resid_db's math (its docstring calls it an independent second pass, so intentional; only flagging that the helper is not shared).

23. [Someday] docs/research/key-bench/bench.py:79-81 ("current bpm.py: top-3 renormalised to 100") and :106-107 ("Exactly what bpm.py does today", m_current = librosa Krumhansl) are stale claims about bpm.py; PROFILES (49-65) copies BGATE/EDMA from bpm.py while m_bpmpy (:309) sits in the same file; METHODS is rebuilt three times (211, 305, 318); hpcp_to_scores (:269-280) is a second copy of bpm.hpcp_to_pcp12 with a `detune` flag.

24. [Someday] Magic numbers without a stated source: hlib.py:668 (bypass colour thresholds 150/60), hlib.py:677 (six OCR vote boxes), harvest.py:38 (WATCHDOG_S 1800, weak note "healthy < 12 min"), harvest.py:395 (-50 dB silence), app_run.py:69 (analysis timeout 120 s, no source), bpm.py:335 refine_bpm span=1.5/step=0.01. Sourced and fine: BoundaryDetector (tuned 2026-11-01, stated), top3_with_confidence (research doc, 39 clips), audiocheck verdict (calibration, beatfind.py:16-17), OPEN_TIMEOUT (607 s note). Markers "temporary", "for now", "hack", "workaround", "TODO" were grepped in my files: none found; "fallback" appears as design wording only.

25. [Someday] Sleeps as synchronisation: harvest.py:143-148, 240, 586-590, 866-870; hlib.py:599, 639-646, 721; dialog_clicker.py:140, 229, 242. relaunch_pt stacks sleep(10) + launch + sleep(20) + 18 x sleep(10) polls; stage_screen sleeps 2 s right after bring_pt_forward, which already sleeps 1.0 s. Source fix: wait on the observable (AX window present, PTSL port open) with one timeout.

## Marble test (rate per file group)

- bpm.py: stack (1), tolerance (2, 9, 10), duplicates (13, 14, 18), dead path (19), unsourced number (24) = 5 of 6 categories. High; the neighbors (key_baseline, key_eval, key-bench) are cracked too.
- downloader.py + app_run.py: stack (3), tolerance (7, 9), duplicates (8, 18), dead (19). 4 of 6. High.
- harvest.py + hlib.py + beatfind.py: stack (4), tolerance (6, 9, 11, 12), duplicates (17, 22), dead (19), sleeps (25). 5 of 6. High.
- dialog_clicker.py: duplicate mechanisms (21), tolerance (9). 2 of 6. Medium.
- manifest*.py: stack + copied helpers (5). Medium.
- key_baseline.py / key_eval.py / key-bench bench.py: duplicate truth (13, 15, 16, 23) with a measured drift in key_baseline. High for this group.
- tempocnn_np.py, dropped.py, midi_analyze.py (one literal), train.py, model.py, verify-labels/server.py (path only): 0 or 1 findings. Clean or near clean.

## Ordinary correctness items noticed (secondary)
- app_run.py:107-108 rebinds `name` inside analyze_file's extras loop (it held the file name used by earlier log lines; harmless today).
- bpm.py:913 and :835 both install the SIGUSR1 handler (the second is redundant).
- leakage_check.py:128-129: a failed feature load logs an error and the run continues over fewer rows; the final percentages do not say they cover a smaller set.

## Run log (errors and skips)
- First Read of bpm.py returned lines 1-500 (limit set); a second Read from line 500 to the end succeeded. No file was unreadable.
- Two bash outputs exceeded the inline limit (pt-harvest small probes; train-tempocnn files). Both were saved by the tool and re-read from the saved copies in full. Nothing skipped.
- Two git/bash invocations were refused by the worktree guard ("too complex to verify"): a for-loop around `git log -S` over six patterns, and a heredoc write combined with the report. Re-ran the git queries as plain separate `git log -S` commands (history obtained for strategies_to_try, _upgrade_ytdlp, def login_reason, "sign in to confirm your age", _STRATEGIES). The patterns "def explain_error" and "def cookies_stale" were not re-run; the explain_error history in finding 8 rests on the phrase search plus the 58c71ba/76de036 attribution inferred from it (so the exact first commit of explain_error is not individually proven).
- `git log -S "def edl_tempos" -- tools/pt-harvest/hlib.py` returned nothing: the function never existed in this repo's history. Sofia's copy of hlib.py may differ (the repo mirrors Sofia; sync not proven).
- UNPROVEN, stated where used: whether the hpcp_to_pcp12 roll is a no-op after the e20b9ce rebuild (needs a measurement run, not done: recon only); whether Sofia's live DB has a beat_comments_raw column; whether the app filters a "0.0" BPM; whether the librosa path is reachable in any shipped build.
- Not read (outside the claimed list): bpm-bench/bench.py, build-old-mac/extract-tempocnn-weights.py, app/tools/textures.py, BeatKeyAbleton.py, friends-page/serve.py, tools/pt-harvest/*.sh. tests/, vendor/, archive/ excluded by instruction.
- No harvest, training, download or notification command was run; no file in the repo was changed; no other machine was contacted.
