# Symphony review 1: Swift audio / listening / detection core

Worktree: /Users/jshriver/dev/beat_dl/.claude/worktrees/agent-a2e26bb85e2fffba9 (branch worktree-agent-a2e26bb85e2fffba9, HEAD 036793b). Read-only. Paths below are relative to `app/Sources/Orion/`. History hashes are from `git log` / `git blame` / `git show` run in this worktree (305 commits).

## Coverage table

| File | Lines | Read fully | Verdict |
|---|---|---|---|
| Live/LiveSession.swift | 698 | yes | 5 findings (1,3,4,9,12), high marble rate |
| Live/SongBoundary.swift | 387 | yes | 2 findings (1,3) |
| Live/SystemAudio.swift | 204 | yes | 3 findings (2,6,9) |
| Live/AudioInput.swift | 201 | yes | 2 findings (6,9) |
| Live/ListenLog.swift | 152 | yes | 2 findings (2,5) |
| Engine.swift | 330 | yes | 1 finding (10) |
| Reading.swift | 267 | yes | clean |
| Harmony.swift | 304 | yes | clean |
| OrionApp.swift | 328 | yes | 2 findings (1,14) |
| YouTubeLogin.swift | 282 | yes | 1 finding (10) |
| AppLog.swift | 138 | yes | 1 minor finding (15) |
| Runtime.swift | 173 | yes | 1 finding (8) |
| Doctor.swift | 132 | yes | 1 finding (8) |
| Event.swift | 109 | yes | 1 finding (11) |
| Updater.swift | 42 | yes | clean |
| Intake.swift | 62 | yes | clean |
| KeySpelling.swift | 124 | yes | 2 findings (1,7) |
| ManualKeySelection.swift | 109 | yes | 1 finding (1) |
| KeyTeach.swift | 239 | yes | clean |
| Lamp.swift | 79 | yes | clean |
| LoginItem.swift | 99 | yes | 1 finding (13) |
| Hotkeys.swift | 200 | yes | clean |
| PlayToFind.swift | 211 | yes | 1 finding (1) |

23 files, 4,861 lines, all read top to bottom. Also read: `app/runtime.sh` (build script only, clean, no Swift chain), `bpm.py` lines 17-22 and 450-905 (LiveAnalyzer, BoundaryDetector header, stream_main), `app_run.py` emit lines (grep only).

