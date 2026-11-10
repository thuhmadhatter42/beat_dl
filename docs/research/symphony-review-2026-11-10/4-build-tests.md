# Symphony review 4: build / release / install machinery and tests

Repo: beat_dl worktree agent-a7cd31778ef1480ca (VERSION = 0.1.59). Recon only: nothing changed, nothing built or run.
Standard: ~/.claude/skills/code-symphony/SKILL.md (rules 1-8). Method: every claimed file read in full, then `git log -S` / `git show` for layer history where a stack was suspected.

## Coverage table

| File | Lines | Read fully | Verdict |
|---|---|---|---|
| app/build.sh | 256 | yes | 9 findings (F2, F4, F5, F7, F8, F9, F11; marble: ~9 problems in 14 stages) |
| app/runtime.sh | 116 | yes | 4 findings (F3, F2, F5; marble: 4 problems in 6 functions) |
| app/Package.swift | 25 | yes | 1 (min OS duplicate, F5) |
| app/Info.plist | 63 | yes | 1 (F5 duplicates: bundle id, min OS, name) |
| app/entitlements.plist | 9 | yes | clean |
| app/entitlements-app.plist | 20 | yes | 1 (key list duplicated in build.sh asserts, F5) |
| app/entitlements-deno.plist | 17 | yes | 1 (same) |
| app/entitlements-ytdlp.plist | 18 | yes | 1 (same) |
| app/dmg/make_background.swift | 121 | yes | 1 (layout constants copied, F4) |
| app/dmg/background.png, background@2x.png | binary | no (binary art, checked for existence only via build.sh:31) | n/a |
| app/tools/textures.py | 88 | yes | 1 minor (F22) |
| app/RELEASING.md | 50 | yes | 2 (stale version sentence line 31, procedure duplicated by publish.sh, F6) |
| tools/publish.sh | 18 | yes | 4 (F1) |
| tools/build-old-mac/check-macho.sh | 40 | yes | clean |
| tools/build-old-mac/essentia.sh | 209 | yes | clean (pinned hashes, set -euo pipefail, every `|| true` justified: grep for display only) |
| tools/build-old-mac/ffmpeg-arm64.sh | 96 | yes | clean (GPG check is "only if gpg installed" at :41, sha256 pin is the real gate) |
| tools/build-old-mac/extract-tempocnn-weights.py | 222 | yes | clean as code; header is stale (F15) |
| install.command | 19 | yes | 1 (F10) |
| run.command | 7 | yes | clean |
| run.sh | 95 | yes | 3 (F10, F12) |
| deps.sh | 140 | yes | 4 (F10, F11; marble: 4 problems in 9 functions) |
| VERSION | 1 | yes | clean (it is the source; hardcodes elsewhere are F6) |
| tests/fixtures/make_click.sh | 18 | yes | 1 (F13, duplicate signal) |
| docs/research/bpm-bench/fetch.sh | 19 | yes | 1 minor (F23: `set -e` only, no pipefail, pins an IP) |
| docs/research/key-bench/fetch.sh | 11 | yes | 1 minor (F23) |
| tools/train-tempocnn/retrain.sh | 46 | yes | 1 (F15 model naming); otherwise rigid |
| tools/pt-harvest/btail.sh | 9 | yes | clean |
| tools/pt-harvest/ilokcheck.sh | 5 | yes | clean |
| tools/pt-harvest/ptkill.sh | 8 | yes | 1 minor (pattern duplicated with harvest.py by its own comment, F16) |
| tools/pt-harvest/ptslcmds.sh | 5 | yes | clean |
| tools/pt-harvest/rtail.sh | 7 | yes | clean |
| tools/pt-harvest/run_batch.sh | 38 | yes | 1 (`sleep 2`, F16) |
| tools/pt-harvest/sv.sh | 52 | yes | 3 (F16) |
| tools/pt-harvest/sync_from_sofia.sh | 67 | yes | 2 (F16) |
| tools/pt-harvest/usblist.sh | 3 | yes | clean |
| tools/pt-harvest/waitnew.sh | 16 | yes | clean |
| tools/pt-harvest/watch.sh | 15 | yes | 2 (F16) |
| tests/stub/yt-dlp | 105 | yes | clean |
| app/Tests/OrionTests/AccentTests.swift | 247 | yes | 3 (F17 render, F20 timing :123, F21 suite) |
| AccessibilityTests.swift | 105 | yes | clean (tearDown does not call super, trivial) |
| AutoTuneSendTests.swift | 41 | yes | clean |
| AXDriverTests.swift | 468 | yes | clean (fake tree, 0.05 s timeout is on a synchronous fake) |
| BeatKeyTests.swift | 296 | yes | 5 (F14 constants/text-greps :241, :54-55, :71-72; F20 negative waits :190, :259, :271; :240 no assertion) |
| DAWSendTests.swift | 327 | yes | 2 (F20 fixed ports 47_041-47_044, 47_416, 47_499; Thread.sleep :175) |
| EngineTests.swift | 182 | yes | 1 (F20 :88 0.7 s vs Engine.swift:238 0.4 s) |
| EventTests.swift | 37 | yes | clean |
| FaceplateTests.swift | 233 | yes | 2 (F14 pinned design numbers :15-16, :83, :105; duplicate errorText :181) |
| FooterReadoutRenderTests.swift | 74 | yes | 1 (F17, the whole file is a generator) |
| HarmonyTests.swift | 432 | yes | 3 (F17 :379; :308 magic 19; :364 depends on system sound bank) |
| HelpTests.swift | 176 | yes | 2 (F17 :127; source-grep :61) |
| HoldSpellingTests.swift | 204 | yes | 1 (F21 suite leak :84, :136) |
| HotkeyTests.swift | 95 | yes | 2 (F21 :22; registers a real global hotkey :74-83) |
| KeyChoiceTests.swift | 64 | yes | 1 (F21 fixed suite "KeyChoiceTests" :45 never removed) |
| KeyTeachTests.swift | 189 | yes | 1 (F21 `trashItem` :16) |
| ListenLogTests.swift | 282 | yes | 3 (F18 hardcoded path :236; F13 duplicate; :280 contrived assertion) |
| LiveFallbackTests.swift | 94 | yes | clean |
| LiveTests.swift | 423 | yes | 3 (F18 :390; F13; F14 :233-246 greps build.sh) |
| LoginItemTests.swift | 70 | yes | clean |
| LoginTests.swift | 284 | yes | clean (wall-clock `soon` is stable within a run) |
| ManualKeySelectionTests.swift | 235 | yes | 2 (F17 :190; F21 :14) |
| MarketingRenderTests.swift | 93 | yes | 1 (F17, whole file a generator; also F21 :72) |
| MenuBarTests.swift | 58 | yes | clean |
| MidiExportTests.swift | 90 | yes | 1 (:62-89 can silently skip: system python3, ImportError -> SKIP) |
| MiniTests.swift | 269 | yes | 2 (F17 :238; unseeded random :151) |
| MotionFrameTests.swift | 387 | yes | 5 (F9 flake lines; F19 duplicate of LiveTests; shared static `FrameProbe.stamps` :54) |
| MotionTests.swift | 141 | yes | 3 (F14 :58-73 constants twice; :139 only non-nil) |
| PocketTests.swift | 223 | yes | 1 (F17 :132) |
| ReadingTests.swift | 285 | yes | clean |
| SongBoundaryTests.swift | 172 | yes | clean (injected clock) |
| SpellingMenuBarTests.swift | 249 | yes | 2 (F17 :170; F21 :15) |
| WavesTuneSendTests.swift | 23 | yes | 1 (:6 temp .xps never removed) |
| WindowParityTests.swift | 152 | yes | 1 (F17 :85) |
| tests/test_app_run.py | 573 | yes | 3 (F12b WAV fixture :17; :71/:82 duplicate; needs essentia but not skipped) |
| tests/test_bpm_extras.py | 339 | yes | 2 (F18 :311 hardcoded ffmpeg; skips) |
| tests/test_bpm_stream.py | 263 | yes | 2 (F20 sleeps :211, :213; F13 duplicate signal) |
| tests/test_bpm_tuning.py | 197 | yes | 1 minor (expected_key derives its expectation from the measured value, :70-75) |
| tests/test_daw_scripts.py | 199 | yes | 1 (lua / node absent = silent skip :131, :181) |

