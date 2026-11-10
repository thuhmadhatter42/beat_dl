# Symphony review 2: Swift interface + DAW send (app/Sources/Orion)
Worktree: /Users/jshriver/dev/beat_dl/.claude/worktrees/agent-ac336c7d9100906c1 (HEAD 036793b). Read-only; nothing edited, built or launched.
Paths below are relative to app/Sources/Orion/.

## Coverage table (all read top to bottom, in full)
| File | Lines | Read fully | Verdict |
|---|---|---|---|
| Pocket/PocketView.swift | 1551 | yes (3 chunks) | 9 findings (marble rate ~100%) |
| Pocket/Pocket.swift | 187 | yes | 2 findings |
| Pocket/PocketAdvanced.swift | 158 | yes | 1 finding |
| Faceplate/Theme.swift | 296 | yes | 2 findings |
| Faceplate/LCD.swift | 518 | yes | 5 findings (~80%) |
| Faceplate/FaceplateView.swift | 391 | yes | 4 findings |
| Faceplate/FaceplateModel.swift | 244 | yes | 1 finding (test scaffolding in app) |
| Faceplate/Controls.swift | 277 | yes | 2 findings |
| Faceplate/Chassis.swift | 142 | yes | 2 findings |
| Faceplate/Accent.swift | 292 | yes | 2 findings |
| Faceplate/Motion.swift | 85 | yes | clean |
| DAWSend/DAWSend.swift | 356 | yes | 3 findings |
| DAWSend/AXRoutes.swift | 233 | yes | 2 findings |
| DAWSend/AXDriver.swift | 578 | yes | 5 findings (~80%) |
| DAWSend/ProToolsDriver.swift | 77 | yes | 1 finding |
| DAWSend/PTSLClient.swift | 309 | yes | 2 findings |
| DAWSend/OSC.swift | 142 | yes | 1 finding |
| DAWSend/AbletonDriver.swift | 87 | yes | 2 findings |
| DAWSend/ReaperDriver.swift | 77 | yes | 1 finding |
| DAWSend/BitwigDriver.swift | 41 | yes | 1 finding (shared with Ableton/Reaper) |
| DAWSend/MidiFileDriver.swift | 46 | yes | 1 finding |
| HarmonyView.swift | 779 | yes (2 chunks) | 4 findings |
| Mini.swift | 526 | yes | 4 findings |
| MenuBar.swift | 584 | yes | 5 findings (~60%) |
| Help.swift | 384 | yes | 3 findings |
| Settings.swift | 271 | yes | 3 findings |
| AutoTuneSend.swift | 93 | yes | 2 findings |
| WavesTuneSend.swift | 83 | yes | 1 finding |
| Brand.swift | 24 | yes | clean |
| Lamp.swift | 79 | yes | 1 finding |
| Hotkeys.swift | 200 | yes | 2 findings |
| LoginItem.swift | 99 | yes | 1 finding |
| Intake.swift | 62 | yes | 1 finding |
| KeyTeach.swift | 239 | yes | 1 finding |
| ManualKeySelection.swift | 109 | yes | 1 finding |
| PlayToFind.swift | 211 | yes | 1 finding |
| KeySpelling.swift | 124 | yes | 3 findings (home of the dead layer) |
| MidiExport.swift | 122 | yes | 2 findings |
| NoteSynth.swift | 113 | yes | 1 finding |