Not claimed (another reviewer has them, or not audio/detection): Faceplate/*, Pocket/*, DAWSend/*, Mini, MenuBar, Help, Settings, HarmonyView, Brand, AutoTuneSend, WavesTuneSend, MidiExport, NoteSynth.

Marble rates: LiveSession.swift 5 of its ~8 behaviours cracked; SystemAudio.swift 3 of 4 (filter, retry/reopen, resample, permission); Runtime+Doctor 2 of 2 (same repair ladder twice); KeySpelling.swift 2 of 3 (spelling switch, choice identity). Treat the Live/ directory as a bag with a high crack rate.

---

## Findings (most damaging first)

1. [Now] LiveSession.swift:29 + KeySpelling.swift:60 + OrionApp.swift:142-144. Every live reading is built with the same identity, so a Manual Key Selection (and the x2/x0.5 tempo factor) survives every automatic new-song boundary and every reset, and is cleared only by the manual New Song button.
   - Governing lines: `LiveSession.swift:29: return Event.reading(obj, file: LiveSession.placeholderFile, name: "LIVE")` (placeholderFile is `/`, line 87). `KeySpelling.swift:60: func matches(_ r: Result) -> Bool { file == r.file && name == r.name }`. The doc comment at KeySpelling.swift:36-37 promises "the next file or song shows the analyzer's own order again". The only call that clears on a new song is `OrionApp.swift:143: if SpellingSettings.shared.manualKey != nil { ...clearManualKey(of: nil, from: .newSong) }`, inside the `newSong` closure. `grep clearManualKey` finds no other callers besides the dial / wheel click handlers (PocketView.swift:990, HarmonyView.swift:72). The audio boundary (`LiveSession.feed` `.reset, .boundary: begin()`, line 127) and title boundary never touch manualKey or tempoFactor.
   - Same duplicate identity hits PlayToFind.swift:176 (`lastReading.map({ $0.0 != r.file || $0.1 != r.name })`: the keyboard root never starts over between live songs) and ManualKey.of (ManualKeySelection.swift:82).
   - Two song identities exist: SongLog.file(started) (SongBoundary.swift:96-98, used for Recent Readings) and the constant placeholder (shown on the LCD). Not observed running; established from code and grep. Unproven: whether the faceplate model (not claimed) resets manualKey elsewhere; grep over all of app/Sources found no such call.
   - Layer history: placeholder identity (2d942ff 2026-11-01, line 29 rewritten 207ceef 2026-11-08) -> KeyChoice keyed on file+name (c770111 2026-11-02, 8d126d5 2026-11-05) -> boundary detection that changes songs without user action (4e2e08e 2026-11-01) -> clear wired only into the button closure (f46909e 2026-11-09). The button-only clear is the compensation; the missing identity is the source.
   - Source fix: LiveSession mints a song id at `begin()` and at every `.reset`/`.boundary` and puts it in `Result.file` (reuse `SongLog.file(started)`); delete the "LIVE" placeholder and the `clearManualKey(.newSong)` / tempoFactor reset in the OrionApp closure, because identity change retires all of it by itself.

2. [Now] SystemAudio.swift:72-74 + ListenLog.swift:121-125 + LiveSession.swift:563-567. "Hear only the players" is three layers deep: include players, then exclude everyone else, then widen to all apps when it hears nothing. The last layer defeats the first layer's purpose.
   - Governing lines: `SystemAudio.swift:73: let players = self.allApps ? [] : apps.filter {...isPlayer...}`; `:74: let others = players.isEmpty ? [] : apps.filter { !...isPlayer }`; `ListenLog.swift:121-125: if case .playersOnly? = filter { filter = .allApps ... return .hearAllApps }`. The stated purpose (SystemAudio.swift:66-67) is that a mic monitored through Artemis/DAW never mixes into the key; the guard widens to every app after 5 s of silence (ListenLog.swift:87 `static let seconds = 5`), including a song paused for 5 s, so the mic bleed returns exactly then.
   - Layer history oldest to newest: 1533925 (2026-11-02) `SCContentFilter(display:, including: players)`; 82b1389 (2026-11-09 21:12, 0.1.58) switched to `excludingApplications: others` because "the stream heard silence" with Chrome (its message); c2d11ab (2026-11-09 23:37, 0.1.59) added `allApps` + SilenceGuard to rescue the case the previous layer still missed. Layer 2 compensates layer 1; layer 3 compensates layer 2.
   - Source fix: pick one filter policy and make it a bring-up check: capture all apps except Beat Key (SCK's own `excludesCurrentProcessAudio`), and drop the player list, exclusion list and widening state. Mic isolation is the Input source choice in Settings.

3. [Next session] LiveSession.swift:470-475 (stale comment + restart) + SongBoundary.swift:42-47 + bpm.py:631-643. "New song, start over" has four owners, and the manual one is the older, heavier mechanism that the newer one made unnecessary.
   - Owners: (a) analyzer gap reset on silence, `{"event":"reset"}` (bpm.py:689-697, LiveSession.swift:127); (b) analyzer BoundaryDetector `boundary/audio` (bpm.py:699-706); (c) title change -> SIGUSR1 -> `boundary/title` with `awaitingFlush` + `titleJoinWindow` bookkeeping (SongBoundary.swift:197-216, bpm.py:830-833); (d) the New Song button, which tears down capture and analyzer and relaunches both (`LiveSession.swift:472-475 reset() { ... start(why: "new song") }`).
   - The comment at :470-471 says "The analyzer's stdin carries only samples (no control channel), so the stream is started over", yet SongBoundary.swift:45 already signals the same process (`kill(process.processIdentifier, SIGUSR1)`).
   - Layer history: reset-on-gap (2d942ff 2026-11-01) -> restart-based New Song with the comment (b98ef58 2026-11-01 21:52) -> SIGUSR1 control channel and BoundaryDetector (4e2e08e 2026-11-01, same day, later). The restart path and its comment were never removed. `awaitingFlush` (SongBoundary.swift:124) exists only because the title path is asynchronous.
   - Source fix: one verb `LiveController.newSong()` that sends SIGUSR1 (the control channel that exists); delete `reset()`'s restart, the stale comment and the title-vs-audio join window; audio boundary and title boundary become one `boundary` event with a `reason` for the log only.

4. [Next session] LiveSession.swift:132-142, :88, :97, :43. `LiveState.locked` and the 6-second `lockAfter` clock do nothing: `.locked(r)` and `.reading(r)` with a green key render, report and act identically.
   - Governing lines: `:132: if Lamp.of(r.keys) == .locked, r.bpm != nil ... greenSince = now ... >= lockAfter { current = .locked(r) }`. Every consumer treats them as one case: `:55 case .reading(let r), .locked(let r)`, `:163 case .reading(let r), .locked(let r)`, MenuBar.swift:67 same; the lamp for `.reading` is already `Lamp.of(r.keys)` = green (`:64`) and the caption `confidenceLine` is the same string (`:75-76`). Only the log word differs (`summary` "locked" vs "reading", `:678-679`).
   - Layer history: 2d942ff (2026-11-01) "auto-lock after 6 s green" froze the reading; 39863c5 (2026-11-01 22:12) removed the freeze (`-if case .locked = state { return }`, and " · HELD" from the caption) but kept the state, `greenKey`, `greenSince`, `lockAfter` and a per-session instance copy `var lockAfter = LiveSession.lockAfter` (`:97`, duplicate of `:88`). Hold (c860c0b) later became the real "stay put" button.
   - Source fix: delete `.locked`, `greenKey`, `greenSince`, `lockAfter`; the lamp comes from `KeyConfidence` alone (one threshold, Reading.swift:180).

5. [Next session] ListenLog.swift:14 vs bpm.py:646/799 vs LiveSession.swift:361-378. "Silence" is decided in three places with different thresholds, measures and clocks.
   - Python: `silence_db=-50.0` on a chunk's RMS, counted in audio-sample seconds (`bpm.py:689-697`, `:799`). Swift guard: `LevelSecond.silentDB = -70` on peak, counted in calls of `second()` (`ListenLog.swift:14,16,118`). Swift filler: zeros written by a wall-clock timer when no samples arrive for 0.5 s (`LiveSession.swift:373-377`, timer `:535`).
   - Effect (derived from the two constants, not observed): a source between -70 and -50 dB reads as signal to the guard (no NO SOUND notice) while the analyzer treats it as silence and resets every 3 s with no explanation in the log.
   - Layer history: gap + analyzer threshold + filler (2d942ff 2026-11-01); guard and level log (c2d11ab 2026-11-09). The guard was added without reusing the existing analyzer threshold.
   - Source fix: one silence definition, owned by the analyzer: it emits a once-a-second level event and `silent` transitions; Swift's meter/guard consume that; delete `LevelSecond.silentDB`, the second `-70` constant and Swift-side second counting.

6. [Next session] AudioInput.swift:101-115 and SystemAudio.swift:135-137. Resampler failures and a missing resampler are swallowed and look like "no sound".
   - Lines: `process` returns `[]` at `:102`, `:106`, `:115` (`guard ... else { return [] }`) with no log; `SystemAudio.swift:135: guard let r = resampler else { return }`, `:136 let mono = try? sb.withAudioBufferList {...}`, `:137 if let m = mono, !m.isEmpty {...}`. A failed conversion drops audio silently; the symptom is the silence guard widening (finding 2) or NO SOUND, which blames the source, not the conversion. This is the same class as the 48 kHz flat-key bug (comment SystemAudio.swift:22-25).
   - Resample policy is also decided three times: SystemAudio re-reads the rate per buffer (`:134`), InputCapture reads it once at bring-up (`AudioInput.swift:164-166`), and bpm.py has its own `_resample` for `--rate != 44100` (`:652-656`) that Swift never uses (`LiveProcess.sampleRate = 44100` always passed, LiveSession.swift:295). Unproven: whether AVAudioEngine can change the input rate mid-run without the tap raising; if it can, InputCapture's frozen resampler is a silent wrong-rate path.
   - Source fix: one `Resampler` contract that throws/logs on failure, one caller policy (read rate per buffer, rebuild on change), and delete the Python resample branch (analyzer accepts only 44.1 kHz and refuses otherwise).

7. [Next session] KeySpelling.swift:101, :123, :72-85, :15-31; MenuBar.swift:334; HarmonyView.swift:492. The sharps/flats switch was "removed" by pinning it to nil instead of deleting it, so the old mechanism and the new rule both run.
   - Lines: `:101 @Published var preference: KeySpelling? = nil` ("Always nil"), `:123 func click(on name: String) -> Bool { false }` (still called at MenuBar.swift:334), `respelled(_ spelling:)` still has both branches (`:82` sharps/flats, `:85` Auto-Tune names), `KeySpelling.respell` and `clickTarget` live on, and `init` wipes a stored `keySpelling` default (`:115-118`) as old-format tolerance. Spelling is decided in five places: KeySpelling.respell, KeyChoice.autoTuneName/keyName (`:46-54`, via AXKeyNames.roots in DAWSend), Scale.spell (Harmony.swift:29,176), Camelot.relative's own `#`/`b` replace (Harmony.swift:30), and the Python analyzer's names.
   - Layer history: click-to-respell (c860c0b 2026-11-01) -> preference persisted (c770111 2026-11-02, 8d126d5, 1047c4a) -> 71a4837 (2026-11-09 0.1.57) "switch removed, stored keySpelling wiped", which set the property to nil and added the wipe.
   - Source fix: delete `KeySpelling`, `preference`, `click(on:)`, `clickTarget`, `respell`, the `$preference` half of `changes`, and the launch wipe (after one release); one function owns pitch-class-to-name for the app, wheel, chord strip and Camelot.

8. [Next session] Runtime.swift:151-172 vs Doctor.swift:77-92 and :126-131. The yt-dlp repair ladder exists twice, with extra copies of the stamp write.
   - Runtime: `-U`, if not running `reseed`, if still not running ad-hoc `codesign` and `reseed` again (`:152-168`). Doctor: before-check, `try? reseed()`, `-U`, `try? reseed()` again, no codesign step (`:77-86`). Stamp-touch is written in `Runtime.seedYtDlp` (`:129-131`), `Runtime.upgradeYtDlpSync` (`:169-171`) and `Doctor.touchStamp` (`:126-131`). Doctor swallows reseed errors: `(try? reseed()) != nil` (`:79,:84`); `Runtime.ensureSeeded` logs and carries on "downloads will fail" (`:121`).
   - Layer history: Runtime ladder (020b16a 2026-10-27 17:14, codesign step included) -> Doctor written as a separate copy (123cf53 2026-10-27 20:22) -> weekly -U moved to the app-owned binary (d1ceef4) -> c2d11ab (2026-11-09) added only logging to Runtime.
   - Source fix: one `Runtime.repairYtDlp(force:) throws -> Outcome`; Doctor and weekly maintenance both call it and map the outcome to text; the stamp lives only there.

9. [Next session] LiveSession.swift:207-233, :247-256, :183-188, :497; AudioInput.swift:152-156. Source selection is tolerant in four places and the macOS 13 gate is decided three times.
   - `LiveSourcePlan.plan` silently swaps a missing saved input for System Audio (8 s notice, :221-223); `LiveSettings.init` repeats the default expression instead of calling `defaultSource` (`:250-252` vs `:188`) and silently clamps the gap (`:255 min(max($0, 1), 30)` while the picker offers [2,3,5,10], `:238`); `systemAvailable` is `LiveSource.systemAvailable` (`:183`), `LiveSettings.systemAvailable` (`:241`) and `#available` in `realCapture` (`:460`); `start` maps any nil capture to "SYSTEM AUDIO NEEDS MACOS 13 OR NEWER" (`:497`); InputCapture still raises "THAT INPUT IS NOT CONNECTED" (`AudioInput.swift:155`) for the condition the plan already handled (a dead branch unless the device vanishes between plan and open).
   - Layer history: 2d942ff (input error) -> 1522777 (2026-11-09 0.1.39) fallback to Mac audio added on top, old error left in place.
   - Source fix: one resolver producing a source or a refusal at bring-up; settings reject out-of-range instead of clamping; macOS 13 gated in one place. Whether a missing mic should fall back at all is J's call (2026-11-05 17:06 per the code comment); if kept, say so in one place and keep the notice.

10. [Someday] YouTubeLogin.swift:11 + Engine.swift:296-310. A global "THE switch" for a feature that was flipped and flipped back, with a fallback branch nobody ships, plus an automatic saved-login retry stacked on the login prompt.
   - `YouTubeLogin.swift:11: static var inApp = true` ("false = the fallback"). Used by `YouTubeSession.savedLogin` (`:148`), Engine (`:301`), OrionApp (`:103`) and tests/fake state (FaceplateModel.swift:214, LoginTests). Engine.handle(.needsLogin) has three paths (`stale || usedLogin` -> `dropLogin`; `inApp, savedLogin != nil` -> straight re-run; else prompt), held together by `usedLogin` and `pendingURL` (extra state vars, Engine.swift:84,98).
   - Layer history: 554b888 (2026-10-27) one switch; 7ee9a65 needs_login; 1b565fe (10-28 12:31) in-app window; 2f57515 (10-28) "No login at all" (switch off); 061b4b2 (10-28 13:16) window back + the saved-login auto re-run branch.
   - Source fix: delete `inApp` (true in the product); one login state machine (none | saved | stale) in the Engine; tests set the saved-login file instead of a global flag.

11. [Someday] Event.swift:87 vs LiveSession.swift:21 vs app_run.py:47 / bpm.py stream. Two helpers speak two wire formats and one parser accepts both.
   - `Event.swift:87: let kind = (obj["event"] as? String) ?? (obj["stage"] as? String)`. app_run.py always emits `stage=` (app_run.py:236-371) while bpm.py --stream emits `event` and LiveEvent.parse reads only `event` (`:21`). Event.swift's own header comment says "A line with 'event' as the kind key is accepted too". `keyList`/`chroma` also drop malformed pieces with a log (`:51-68`).
   - History: 020b16a (2026-10-27) wrote both; the `event` half was never used by app_run.py.
   - Source fix: one key `event` in both helpers; Event.parse refuses lines without it.

12. [Someday] LiveSession.swift:394-433, :607-612. LiveController keeps hand-synced copies of the session: `state`, `isHeld`, `sourceName`, `notice`, `generation`.
   - `publish()` copies `session.state` and `session.isHeld` by hand (`:610-611`) and must be called after every session mutation (`setHold`, `stop`, `fail`, `handle`, `start`). There are also two accumulators of one signal (the 20 Hz `peak` and the 1 s `LevelWindow`, `:424,:426`) and three timers (`fillTimer`, `levelTimer`, `noticeWork`) plus an injected `now` that LiveSession.feed also takes. No defect found today; the structure is the risk.
   - Source fix: LiveSession is the only state, exposed through one `@Published private(set) var session`; one tick timer drives filler, level and notice expiry.

13. [Someday] LoginItem.swift:45-90. macOS 12 LaunchAgent fallback and a "legacy" cleanup path for upgraded Macs (`legacy` agent removed on `set`, still counted in `refresh`: `enabled = backend.isEnabled || (legacy?.isEnabled ?? false)`). Old-format support by design; history not traced (low value). Source fix: one backend per macOS version chosen at startup; the legacy agent removed by an explicit one-time migration, not on every refresh.

14. [Someday] OrionApp.swift:186-215 and Runtime.swift:16-24. Test/mockup switches live in the production launch path: `ORION_FAKE_STATE`, `ORION_FAKE_FLIP_MODE`, `ORION_OPEN_LOGIN`, `ORION_RUNTIME_ROOT`, `ORION_DOWNLOADS`, `ORION_LOGIN_LOG`. `launch()` returns early under `ORION_FAKE_STATE` (`:207`), so hotkeys, status item and Runtime maintenance are skipped in that mode. Source fix: move the fake/mock launcher to a debug target; the app reads one environment object at launch.

15. [Someday] AppLog.swift:56-69, :72-89. Two rotation rules (beatkey.log -> beatkey.1.log at 5 MB; analyzer.log deleted at 5 MB) and many `try?` inside the logger, so a failed log write is invisible. Acceptable for a logger, but only `analyzerHandle` reports its own failure (`:83`). Source fix: one rotation function for both files; a failed open of beatkey.log counted and surfaced in Run Doctor.

---

## Not findings (clean on purpose, so the next pass does not re-open them)

- Sample rate constant: `LiveProcess.sampleRate = 44100` is the only Swift definition (Wav, ClipRing, Resampler default, Python `--rate` all read it). One owner.
- Reading.swift / Harmony.swift / Lamp.swift / KeyTeach.swift / Intake.swift / Hotkeys.swift / Updater.swift: one question per function answered; no stacks. Lamp and KeyConfidence share `lockedMin = 70` in one place.
- Engine `generation` token is a single stale-event guard; LiveController's `generation` is the same pattern on another object, consistent.
- The ClipRing / teach path is single-sourced (LiveController.recentClip -> KeyTeach).

## Run log

- First `grep -rn ... --include=*.swift` call in zsh failed with `no matches found` (glob). Re-run without `--include`, worked. Nothing skipped.
- One `echo "======="` in a `git show` chain printed "====== not found" noise; harmless.
- A combined `mkdir && cat <<EOF` Bash command was refused by the worktree-isolation checker (too complex to verify); report written with the Write tool instead.
- `git log --follow` was not used; `git log -- <path>`, `git blame -L` and `git show -- <path>` were enough. Renames before 2026-10-27 not checked.
- Not read in full (only as far as the chain required): `bpm.py` (lines 17-22, 450-905; BoundaryDetector body 457-626 skimmed by header only), `app_run.py` (grep of emit lines only). Findings 3, 5 and 6 depend on the bpm.py lines quoted; the BoundaryDetector math was not audited.
- No repo files changed; nothing built or launched. Only this report was written.