Totals: 26 shell scripts claimed (all in the `git ls-files` list, none skipped) + 1 extensionless shell stub; 34 Swift test files (6,700 lines); 5 Python test files (1,571 lines). All read in full except the two binary PNGs.

---

## Findings (most damaging first)

### Release machinery

**F1. [Now] tools/publish.sh:11-18 — the publish script makes the public release before it checks anything, and says PUBLISHED no matter what.**
Evidence, each quoted:
- `:11` `git tag -f "Beat-Key-$V" && git push origin main && git push origin "Beat-Key-$V"` — the tag goes on HEAD, the push is of `main`. If HEAD is not main the tag points at a commit that is not the one pushed. Nothing checks branch or a clean tree.
- `:12` `gh release create ...` (public, irreversible) runs BEFORE `:13` `test ! -e ~/fourletterrecords/beat-key-releases/Beat-Key-$V.dmg`. If that file already exists the script dies after the GitHub release is live: GitHub on the new version, site not, no rollback, and a rerun fails at `gh release create` because the release exists.
- `:10` only `xcrun stapler validate "$D"` is checked. Nothing checks that `app/build/appcast.xml` names `$V`. build.sh writes that file with `$VER` (build.sh:233-250), but a stale appcast left in `app/build/` from an earlier build uploads happily and every installed Beat Key reads the wrong feed.
- `:17` `curl -sI ... | head -1` prints a line but asserts nothing; `:18` `echo "PUBLISHED $V"` runs regardless. RELEASING.md:43 says the check is "→ 303"; the script does not enforce it.
- `:14`, `:16` use `scp` for Sofia, not ssh-rc. Whether scp hides a failure the way ssh does is unproven (my guess: it returns a real code); the rule in CLAUDE.md is about ssh.
- `:8` `V=$(cat VERSION)` vs build.sh:13 `tr -d '[:space:]'` — two readers of one file.
Layers: 65950c1 (2026-11-03, "one publish script that reads VERSION") is the only layer. It replaced scratchpad copies; the RELEASING.md step 3-4 text still describes the same sequence by hand (duplicate procedure, F6).
Source fix: make publish.sh two phases. Phase 1 reads only: on main, tree clean, tag absent locally and remotely, DMG stapled, `plutil`/grep of appcast.xml names `$V`, DMG's embedded app version == `$V`, Sofia target path absent. Phase 2 does the irreversible steps in order and ends with `[ "$(curl -s -o /dev/null -w '%{http_code}' ...)" = 303 ]` or exit non-zero. Delete the by-hand steps 3-4 from RELEASING.md.