Claimed beyond the named list (views, sends, settings, menus, key tables): AutoTuneSend, WavesTuneSend, Brand, Lamp, Hotkeys, LoginItem, Intake, KeyTeach, ManualKeySelection, PlayToFind, KeySpelling, MidiExport, NoteSynth.
NOT read (other reviewer's): Engine, Reading, Harmony, OrionApp, YouTubeLogin, Live/*.
NOT read and on nobody's list that I can see: Event, Runtime, AppLog, Doctor, Updater. Flag to the main session.
Total read: 39 files, 9,945 lines.

## Findings (most damaging first)

1. [Now] MenuBar.swift:331-335, KeySpelling.swift:121-123, Pocket/Pocket.swift:129, Pocket/PocketView.swift:1020-1023 + 1034, Help.swift:57. A clickable, pointing-hand key name that does nothing. `canRespell` is true for black-key tonics, so Dial draws a Button wired to `respellKey`, which calls `SpellingSettings.shared.click(on:)`, and that is `func click(on name: String) -> Bool { false }`. VoiceOver is told "Click to switch between sharp and flat spelling"; help says "Click a sharp or flat key to respell it." Test HoldSpellingTests.swift:141 asserts the click returns false, so the dead end is pinned in.
   Layers (git): c860c0b 11-01 22:26 "Manual Hold and click-to-respell keys" (button + switch) -> 71a4837 11-09 16:24 0.1.57 "sharps/flats switch removed" (made `preference` always nil and `click` return false; it touched KeySpelling.swift, OrionApp.swift and tests only, no view file). It left the button, `canRespell`, `respellKey`, `KeySpelling.respell/clickTarget`, and the `spelling:` parameter on `Result.respelled`, `MenuBarReadout.of`, `PocketState.shown`, `MidiExport.current`, `Faceplate.readout`, all always nil now. Proven: 71a4837 left the dead control.
   Source fix: delete the respell chain end to end (button, canRespell, respellKey, SpellingSettings.click/preference, the KeySpelling enum, the nil `spelling` parameters, the else-branch in `respelled`). Key naming keeps one owner: KeyChoice.keyName / autoTuneName.

2. [Next session] Pocket/PocketView.swift:515-523 vs Faceplate/Chassis.swift:117-128 + Faceplate/FaceplateView.swift:264-272. The status word/lamp/colour rule exists twice and has already diverged. The window's `railStatus` maps `.doctor` with outcome `.failed` to FAILED (red); the pocket legend's switch has only `.working`, `.error`, `default`, so a failed Doctor shows READY in green. Quotes: (pocket) `default: return ("READY", .locked, Theme.greenText)`; (window) `case .doctor(let r): return r.outcome == .failed ? .failed : .ready`.
   Layers: window rule from 123cf53 10-27 20:22 (Run Doctor); pocket copy came with b98ef58 11-01 21:52 and has no doctor case. Unproven only as to whether a failed Doctor can be on show in the pocket while not listening; the code path exists.
   Source fix: one StatusLegend fed by `FaceplateFace.railStatus(state)` for both surfaces; delete PocketHeader.legend.

3. [Next session] Pocket/PocketView.swift:580-665 (PocketLCD.right) vs Faceplate/LCD.swift:124-250 + 499-517 (Idle/Drop/Working/Listening/Doctor/Login/ErrorReadout). Two renderers for one `Readout` enum, kept in step by hand: error text `Theme.T.value` (pocket) vs `Theme.T.title` (window); the red hint literal `Theme.rgb(255, 106, 92, Theme.highContrast ? 1 : 0.75)` at PocketView.swift:635 and LCD.swift:513, but `0.85` at LCD.swift:229; the working step row built twice (`steps(...)` vs `stepLights`). Three of three pairs differ in some detail.
   Source fix: one readout view per state taking `compact:`; delete the pocket copies. The red hint becomes a Theme token.

4. [Next session] Faceplate/LCD.swift:46 and :55. A value and its counter-value in one layout chain. `bandHeight = Theme.S.l + topHeight + Theme.S.s + KeyStrip.ruleRowHeight / 2` and, nine lines on, `KeyStrip(...).padding(.top, -KeyStrip.ruleRowHeight / 2)`. The +10 and -10 cancel exactly: the strip sits where it did before (S.l + topHeight + S.s).
   Layers: 8d126d5 / 15a18ec / 8aa9965 (topHeight 136->148, strip `.padding(.top, S.s)`, `.padding(.vertical, S.l)`) -> b133b5b 11-09 14:34 0.1.53 added BOTH the `+ rule/2` in bandHeight AND the `-rule/2` pad, plus `.padding(.bottom)` replacing `.vertical`, in one commit, so the reading could centre "down to the hairline". The pair has no net layout effect; the only thing it buys is the centring band's size. Proven compensation within one commit.
   Source fix: make the hairline the band's bottom edge in structure (split KeyStrip into its rule row, which belongs to the band, and the content below); delete the +/- pair.

5. [Next session] Faceplate/LCD.swift:346 `.offset(y: -6)` on the BPM label row. A post-layout nudge with no layout owner: the row keeps `.frame(height: Theme.H.sm)` and the number `.padding(.top, Theme.S.s)`; the offset moves the row and its hit area 6 pt without changing the space reserved. Layers: b133b5b (centred group) -> 63705f4 11-09 14:47 0.1.54 "BPM label row slides up 6 pt on its own (J)", 13 minutes later. A partner that this lifts back is unproven (nothing I can point to pushes it down), so this is a nudge stacked on finding 4, not a proven pair.
   Source fix: an explicit padding in the VStack so the gap is real; remove the offset.

6. [Now] Faceplate/FaceplateView.swift:34, 291; Pocket/PocketView.swift:80; MenuBar.swift:494; Mini.swift:412. Globals held next to their observable twins, then a forced rebuild to sync them. `Theme.accent` (static var) is the real display colour; `AccentSettings.effective` (@Published) is a copy; `Theme.highContrast` (static) is mirrored by `DisplaySettings.highContrast` and by `PocketState.highContrast`. Views read the static while drawing, so every surface is wrapped in `.id(accent.effective)` / `.id(state.highContrast)`, which destroys and rebuilds the whole face (and all @State: TempoLight timers, hover state, the NSTextField's focus) on every colour-wheel step (AccentSettings.drag fires at 30 Hz, Accent.swift:135). The rebuild was then compensated: Mini.swift:512 `.onDisappear { ... release(p) }`, comment "redrawn away mid-hold (a new display colour): the note still stops".
   Layers: e1663e1 11-09 13:22 added `.id(accent.effective)` (window, pocket, Mini) and the Mini `.onDisappear` release in the same commit. Proven: the onDisappear is compensation for the `.id`.
   Also, unproven in the field: `pointingHand()` (Faceplate/LCD.swift:450) pushes/pops NSCursor on hover enter/exit with no balance (17 uses; only Dial balances it, PocketView.swift:980); a view destroyed by the `.id` while hovered would leave a pushed cursor.
   Source fix: Theme accent and highContrast become environment values read through `@Environment`; delete the statics, both `.id()`s and the Mini onDisappear.

7. [Next session] Pocket/PocketAdvanced.swift:65-71 (+ MenuBar.swift:157-167). Two sizes for one popover, one a hand-added estimate and one a measurement. `@State private var natural: CGFloat = 560` ("an estimate until the first layout") and `screen - 622 - Theme.S.l - 28 - (listening ? 36 : 0)` ("the pocket without the harmony part"), while PocketContainer already measures the whole pocket (`PocketSizeKey`) and sets `popover.contentSize`. 622, 28 and 36 are sums of other views' heights with no source. e1663e1 11-09 13:22 is their only commit; later changes to that height (keyboard 64 pt, the TUNING row from 8f6a324) did not touch it. Whether 622 is still right is unproven (not rendered).
   Source fix: measure the pocket-without-harmony with the same GeometryReader and drop 622 / 28 / 36 / 560.

8. [Next session] DAWSend/AXRoutes.swift:176, DAWSend/DAWSend.swift:166, DAWSend/MidiFileDriver.swift:28-44, DAWSend/ProToolsDriver.swift:6. A removed fallback layer still described and half present. DAWSend.swift:166 says `// Accessibility, MIDI fallback (AXRoutes.swift)` while AXRoutes.swift:176 says "No MIDI-file fallback". MidiFileDriver.howTo still carries `.proTools`, `.logic`, `.studioOne` cases no code path reaches (MidiFileDriver is built only for flStudio / reason / cubase, DAWSend.swift:167).
   Layers: 330b5c5 11-01 20:57 added the MIDI fallback for the AX DAWs -> 19c2961 11-05 17:36 0.1.36 removed it ("no MIDI-file fallback ... Export MIDI is its own button") but left the comment and the dead branches. Proven.
   Source fix: delete the stale comment and the three dead howTo cases.

9. [Next session] DAWSend/AXDriver.swift, AXRoutes.swift. Stacked safety mechanisms, all from one commit (19c2961, 11-05 17:36, Pro Tools stuck at >1000 BPM).
   a) Tempo range 20...999 is checked three times for one value: `sendAX` (AXRoutes.swift:191 `!AXFieldKind.tempoRange.contains(b)`), `AXRunner.step .set` (AXDriver.swift:413), `AXFieldKind.refusal` (AXDriver.swift:292); MidiExport.swift:40 has a fourth, `(1...1000)`. The first makes the other two unreachable for a plan built from the same payload.
   b) A dialog is closed by Cancel, then Escape, then Escape again with a `wait` between each (AXDriver.swift:361-372): "if that fails try X, then X again".
   c) Hand-tuned timings with no stated source: `Thread.sleep(0.25)` after activate (AXDriver.swift:560), `usleep(8000)` per character (:188), `usleep(15000)` (:199), `usleep(150_000)` after a double-click (:212), `timeout: 3, poll: 0.1` (:339), `AXUIElementSetMessagingTimeout(e, 1.5)` (:489), `prefix(3)` neighbours and `budget: 200` (:112, :116), `budget = 6000` (:83). Ableton 1.0 s ping + 2.0 s request, Reaper 2.0 s with a 0.05 s poll, Bitwig 1.5 s, PTSL 30 s receive timeout (PTSLClient.swift:203).
   d) Alternative routes by design: Pro Tools tempo has two (AXRoutes.swift:63-70) and Studio One tempo two (:110-113); a failed route 1 falls through to route 2. Studio One labels are marked "unverified" (AXRoutes.swift:10-11): a shipped guess.
   Layers: 330b5c5 (routes, waits) -> 19c2961 (all checks, cancel, focus guard) in one commit. No second commit proves compensation, so (a)-(c) are stacked checks by one author, not proven pairs.
   Source fix: one `validate(payload)` at the top of `sendAX` owning 20...999 (MidiExport reads the same constant); one `closeDialog()` with a single Cancel and a loud failure; timings named in one AXTiming struct with the measured source in a comment.