**F2. [Next session] app/build.sh:44 + app/runtime.sh:58-64 — three layers of "refresh the cached runtime" because the cache is keyed on the directory existing.**
`:44` `[ -d "$B/runtime/arm64" ] && [ -d "$B/runtime/x86_64" ] && [ -d "$B/runtime/scripts" ] || "$APP/runtime.sh" build` — the heavy runtime (python, essentia, ffmpeg, deno, yt-dlp copied from vendor/) is rebuilt only if a folder is missing.
Layers, oldest to newest:
1. 2f216ac (2026-10-27) runtime.sh build + sign.
2. 101ffcf (2026-10-27) build.sh adds the `[ -d ... ] ||` cache.
3. d1ceef4 (2026-10-27, "scripts always rebuilt") adds `runtime.sh scripts` at build.sh:47 and its own comment at :45 "so an edit never ships stale behind an old runtime" — a patch for stage 2 shipping stale python scripts.
4. 76de036 (0.1.9) bundles deno; a cached runtime without deno still passes the `-d` test, so the new binary needed a manual `runtime.sh build` first.
vendor/yt-dlp, vendor/*/deno.zip, ffmpeg, the essentia wheel, and `entitlements-*.plist` changes still ship stale until someone remembers. This is the "bigger is louder barking" pattern: each stale ship got a patch for that one input.
Source fix: delete the existence test. Build the runtime from its inputs every release build and stamp `runtime/.inputs` with a hash of vendor/ + the four entitlement plists + scripts + models; rebuild when the hash differs. `runtime.sh scripts` then disappears as a separate mode.

**F3. [Next session] app/runtime.sh:62 and :70 — a Task-1 spike tolerance and a blanket `|| true` that can ship a broken runtime.**
- `:62` `if [ -f "$ROOT/app_run.py" ]; then cp -f ...; else echo "  (app_run.py not present yet: Task 2)"; fi` — build continues and ships a Beat Key with no `app_run.py`, the entry script for every download and analysis. Origin 2f216ac, written before app_run.py existed (it landed in 258fac6). A marker, "not present yet", that outlived its reason.
- `:70` `run_arch ... -m compileall -q "$OUT/$a/python" >/dev/null || true  # essentia ships py2 example scripts that cannot compile` — hides every compile failure in the bundled python tree to tolerate known-bad example files; a truly broken site-packages gets no bytecode and no error. (Rule 5.)
- `:53` `chmod +x "$d"/bin/* 2>/dev/null || true` hides a missing binary.
- `:92` `SKIP_YTDLP=1` escape hatch lets a build skip signing yt-dlp; the verify loop at :102-104 then fails on the unsigned or stale one only if it happens to be unsigned. Left-over debug path.
Source fix: `cp -f "$ROOT/app_run.py"` unconditionally (set -e dies if absent); delete essentia's example/ tests directories during build_arch so `compileall` runs strict with no `|| true`; remove SKIP_YTDLP; drop the `2>/dev/null || true` on chmod.

**F4. [Next session] app/build.sh:146-198 — the DMG window layout has two mechanisms and a delay-stack, and the "layout saved" check checks a file exists.**
- Mechanism 1: Finder scripted by osascript at :167-193 with `delay 2`, `close`, `open`, `delay 1`, `close` (sleeps to make Finder flush .DS_Store; reopen to make it write again).
- Mechanism 2: `DMG_LAYOUT_FROM` at :146-162 copies .DS_Store from an earlier DMG so no Finder window opens, with `-nobrowse` switching (:150-151), `TITLE=32` fudge (:166) "measured".
- :194 `[ -f "$MNT/.DS_Store" ] || { echo "Finder wrote no .DS_Store: layout not saved"; exit 1; }` — proves a file exists, not that icons landed at 160/440.
Layers: 101ffcf (2026-10-27) Finder script; 90eb05e (2026-10-28) `DMG_LAYOUT_FROM` bolted on because the Finder window showed on screen while someone was using the Mac (RELEASING.md:26-27). Both paths stay.
Duplicate truth in the same area: `WIN_W=600; WIN_H=380; ICON=112; APP_X=160; LINK_X=440; ICON_Y=190` (build.sh:27) are re-typed at make_background.swift:13-14 (`W: CGFloat = 600, H: CGFloat = 380`, `appX... linkX... iconY...`) under a comment that says they are "shared with build.sh". They are copies.
Source fix: generate the .DS_Store once, commit it as `app/dmg/DS_Store`, always copy it into the volume; delete the osascript block, both delays, `TITLE`, `NB`, and `DMG_LAYOUT_FROM`. Constants live in one `app/dmg/layout.env` read by build.sh and passed to make_background.swift as arguments.

**F5. [Next session] Duplicate truth: identity, platform and name are written in many files; VERSION is the only constant that is single-sourced.**
Each with file:line:
- Signing identity / team id: build.sh:14 and runtime.sh:15 both literal `Developer ID Application: J Shriver (9WTFGV63S2)`.
- Notary profile `artemis-notary`: build.sh:15 (and RELEASING.md:21).
- Bundle id `com.jshriver.orion`: Info.plist:9; asserted again in BeatKeyTests.swift:53 and LoginItemTests.swift:14; RELEASING.md:49-50 (`defaults write com.jshriver.orion`).
- Minimum macOS 12: Package.swift:6 `.macOS(.v12)`, Info.plist:18 `LSMinimumSystemVersion 12.0`, build.sh:65 `--minimum-deployment-target 12.0`, build.sh:245 `<sparkle:minimumSystemVersion>12.0.0`. (Plus deps.sh:40 `MIN_MACOS=10.15` for the separate CLI.) Four places, no check that they agree.
- Repo slug `thuhmadhatter42/beat_dl`: build.sh:226, :238, :241; Info.plist:58; publish.sh:12; RELEASING.md:5, :30, :34; friends-page/serve.py:22; BeatKeyTests.swift:66, :226.
- Public name "Beat Key": build.sh:18 `APP_NAME`; Info.plist:7, :8, :41; Brand.swift; BeatKeyTests.swift:39-56 greps build.sh for it (the test exists to police the duplication).
- Entitlement keys: entitlements-app.plist, -deno.plist, -ytdlp.plist, and again as grep strings at build.sh:107-123.
- Sofia host `js-mac-pro`: publish.sh:13, sv.sh:7, watch.sh:8, sync_from_sofia.sh:14.
Source fix: one `app/release.env` (IDENTITY, TEAM, NOTARY_PROFILE, BUNDLE_ID, MIN_OS, REPO, APP_NAME) sourced by build.sh, runtime.sh, publish.sh. build.sh stamps `plutil -replace` for CFBundleIdentifier, LSMinimumSystemVersion, CFBundleName, SUFeedURL, appcast `minimumSystemVersion`, and actool's target, then fails if Package.swift's `.v12` disagrees (a single grep). Delete the text-grep tests that police it (F14).

**F6. [Next session] Stale hardcoded versions despite VERSION being the single source.**
- THIRD-PARTY-LICENSES.md:20 `| Beat Key (Swift app, ...) | 0.1.16 | AGPL-3.0` — the file build.sh:70-71 copies into every DMG (Beat Key > Licenses). 0.1.59 ships saying 0.1.16.
- app/RELEASING.md:31 "as of 2026-11-08 0.1.34 is the latest public release and 0.1.38 is built and installed on the MBP but unpublished" — VERSION is 0.1.59 and 0.1.59 is public (per the repo's own recent commits).
- Info.plist:15-16 carry `0.0.0` placeholders that build.sh:55-56 overwrite; harmless but a second place a version-shaped literal lives.
- build.sh:13 and publish.sh:8 read VERSION two different ways.
Source fix: put `{{VERSION}}` in the licences row and let build.sh `sed` it into the bundle copy; delete the dated sentence from RELEASING.md; one `read_version` helper.

**F7. [Next session] app/build.sh:7-8 and 76/91/133 — a comment the code contradicts, and a clean-then-add-then-clean sweep.**
- `:8` "Nothing is written into the bundle after it is signed." Then :133-134 write two xattrs onto the already-signed `$OUTAPP`, and :135 re-verifies in case it broke the seal (`"metadata xattrs broke the signature"`). The author doubted it, so verified.
- `xattr -cr "$OUTAPP"` at :76 (layer 101ffcf), then Sparkle is copied in and `xattr -cr "$SPK"` runs again at :91 (layer 4be2f5a, 2026-10-28), then xattrs are added at :133-134 (layer 123cf53, "public name"). Clear, add, clear again, add again.
Source fix: embed Sparkle before the one `xattr -cr`; set the Finder comment/keywords on the staged copy inside the DMG (`$STAGE/$APP_NAME.app`, after the `ditto` at :141) so the signed bundle is untouched; delete the re-verify at :135 and fix the comment to be true.

**F8. [Someday] app/build.sh:161, :195, :209-210, :213 — `|| true` / `2>/dev/null` tolerances.**
`:195` `chmod -Rf go-w "$MNT" 2>/dev/null || true` — a failure to write-protect the DMG volume is invisible. `:209-210` `plutil -extract id/status ... || true` then `:213` `[ -n "$ID" ] && xcrun notarytool log ... || true` — notary log fetch failure disappears; the exit still fails loudly later (`exit 1` at :214), so this one is low risk.
Unproven separate item: notarisation (:208) and stapling (:216) cover the DMG only; the .app inside the DMG is stapled to nothing (ditto'd at :141 before notarising). Whether an offline first launch after dragging to Applications is affected: unproven, I did not test.
Source fix: delete the `|| true`s; staple the app before building the DMG if the offline case matters (verify with `spctl --assess` on a copy with the network off).

**F9 see Tests section.**

### CLI installer (deps.sh, run.sh, install.command)

**F10. [Next session] deps.sh:126-140 + run.sh:56-70 — the yt-dlp upgrade policy is implemented twice in the CLI, plus a restore step that undoes the upgrade, and again in the app.**
- Weekly stamp: `maybe_upgrade_ytdlp` (deps.sh:136-140), layer a5c3e94 (2026-09-10).
- On failure: run.sh:57-70 `upgraded_this_run=1; upgrade_ytdlp; echo "Retrying..."`, same layer a5c3e94.
- `deps.sh:129-131` `"$BIN_DIR/yt-dlp" -U >/dev/null 2>&1` then `runs yt-dlp || cp -f "$VENDOR_DIR/yt-dlp" "$BIN_DIR/yt-dlp"` — value and counter-value: the upgrade may break the binary and the next line restores the vendored copy. Layer f5d462b (2026-10-06, "runs on every Mac").
- Third and fourth copies in the app: `Runtime.needsWeeklyUpgrade` / `upgradeYtDlpSync` (EngineTests:165-181), and downloader.py / app_run.py upgrade-then-retry (tests/test_app_run.py:119-131).
- `deps.sh:43` `ANALYZER_BUILD=essentia-notf-1   # bump when the vendored analyzer changes` is a manual cache-invalidation counter (same shape as F2); layer f5d462b.
Source fix: one upgrade policy, in one place (downloader.py already owns "upgrade once and retry" for both front ends); shell scripts just call it. Drop the restore step by testing the upgraded binary before replacing the old one (`-U` to a temp copy, `--version` it, then `mv`).

**F11. [Someday] deps.sh:94-95 and :76-77 — failures print and return success.**
`install_tool` echoes "won't run on this Mac" and returns 0; `ensure_deps` carries on (:117-123, final `chmod ... 2>/dev/null` sets the function's status). `install_python` prints "Downloads still work, without BPM/key in the name." and `ensure_python` result is discarded. Designed fallback (rule 5: die loud, never fall back).
Source fix: `ensure_deps` returns non-zero if yt-dlp, ffmpeg or ffprobe won't run; analyzer failure is the one allowed degrade, and it must be logged in a file (see F12).

**F12. [Someday] run.sh:19 and :46-53 — analyzer errors discarded; unknown exit codes fall through.**
`:19` `analysis=$("$PY" "$SCRIPT_DIR/bpm.py" "$1" 2>/dev/null) || analysis=""` — all analyzer stderr thrown away; the user sees only "Couldn't analyze that file." The app side now logs every one of those (tests/test_app_run.py:521-569 `TestFailuresLogToStderr`, 0.1.59 "a missing log is a failure"). `:46-53` `case $? in 0) ... 1) continue ;; esac` — exit codes 2+ from dropped.py fall through to the download branch with a local path as the URL.
Source fix: send bpm.py stderr to the same `last-run.log` the app uses; `case ... *) continue`.

### Models

**F15. [Next session] app/runtime.sh:63, models/README.md, tools/train-tempocnn/retrain.sh:38-39, tools/build-old-mac/extract-tempocnn-weights.py:2-3 — the shipped weights wear the original model's name.**
`runtime.sh:63` copies `models/deeptemp-k16-3.npz`. Since e75055a (0.1.40) that file IS fine-tuned candidate ftC (README: "now candidate ftC ... original in archive/deeptemp-k16-3-pre-ftC.npz"). retrain.sh writes `deeptemp-k16-3-ft<N>.npz`, so shipping a retrain means overwriting the live name by hand. extract-tempocnn-weights.py:2-3 still says the npz is extracted from the `.pb`, which is no longer how that file was made; bpm.py:200 says "Benchmarked at 87.5% Acc1" (the pre-ftC number; the README gives 82.5% on the public set). Model name is written in runtime.sh:63, bpm.py:30-31, tempocnn_np.py:26.
Layers: 09fcd69 (npz = pb converted) -> e75055a (overwritten with ftC, old copied to archive/).
Source fix: name by content (`tempocnn-ftC.npz`), one constant `models/ACTIVE` read by runtime.sh, bpm.py and tempocnn_np.py; the extract script's header describes only the base weights.

### Sofia / harvest dev scripts (tools/pt-harvest)

**F16. [Someday] tools/pt-harvest — two pullers for one job, a silent monitor, host copies, and a sleep.**
- Two mechanisms for "pull the harvest DB and audio from Sofia": sv.sh:39-47 `pull` (uses `sqlite3 .backup` for a consistent snapshot, overwrites the local DB with no backup, rsyncs logs and crops too) vs sync_from_sofia.sh (rsync of the LIVE sqlite file, integrity check, archive of the old DB, log). Layers: sv.sh from 8b9e02a / 8996122 (2026-10-06); sync_from_sofia.sh aa56b94 (2026-11-05). Each has the safety the other lacks.
- watch.sh:8 `... 2>/dev/null || true` — if Sofia is unreachable the monitor prints nothing for the whole run; "quiet" and "dead" look identical.
- run_batch.sh:16-18 `nohup ... &` then `sleep 2` then reads `clicker.pid` — a sleep added to make the earlier background start finish writing its pid.
- Host `js-mac-pro` literal in four scripts; `$HOME/.claude/scripts/ssh-rc` literal in sv.sh:8, watch.sh:4 (sync_from_sofia.sh:16 has an env override).
- sv.sh:6 `set -u` only (no `-e`), so `push)` etc. can succeed after a failed scp (`scp ... && echo pushed` handles that one, others don't).
Source fix: keep sync_from_sofia.sh, change it to pull the `.backup` snapshot instead of the live file, delete sv.sh `pull`; watch.sh emits an explicit "UNREACHABLE" line instead of `|| true`; the supervisor writes the pid before forking (or the child writes it) instead of sleeping.

### Tests

**F9. [Next session] app/Tests/OrionTests/MotionFrameTests.swift — why it flakes under load, line by line.**
The test samples a wall-clock animation with a probe that costs more than the animation is long.
1. `:138-179` `capture(... count: 12, seconds: 0.6)` schedules frame i at `due = Double(i) * seconds / Double(count)` (:169) = every 50 ms. Each frame is a `grab(host)` (:173) that, per the comment at :171-172, "blocks the main thread (~80 ms for the whole face)", and `spin(max(0.03, due - elapsed))` (:172) always burns at least 30 ms first. So each frame costs at least ~110 ms and 12 frames span ~1.3 s.
2. The animation being sampled is `Theme.Motion.valueDuration` = 0.45 s (MotionTests.swift:59). So only the first ~3-4 frames can fall inside the animation. The pass condition is `inBetween(p) >= 2` (:267, :279, :291) where `inBetween` counts frames with progress strictly between 0.03 and 0.97 (:209). Any extra load stretches `grab` further; frame 2 lands after the animation ends; count falls to 1 or 0; the test fails with "snapped".
3. Fixed settles that hope the previous animation finished: `spin(0.4)` :149, `spin(0.8)` :152, `spin(1.0)` :175, `spin(0.8)` :337.
4. `testValueCurveGlidesInsteadOfClicking` (:369-386) takes `st.last { ($0.t - t0) * 1000 <= m }` (:326): a 60 Hz sample point that the main thread skipped under load reports the previous frame's value, which makes the "biggest step in one 60 Hz frame" (:375) grow past `< 0.15` (:379). It also starts `t0` at :318 before `box.tick += 1` (:320), so any delay before the first frame shifts every sample (`c[2] < 0.3` at 50 ms, :380).
5. `testMeterTickDoesNotRedrawTheFace` (:353-365) compares median milliseconds between two paths and asserts `wNew < wOld / 2` (:362) and `pNew < pOld * 1.5 + 1` (:364): a ratio of wall-clock times, flaky by construction. It duplicates LiveTests.swift:302-322 `testLevelTicksNeverRepublishTheController`, which proves the same fact by counting publishes.
6. `FrameProbe.stamps` is a `static var` (:54) shared across tests.
Source fix: separate "what is the curve" from "what did the screen do". Test the curve as a pure function with injected time (expose the Motion.value timing curve and duration as data; sample at t = 17, 33, 50 ... ms with no run loop). Test "reading change moves instead of snaps" by asserting the view animates (`animation` modifier present, not nil, under `reduceMotionOverride = false`), not by pixel-diffing live frames. Delete `testMeterTickDoesNotRedrawTheFace` (keep the publish-count test).

**F13. [Next session] Tests cannot run from a clean checkout: a gitignored fixture and a hard-coded absolute path, and on any other machine the live-path tests silently skip.**
- `.gitignore:40` `tests/fixtures/*.wav`; the repo ships only `tests/fixtures/make_click.sh`. tests/test_app_run.py:17 `WAV = ROOT / "tests" / "fixtures" / "click120.wav"` is the audio the stub "downloads" (`cp "$STUB_AUDIO" "$dest"`, tests/stub/yt-dlp:~102). In this worktree the file does not exist, so the TestDownload / TestLogin / TestJsRuntime / TestAnalyze classes would fail, not skip (from reading; I did not run them). Only tests/test_bpm_extras.py:321-323 `skipTest("run tests/fixtures/make_click.sh first")` guards it.
- `bin/` is ignored too (`.gitignore` "bin/"). LiveTests.swift:390 and ListenLogTests.swift:236 fall back to `URL(fileURLWithPath: "/Users/jshriver/dev/beat_dl/bin/python/bin/python3")`; test_bpm_extras.py:311 falls back to `/Users/jshriver/dev/beat_dl/bin/ffmpeg`. In a worktree, they pass only because the main checkout on this one Mac has `bin/`. On any other machine `XCTSkip("no bundled Python (bin/python)")` makes `swift test` green with the two real analyzer end-to-end tests not run.
- Several Python classes use `skipUnless(HAVE_ESSENTIA, ...)` (test_bpm_stream.py:48, test_bpm_tuning.py:101, test_bpm_extras.py:213); a runner using the system Python reports green and has tested nothing from the analyzer.
- Duplicate signal (rule 2): the same "120 BPM click over an A-minor drone" is synthesised in four places — tests/fixtures/make_click.sh:16, tests/test_bpm_stream.py:26-33 `click_drone`, LiveTests.swift:404-409, ListenLogTests.swift:250-255 — with different click amplitudes (0.9 vs 0.6). LiveTests.testRealAnalyzerReadsWhatThePipeWrites (:385) and ListenLogTests.testSyntheticStreamThroughTheLivePathLogsLevelsAndReadings (:232) both pipe it into the real `bpm.py --stream` and assert 120 BPM and "Am"; test_bpm_stream.test_stdin_to_json_lines asserts the same from Python. Two of these are the same test.
Source fix: tests make their own fixtures (numpy, as chord_wav does at test_bpm_extras.py:195 / test_bpm_tuning.py `progression`) in `setUpModule`; one Swift `Fixtures.clickDrone` helper; the runtime is found via `ORION_RUNTIME_ROOT` / `app/build/runtime`, and a missing runtime is a test FAILURE (a missing prerequisite is a bug in the run, not a skip). Remove the `/Users/jshriver/...` fallbacks.

**F14. [Next session] Tests that assert a constant, a copy of a constant, or the text of a script.**
Each can only fail when someone edits both sides or reformats the file.
- BeatKeyTests.swift:241 `testYtDlpTimeoutsSuitSlowIntelMacs`: `XCTAssertEqual(Runtime.versionTimeout, 120)` / `upgradeTimeout, 300`.
- MotionTests.swift:58-73: `valueDuration == 0.45`, `swapDuration == 0.25`, `hoverDuration == 0.12` in `testTokens`, then the same three numbers again in `testDurations`.
- FaceplateTests.swift:15-16 `[Theme.H.lg ...] == [36, 28, 20, 16]`, `[Theme.R.plate ...] == [12, 6, 3]`; :105 `PocketFooter.usable == 344`; :83 `LCD.bandHeight == Theme.S.l + 148 + Theme.S.s + Theme.H.sm / 2` (re-derives the formula in LCD.swift:46 with a literal 148); HarmonyTests.swift:349 `b.width == 528`.
- LiveTests.swift:242-245 greps build.sh for `--entitlements "$APP/entitlements-app.plist"` and asserts runtime.sh does NOT contain the string; BeatKeyTests.swift:54-55 greps build.sh for `APP_NAME="Beat Key"`; :71-72 greps build.sh for `THIRD-PARTY-LICENSES.md`; HelpTests.swift:61-71 greps six Swift sources for `.help(`; BeatKeyTests.swift:221-233 and :256-263 restate Info.plist strings as literals.
The real proof is already in build.sh: the post-sign `codesign -d --entitlements` asserts at build.sh:107-123 check the signed product.
Source fix: delete the constant-equals-constant and script-grep tests; for the layout numbers keep only the relation tests (fits, on the 4/8 grid), not the literals.

**F17. [Next session] Ten always-skipping "render" generators live in the test target and cannot fail.**
Each begins with `guard let dir = ProcessInfo.processInfo.environment["ORION_SNAPSHOT_DIR"] else { throw XCTSkip(...) }` and then only writes PNGs (assertion: "image is not nil"): AccentTests.swift:193, FooterReadoutRenderTests.swift:16, HarmonyTests.swift:379, HelpTests.swift:127, ManualKeySelectionTests.swift:190, MarketingRenderTests.swift:17, MiniTests.swift:238, PocketTests.swift:132, SpellingMenuBarTests.swift:170, WindowParityTests.swift:85. The same ten-line `write<V: View>(_ v: V, _ name: String)` helper is pasted into at least nine of them (ImageRenderer at scale 2, PNG out). Every normal `swift test` reports them as skipped. MotionTests.swift:139 `testLiveModulesRender` asserts only `XCTAssertNotNil(rr.cgImage)`.
Source fix: move them to an executable target (`swift run render --out <dir>`) sharing one `Render.write`; leave the test target with tests that can fail.

**F18. [Next session] Other tests that depend on timing or machine state.**
- EngineTests.swift:88 spins 0.7 s waiting for the "updating" stage that Engine.swift:238 raises after `asyncAfter(.now() + 0.4)`: a 300 ms margin on a loaded Mac.
- Negative waits that pass vacuously when the code is merely slow: BeatKeyTests.swift:190 (0.2 s, "ignored while the doctor runs"), :259 and :271 (0.3 s), AccentTests.swift:123-125 (0.3 s spin for drag coalescing), LoginTests.swift `RunLoop.main.run(until: 0.1/0.2)` after `XCTAssertEqual(f.launches.count, 0)` (:188).
- DAWSendTests.swift: fixed ports 47_041, 47_042, 47_043/47_044, 47_416, 47_499 — collide with another run, another process, or a parallel test plan; :175 `Thread.sleep(forTimeInterval: 0.02)` polling loop.
- tests/test_bpm_stream.py:211 and :213 `time.sleep(1.0)` / `time.sleep(0.3)` around SIGUSR1: the signal can arrive before bpm.py has read the audio written at :209; the assertion `secs <= 5.0` (:222) then passes either way.
- ListenLogTests.swift:260 a 120 s deadline loop on a real Python process; LiveTests.swift:413 `wait(for: [exited], timeout: 120)`.
- HotkeyTests.swift:74-83 registers a real global ⌃⌥⇧⌘F19 hot key on the host Mac.
Source fix: bind port 0 and hand the chosen port to the driver; inject the clock (as LiveSession / SongTracker already do: `now:` parameters) instead of spinning; wait on explicit expectations or events; for the signal test wait for the first reading before signalling.

**F19. [Someday] Redundant tests.**
- `HelpText.problems()` equals `[]` is asserted in AccentTests.swift:137, HelpTests.swift:101, ManualKeySelectionTests.swift:172, MiniTests.swift:189.
- tests/test_app_run.py:71 `test_cli_default_order_unchanged` is the first element of the list asserted whole at :82 `test_old_strategy_order_literal`, and again at :80.
- `Faceplate.errorText("That video is private or was removed.")` asserted in BeatKeyTests.swift:89 and FaceplateTests.swift:181.
- MotionTests `testTokens` vs `testDurations` (F14).
- MotionFrameTests.testMeterTickDoesNotRedrawTheFace vs LiveTests.testLevelTicksNeverRepublishTheController (F9).
Source fix: delete the later copies; one `HelpLines` test.

**F20. [Someday] Weak or contrived assertions.**
- BeatKeyTests.swift:235-242 `testUpdaterIsInertOutsideABundledApp`: after `u.checkForUpdates()` and a 0.1 s spin there is no assertion; it can only fail by crashing.
- ListenLogTests.swift:280 `XCTAssertFalse(got.contains { $0.hasPrefix("[LiveSession] listen: off · source ") && $0 == got.first })` — fails only if the very first log line is an "off" line; the intent is not stated by the assertion.
- HarmonyTests.swift:308 `XCTAssertEqual(KeyWheel.section(at: ...), 19)` with the comment `// Fm? slot 9 inner` — the author was unsure what 19 means; the number is the code's output copied.
- MiniTests.swift:151-152 `SystemRandomNumberGenerator`, 500 unseeded random presses: a failure cannot be reproduced.
- MidiExportTests.swift:62-89 uses `/usr/bin/env python3` (the system one) and turns an `ImportError` into `print("SKIP")` -> `XCTSkip`.
- tests/test_bpm_tuning.py:70-75 `expected_key(name, cents, measured)` builds the expected key from the measured tuning; a detector that is wrong about tuning by exactly a semitone passes.
- tests/test_daw_scripts.py:131, :181 lua / node absent = skip; a machine without them reports green for Reaper and Bitwig.
Source fix: assert the stated intent (a named condition), seed the generator and print the seed, fail instead of skip when the tool the test exists to exercise is absent.

**F21. [Someday] State leaks from tests.**
Fixed `UserDefaults(suiteName:)` names that are never removed: KeyChoiceTests.swift:45 (`"KeyChoiceTests"`, sets a manual key G# and leaves it), ManualKeySelectionTests.swift:14, SpellingMenuBarTests.swift:15, MarketingRenderTests.swift:72 (all remove at the start only, so one stale plist each in ~/Library/Preferences); UUID-named suites that are never removed: HoldSpellingTests.swift:84, :136, HotkeyTests.swift:22. KeyTeachTests.swift:16 `trashItem(at: root...)` sends a temp directory to J's Trash on every run. WavesTuneSendTests.swift:6 writes a temp .xps and never deletes it.
Source fix: one `TestDefaults.make(self)` helper (UUID suite + `addTeardownBlock { removePersistentDomain }`), used by all; `removeItem` for temp dirs.

**F22. [Someday] app/tools/textures.py:79-82 — a stretch factor added to make a different noise look like the original.**
`mean = np.clip(0.5 + (mean - 0.5) * 1.7, 0, 1)` ("Our noise has a narrower spread than the SVG filter's, so it is stretched") before `a = np.clip(0.42 * mean - 0.21, 0, 1)`: a compensation (1.7 widens, the matrix then narrows). Small, generated once and committed. Source fix: choose the octave amplitudes so the spread matches and delete the 1.7.

**F23. [Someday] docs/research/*/fetch.sh — `set -e` without pipefail and a pinned IP.**
bpm-bench/fetch.sh:6 `set -e`, :9-10 pins `140.78.124.154` with `--resolve` because "curl on J's MBP can't resolve www.cp.jku.at (Tailscale DNS)"; :14 prints "md5 mismatch" and continues. key-bench/fetch.sh:6 `set -e` and `curl -sL` with no `-f` (an HTML error page is saved as the dataset). Source fix: `set -euo pipefail`, `curl -fsSL`, md5 mismatch = delete the file and exit 1.