10. [Next session] Key tables are defined in many places, not one. AutoTuneSend.swift:16-26 (keyClass dictionary); SendPayload.parseKey (DAWSend.swift:94-109, letter + accidentals, accepts spellings keyClass rejects, e.g. "Fbb"); MidiExport.swift:12-27 (signature tables plus pitch-class fallback tables); AXRoutes.swift:15-16 (AXKeyNames, which KeySpelling.swift:47 uses as the app's naming authority, a DAW-send table owning key names); Pocket/Pocket.swift:19-22 (sharpNames, flatNames, letterPC); KeySpelling.swift:11-12 (sharpRoots, flatRoots); AbletonDriver.swift:40 (a third literal name list); WavesTuneSend.swift:24-25 (step Sets) vs Pocket.swift:17-18 (Scale.major / naturalMinor). The "X minor" text is built again in DAWSend.swift:115-119, PocketView.swift:715 and Mini.swift:461. "The reading on show" with its page clamp is derived four times: KeyTeach.swift:203, MenuBar.swift:48, Pocket/Pocket.swift:183 and Faceplate/FaceplateView.swift:382, spelled `min(max(page.index, 0), rs.count - 1)` three ways.
    Source fix: one KeyName module (parse, canonical name, scale, key signature, DAW names) and one `ViewState.shown(page:)`; every table above reads from it.

11. [Next session] Hand-synced duplicate state. Mini.swift:219-221, 237-239, 256-257: `view.help` is a copy of `HelpSettings.shared.isOn` subscribed by hand (`helpWatch`); `view.key` / `view.layout` copy `feed.key`; `view.sound` mirrors UserDefaults; `watch` re-reads the whole feed "on the next turn of the run loop" because objectWillChange fires early. Settings.swift:184-213: `advanced` and `pocketAdvanced` are two flags synced by `linkFirstChange` and an `advancedLinkUsed` latch ("first change each launch sets both"); the rule is written in three places that must agree (Settings.swift:16, Help.swift:96, Settings.swift:203). Pocket/PocketView.swift:355 `AutoTuneCap` clears its flash with `asyncAfter(1.6)` and no cancel: a second press 1 s after the first is cleared 0.6 s later (visible in code, not run).
    Source fix: Mini reads HelpSettings through the environment and derives key / layout from `feed` in one computed property; one advanced setting per surface with the link as an explicit one-time action, not a latch; cancellable flash timers.

12. [Next session] Hover and flash timings picked by hand against Theme.Motion's own rule ("nothing else picks its own timing", Theme.swift:155). `.easeOut(duration: 0.12)` appears 6 times (Controls.swift:275, LCD.swift:427, PocketView.swift:854 and 1225, HarmonyView.swift:275, Help.swift:307) although `Theme.Motion.hover` is exactly 0.12 and honours Reduce Motion. ChordCell.play uses 0.08 / 0.22 / 0.25 (HarmonyView.swift:289-292); Mini pad accessibility release is `asyncAfter(0.6)` (Mini.swift:523). TempoLight (LCD.swift:479-491) schedules the "off" flash twice, once in `restart()` and once per timer tick, driving the display from a free-running Timer rather than the reading. RunningBar (LCD.swift:276) and Dial's spin (PocketView.swift:924) both start with `DispatchQueue.main.async` to dodge a replay bug named in the comment (0.1.11): RunningBar from 44cbb42 10-27, the copy in Dial from b98ef58 11-01, a recorded workaround copied twice.
    Source fix: all animations through Theme.Motion; one Pulse view for the repeating-animation start; TempoLight driven by TimelineView, not Timer + asyncAfter.

13. [Next session] Constants with several owners. Cap width 152: `Pocket.downloadCapWidth` (PocketView.swift:48) and `FaceplateView.capWidth` (FaceplateView.swift:95, from 8aa9965). The plate gradient `0x232326/0x191a1c/0x131315` in Chassis.swift:20 and PocketView.swift:487, and the wordmark gradient `0xf4f4f6/0xababb0/0xcbcbcf` in Chassis.swift:110 and PocketView.swift:506. Lamp green/red re-typed in Lamp.swift:21,23 with "// Theme.green" comments instead of reading Theme. URLTextField colours (Controls.swift:137,143) duplicate Theme.textHi / textLo. Key codes: a `KeyCode` enum (AXDriver.swift:174) vs literals 53/51/117 (Settings.swift:133-135), 36/76/49 (Controls.swift:114-115), 123/124 (FaceplateView.swift:207), 53 (Mini.swift:379), MusicalTyping's table (PlayToFind.swift:21-36). The MIDI 0...127 clamp is written ten times (NoteSynth.swift:35,50,56; Mini.swift:92,93,117; MidiExport.swift:48 and others); `UInt8(clamping: max(0, min(127, n)))` (Mini.swift:92, NoteSynth.swift:35, MidiExport.swift:48) is a clamp inside a clamp. `Theme.T.heroSize` 68 ("the window's BPM", Theme.swift:75) is dead since b133b5b set `ResultReadout.bpmSize = 80`; only tests use it (FaceplateTests.swift:78, MotionTests.swift:129).
    Source fix: Theme tokens for plate / wordmark / red hint; one KeyCode enum; one `MIDI.clamp(note)`; delete T.heroSize / T.hero.

14. [Someday] Code kept alive by tests only or by nothing: `HelpTipLogic.place` (Help.swift:157-162, used only in HelpTests.swift:82-87; the live placement is `cardOrigin`, from 8f6a324); `AXTrust.isTrusted(prompt:)` (AXDriver.swift:219, no caller; `sendAX` calls `AXIsProcessTrusted()` and `promptOnce()` directly, two prompt functions sharing one `prompted` flag); `AXKeyNames.pretty` ("kept for clarity", AXRoutes.swift:26); `MenuBarImage.side = 11` vs `make(side: 12)` "kept for callers sizing it" (MenuBar.swift:418, 423); `PocketState.lampWord` (Pocket.swift:169, test only); `FakeState` and the ORION_FAKE_STATE scenes in the app target (FaceplateModel.swift:185-243); `Pocket.snapshot` as a global static read by Theme.Motion, LinkField, PocketHarmony, KeyWheel and HelpTipLayer (a test switch inside production views).
    Source fix: delete, or move to the test target.

15. [Next session] Silent failures. (a) SettingsOpener.open (Settings.swift:263-270) clicks the app menu's "," item; on a miss it only `NSSound.beep()`, no log. (b) ShortcutStore.load (Hotkeys.swift:73) `(try? JSONDecoder().decode(...)) ?? nil`: a corrupt stored shortcut silently becomes "off", no log. (c) `try? sessionTempo()` (ProToolsDriver.swift:15) discards why the read-back failed; only "unavailable" is logged (AXRoutes.swift:205). (d) PTSLClient.call (PTSLClient.swift:235) returns `[:]` when a Completed response's JSON will not parse, and `sessionTempo` then blames "gave no time". (e) UDP.request (OSC.swift:123) `guard n > 0 else { throw Failure.noReply }` turns a socket error (n < 0) into "no reply", which Ableton / Bitwig turn into "install / turn it on" dialogs (AbletonDriver.swift:60, BitwigDriver.swift:22). (f) Missing textures -> nil -> "the plate simply draws without grain" (Theme.swift:221-223). (g) Intake.waiting (Intake.swift:21) is overwritten, not appended, when files arrive twice before the window is up.
    Source fix: each logs one line with its cause (OSStatus / errno / decoder error); (e) tells timeout from error.

16. [Someday] Pocket/PocketView.swift:804-808: `TuningMeterRow.markerX` clamps the fraction to 0...1, then clamps the result to 0...width-markerWidth: a clamp inside a clamp. The row's `textWidth 108` / `labelWidth 44` (PocketView.swift:742-744) are typed-in measurements ("106.5 pt", "44 pt") while PocketFooter measures the same way with `FooterChip.textWidth` (:432). History: 8f6a324 11-09 02:08 only; one commit, so not proven compensation.
    Source fix: one clamp; measure both widths with FooterChip.textWidth.

17. [Someday] Two shortcut mechanisms. Send to DAW (⌃⌥⌘S), Send to All (⌃⌥⌘D), Auto-Tune (⌃⌥⌘A) and Export MIDI (⌃⌥⌘E) are fixed `.keyboardShortcut` menu items (DAWSend.swift:324-327, AutoTuneSend.swift:90, MidiExport.swift:119); Listen, Analyze File, New Song, Hold, Analyze Selection live in ShortcutStore and the recorder (Hotkeys.swift:28-57). Two ways to set a shortcut, one editable. Help.swift:89 adds a third (⇧⌘A from PlayToFind, PlayToFind.swift:42).
    Source fix: all shortcuts become HotkeyActions.

## Marble test (rate per file, symphony rule 4)
- Pocket/PocketView.swift: every area probed showed a pattern (dead respell, divergent status legend, duplicate readouts, raw hover timings, hand-measured widths, clamp pair, two hex plates, timer flash, async-start hack). ~100%.
- Faceplate/LCD.swift: bandHeight pair, -6 offset, TempoLight double timers, RunningBar async start, red literal, hover 0.12 in 6 of 7 blocks. ~80%.
- DAWSend/AXDriver.swift: range checks, 3-step close, hand sleeps, dead isTrusted in 4 of 5 areas. ~80%.
- MenuBar.swift: dead respell wiring, `.id(accent)`, size estimate, duplicate 24-key menu builder, `side` vs 12. ~60%.
- Mini.swift, HarmonyView.swift, Settings.swift, Help.swift: ~40% each.
- Clean: Faceplate/Motion.swift, Brand.swift.

## Smaller items (real, low damage)
- MenuBar.swift:340-346 and Pocket/PocketAdvanced.swift:46-53 build the same 24-key menu with `i == 12 ? [.separator, item]`.
- MenuBar.swift:205-209 `fixedWidth` measures the literal "⏸ G#m 888.8 " plus the key image plus 6: a longest-case guess, not the data.
- MenuBar.swift:129-144 a CombineLatest of seven publishers with `_ = readings` used only as a trigger; AccentSettings.$effective is a second route to `show` (MenuBar.swift:146).
- FaceplateView.swift:41, 42, 52: `tempoFactor = .one` reset in three places.
- FaceplateView.swift:27, 54, 57-61: a 1 s Timer polling NSPasteboard.changeCount plus didBecomeActive plus onAppear, three triggers for `extras.refresh`.
- HarmonyView.swift:434-435 + 412-420: a section calls `choose(name)`, wrapped to ignore the name and call `click(id)`, which rebuilds the name from the slot: name -> id -> name. KeyWheel.side 216 vs outerRadius 100 (diameter 200) leaves 16 pt with no owner.
- HarmonyPanel's `compact ? ... : ...` appears 7 times: two layouts in one view.
- Chassis.swift:135 `maxWidth: 250` vs PocketView.swift:532 `maxWidth: 200` for the same status text.
- WavesTuneSend.swift:34 `0..<83` "R" parameters and the hard-coded /Applications/Waves and /Users/Shared/Waves paths (:14, :20), no source named. AutoTuneSend.swift:8 "KeyType 0 = major, 1 = minor (... not yet confirmed live)": an unconfirmed assumption shipped.
- LoginItem.swift:85-87: `legacy?.setEnabled(false)` after a successful `backend.setEnabled` can throw and report failure after the real change succeeded.
- NoteSynth.swift:91 GM bank failure falls back to a plain tone, logged once.
- DAWSend.swift:256 analyzeSelection has no `busy` guard (send has one).
- Ableton/Reaper/Bitwig each carry their own copy of the same installed / not-installed `setupStep()` shape and "key not sent" sentence.

## Run log (errors, skips)
- A multi-line compound git/bash batch was refused by the worktree guard ("too complex to verify"); I re-ran each `git log -S/-L/show` as a single plain command from the worktree. A second compound heredoc write was refused for the same reason; this report was written with the Write tool instead. No data lost.
- Several multi-file `cat -n` reads (Motion+Accent+FaceplateModel, Controls+Theme, DAWSend+AXRoutes, Hotkeys+LoginItem+Intake+KeyTeach) returned "output too large" with only a preview. I re-read each file separately so every line of every claimed file was seen. Hotkeys.swift lines 40-200 were read via `sed` (lines 1-39 from the preview); DAWSend.swift lines 1-37 from the preview, 38-357 via Read.
- `git log -S'a turn later'` returned nothing (wrong phrase); re-ran with `sweep = true`, found 44cbb42.
- No repo file was changed; no commit, build, launch or notification. No file was unreadable.
- Not verified by running or rendering: the height interplay in findings 4, 5 and 7, the focus-loss effect of the `.id()` rebuild (6), whether a failed Doctor can reach the pocket (2). These are labelled where they appear.
- Event.swift, Runtime.swift, AppLog.swift, Doctor.swift, Updater.swift: not read by me and not on the other reviewer's list as given to me.