---

## Coverage gaps (names only)

Swift sources with no direct test: OrionApp.swift; Faceplate/Chassis.swift, Controls.swift, LCD.swift, Theme.swift (only layout-number tests, F14); NoteSynth.swift (only "the system bank file exists and loads", HarmonyTests:364); DAWSend/AXRoutes.swift (only through the fake tree in AXDriverTests); Updater.swift (only the inert path, BeatKeyTests:235); YouTubeLogin.swift (cookie file, UA and prompt text only, no web-view flow); Hotkeys.swift Carbon firing; KeyTeach.swift UI (TeachStore tested); Live/AudioInput.swift and Live/SystemAudio.swift capture classes (static helpers only); Pocket/PocketAdvanced.swift; LoginItem real SMAppService path (fake backend only).
Python with no test: dropped.py (zero references in tests/), tempocnn_np.py (no numpy-vs-.pb parity in `tests/`; parity lives in tools/train-tempocnn/parity.py and is not part of `unittest discover -s tests`), friends-page/serve.py, downloader.py (only through app_run subprocess runs and two mocks).
Machinery with no test: app/build.sh, app/runtime.sh, tools/publish.sh (no dry-run that generates and checks an appcast or an Info.plist), deps.sh / run.sh / install.command.

## Marble-test rates

- app/build.sh: 9 of 14 stages carry a problem (F2, F4, F5, F7, F8; plus F6 via the licences copy) -> read the neighbours: runtime.sh 4 of 6 functions, publish.sh 4 of 4 steps. The release path is a bag with most of its marbles cracked.
- app/runtime.sh: 4 problems in 6 functions (F2, F3 x3).
- deps.sh: 4 problems in 9 functions (F10 x2, F11 x2).
- MotionFrameTests.swift: 3 of 3 live-timing tests are timing dependent, plus 1 duplicate.
- tools/pt-harvest: 4 of 11 scripts (sv.sh, watch.sh, run_batch.sh, sync_from_sofia.sh).
- Test suite as a whole: 10 of 34 Swift files are partly generators that cannot fail (F17); 14 of 34 contain at least one timing, state or constant problem.

## Run log

- Read of `/private/tmp/claude-501/-Users-jshriver-dev-beat-dl/.../placeholder` (a typo path I typed while reading a persisted output) returned "File does not exist". No effect; re-read the right file.
- Two bash calls began with `echo ===` / `echo =====`; zsh treated `=` as command substitution ("`===deps` not found"). The first time that call lost the `deps.sh` output, which I re-ran separately; the second time it only lost a divider echo. No file was affected.
- Large `cat` outputs were truncated by the harness into persisted files; each was re-read from the persisted file or re-cat'd in smaller pieces. Nothing was skipped as a result (checked line counts against `wc -l`: AXDriverTests 468, BeatKeyTests 296, DAWSendTests 327, EngineTests 182, FaceplateTests 233, FooterReadoutRenderTests 74, HarmonyTests 432, HelpTests 176, LiveTests 423, LoginItemTests 70).
- `git log -S'not present yet' -- app/runtime.sh` returned nothing (pickaxe quirk with that string); `-S'Task 2'` found 2f216ac, which is the layer cited in F3.
- Not read: `app/dmg/background.png`, `background@2x.png` (binary art). Not in the claimed list and only grepped, not read: THIRD-PARTY-LICENSES.md (only line 20 and its use at build.sh:70), friends-page/serve.py (only line 22), models/README.md (read for F15), THIRD-PARTY text.
- Not run: any build, test, or release script (as instructed). Statements about what a test "would do" on a clean checkout (F13) are from reading the code and `ls`, not from running it.
- No ssh, no other machine contacted. No file in the repo changed. No alert sent. Worktree left as found (only this report written, in the scratchpad).
