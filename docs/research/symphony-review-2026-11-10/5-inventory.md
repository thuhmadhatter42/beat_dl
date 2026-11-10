# beat_dl read-only inventory

Repo: /Users/jshriver/dev/beat_dl, worktree agent-a81016d9906bb5779 (branch worktree-agent-a81016d9906bb5779). Date 2026-11-10.
Read-only: no repo file changed, nothing committed, no build, test or publish script run. vendor/ and .git/ skipped everywhere. Facts only, each table is generated from the saved command output in this folder.

## Task 1: Marker sweep

Commands (run from the worktree root; scratch files in the symphony-review folder):

```sh
git ls-files | grep -v -E '^(vendor|archive|docs|handoff)/' | grep -E '\.(swift|py|sh|command|md)$' > scope-files.txt
xargs grep -n -I -i -E 'for now|temporary|temp fix|workaround|hack|fallback|TODO|FIXME|XXX|legacy|old layout|just in case|grace' < scope-files.txt > t1-raw.txt
```


Total matching lines: **159** in **48** files. Exit status of the grep: 0.

### Counts per file (highest first)

| Count | File |
|---|---|
| 15 | `tools/pt-harvest/beatfind.py` |
| 12 | `bpm.py` |
| 10 | `THIRD-PARTY-LICENSES.md` |
| 10 | `app/Sources/Orion/Live/LiveSession.swift` |
| 9 | `PICKUP.md` |
| 7 | `app/Sources/Orion/Faceplate/FaceplateModel.swift` |
| 7 | `app/Sources/Orion/LoginItem.swift` |
| 7 | `tests/test_bpm_extras.py` |
| 7 | `tools/pt-harvest/harvest.py` |
| 6 | `app/runtime.sh` |
| 5 | `app/Tests/OrionTests/DAWSendTests.swift` |
| 5 | `app/Tests/OrionTests/EngineTests.swift` |
| 5 | `app/Tests/OrionTests/LoginItemTests.swift` |
| 4 | `tests/test_app_run.py` |
| 4 | `tools/build-old-mac/essentia.sh` |
| 3 | `app/Tests/OrionTests/FaceplateTests.swift` |
| 3 | `app/Tests/OrionTests/LiveFallbackTests.swift` |
| 3 | `app/Tests/OrionTests/LoginTests.swift` |
| 3 | `app/Tests/OrionTests/WindowParityTests.swift` |
| 3 | `tools/build-old-mac/ffmpeg-arm64.sh` |
| 2 | `app/Sources/Orion/DAWSend/ProToolsDriver.swift` |
| 2 | `app/Sources/Orion/Runtime.swift` |
| 2 | `deps.sh` |
| 1 | `app/Sources/Orion/DAWSend/AXRoutes.swift` |
| 1 | `app/Sources/Orion/DAWSend/DAWSend.swift` |
| 1 | `app/Sources/Orion/Faceplate/LCD.swift` |
| 1 | `app/Sources/Orion/Harmony.swift` |
| 1 | `app/Sources/Orion/HarmonyView.swift` |
| 1 | `app/Sources/Orion/Live/SystemAudio.swift` |
| 1 | `app/Sources/Orion/MenuBar.swift` |
| 1 | `app/Sources/Orion/OrionApp.swift` |
| 1 | `app/Sources/Orion/YouTubeLogin.swift` |
| 1 | `app/Tests/OrionTests/AXDriverTests.swift` |
| 1 | `app/Tests/OrionTests/AutoTuneSendTests.swift` |
| 1 | `app/Tests/OrionTests/HarmonyTests.swift` |
| 1 | `app/Tests/OrionTests/KeyTeachTests.swift` |
| 1 | `app/Tests/OrionTests/LiveTests.swift` |
| 1 | `app/Tests/OrionTests/MidiExportTests.swift` |
| 1 | `app/Tests/OrionTests/PocketTests.swift` |
| 1 | `app/Tests/OrionTests/ReadingTests.swift` |
| 1 | `app/Tests/OrionTests/WavesTuneSendTests.swift` |
| 1 | `app/icon/archive/make_icon-staff-key.swift` |
| 1 | `app_run.py` |
| 1 | `models/README.md` |
| 1 | `tests/test_bpm_tuning.py` |
| 1 | `tools/pt-harvest/discover.py` |
| 1 | `tools/train-tempocnn/key_baseline.py` |
| 1 | `tools/train-tempocnn/runs/key-baseline-2026-11-05/eval.md` |

Top five: `tools/pt-harvest/beatfind.py` (15), `bpm.py` (12), `THIRD-PARTY-LICENSES.md` (10), `app/Sources/Orion/Live/LiveSession.swift` (10), `PICKUP.md` (9)

### Table: file:line and line text

| file:line | line text |
|---|---|
| `PICKUP.md:11` | `3. Older hand tests still untried: MINI MIDI into a DAW, live tuning with pitched Spotify, chord drag, MATCH TO, Send to DAW Pro Tools, ⇧⌘A, unplugged-interface fallback, ftC tempo on known beats.` |
| `PICKUP.md:14` | `**Closed 2026-11-10 (settled, do not re-list):** tempo model ftC shipped in 0.1.40 (e75055a); input-missing fallback built 0.1.39 (1522777; hand test still in item 3); signing keys in Passwords 2026-11-09 00:35; Orra parity + Session Key parity features all built and public (0.1.57+); FLR /beat-key page live 00:08 incl. the Finder right-click line; Waves Tune RT back-burnered by J 2026-11-05 17:17; design picks built 0.1.46; every publish.sh release up to 0.1.59 done.` |
| `PICKUP.md:47` | `1. DONE 0.1.39 (1522777): saved Listen input missing → Mac audio (System Audio) instead of "THAT INPUT IS NOT CONNECTED"; LCD shows "SAVED INPUT MISSING · USING MAC AUDIO" 8 s; saved choice kept so the device returns when plugged in; macOS 12 keeps the old error; logged to beatkey.log ("listen: saved input missing (uid …), falling back to Mac audio"). Pure LiveSourcePlan.plan + LiveFallbackTests. Swift 294 tests, 3 skipped, 0 failures. Built ('app/build.sh --no-notarize', DMG app/build/Beat-Key-0.1.39.dmg) and installed in /Applications, codesign verify OK, CFBundleShortVersionString 0.1.39. Not tried by hand: unplug the saved interface, press Listen.` |
| `PICKUP.md:68` | `- 0.1.36 = Send to DAW safety (19c2961: no BPM → tempo untouched; no Accessibility → prompt once, nothing sent; field finder never crosses labels, Location refuses a number, BPM read back 20-999 within 0.01 or abort; Cancel/Escape the dialog it opened on any failure; NO MIDI-file fallback for Pro Tools/Logic/Studio One (J: Export MIDI is its own button); every step logged) + Analyze Selection global hotkey ⌥⌘B (d7ea902; ⌃⌥⌘L is taken by Pro Tools; changeable in Settings) + play-to-find fix (930df35: the empty link field held the caret and every key was ignored). Swift 263 tests pass.` |
| `PICKUP.md:96` | `1. [BACK-BURNERED by J 2026-11-05 17:17] Waves Tune RT auto-send. Found 17:13: no MIDI Learn in the plug-in; Transmission (Send to All/Receive) is Waves instance-to-instance only; MIDI input = Reference Tone/Target Pitch, not key. Untested route if revived: host automation list (Auto button) showing Scale/Root. Preset stays the manual fallback.` |
| `PICKUP.md:126` | `1. [CLOSED 2026-11-05 17:17: BACK-BURNERED by J; no Waves Tune auto-send, preset stays the manual fallback] Waves Tune MIDI Learn test (dashboard j183/j185/j238): can Waves Tune RT Root/Scale be MIDI-learned? Yes → Beat Key sends CCs over a virtual MIDI port. No → preset stays the manual fallback, say so plainly. Mouse clicking rejected by J.` |
| `PICKUP.md:158` | `  1. [CLOSED 2026-11-05 17:17: back-burnered by J] WAVES TUNE NOT WORKING (J 02:02-02:03): J expected Send to change Waves Tune by itself; the preset route needs a manual load, so it never changed. MOUSE/WINDOW CLICKING REJECTED by J (02:05: too many permissions for a small feature). Only route left: MIDI Learn — test in J's Artemis session whether Waves Tune RT's Root and Scale controls can be MIDI-learned; if yes, Beat Key sends CCs over a virtual MIDI port (no permissions). If not, Waves Tune gets no auto-send (preset stays as the manual fallback, say so plainly). Keep the preset as fallback. Fix: J (or Claude via the Artemis window) saves any preset from Waves Tune RT (Save ▾ → Save to New File) into the User Presets folder; diff its .xps header/wrapper (PresetXMLTree version, PluginSubComp, PluginVersion, Parameters Type) against Beat Key.xps and match it. Preset "Beat Key - Am" written 01:18. Waves Tune RT is open in ARTEMIS (Track 2, window 672, on another desktop, shows C Major). Load preset ▼ → Beat Key; expect scale Natural Minor, root A. If it doesn't load, diff against a preset J saves from the plug-in.` |
| `PICKUP.md:222` | `- ffmpeg/ffprobe: 'vendor/macos-arm64/' 9.0.2 (martin-riedl) on arm64 macOS ≥ 12.0; 'vendor/macos-arm64-legacy/' our 7.1.1 minimal static build (minos 11.0, built by 'tools/build-old-mac/ffmpeg-arm64.sh') below 12; 'vendor/macos-x86_64/' evermeet 7.1.1 (minos 10.9) on Intel.` |
| `PICKUP.md:234` | `3. [CLOSED 2026-10-09] Studio-E-2: has 072cd89 (J). Per J 2026-10-28 09:54: nothing on Studio D or E for now.` |
| `THIRD-PARTY-LICENSES.md:46` | `\| ffmpeg macOS 11 licence \| 'arm64/bin-legacy/ffmpeg -L' ("GNU Lesser General Public License ... version 2.1 or later"); its configuration has no '--enable-gpl'; 'tools/build-old-mac/ffmpeg-arm64.sh' (ffmpeg 7.1.1, LAME 3.100). \|` |
| `THIRD-PARTY-LICENSES.md:1748` | `  'Gnomovision' (which makes passes at compilers) written by James Hacker.` |
| `THIRD-PARTY-LICENSES.md:2261` | `  library 'Frob' (a library for tweaking knobs) written by James Random Hacker.` |
| `THIRD-PARTY-LICENSES.md:6170` | `     software found in the legacy autoconf/ directory and its` |
| `THIRD-PARTY-LICENSES.md:7760` | `  library 'Frob' (a library for tweaking knobs) written by James Random Hacker.` |
| `THIRD-PARTY-LICENSES.md:9330` | `  'Gnomovision' (which makes passes at compilers) written by James Hacker.` |
| `THIRD-PARTY-LICENSES.md:9344` | `PyCryptodome \| Public Domain and BSD-2-Clause` |
| `THIRD-PARTY-LICENSES.md:9345` | `URL: https://www.pycryptodome.org/` |
| `THIRD-PARTY-LICENSES.md:9347` | `The source code in PyCryptodome is partially in the public domain` |
| `THIRD-PARTY-LICENSES.md:9385` | `All direct contributions to PyCryptodome are released under the following` |
| `app/Sources/Orion/DAWSend/AXRoutes.swift:176` | `/// Pro Tools, Logic Pro and Studio One / Studio Pro through Accessibility. No MIDI-file fallback` |
| `app/Sources/Orion/DAWSend/DAWSend.swift:166` | `        case .logic, .studioOne: return AXDAWDriver(daw: d)   // Accessibility, MIDI fallback (AXRoutes.swift)` |
| `app/Sources/Orion/DAWSend/ProToolsDriver.swift:6` | `/// and Key Change dialogs), and the tempo is read back over PTSL. No MIDI-file fallback.` |
| `app/Sources/Orion/DAWSend/ProToolsDriver.swift:20` | `        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BeatKey-PT-\(UUID().uuidString)", isDirectory: true)` |
| `app/Sources/Orion/Faceplate/FaceplateModel.swift:60` | `    /// fallback readout, which only says the video can't be downloaded.` |
| `app/Sources/Orion/Faceplate/FaceplateModel.swift:187` | `/// needs-login-off = the fallback readout (YouTubeLogin.inApp off).` |
| `app/Sources/Orion/Faceplate/FaceplateModel.swift:195` | `            model.url = "https://www.youtube.com/watch?v=xxxxxxxxxxx"` |
| `app/Sources/Orion/Faceplate/FaceplateModel.swift:205` | `            model.url = "https://youtu.be/xxxxxxxxxxx"` |
| `app/Sources/Orion/Faceplate/FaceplateModel.swift:215` | `            model.url = "https://www.youtube.com/watch?v=xxxxxxxxxxx"` |
| `app/Sources/Orion/Faceplate/FaceplateModel.swift:218` | `            model.url = "https://www.youtube.com/watch?v=xxxxxxxxxxx"` |
| `app/Sources/Orion/Faceplate/FaceplateModel.swift:224` | `            model.url = "https://youtu.be/xxxxxxxxxxx"` |
| `app/Sources/Orion/Faceplate/LCD.swift:45` | `    /// same 182 pt the old layout spent there, so the window keeps its height.` |
| `app/Sources/Orion/Harmony.swift:288` | `        FileManager.default.temporaryDirectory.appendingPathComponent("Beat Key Chords", isDirectory: true)` |
| `app/Sources/Orion/HarmonyView.swift:486` | `    /// key whose name does not resolve is skipped and logged once (the fallback spelling stands).` |
| `app/Sources/Orion/Live/LiveSession.swift:213` | `    case fallback(LiveSource, missingUID: String, channel: Int)` |
| `app/Sources/Orion/Live/LiveSession.swift:217` | `        case .use(let s), .fallback(let s, _, _): return s` |
| `app/Sources/Orion/Live/LiveSession.swift:221` | `    static let fallbackNotice = "SAVED INPUT MISSING · USING MAC AUDIO"` |
| `app/Sources/Orion/Live/LiveSession.swift:231` | `        return .fallback(.system, missingUID: uid, channel: ch)` |
| `app/Sources/Orion/Live/LiveSession.swift:344` | `    /// EOF on stdin ends the analyzer; it is stopped outright if it lingers past 'grace' s` |
| `app/Sources/Orion/Live/LiveSession.swift:346` | `    func close() { close(grace: 2) }` |
| `app/Sources/Orion/Live/LiveSession.swift:348` | `    func close(grace: TimeInterval) {` |
| `app/Sources/Orion/Live/LiveSession.swift:355` | `        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { if p.isRunning { p.terminate() } }` |
| `app/Sources/Orion/Live/LiveSession.swift:489` | `        if case .fallback(_, let uid, let ch) = plan {` |
| `app/Sources/Orion/Live/LiveSession.swift:493` | `            showNotice(LiveSourcePlan.fallbackNotice, gen: gen)` |
| `app/Sources/Orion/Live/SystemAudio.swift:54` | `        // First time: macOS shows its own prompt and says no for now; the user allows it in` |
| `app/Sources/Orion/LoginItem.swift:60` | `    private let legacy: LaunchAgentLoginItem?` |
| `app/Sources/Orion/LoginItem.swift:62` | `    init(backend: LoginItemBackend? = nil, legacy: LaunchAgentLoginItem? = nil) {` |
| `app/Sources/Orion/LoginItem.swift:65` | `            self.legacy = legacy` |
| `app/Sources/Orion/LoginItem.swift:68` | `            self.legacy = LaunchAgentLoginItem()` |
| `app/Sources/Orion/LoginItem.swift:71` | `            self.legacy = nil` |
| `app/Sources/Orion/LoginItem.swift:77` | `        enabled = backend.isEnabled \|\| (legacy?.isEnabled ?? false)` |
| `app/Sources/Orion/LoginItem.swift:86` | `            try legacy?.setEnabled(false)` |
| `app/Sources/Orion/MenuBar.swift:87` | `/// would need a second, fallback path for 12). The title follows the LCD's reading. A click opens` |
| `app/Sources/Orion/OrionApp.swift:201` | `                let scratch = CookieFile(url: FileManager.default.temporaryDirectory` |
| `app/Sources/Orion/Runtime.swift:28` | `        let legacy = arch == "arm64" && osMajor == 11` |
| `app/Sources/Orion/Runtime.swift:29` | `        return root.appendingPathComponent(arch).appendingPathComponent(legacy ? "bin-legacy" : "bin")` |
| `app/Sources/Orion/YouTubeLogin.swift:9` | `    /// THE switch. true = LOG IN TO YOUTUBE opens Beat Key's login window. false = the fallback:` |
| `app/Tests/OrionTests/AXDriverTests.swift:261` | `    func testLogicTempoFallsBackToDoubleClickAndTyping() {` |
| `app/Tests/OrionTests/AutoTuneSendTests.swift:29` | `        let root = FileManager.default.temporaryDirectory.appendingPathComponent("atk-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/DAWSendTests.swift:129` | `        let lib = FileManager.default.temporaryDirectory.appendingPathComponent("bk-ul-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/DAWSendTests.swift:164` | `        let box = FileManager.default.temporaryDirectory.appendingPathComponent("bk-reaper-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/DAWSendTests.swift:183` | `        let box = FileManager.default.temporaryDirectory.appendingPathComponent("bk-reaper-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/DAWSendTests.swift:193` | `        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bk-midi-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/DAWSendTests.swift:322` | `        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bk-pt-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/EngineTests.swift:149` | `    func testLegacyBinOnArm64Macos11() {` |
| `app/Tests/OrionTests/EngineTests.swift:150` | `        XCTAssertEqual(rt(os: 11).environment()["ORION_BIN"], "/R/runtime/arm64/bin-legacy")` |
| `app/Tests/OrionTests/EngineTests.swift:151` | `        XCTAssertTrue(rt(os: 11).environment()["PATH"]!.contains("/R/runtime/arm64/bin-legacy:"))` |
| `app/Tests/OrionTests/EngineTests.swift:157` | `        // deno lives in bin/ even when ffmpeg comes from bin-legacy, and only from macOS 12` |
| `app/Tests/OrionTests/EngineTests.swift:166` | `        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("orion-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/FaceplateTests.swift:82` | `        // the window keeps its height: the band is what the old layout spent above the hairline` |
| `app/Tests/OrionTests/FaceplateTests.swift:193` | `        let dir = fm.temporaryDirectory.appendingPathComponent("orion-drop-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/FaceplateTests.swift:210` | `        let dir = fm.temporaryDirectory.appendingPathComponent("orion-formats-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/HarmonyTests.swift:184` | `        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("orion-test-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/KeyTeachTests.swift:12` | `        root = FileManager.default.temporaryDirectory.appendingPathComponent("teach-tests-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/LiveFallbackTests.swift:5` | `final class LiveFallbackTests: XCTestCase {` |
| `app/Tests/OrionTests/LiveFallbackTests.swift:19` | `        XCTAssertEqual(p, .fallback(.system, missingUID: "scarlett", channel: 3))` |
| `app/Tests/OrionTests/LiveFallbackTests.swift:56` | `        XCTAssertEqual(c.notice, LiveSourcePlan.fallbackNotice)` |
| `app/Tests/OrionTests/LiveTests.swift:412` | `        p.close(grace: 100)   // let it finish the backlog (the app's Stop gives it 2 s)` |
| `app/Tests/OrionTests/LoginItemTests.swift:6` | `        let u = FileManager.default.temporaryDirectory.appendingPathComponent("orion-la-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/LoginItemTests.swift:61` | `        let legacy = LaunchAgentLoginItem(folder: tempFolder(), bundleID: "com.jshriver.orion")` |
| `app/Tests/OrionTests/LoginItemTests.swift:62` | `        try legacy.setEnabled(true)` |
| `app/Tests/OrionTests/LoginItemTests.swift:64` | `        let s = LoginItemSettings(backend: b, legacy: legacy)` |
| `app/Tests/OrionTests/LoginItemTests.swift:68` | `        XCTAssertFalse(legacy.isEnabled)         // one login item, not two` |
| `app/Tests/OrionTests/LoginTests.swift:11` | `        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("orion-login-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/LoginTests.swift:138` | `        // the fallback: a plain readout` |
| `app/Tests/OrionTests/LoginTests.swift:147` | `        XCTAssertNil(Faceplate.loginCap(busy: false, inApp: false))   // fallback: no button` |
| `app/Tests/OrionTests/MidiExportTests.swift:63` | `        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("midiexport-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/PocketTests.swift:178` | `        failed.url = "https://youtu.be/xxxxxxxxxxx"` |
| `app/Tests/OrionTests/ReadingTests.swift:274` | `        let dir = fm.temporaryDirectory.appendingPathComponent("orion-intake-\(UUID().uuidString)")` |
| `app/Tests/OrionTests/WavesTuneSendTests.swift:6` | `        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wt-\(UUID()).xps")` |
| `app/Tests/OrionTests/WindowParityTests.swift:73` | `    func testDownloadPressedWithNothingToPasteFallsToDownload() {` |
| `app/Tests/OrionTests/WindowParityTests.swift:97` | `        idle.clipboardLink = "https://www.youtube.com/watch?v=xxxxxxxxxxx"` |
| `app/Tests/OrionTests/WindowParityTests.swift:128` | `        login.url = "https://www.youtube.com/watch?v=xxxxxxxxxxx"` |
| `app/icon/archive/make_icon-staff-key.swift:227` | `let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orion-\(getpid()).iconset")` |
| `app/runtime.sh:4` | `#   bin/     ffmpeg ffprobe yt-dlp deno   (arm64 also gets bin-legacy/ = ffmpeg 7.1.1 for macOS 11)` |
| `app/runtime.sh:7` | `#            built for macOS 12.0 (LC_BUILD_VERSION minos), so bin-legacy/ (macOS 11) gets none.` |
| `app/runtime.sh:49` | `    mkdir -p "$d/bin-legacy"` |
| `app/runtime.sh:50` | `    unzip -oq "$ROOT/vendor/macos-arm64-legacy/ffmpeg.zip" -d "$d/bin-legacy"` |
| `app/runtime.sh:51` | `    unzip -oq "$ROOT/vendor/macos-arm64-legacy/ffprobe.zip" -d "$d/bin-legacy"` |
| `app/runtime.sh:54` | `  [ -d "$d/bin-legacy" ] && chmod +x "$d"/bin-legacy/*` |
| `app_run.py:85` | `        # warnings (librosa fallback, decimal BPM skipped) and tracebacks, kept` |
| `bpm.py:6` | `     - legacy essentia (no TensorFlow, no ffmpeg; old Macs): tempocnn_np.py (numpy port, weights in` |
| `bpm.py:13` | `Fallback without essentia-tensorflow: librosa (tempo on the loudest 60 s; HPSS + CENS` |
| `bpm.py:67` | `        print("Missing: essentia-tensorflow (or librosa as fallback) — install with:  "` |
| `bpm.py:152` | `    """AudioLoader stand-in for the legacy (ffmpeg-less) essentia build: returns (stereo (n, 2) float32,` |
| `bpm.py:186` | `    The legacy essentia build has no AudioLoader; decode_ffmpeg gives the same samples."""` |
| `bpm.py:206` | `    else:                                   # legacy essentia: same network in numpy` |
| `bpm.py:411` | `# ---------------------------------------------------------------- librosa fallback` |
| `bpm.py:426` | `    """Fallback: librosa tempo on the loudest 60 s (the pre-TempoCNN method).` |
| `bpm.py:439` | `    """Fallback: HPSS harmonic -> chroma_cens (tuning-corrected) -> edma profiles, whole track.` |
| `bpm.py:480` | `    title watcher (app) is the sure signal; this is the fallback.` |
| `bpm.py:894` | `        _warn("TempoCNN model missing in models/; BPM via librosa fallback")` |
| `bpm.py:898` | `    _warn("essentia-tensorflow not installed; BPM + key via librosa fallback (less accurate) — "` |
| `deps.sh:35` | `#   ffmpeg/ffprobe arm64 7.1.1     11.0   macos-arm64-legacy, ours: tools/build-old-mac/ffmpeg-arm64.sh` |
| `deps.sh:57` | `        FF_ARCH=arm64-legacy` |
| `models/README.md:31` | `with the legacy essentia build on old Macs). Generated from 'deeptemp-k16-3.pb' by` |
| `tests/test_app_run.py:51` | `        self._t = tempfile.TemporaryDirectory()` |
| `tests/test_app_run.py:135` | `        p, ev = run_cli(["download", "https://www.youtube.com/watch?v=xxxxxxxxxxx"], "fail-unavailable",` |
| `tests/test_app_run.py:208` | `    URL = "https://www.youtube.com/watch?v=xxxxxxxxxxx"` |
| `tests/test_app_run.py:353` | `    URL = "https://www.youtube.com/watch?v=xxxxxxxxxxx"` |
| `tests/test_bpm_extras.py:68` | `        with tempfile.TemporaryDirectory() as d:` |
| `tests/test_bpm_extras.py:135` | `        with tempfile.TemporaryDirectory() as d:` |
| `tests/test_bpm_extras.py:145` | `        with tempfile.TemporaryDirectory() as d:` |
| `tests/test_bpm_extras.py:216` | `        with tempfile.TemporaryDirectory() as d:` |
| `tests/test_bpm_extras.py:243` | `        with tempfile.TemporaryDirectory() as d:` |
| `tests/test_bpm_extras.py:295` | `        with tempfile.TemporaryDirectory() as d:` |
| `tests/test_bpm_extras.py:324` | `        with tempfile.TemporaryDirectory() as d:` |
| `tests/test_bpm_tuning.py:80` | `    with tempfile.TemporaryDirectory() as d:` |
| `tools/build-old-mac/essentia.sh:4` | `#   tools/build-old-mac/essentia.sh arm64     -> vendor/macos-arm64/wheels-legacy/essentia-2.1b6.dev1110-cp311-cp311-macosx_11_0_arm64.whl` |
| `tools/build-old-mac/essentia.sh:5` | `#   tools/build-old-mac/essentia.sh x86_64    -> vendor/macos-x86_64/wheels-legacy/essentia-2.1b6.dev1110-cp311-cp311-macosx_10_15_x86_64.whl` |
| `tools/build-old-mac/essentia.sh:34` | `OUT="$REPO/vendor/macos-$ARCH/wheels-legacy"` |
| `tools/build-old-mac/essentia.sh:177` | `                       "Summary: Essentia audio analysis (beat_dl legacy build: no TensorFlow, no ffmpeg, static FFTW + libsamplerate)\n"` |
| `tools/build-old-mac/ffmpeg-arm64.sh:4` | `# Output: vendor/macos-arm64-legacy/{ffmpeg,ffprobe}.zip (binary at the zip root).` |
| `tools/build-old-mac/ffmpeg-arm64.sh:10` | `OUT="$REPO/vendor/macos-arm64-legacy"` |
| `tools/build-old-mac/ffmpeg-arm64.sh:45` | `  GH="$(mktemp -d /tmp/ffgpg.XXXXXX)"; chmod 700 "$GH"` |
| `tools/pt-harvest/beatfind.py:11` | `Priority: the legacy 'Beat Buss' folder (proven on the first sessions) -> another beat-named folder ->` |
| `tools/pt-harvest/beatfind.py:13` | `the beat probe must be beat-like (sub-bass + onset pulse) and, for every source except the legacy folder,` |
| `tools/pt-harvest/beatfind.py:26` | `                     # 5: fallback sets (non-vocal tracks) tried by ear when the first set fails` |
| `tools/pt-harvest/beatfind.py:202` | `        """Fallback beat sets that only the listening checks can accept (beat_source 'audio'): everything` |
| `tools/pt-harvest/beatfind.py:216` | `                        "method": "solo-tracks", "beat_source": "audio", "confidence": "low", "legacy": False,` |
| `tools/pt-harvest/beatfind.py:229` | `    # 1. legacy Beat Buss folder (proven path, solo the folder)` |
| `tools/pt-harvest/beatfind.py:232` | `    legacy_tracks = [t for t in tl if t["type"] == "TType_Audio" and` |
| `tools/pt-harvest/beatfind.py:235` | `    res["old_rule"] = bool(fol) or bool(legacy_tracks)` |
| `tools/pt-harvest/beatfind.py:241` | `                       solo=[(f0["name"], f0["id"])], tracks=kids, legacy=True, why="Beat Buss folder")` |
| `tools/pt-harvest/beatfind.py:245` | `    if legacy_tracks and use_folders:` |
| `tools/pt-harvest/beatfind.py:246` | `        lt = [t for t in live if t in legacy_tracks]` |
| `tools/pt-harvest/beatfind.py:249` | `                       solo=[(t["name"], t["id"]) for t in lt], tracks=lt, legacy=True,` |
| `tools/pt-harvest/beatfind.py:264` | `                       tracks=kids, legacy=False, why="beat-named folder")` |
| `tools/pt-harvest/beatfind.py:274` | `                       tracks=tr, legacy=False, why=res["why"] + "; trying the non-vocal tracks by ear")` |
| `tools/pt-harvest/beatfind.py:300` | `               solo=[(t["name"], t["id"]) for t in beat], tracks=beat, legacy=False,` |
| `tools/pt-harvest/discover.py:14` | `    method = "find-fallback"` |
| `tools/pt-harvest/harvest.py:217` | `            "confidence": res["confidence"], "legacy": res.get("legacy", False), "finder": res,` |
| `tools/pt-harvest/harvest.py:339` | `    """Isolate a beat set (solo the folder / solo the beat tracks / fallback: mute everything else), LISTEN` |
| `tools/pt-harvest/harvest.py:341` | `    set fails the ears, its fallback sets (beatfind alt_sets: non-vocal tracks) get the same test.` |
| `tools/pt-harvest/harvest.py:434` | `        if not cand["legacy"]:` |
| `tools/pt-harvest/harvest.py:453` | `            chk["note"] = "legacy beat probe vocal-like"` |
| `tools/pt-harvest/harvest.py:459` | `                   "confidence": meta["confidence"], "legacy": meta["legacy"],` |
| `tools/pt-harvest/harvest.py:484` | `            note(f"beat = fallback set {tag} ({len(cand['solo'])} non-vocal tracks), accepted by ear")` |
| `tools/train-tempocnn/key_baseline.py:5` | `keeps for its librosa fallback) so a trained model has two numbers to beat.` |
| `tools/train-tempocnn/runs/key-baseline-2026-11-05/eval.md:7` | `  call). Variant: 'EDMA' profile on the same HPCP (bpm.py keeps it for the librosa fallback).` |

## Task 2: Swallowed errors

Commands (run from the worktree root; scratch files in the symphony-review folder):

```sh
git ls-files | grep -v -E '^vendor/' > all-tracked.txt
grep -E '\.swift$' all-tracked.txt > swift-files.txt ; grep -E '\.py$' all-tracked.txt > py-files.txt ; grep -E '\.(sh|command)$' all-tracked.txt > sh-files.txt
xargs grep -n -I -E 'try\?|_ = try' < swift-files.txt > t2-swift-try.txt
xargs grep -n -I -E 'catch *\{' < swift-files.txt > t2-swift-catch.txt   (bodies also read with: xargs grep -n -I -A2 -E 'catch *\{' < swift-files.txt)
xargs grep -n -I -E '^\s*except\s*:|except\s+Exception' < py-files.txt > t2-py.txt
xargs grep -n -I -E '^\s*except\s*:' < py-files.txt   (bare-except only: no output, exit 1)
xargs grep -n -I -A1 -E 'except\s+Exception' < py-files.txt   (next line read for pass/continue)
xargs grep -n -I -E '\|\| *true|2>/dev/null' < sh-files.txt > t2-sh.txt
```


### Swift: `try?` and `_ = try`

Total: **66** lines in **30** files.

| Count | File |
|---|---|
| 14 | `app/Sources/Orion/AppLog.swift` |
| 5 | `app/Sources/Orion/Doctor.swift` |
| 5 | `app/Sources/Orion/Runtime.swift` |
| 5 | `app/Tests/OrionTests/MotionFrameTests.swift` |
| 3 | `app/Tests/OrionTests/DAWSendTests.swift` |
| 2 | `app/Sources/Orion/AutoTuneSend.swift` |
| 2 | `app/Sources/Orion/DAWSend/PTSLClient.swift` |
| 2 | `app/Sources/Orion/DAWSend/ProToolsDriver.swift` |
| 2 | `app/Sources/Orion/Hotkeys.swift` |
| 2 | `app/Sources/Orion/Live/LiveSession.swift` |
| 2 | `app/Sources/Orion/Reading.swift` |
| 2 | `app/Tests/OrionTests/FaceplateTests.swift` |
| 2 | `app/Tests/OrionTests/LoginTests.swift` |
| 2 | `app/icon/archive/make_icon-staff-key.swift` |
| 1 | `app/Sources/Orion/DAWSend/AbletonDriver.swift` |
| 1 | `app/Sources/Orion/DAWSend/DAWSend.swift` |
| 1 | `app/Sources/Orion/DAWSend/ReaperDriver.swift` |
| 1 | `app/Sources/Orion/Event.swift` |
| 1 | `app/Sources/Orion/Faceplate/FaceplateModel.swift` |
| 1 | `app/Sources/Orion/KeyTeach.swift` |
| 1 | `app/Sources/Orion/Live/SystemAudio.swift` |
| 1 | `app/Sources/Orion/WavesTuneSend.swift` |
| 1 | `app/Sources/Orion/YouTubeLogin.swift` |
| 1 | `app/Tests/OrionTests/AutoTuneSendTests.swift` |
| 1 | `app/Tests/OrionTests/EngineTests.swift` |
| 1 | `app/Tests/OrionTests/HarmonyTests.swift` |
| 1 | `app/Tests/OrionTests/KeyTeachTests.swift` |
| 1 | `app/Tests/OrionTests/LoginItemTests.swift` |
| 1 | `app/Tests/OrionTests/MidiExportTests.swift` |
| 1 | `app/Tests/OrionTests/ReadingTests.swift` |

Top five: `app/Sources/Orion/AppLog.swift` (14), `app/Sources/Orion/Doctor.swift` (5), `app/Sources/Orion/Runtime.swift` (5), `app/Tests/OrionTests/MotionFrameTests.swift` (5), `app/Tests/OrionTests/DAWSendTests.swift` (3)

| file:line | line text |
|---|---|
| `app/Sources/Orion/AppLog.swift:58` | `            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)` |
| `app/Sources/Orion/AppLog.swift:59` | `            if let a = try? fm.attributesOfItem(atPath: url.path), (a[.size] as? Int ?? 0) > 5_000_000 {` |
| `app/Sources/Orion/AppLog.swift:61` | `                try? fm.removeItem(at: old)` |
| `app/Sources/Orion/AppLog.swift:62` | `                try? fm.moveItem(at: url, to: old)` |
| `app/Sources/Orion/AppLog.swift:65` | `            guard let h = try? FileHandle(forWritingTo: url) else { return }` |
| `app/Sources/Orion/AppLog.swift:68` | `            try? h.close()` |
| `app/Sources/Orion/AppLog.swift:77` | `        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)` |
| `app/Sources/Orion/AppLog.swift:78` | `        if let a = try? fm.attributesOfItem(atPath: analyzerURL.path), (a[.size] as? Int ?? 0) > 5_000_000 {` |
| `app/Sources/Orion/AppLog.swift:79` | `            try? fm.removeItem(at: analyzerURL)` |
| `app/Sources/Orion/AppLog.swift:82` | `        guard let h = try? FileHandle(forWritingTo: analyzerURL) else {` |
| `app/Sources/Orion/AppLog.swift:95` | `        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)` |
| `app/Sources/Orion/AppLog.swift:96` | `        if let prev = try? String(contentsOf: marker, encoding: .utf8) {` |
| `app/Sources/Orion/AppLog.swift:101` | `        try? me.write(to: marker, atomically: true, encoding: .utf8)` |
| `app/Sources/Orion/AppLog.swift:109` | `        try? FileManager.default.removeItem(at: marker)` |
| `app/Sources/Orion/AutoTuneSend.swift:54` | `                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)` |
| `app/Sources/Orion/AutoTuneSend.swift:61` | `            try? FileManager.default.removeItem(at: tmp)` |
| `app/Sources/Orion/DAWSend/AbletonDriver.swift:50` | `        _ = try ping()` |
| `app/Sources/Orion/DAWSend/DAWSend.swift:347` | `        for case let u? in urls { if let s = try? String(contentsOf: u, encoding: .utf8) { return s } }` |
| `app/Sources/Orion/DAWSend/PTSLClient.swift:235` | `        return ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any]) ?? [:]` |
| `app/Sources/Orion/DAWSend/PTSLClient.swift:240` | `        guard let d = json.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],` |
| `app/Sources/Orion/DAWSend/ProToolsDriver.swift:15` | `        try AXDAWDriver.sendAX(.proTools, p, readBack: { try? sessionTempo() })` |
| `app/Sources/Orion/DAWSend/ProToolsDriver.swift:39` | `        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []` |
| `app/Sources/Orion/DAWSend/ReaperDriver.swift:53` | `            if let text = try? String(contentsOf: reply, encoding: .utf8) {` |
| `app/Sources/Orion/Doctor.swift:56` | `        try? FileManager.default.removeItem(at: probe)` |
| `app/Sources/Orion/Doctor.swift:79` | `            if (try? reseed()) != nil { fixed.append("RESTORED YT-DLP") }` |
| `app/Sources/Orion/Doctor.swift:84` | `            if (try? reseed()) != nil, !fixed.contains("RESTORED YT-DLP") { fixed.append("RESTORED YT-DLP") }` |
| `app/Sources/Orion/Doctor.swift:128` | `        try? fm.createDirectory(at: rt.support, withIntermediateDirectories: true)` |
| `app/Sources/Orion/Doctor.swift:130` | `        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: rt.stamp.path)` |
| `app/Sources/Orion/Event.swift:85` | `              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]` |
| `app/Sources/Orion/Faceplate/FaceplateModel.swift:132` | `                  (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true` |
| `app/Sources/Orion/Hotkeys.swift:112` | `        return (try? JSONDecoder().decode(Shortcut?.self, from: data)) ?? nil` |
| `app/Sources/Orion/Hotkeys.swift:127` | `        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: ShortcutStore.key(a)) }` |
| `app/Sources/Orion/KeyTeach.swift:111` | `            let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue` |
| `app/Sources/Orion/Live/LiveSession.swift:20` | `              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],` |
| `app/Sources/Orion/Live/LiveSession.swift:352` | `            try? stdin.fileHandleForWriting.close()` |
| `app/Sources/Orion/Live/SystemAudio.swift:136` | `        let mono: [Float]? = try? sb.withAudioBufferList { list, _ in SystemAudioCapture.mono(list) }` |
| `app/Sources/Orion/Reading.swift:245` | `        let saved = defaults.data(forKey: RecentStore.key).flatMap { try? JSONDecoder().decode([Reading].self, from: $0) }` |
| `app/Sources/Orion/Reading.swift:265` | `        if let data = try? JSONEncoder().encode(readings) { defaults.set(data, forKey: RecentStore.key) }` |
| `app/Sources/Orion/Runtime.swift:129` | `        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)` |
| `app/Sources/Orion/Runtime.swift:131` | `        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: stamp.path)` |
| `app/Sources/Orion/Runtime.swift:142` | `        guard let m = (try? FileManager.default.attributesOfItem(atPath: stamp.path))?[.modificationDate] as? Date` |
| `app/Sources/Orion/Runtime.swift:169` | `        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)` |
| `app/Sources/Orion/Runtime.swift:171` | `        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: stamp.path)` |
| `app/Sources/Orion/WavesTuneSend.swift:20` | `        guard let dirs = try? fm.contentsOfDirectory(atPath: "/Applications/Waves") else { return false }` |
| `app/Sources/Orion/YouTubeLogin.swift:134` | `    func delete() { try? FileManager.default.removeItem(at: url) }` |
| `app/Tests/OrionTests/AutoTuneSendTests.swift:32` | `        defer { try? FileManager.default.removeItem(at: root) }` |
| `app/Tests/OrionTests/DAWSendTests.swift:170` | `                if let t = try? String(contentsOf: req, encoding: .utf8) {` |
| `app/Tests/OrionTests/DAWSendTests.swift:172` | `                    try? DAWFiles.write(ReaperDriver.encode(["id": r["id"]!, "ok": "1", "bpm": r["bpm"]!]), to: box.appendingPathComponent("reply.txt"))` |
| `app/Tests/OrionTests/DAWSendTests.swift:323` | `        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)` |
| `app/Tests/OrionTests/EngineTests.swift:167` | `        defer { try? FileManager.default.removeItem(at: tmp) }` |
| `app/Tests/OrionTests/FaceplateTests.swift:195` | `        defer { try? fm.removeItem(at: dir) }` |
| `app/Tests/OrionTests/FaceplateTests.swift:212` | `        defer { try? fm.removeItem(at: dir) }` |
| `app/Tests/OrionTests/HarmonyTests.swift:185` | `        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }` |
| `app/Tests/OrionTests/KeyTeachTests.swift:16` | `        try? FileManager.default.trashItem(at: root, resultingItemURL: nil)` |
| `app/Tests/OrionTests/LoginItemTests.swift:7` | `        addTeardownBlock { try? FileManager.default.removeItem(at: u) }` |
| `app/Tests/OrionTests/LoginTests.swift:12` | `        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)` |
| `app/Tests/OrionTests/LoginTests.swift:17` | `        try? FileManager.default.removeItem(at: tmp)` |
| `app/Tests/OrionTests/MidiExportTests.swift:65` | `        defer { try? FileManager.default.removeItem(at: dir) }` |
| `app/Tests/OrionTests/MotionFrameTests.swift:214` | `        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)` |
| `app/Tests/OrionTests/MotionFrameTests.swift:233` | `            try? png.write(to: out.appendingPathComponent("\(name).png"))` |
| `app/Tests/OrionTests/MotionFrameTests.swift:247` | `            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)` |
| `app/Tests/OrionTests/MotionFrameTests.swift:249` | `            if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }` |
| `app/Tests/OrionTests/MotionFrameTests.swift:250` | `            else { try? line.write(to: u, atomically: true, encoding: .utf8) }` |
| `app/Tests/OrionTests/ReadingTests.swift:276` | `        defer { try? fm.removeItem(at: dir); Intake.handler = nil }` |
| `app/icon/archive/make_icon-staff-key.swift:228` | `try? fm.removeItem(at: iconset)` |
| `app/icon/archive/make_icon-staff-key.swift:241` | `try? fm.removeItem(at: iconset)` |

### Swift: `catch {` blocks

Total: **25** catch blocks in **17** files. Body status is from a brace count in the worktree source (heuristic) and was also checked by reading the two lines after each catch (grep -A2).

| file:line | line text | body status |
|---|---|---|
| `app/Sources/Orion/AutoTuneSend.swift:59` | `        } catch {` | body has statement(s) |
| `app/Sources/Orion/DAWSend/AXDriver.swift:399` | `            do { try step(inner) } catch { note("skipped \(inner): \(error)") }` | inline body with statement(s) |
| `app/Sources/Orion/DAWSend/AXRoutes.swift:160` | `                catch {` | body has statement(s) |
| `app/Sources/Orion/DAWSend/DAWSend.swift:286` | `                do { try s.install?() } catch { return SendOutcome(daw: d, ok: false, message: "\(error)") }` | inline body with statement(s) |
| `app/Sources/Orion/DAWSend/DAWSend.swift:287` | `            } catch {` | body has statement(s) |
| `app/Sources/Orion/Engine.swift:43` | `            do { try p.run() } catch {` | body has statement(s) |
| `app/Sources/Orion/Harmony.swift:299` | `        } catch {` | body has statement(s) |
| `app/Sources/Orion/KeyTeach.swift:119` | `                } catch {` | body has statement(s) |
| `app/Sources/Orion/KeyTeach.swift:136` | `                } catch {` | body has statement(s) |
| `app/Sources/Orion/KeyTeach.swift:233` | `            } catch {` | body has statement(s) |
| `app/Sources/Orion/Live/AudioInput.swift:185` | `        } catch {` | body has statement(s) |
| `app/Sources/Orion/Live/LiveSession.swift:312` | `        do { try process.run() } catch { AppLog.log("analyzer failed to start: \(error)"); return nil }` | inline body with statement(s) |
| `app/Sources/Orion/Live/LiveSession.swift:337` | `            do { try stdin.fileHandleForWriting.write(contentsOf: data) } catch {` | body has statement(s) |
| `app/Sources/Orion/Live/SystemAudio.swift:94` | `            } catch {` | body has statement(s) |
| `app/Sources/Orion/LoginItem.swift:88` | `        } catch {` | body has statement(s) |
| `app/Sources/Orion/MidiExport.swift:105` | `        } catch {` | body has statement(s) |
| `app/Sources/Orion/NoteSynth.swift:89` | `        } catch {` | body has statement(s) |
| `app/Sources/Orion/NoteSynth.swift:96` | `        } catch {` | body has statement(s) |
| `app/Sources/Orion/Runtime.swift:79` | `        do { try p.run() } catch { return (-1, "\(error)") }` | inline body with statement(s) |
| `app/Sources/Orion/Runtime.swift:121` | `        do { try seedYtDlp() } catch { AppLog.log("yt-dlp seed into \(ytdlp.path) failed: \(error); downloads will fail") }` | inline body with statement(s) |
| `app/Sources/Orion/Runtime.swift:158` | `            do { try reseed() } catch { AppLog.log("yt-dlp reseed failed: \(error)") }` | inline body with statement(s) |
| `app/Sources/Orion/Runtime.swift:165` | `                do { try reseed() } catch { AppLog.log("yt-dlp reseed failed: \(error)") }` | inline body with statement(s) |
| `app/Sources/Orion/WavesTuneSend.swift:77` | `        } catch {` | body has statement(s) |
| `app/Sources/Orion/YouTubeLogin.swift:246` | `            do { try self.file.write(cookies) } catch {` | body has statement(s) |
| `app/Tests/OrionTests/MarketingRenderTests.swift:40` | `            } catch {` | body has statement(s) |

Catch blocks with an empty or comment-only body: **0**.

Counts per file:

| Count | File |
|---|---|
| 4 | `app/Sources/Orion/Runtime.swift` |
| 3 | `app/Sources/Orion/KeyTeach.swift` |
| 2 | `app/Sources/Orion/DAWSend/DAWSend.swift` |
| 2 | `app/Sources/Orion/Live/LiveSession.swift` |
| 2 | `app/Sources/Orion/NoteSynth.swift` |
| 1 | `app/Sources/Orion/AutoTuneSend.swift` |
| 1 | `app/Sources/Orion/DAWSend/AXDriver.swift` |
| 1 | `app/Sources/Orion/DAWSend/AXRoutes.swift` |
| 1 | `app/Sources/Orion/Engine.swift` |
| 1 | `app/Sources/Orion/Harmony.swift` |
| 1 | `app/Sources/Orion/Live/AudioInput.swift` |
| 1 | `app/Sources/Orion/Live/SystemAudio.swift` |
| 1 | `app/Sources/Orion/LoginItem.swift` |
| 1 | `app/Sources/Orion/MidiExport.swift` |
| 1 | `app/Sources/Orion/WavesTuneSend.swift` |
| 1 | `app/Sources/Orion/YouTubeLogin.swift` |
| 1 | `app/Tests/OrionTests/MarketingRenderTests.swift` |

Top five: `app/Sources/Orion/Runtime.swift` (4), `app/Sources/Orion/KeyTeach.swift` (3), `app/Sources/Orion/DAWSend/DAWSend.swift` (2), `app/Sources/Orion/Live/LiveSession.swift` (2), `app/Sources/Orion/NoteSynth.swift` (2)

### Python: bare `except:` and `except Exception`

Bare `except:` matches: **0** (command returned no lines).

`except Exception` lines (bare and broad, grep output): **41** in **14** files.

| file:line | line text | body status |
|---|---|---|
| `app/Sources/Orion/Resources/BeatKeyAbleton.py:113` | `    except Exception as e:  # never let a bad packet take the script down` | returns a value (not pass/continue) |
| `app/Sources/Orion/Resources/BeatKeyAbleton.py:136` | `        except Exception as e:` | logs or handles (next line: self.log_message("Beat Key could not open port %d: %s" % (PO) |
| `app/Sources/Orion/Resources/BeatKeyAbleton.py:141` | `        except Exception:` | logs or handles (next line: self._major = 0) |
| `app/Sources/Orion/Resources/BeatKeyAbleton.py:159` | `            except Exception as e:` | logs or handles (next line: self.log_message("Beat Key reply failed: %s" % e)) |
| `app_run.py:153` | `        except Exception as exc:  # keep the process alive; report as a download error` | logs or handles (next line: err.write(f"Download failed: {exc}\n")) |
| `app_run.py:220` | `    except Exception as exc:` | logs or handles (next line: log(f"could not write last-run.log: {exc}")  # the log must ) |
| `app_run.py:278` | `    except Exception as exc:` | logs or handles (next line: log(f"analysis crashed on {path.name}: {exc!r}")) |
| `app_run.py:290` | `        except Exception as exc:` | logs or handles (next line: # Rename failed: keep the original file and its analysis.) |
| `app_run.py:304` | `    except Exception as exc:` | logs or handles (next line: log(f"could not append to the links log {log_path()}: {exc}") |
| `app_run.py:330` | `        except Exception as exc:` | logs or handles (next line: log(f"analysis crashed on {path.name}: {exc!r}")) |
| `app_run.py:335` | `        except Exception:` | logs or handles (next line: full = str(path)) |
| `bpm.py:323` | `        except Exception as exc:                   # the 440 Hz reading stands` | logs or handles (next line: _warn(f"retuned key skipped: {exc}")) |
| `bpm.py:405` | `    except Exception as exc:` | logs or handles (next line: _warn(f"tuning skipped: {exc}")) |
| `bpm.py:433` | `    except Exception:` | logs or handles (next line: bpm = float(tempo)) |
| `bpm.py:756` | `            except Exception as exc:               # the whole number stands` | logs or handles (next line: _warn(f"decimal BPM skipped: {exc}")) |
| `bpm.py:891` | `            except Exception as exc:               # the whole number stands` | logs or handles (next line: _warn(f"decimal BPM skipped: {exc}")) |
| `docs/research/bpm-bench/bench.py:182` | `            except Exception as e:` | logs or handles (next line: est = float("nan"); print(f"[{m}] {n}: ERROR {e!r}", file=sy) |
| `docs/research/key-bench/bench.py:223` | `        except Exception as e:` | logs or handles (next line: print(f'  {name}: ERROR {e}', file=sys.stderr); continue) |
| `downloader.py:114` | `        except Exception:` | swallowed: next line is pass |
| `downloader.py:307` | `        except Exception as exc:` | logs or handles (next line: meta_err = [str(exc)]) |
| `downloader.py:342` | `        except Exception as exc:` | logs or handles (next line: last_err = [str(exc)]) |
| `friends-page/serve.py:18` | `    except Exception: pass` | swallowed: pass on same line |
| `tools/pt-harvest/dialog_clicker.py:84` | `            except Exception:` | swallowed: next line is pass |
| `tools/pt-harvest/dialog_clicker.py:105` | `        except Exception:` | swallowed: next line is pass |
| `tools/pt-harvest/dialog_clicker.py:274` | `        except Exception as e:` | logs or handles (next line: log(f"err {type(e).__name__}")) |
| `tools/pt-harvest/harvest.py:323` | `        except Exception as ex:` | logs or handles (next line: fe = {"mean_db": hlib.mean_db(pp), "err": type(ex).__name__}) |
| `tools/pt-harvest/harvest.py:533` | `    except Exception:` | returns a value (not pass/continue) |
| `tools/pt-harvest/harvest.py:693` | `            except Exception as ex:` | logs or handles (next line: rec["notes"].append(f"autotune read error {type(ex).__name__) |
| `tools/pt-harvest/harvest.py:749` | `        except Exception:` | swallowed: next line is pass |
| `tools/pt-harvest/harvest.py:793` | `        except Exception:` | logs or handles (next line: w = 0) |
| `tools/pt-harvest/harvest.py:876` | `        except Exception:` | logs or handles (next line: time.sleep(10)) |
| `tools/pt-harvest/hlib.py:354` | `    except Exception:` | returns a value (not pass/continue) |
| `tools/pt-harvest/lt_probe.py:12` | `    except Exception as e:` | logs or handles (next line: print(lt, "fail", str(e).split("command_error_message")[-1][) |
| `tools/train-tempocnn/key_baseline.py:122` | `        except Exception as exc:` | logs or handles (next line: log.error("parity-%02d failed: %s", i, exc)) |
| `tools/train-tempocnn/key_baseline.py:157` | `        except Exception as exc:` | logs or handles (next line: log.error("pt%04d: truth key unparsable (%s)", sid, exc)) |
| `tools/train-tempocnn/key_baseline.py:172` | `            except Exception as exc:` | logs or handles (next line: log.error("%s: detector failed: %s", rid, exc)) |
| `tools/train-tempocnn/leakage_check.py:128` | `        except Exception:` | logs or handles (next line: logging.error("cannot load features for %s (%s)", i, p.paren) |
| `tools/verify-labels/server.py:148` | `        except Exception as e:` | logs or handles (next line: log.error("GET %s: %s", self.path, traceback.format_exc())) |
| `tools/verify-labels/server.py:152` | `            except Exception:` | swallowed: next line is pass |
| `tools/verify-labels/server.py:170` | `        except Exception as e:` | logs or handles (next line: log.error("POST %s: %s", self.path, traceback.format_exc())) |
| `tools/verify-labels/server.py:174` | `            except Exception:` | swallowed: next line is pass |

Swallowed (pass/continue): **7**.

Counts per file (grep matches):

| Count | File |
|---|---|
| 7 | `app_run.py` |
| 6 | `tools/pt-harvest/harvest.py` |
| 5 | `bpm.py` |
| 4 | `app/Sources/Orion/Resources/BeatKeyAbleton.py` |
| 4 | `tools/verify-labels/server.py` |
| 3 | `downloader.py` |
| 3 | `tools/pt-harvest/dialog_clicker.py` |
| 3 | `tools/train-tempocnn/key_baseline.py` |
| 1 | `docs/research/bpm-bench/bench.py` |
| 1 | `docs/research/key-bench/bench.py` |
| 1 | `friends-page/serve.py` |
| 1 | `tools/pt-harvest/hlib.py` |
| 1 | `tools/pt-harvest/lt_probe.py` |
| 1 | `tools/train-tempocnn/leakage_check.py` |

Top five: `app_run.py` (7), `tools/pt-harvest/harvest.py` (6), `bpm.py` (5), `app/Sources/Orion/Resources/BeatKeyAbleton.py` (4), `tools/verify-labels/server.py` (4)

### Shell: `|| true` and `2>/dev/null`

Total: **34** lines in **17** files.

| Count | File |
|---|---|
| 10 | `app/build.sh` |
| 6 | `deps.sh` |
| 3 | `tools/pt-harvest/run_batch.sh` |
| 2 | `app/runtime.sh` |
| 1 | `docs/research/bpm-bench/fetch.sh` |
| 1 | `run.sh` |
| 1 | `tests/fixtures/make_click.sh` |
| 1 | `tools/build-old-mac/check-macho.sh` |
| 1 | `tools/build-old-mac/essentia.sh` |
| 1 | `tools/build-old-mac/ffmpeg-arm64.sh` |
| 1 | `tools/pt-harvest/btail.sh` |
| 1 | `tools/pt-harvest/ilokcheck.sh` |
| 1 | `tools/pt-harvest/rtail.sh` |
| 1 | `tools/pt-harvest/usblist.sh` |
| 1 | `tools/pt-harvest/waitnew.sh` |
| 1 | `tools/pt-harvest/watch.sh` |
| 1 | `tools/train-tempocnn/retrain.sh` |

Top five: `app/build.sh` (10), `deps.sh` (6), `tools/pt-harvest/run_batch.sh` (3), `app/runtime.sh` (2), `docs/research/bpm-bench/fetch.sh` (1)

| file:line | line text |
|---|---|
| `app/build.sh:107` | `codesign -d --entitlements - "$OUTAPP" 2>/dev/null \| grep -q com.apple.security.device.audio-input \` |
| `app/build.sh:110` | `codesign -d --entitlements - "$OUTAPP" 2>/dev/null \| grep -q com.apple.security.automation.apple-events \` |
| `app/build.sh:116` | `  ents="$(codesign -d --entitlements - "$OUTAPP/Contents/Resources/runtime/$a/bin/yt-dlp" 2>/dev/null)"` |
| `app/build.sh:120` | `  ents="$(codesign -d --entitlements - "$OUTAPP/Contents/Resources/runtime/$a/bin/deno" 2>/dev/null)"` |
| `app/build.sh:154` | `detach() { hdiutil detach "$MNT" -quiet 2>/dev/null \|\| hdiutil detach "$MNT" -force -quiet 2>/dev/null \|\| true; }` |
| `app/build.sh:161` | `  rmdir "$OLD" 2>/dev/null \|\| true` |
| `app/build.sh:195` | `chmod -Rf go-w "$MNT" 2>/dev/null \|\| true` |
| `app/build.sh:209` | `ID="$(/usr/bin/plutil -extract id raw -o - "$OUTJ" 2>/dev/null \|\| true)"` |
| `app/build.sh:210` | `STATUS="$(/usr/bin/plutil -extract status raw -o - "$OUTJ" 2>/dev/null \|\| true)"` |
| `app/build.sh:213` | `  [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" \|\| true` |
| `app/runtime.sh:53` | `  chmod +x "$d"/bin/* 2>/dev/null \|\| true` |
| `app/runtime.sh:70` | `    run_arch "$a" "$OUT/$a/python/bin/python3" -m compileall -q "$OUT/$a/python" >/dev/null \|\| true  # essentia ships py2 example scripts that cannot compile` |
| `deps.sh:47` | `if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then CPU=arm64; else CPU=x86_64; fi` |
| `deps.sh:64` | `    "$PY" -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('essentia') else 1)" 2>/dev/null` |
| `deps.sh:94` | `    chmod +x "$BIN_DIR/$1" 2>/dev/null` |
| `deps.sh:112` | `    if [ "$(cat "$PICKS" 2>/dev/null)" != "$picks" ]; then` |
| `deps.sh:123` | `    chmod +x "$DEPS_DIR"/run.sh "$DEPS_DIR"/run.command "$DEPS_DIR"/install.command 2>/dev/null` |
| `deps.sh:137` | `    if [ ! -f "$STAMP" ] \|\| [ -n "$(find "$STAMP" -mtime +"$UPGRADE_EVERY_DAYS" 2>/dev/null)" ]; then` |
| `docs/research/bpm-bench/fetch.sh:10` | `IP=$(nslookup www.cp.jku.at 2>/dev/null \| awk '/^Address/ && $2!~/#/ {print $2}' \| tail -1); IP=${IP:-140.78.124.154}` |
| `run.sh:19` | `    analysis=$("$PY" "$SCRIPT_DIR/bpm.py" "$1" 2>/dev/null) \|\| analysis=""` |
| `tests/fixtures/make_click.sh:14` | `[ -n "$FF" ] \|\| FF="$(command -v ffmpeg \|\| true)"` |
| `tools/build-old-mac/check-macho.sh:30` | `    hits="$(strings -a "$f" \| grep -iE 'libSDL\|SDL2\|libavcodec\|libavformat\|libavdevice\|libtensorflow' \|\| true)"` |
| `tools/build-old-mac/essentia.sh:142` | `grep -E "detected\|ignored\|Building" "$B/essentia.log" \| sed 's/^/   /' \|\| true` |
| `tools/build-old-mac/ffmpeg-arm64.sh:48` | `      "$WORK/dl-ffmpeg/ffmpeg-$FFMPEG_VER.tar.xz" 2>/dev/null \| grep -q "VALIDSIG $FFMPEG_KEY" \` |
| `tools/pt-harvest/btail.sh:8` | `[ -f batch.pid ] && kill -0 "$(cat batch.pid)" 2>/dev/null && echo "supervisor alive" \|\| echo "supervisor NOT running"` |
| `tools/pt-harvest/ilokcheck.sh:3` | `echo "-- USB iLok:"; system_profiler SPUSBDataType 2>/dev/null \| grep -i -A2 'ilok' \| grep -iE 'ilok\|serial' \| sed 's/Serial Number:.*/Serial Number: <present>/' \| head -6` |
| `tools/pt-harvest/rtail.sh:7` | `[ -f batch.pid ] && kill -0 "$(cat batch.pid)" 2>/dev/null && echo "supervisor alive" \|\| echo "supervisor NOT running"` |
| `tools/pt-harvest/run_batch.sh:15` | `    if ! { [ -f clicker.pid ] && kill -0 "$(cat clicker.pid)" 2>/dev/null; }; then` |
| `tools/pt-harvest/run_batch.sh:18` | `        echo "$(date '+%F %T') supervisor: dialog_clicker started pid $(cat clicker.pid 2>/dev/null)"` |
| `tools/pt-harvest/run_batch.sh:29` | `    kill $keeper 2>/dev/null` |
| `tools/pt-harvest/usblist.sh:3` | `system_profiler SPUSBDataType 2>/dev/null \| grep -E '^ {8,}[^ ].*:$' \| sed 's/^ *//' \| sort \| uniq -c \| head -40` |
| `tools/pt-harvest/waitnew.sh:16` | `[ -f batch.pid ] && kill -0 "$(cat batch.pid)" 2>/dev/null \|\| echo "supervisor NOT running"` |
| `tools/pt-harvest/watch.sh:8` | `    out=$("$RC" js-mac-pro "grep -E '#[0-9]{4} (ok\|skip\|excluded\|silent\|error\|mix-only (True\|False))\|supervisor\|BLOCKED\|STOP\|EXC\|target reached\|exhausted\|errors in a row' ~/pt-harvest/logs/batch.log \| tail -n 6; test -f ~/pt-harvest/BLOCKED && echo BLOCKED-FILE" 2>/dev/null \|\| true)` |
| `tools/train-tempocnn/retrain.sh:38` | `N=$(find "$ROOT/models" -maxdepth 1 -name 'deeptemp-k16-3-ft*.npz' \| sed -E 's/.*-ft([0-9]+)\.npz$/\1/' \| grep -E '^[0-9]+$' \| sort -n \| tail -1 \|\| true)` |

## Task 3: Hand-tuned delays

Commands (run from the worktree root; scratch files in the symphony-review folder):

```sh
xargs grep -n -I -E 'sleep\(|Thread\.sleep|usleep|asyncAfter|Task\.sleep|time\.sleep|sleep ' < all-tracked.txt > t3-raw.txt
```


Total matching lines: **63** in **32** files. Matches in PICKUP.md and handoff/ are prose (the word 'sleep' in 'screen-sleep'), not code. `Task.sleep` had no matches. A delay written as a variable (e.g. `wait`, `grace`, `secs`) is shown as written; its value is not resolved here.

Counts per file:

| Count | File |
|---|---|
| 6 | `tools/pt-harvest/harvest.py` |
| 5 | `app/Sources/Orion/DAWSend/AXDriver.swift` |
| 5 | `app/Sources/Orion/OrionApp.swift` |
| 5 | `tools/pt-harvest/dialog_clicker.py` |
| 5 | `tools/pt-harvest/hlib.py` |
| 3 | `tools/pt-harvest/axvis.py` |
| 3 | `tools/pt-harvest/run_batch.sh` |
| 2 | `PICKUP.md` |
| 2 | `app/Sources/Orion/Faceplate/LCD.swift` |
| 2 | `app/Sources/Orion/Live/LiveSession.swift` |
| 2 | `app/Sources/Orion/NoteSynth.swift` |
| 2 | `tests/test_bpm_stream.py` |
| 2 | `tools/pt-harvest/click_at.py` |
| 1 | `app/Sources/Orion/DAWSend/ReaperDriver.swift` |
| 1 | `app/Sources/Orion/Engine.swift` |
| 1 | `app/Sources/Orion/Faceplate/Accent.swift` |
| 1 | `app/Sources/Orion/HarmonyView.swift` |
| 1 | `app/Sources/Orion/Live/SystemAudio.swift` |
| 1 | `app/Sources/Orion/Mini.swift` |
| 1 | `app/Sources/Orion/Pocket/PocketView.swift` |
| 1 | `app/Sources/Orion/Runtime.swift` |
| 1 | `app/Tests/OrionTests/DAWSendTests.swift` |
| 1 | `handoff/TO-FLR-SITE-2026-11-03-finder-item.md` |
| 1 | `tests/stub/yt-dlp` |
| 1 | `tools/pt-harvest/axpress.py` |
| 1 | `tools/pt-harvest/bypass_view.py` |
| 1 | `tools/pt-harvest/drag.py` |
| 1 | `tools/pt-harvest/pt_launch.py` |
| 1 | `tools/pt-harvest/ptkill.sh` |
| 1 | `tools/pt-harvest/sv.sh` |
| 1 | `tools/pt-harvest/waitnew.sh` |
| 1 | `tools/pt-harvest/watch.sh` |

Top five: `tools/pt-harvest/harvest.py` (6), `app/Sources/Orion/DAWSend/AXDriver.swift` (5), `app/Sources/Orion/OrionApp.swift` (5), `tools/pt-harvest/dialog_clicker.py` (5), `tools/pt-harvest/hlib.py` (5)

| file:line | line text | delay as written |
|---|---|---|
| `PICKUP.md:123` | `**Beat Key releases: 0.1.34 is public (J published 2026-11-03 ~00:58; GH release + appcast + Sofia version file verified), installed on the MBP, Services menu shows "Analyze with Beat Key", J did the Finder right-click test ("done the one thing").** 0.1.33 = window matches the menu-bar pocket (15a18ec) + screen-sleep stream reopen (be0a9ce, only permission errors reach the UI). 0.1.34 = Finder service NSRequiredContext. Next release: J runs '! bash ~/dev/beat_dl/tools/publish.sh' (reads VERSION; restarts nothing). Unreleased on main: c1223a9 (intake logs how files arrive, counts only).` | `no literal delay (prose match)` |
| `PICKUP.md:148` | `**Beat Key releases (2026-11-03 00:55): 0.1.34 is public (J published 2026-11-03 ~00:58; GH release + appcast + Sofia version file verified). It has (window matches the menu-bar pocket, screen-sleep stream reopen, Finder 'Analyze with Beat Key' NSRequiredContext) is installed on J's MBP. Next release: J runs '! bash ~/dev/beat_dl/tools/publish.sh' (reads VERSION). [CLOSED 2026-11-03 00:53: J's Finder right-click test was done ("done the one thing"), see the CURRENT STATE block.]** 0.1.29 (e3435a1): no '…', no menu-bar key until locked. 0.1.30 (c22326a): one Send to Auto-Tune button sends Antares + Waves Tune preset. All SESSION Key features merged (plan docs/plans/session-key-parity.md, §1-§5 ticked, §6 release owed). J's standing order (2026-11-01 20:14): build ALL of it, no "next section?" check-ins.` | `no literal delay (prose match)` |
| `app/Sources/Orion/DAWSend/AXDriver.swift:188` | `            usleep(8000)` | `usleep(8000)` |
| `app/Sources/Orion/DAWSend/AXDriver.swift:199` | `        usleep(15000)` | `usleep(15000)` |
| `app/Sources/Orion/DAWSend/AXDriver.swift:212` | `        usleep(150_000)` | `usleep(150_000)` |
| `app/Sources/Orion/DAWSend/AXDriver.swift:380` | `            Thread.sleep(forTimeInterval: poll)` | `sleep(forTimeInterval: poll)` |
| `app/Sources/Orion/DAWSend/AXDriver.swift:560` | `        Thread.sleep(forTimeInterval: 0.25)` | `sleep(forTimeInterval: 0.25)` |
| `app/Sources/Orion/DAWSend/ReaperDriver.swift:57` | `            Thread.sleep(forTimeInterval: 0.05)` | `sleep(forTimeInterval: 0.05)` |
| `app/Sources/Orion/Engine.swift:238` | `            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {` | `now() + 0.4` |
| `app/Sources/Orion/Faceplate/Accent.swift:181` | `            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in` | `now() + wait` |
| `app/Sources/Orion/Faceplate/LCD.swift:486` | `            DispatchQueue.main.asyncAfter(deadline: .now() + p * 0.2) { if timer != nil { lit = false } }` | `now() + p * 0.2` |
| `app/Sources/Orion/Faceplate/LCD.swift:490` | `        DispatchQueue.main.asyncAfter(deadline: .now() + p * 0.2) { if timer != nil { lit = false } }` | `now() + p * 0.2` |
| `app/Sources/Orion/HarmonyView.swift:290` | `        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {` | `now() + 0.22` |
| `app/Sources/Orion/Live/LiveSession.swift:355` | `        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { if p.isRunning { p.terminate() } }` | `now() + grace` |
| `app/Sources/Orion/Live/LiveSession.swift:637` | `        DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: work)` | `now() + secs` |
| `app/Sources/Orion/Live/SystemAudio.swift:159` | `        queue.asyncAfter(deadline: .now() + wait, execute: w)` | `now() + wait` |
| `app/Sources/Orion/Mini.swift:523` | `                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { release(p) }` | `now() + 0.6` |
| `app/Sources/Orion/NoteSynth.swift:39` | `        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: rel)` | `now() + seconds` |
| `app/Sources/Orion/NoteSynth.swift:69` | `        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + NoteSynth.idleSeconds, execute: stop)` | `now() + seconds + NoteSynth.idleSeconds` |
| `app/Sources/Orion/OrionApp.swift:189` | `                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {` | `now() + 0.3` |
| `app/Sources/Orion/OrionApp.swift:197` | `                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { d.advanced.toggle() }` | `now() + 2` |
| `app/Sources/Orion/OrionApp.swift:198` | `                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { d.advanced.toggle() }` | `now() + 5` |
| `app/Sources/Orion/OrionApp.swift:203` | `                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {` | `now() + 0.8` |
| `app/Sources/Orion/OrionApp.swift:211` | `            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [login] in` | `now() + 0.8` |
| `app/Sources/Orion/Pocket/PocketView.swift:355` | `            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { flash = nil }` | `now() + 1.6` |
| `app/Sources/Orion/Runtime.swift:86` | `        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: kill)` | `now() + timeout` |
| `app/Tests/OrionTests/DAWSendTests.swift:175` | `                Thread.sleep(forTimeInterval: 0.02)` | `sleep(forTimeInterval: 0.02)` |
| `handoff/TO-FLR-SITE-2026-11-03-finder-item.md:3` | `- Beat Key 0.1.34 is public (J published 00:58; tag Beat-Key-0.1.34). It carries your finder-service fix (merged, commit 9efbdea) plus the main window matching the menu-bar panel and the screen-sleep fix.` | `no literal delay (prose match)` |
| `tests/stub/yt-dlp:75` | `  sleep 30` | `sleep 30` |
| `tests/test_bpm_stream.py:211` | `        time.sleep(1.0)` | `time.sleep(1.0)` |
| `tests/test_bpm_stream.py:213` | `        time.sleep(0.3)` | `time.sleep(0.3)` |
| `tools/pt-harvest/axpress.py:19` | `    time.sleep(2)` | `time.sleep(2)` |
| `tools/pt-harvest/axvis.py:14` | `    time.sleep(1.5)` | `time.sleep(1.5)` |
| `tools/pt-harvest/axvis.py:37` | `    time.sleep(1)` | `time.sleep(1)` |
| `tools/pt-harvest/axvis.py:44` | `    time.sleep(2.5)` | `time.sleep(2.5)` |
| `tools/pt-harvest/bypass_view.py:21` | `time.sleep(2.5)` | `time.sleep(2.5)` |
| `tools/pt-harvest/click_at.py:7` | `Quartz.CGEventPost(Quartz.kCGHIDEventTap, mv); time.sleep(0.15)` | `time.sleep(0.15)` |
| `tools/pt-harvest/click_at.py:10` | `    Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev); time.sleep(0.06)` | `time.sleep(0.06)` |
| `tools/pt-harvest/dialog_clicker.py:140` | `                    time.sleep(1.5)` | `time.sleep(1.5)` |
| `tools/pt-harvest/dialog_clicker.py:191` | `        time.sleep(0.08)` | `time.sleep(0.08)` |
| `tools/pt-harvest/dialog_clicker.py:229` | `                time.sleep(1.5)` | `time.sleep(1.5)` |
| `tools/pt-harvest/dialog_clicker.py:242` | `                time.sleep(1.5)` | `time.sleep(1.5)` |
| `tools/pt-harvest/dialog_clicker.py:279` | `        time.sleep(2)` | `time.sleep(2)` |
| `tools/pt-harvest/drag.py:3` | `    e=Quartz.CGEventCreateMouseEvent(None,t,(x,y),Quartz.kCGMouseButtonLeft); Quartz.CGEventPost(Quartz.kCGHIDEventTap,e); time.sleep(0.08)` | `time.sleep(0.08)` |
| `tools/pt-harvest/harvest.py:148` | `    time.sleep(2)` | `time.sleep(2)` |
| `tools/pt-harvest/harvest.py:240` | `                time.sleep(1.5)` | `time.sleep(1.5)` |
| `tools/pt-harvest/harvest.py:589` | `        time.sleep(2)` | `time.sleep(2)` |
| `tools/pt-harvest/harvest.py:866` | `    time.sleep(10)` | `time.sleep(10)` |
| `tools/pt-harvest/harvest.py:869` | `    time.sleep(20)` | `time.sleep(20)` |
| `tools/pt-harvest/harvest.py:877` | `            time.sleep(10)` | `time.sleep(10)` |
| `tools/pt-harvest/hlib.py:599` | `        time.sleep(0.35)` | `time.sleep(0.35)` |
| `tools/pt-harvest/hlib.py:618` | `        time.sleep(1)` | `time.sleep(1)` |
| `tools/pt-harvest/hlib.py:638` | `        time.sleep(0.5)` | `time.sleep(0.5)` |
| `tools/pt-harvest/hlib.py:646` | `        time.sleep(1.5)                       # let the GUI paint` | `time.sleep(1.5)` |
| `tools/pt-harvest/hlib.py:721` | `    time.sleep(1.0)` | `time.sleep(1.0)` |
| `tools/pt-harvest/pt_launch.py:17` | `    time.sleep(3)` | `time.sleep(3)` |
| `tools/pt-harvest/ptkill.sh:7` | `sleep 5` | `sleep 5` |
| `tools/pt-harvest/run_batch.sh:17` | `        sleep 2` | `sleep 2` |
| `tools/pt-harvest/run_batch.sh:25` | `    ( while sleep 60; do ensure_clicker; done ) & keeper=$!` | `sleep 60` |
| `tools/pt-harvest/run_batch.sh:34` | `           sleep 30 ;;` | `sleep 30` |
| `tools/pt-harvest/sv.sh:34` | `        sleep 6` | `sleep 6` |
| `tools/pt-harvest/waitnew.sh:12` | `    sleep 10` | `sleep 10` |
| `tools/pt-harvest/watch.sh:14` | `    sleep 60` | `sleep 60` |

## Task 4: Unreferenced files

Commands (run from the worktree root; scratch files in the symphony-review folder):

```sh
grep -E '^app/' swift list | xargs grep -n -I -E '^(final |public |private |fileprivate |internal )*(class|struct|enum|actor|protocol) ' < app-swift.txt > t4-types.txt
per type NAME and FILE: grep -r -l -w --include='*.swift' -- NAME app/ | grep -v -x -F FILE | wc -l   (0 = listed)
grep -E '^[^/]+\.(py|sh|command)$|^tools/.*\.(py|sh|command)$' all-tracked.txt > t4-scripts.txt
per script BASE and MODULE (module = basename without extension): grep -r -I -l -F -- BASE <all tracked files> | grep -v -x -F FILE | wc -l ; same with -w -F -- MODULE
```


### Swift types in app/

Top-level declarations found: **349** (in 89 files, including app/Tests and app/icon/archive). Types with **zero** references outside their own file (grep -w): **116**. Label: 'no reference found by grep' (not 'dead'). XCTestCase subclasses are run by the test runner, not by name, so a zero there is expected. Grep matches a name as a whole word anywhere in app/, so common names can be over-counted, never under-counted.

| file | type | label |
|---|---|---|
| `app/Sources/Orion/DAWSend/AXDriver.swift` | `AXRole` | no reference found by grep |
| `app/Sources/Orion/DAWSend/AXDriver.swift` | `CGKeys` | no reference found by grep |
| `app/Sources/Orion/DAWSend/AXDriver.swift` | `AXFailure` | no reference found by grep |
| `app/Sources/Orion/DAWSend/AXRoutes.swift` | `AXPlan` | no reference found by grep |
| `app/Sources/Orion/DAWSend/DAWSend.swift` | `SendOutcome` | no reference found by grep |
| `app/Sources/Orion/Doctor.swift` | `RealRunner` | no reference found by grep |
| `app/Sources/Orion/Engine.swift` | `RealLauncher` | no reference found by grep |
| `app/Sources/Orion/Faceplate/Accent.swift` | `AccentPanel` | no reference found by grep |
| `app/Sources/Orion/Faceplate/Chassis.swift` | `Screw` | no reference found by grep |
| `app/Sources/Orion/Faceplate/Chassis.swift` | `Wordmark` | no reference found by grep |
| `app/Sources/Orion/Faceplate/Chassis.swift` | `StatusLegend` | no reference found by grep |
| `app/Sources/Orion/Faceplate/Controls.swift` | `PickControl` | no reference found by grep |
| `app/Sources/Orion/Faceplate/Controls.swift` | `PickNSView` | no reference found by grep |
| `app/Sources/Orion/Faceplate/Controls.swift` | `URLTextField` | no reference found by grep |
| `app/Sources/Orion/Faceplate/Controls.swift` | `AmberCaretField` | no reference found by grep |
| `app/Sources/Orion/Faceplate/Controls.swift` | `CapBody` | no reference found by grep |
| `app/Sources/Orion/Faceplate/LCD.swift` | `Centered` | no reference found by grep |
| `app/Sources/Orion/Faceplate/LCD.swift` | `IdleReadout` | no reference found by grep |
| `app/Sources/Orion/Faceplate/LCD.swift` | `DropReadout` | no reference found by grep |
| `app/Sources/Orion/Faceplate/LCD.swift` | `LoginReadout` | no reference found by grep |
| `app/Sources/Orion/Faceplate/LCD.swift` | `WorkingReadout` | no reference found by grep |
| `app/Sources/Orion/Faceplate/LCD.swift` | `ListeningReadout` | no reference found by grep |
| `app/Sources/Orion/Faceplate/LCD.swift` | `DoctorReadout` | no reference found by grep |
| `app/Sources/Orion/Faceplate/LCD.swift` | `StepLabel` | no reference found by grep |
| `app/Sources/Orion/Faceplate/LCD.swift` | `FinderLink` | no reference found by grep |
| `app/Sources/Orion/Faceplate/LCD.swift` | `StateLamp` | no reference found by grep |
| `app/Sources/Orion/Faceplate/LCD.swift` | `TempoLight` | no reference found by grep |
| `app/Sources/Orion/Faceplate/LCD.swift` | `ErrorReadout` | no reference found by grep |
| `app/Sources/Orion/Faceplate/Motion.swift` | `LiveAnimation` | no reference found by grep |
| `app/Sources/Orion/HarmonyView.swift` | `HarmonyRule` | no reference found by grep |
| `app/Sources/Orion/HarmonyView.swift` | `ChordCell` | no reference found by grep |
| `app/Sources/Orion/HarmonyView.swift` | `RingSector` | no reference found by grep |
| `app/Sources/Orion/HarmonyView.swift` | `KeyWheelGrid` | no reference found by grep |
| `app/Sources/Orion/HarmonyView.swift` | `KeyWheelSection` | no reference found by grep |
| `app/Sources/Orion/HarmonyView.swift` | `KeyWheelPress` | no reference found by grep |
| `app/Sources/Orion/Help.swift` | `HelpModeKey` | no reference found by grep |
| `app/Sources/Orion/Help.swift` | `HelpTipForcedKey` | no reference found by grep |
| `app/Sources/Orion/Help.swift` | `HelpTipAnchor` | no reference found by grep |
| `app/Sources/Orion/Help.swift` | `HelpTipKey` | no reference found by grep |
| `app/Sources/Orion/Help.swift` | `HelpTipModifier` | no reference found by grep |
| `app/Sources/Orion/Help.swift` | `NativeHelpModifier` | no reference found by grep |
| `app/Sources/Orion/Help.swift` | `HelpCursor` | no reference found by grep |
| `app/Sources/Orion/Help.swift` | `HelpTipLayer` | no reference found by grep |
| `app/Sources/Orion/Help.swift` | `FloatingHelpCard` | no reference found by grep |
| `app/Sources/Orion/Help.swift` | `HelpCardSizeKey` | no reference found by grep |
| `app/Sources/Orion/KeyTeach.swift` | `TeachSource` | no reference found by grep |
| `app/Sources/Orion/KeyTeach.swift` | `TeachAudio` | no reference found by grep |
| `app/Sources/Orion/KeyTeach.swift` | `Wav` | no reference found by grep |
| `app/Sources/Orion/LoginItem.swift` | `AppServiceLoginItem` | no reference found by grep |
| `app/Sources/Orion/ManualKeySelection.swift` | `ManualHoverForcedKey` | no reference found by grep |
| `app/Sources/Orion/MenuBar.swift` | `SourceMenu` | no reference found by grep |
| `app/Sources/Orion/MenuBar.swift` | `PocketSizeKey` | no reference found by grep |
| `app/Sources/Orion/Mini.swift` | `MiniPad` | no reference found by grep |
| `app/Sources/Orion/Mini.swift` | `MidiOut` | no reference found by grep |
| `app/Sources/Orion/Mini.swift` | `MiniPanel` | no reference found by grep |
| `app/Sources/Orion/Mini.swift` | `FirstMouseHostingView` | no reference found by grep |
| `app/Sources/Orion/Mini.swift` | `MiniHost` | no reference found by grep |
| `app/Sources/Orion/Mini.swift` | `MiniPadView` | no reference found by grep |
| `app/Sources/Orion/OrionApp.swift` | `AppDelegate` | no reference found by grep |
| `app/Sources/Orion/OrionApp.swift` | `WindowConfigurator` | no reference found by grep |
| `app/Sources/Orion/OrionApp.swift` | `ReferencePrompt` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketAdvanced.swift` | `CheckMark` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `ActionCap` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `QuitLink` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `FooterChipStyle` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `PocketPlate` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `PocketHeader` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `KeyGlyph` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `PocketLCD` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `ManualKeyMenu` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `ResultSide` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `ChipWidth` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `ChipSegment` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `NoteKeyboard` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `LiveMeterSegments` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `LiveLevelKey` | no reference found by grep |
| `app/Sources/Orion/Pocket/PocketView.swift` | `MeterSegments` | no reference found by grep |
| `app/Sources/Orion/Settings.swift` | `ShortcutRecorder` | no reference found by grep |
| `app/Tests/OrionTests/AXDriverTests.swift` | `FakeAX` | no reference found by grep |
| `app/Tests/OrionTests/AXDriverTests.swift` | `FakeKeys` | no reference found by grep |
| `app/Tests/OrionTests/AXDriverTests.swift` | `AXDriverTests` | no reference found by grep |
| `app/Tests/OrionTests/AccentTests.swift` | `AccentTests` | no reference found by grep |
| `app/Tests/OrionTests/AccessibilityTests.swift` | `AccessibilityTests` | no reference found by grep |
| `app/Tests/OrionTests/AutoTuneSendTests.swift` | `AutoTuneSendTests` | no reference found by grep |
| `app/Tests/OrionTests/BeatKeyTests.swift` | `FakeRunner` | no reference found by grep |
| `app/Tests/OrionTests/BeatKeyTests.swift` | `BeatKeyTests` | no reference found by grep |
| `app/Tests/OrionTests/DAWSendTests.swift` | `DAWSendTests` | no reference found by grep |
| `app/Tests/OrionTests/EngineTests.swift` | `EngineTests` | no reference found by grep |
| `app/Tests/OrionTests/EventTests.swift` | `EventTests` | no reference found by grep |
| `app/Tests/OrionTests/FooterReadoutRenderTests.swift` | `FooterReadoutRenderTests` | no reference found by grep |
| `app/Tests/OrionTests/HarmonyTests.swift` | `HarmonyTests` | no reference found by grep |
| `app/Tests/OrionTests/HelpTests.swift` | `HelpTests` | no reference found by grep |
| `app/Tests/OrionTests/HoldSpellingTests.swift` | `HoldSpellingTests` | no reference found by grep |
| `app/Tests/OrionTests/HotkeyTests.swift` | `HotkeyTests` | no reference found by grep |
| `app/Tests/OrionTests/HotkeyTests.swift` | `KeyEquivalentProxy` | no reference found by grep |
| `app/Tests/OrionTests/KeyChoiceTests.swift` | `KeyChoiceTests` | no reference found by grep |
| `app/Tests/OrionTests/KeyChoiceTests.swift` | `PlayerFilterTests` | no reference found by grep |
| `app/Tests/OrionTests/KeyTeachTests.swift` | `TeachStoreTests` | no reference found by grep |
| `app/Tests/OrionTests/KeyTeachTests.swift` | `MusicalTypingTests` | no reference found by grep |
| `app/Tests/OrionTests/ListenLogTests.swift` | `ListenLogTests` | no reference found by grep |
| `app/Tests/OrionTests/LiveFallbackTests.swift` | `LiveFallbackTests` | no reference found by grep |
| `app/Tests/OrionTests/LoginItemTests.swift` | `LoginItemTests` | no reference found by grep |
| `app/Tests/OrionTests/LoginTests.swift` | `LoginTests` | no reference found by grep |
| `app/Tests/OrionTests/ManualKeySelectionTests.swift` | `ManualKeySelectionTests` | no reference found by grep |
| `app/Tests/OrionTests/MarketingRenderTests.swift` | `MarketingRenderTests` | no reference found by grep |
| `app/Tests/OrionTests/MenuBarTests.swift` | `MenuBarTests` | no reference found by grep |
| `app/Tests/OrionTests/MidiExportTests.swift` | `MidiExportTests` | no reference found by grep |
| `app/Tests/OrionTests/MiniTests.swift` | `MiniTests` | no reference found by grep |
| `app/Tests/OrionTests/MotionTests.swift` | `MotionTests` | no reference found by grep |
| `app/Tests/OrionTests/PocketTests.swift` | `PocketTests` | no reference found by grep |
| `app/Tests/OrionTests/ReadingTests.swift` | `ReadingTests` | no reference found by grep |
| `app/Tests/OrionTests/SongBoundaryTests.swift` | `SongBoundaryTests` | no reference found by grep |
| `app/Tests/OrionTests/SpellingMenuBarTests.swift` | `SpellingMenuBarTests` | no reference found by grep |
| `app/Tests/OrionTests/WavesTuneSendTests.swift` | `WavesTuneSendTests` | no reference found by grep |
| `app/Tests/OrionTests/WindowParityTests.swift` | `WindowParityTests` | no reference found by grep |
| `app/icon/archive/make_icon-staff-key.swift` | `KeyParts` | no reference found by grep |

Zero-reference types per file:

| Count | File |
|---|---|
| 15 | `app/Sources/Orion/Pocket/PocketView.swift` |
| 12 | `app/Sources/Orion/Faceplate/LCD.swift` |
| 10 | `app/Sources/Orion/Help.swift` |
| 6 | `app/Sources/Orion/HarmonyView.swift` |
| 6 | `app/Sources/Orion/Mini.swift` |
| 5 | `app/Sources/Orion/Faceplate/Controls.swift` |
| 3 | `app/Sources/Orion/DAWSend/AXDriver.swift` |
| 3 | `app/Sources/Orion/Faceplate/Chassis.swift` |
| 3 | `app/Sources/Orion/KeyTeach.swift` |
| 3 | `app/Sources/Orion/OrionApp.swift` |
| 3 | `app/Tests/OrionTests/AXDriverTests.swift` |
| 2 | `app/Sources/Orion/MenuBar.swift` |
| 2 | `app/Tests/OrionTests/BeatKeyTests.swift` |
| 2 | `app/Tests/OrionTests/HotkeyTests.swift` |
| 2 | `app/Tests/OrionTests/KeyChoiceTests.swift` |
| 2 | `app/Tests/OrionTests/KeyTeachTests.swift` |
| 1 | `app/Sources/Orion/DAWSend/AXRoutes.swift` |
| 1 | `app/Sources/Orion/DAWSend/DAWSend.swift` |
| 1 | `app/Sources/Orion/Doctor.swift` |
| 1 | `app/Sources/Orion/Engine.swift` |
| 1 | `app/Sources/Orion/Faceplate/Accent.swift` |
| 1 | `app/Sources/Orion/Faceplate/Motion.swift` |
| 1 | `app/Sources/Orion/LoginItem.swift` |
| 1 | `app/Sources/Orion/ManualKeySelection.swift` |
| 1 | `app/Sources/Orion/Pocket/PocketAdvanced.swift` |
| 1 | `app/Sources/Orion/Settings.swift` |
| 1 | `app/Tests/OrionTests/AccentTests.swift` |
| 1 | `app/Tests/OrionTests/AccessibilityTests.swift` |
| 1 | `app/Tests/OrionTests/AutoTuneSendTests.swift` |
| 1 | `app/Tests/OrionTests/DAWSendTests.swift` |
| 1 | `app/Tests/OrionTests/EngineTests.swift` |
| 1 | `app/Tests/OrionTests/EventTests.swift` |
| 1 | `app/Tests/OrionTests/FooterReadoutRenderTests.swift` |
| 1 | `app/Tests/OrionTests/HarmonyTests.swift` |
| 1 | `app/Tests/OrionTests/HelpTests.swift` |
| 1 | `app/Tests/OrionTests/HoldSpellingTests.swift` |
| 1 | `app/Tests/OrionTests/ListenLogTests.swift` |
| 1 | `app/Tests/OrionTests/LiveFallbackTests.swift` |
| 1 | `app/Tests/OrionTests/LoginItemTests.swift` |
| 1 | `app/Tests/OrionTests/LoginTests.swift` |
| 1 | `app/Tests/OrionTests/ManualKeySelectionTests.swift` |
| 1 | `app/Tests/OrionTests/MarketingRenderTests.swift` |
| 1 | `app/Tests/OrionTests/MenuBarTests.swift` |
| 1 | `app/Tests/OrionTests/MidiExportTests.swift` |
| 1 | `app/Tests/OrionTests/MiniTests.swift` |
| 1 | `app/Tests/OrionTests/MotionTests.swift` |
| 1 | `app/Tests/OrionTests/PocketTests.swift` |
| 1 | `app/Tests/OrionTests/ReadingTests.swift` |
| 1 | `app/Tests/OrionTests/SongBoundaryTests.swift` |
| 1 | `app/Tests/OrionTests/SpellingMenuBarTests.swift` |
| 1 | `app/Tests/OrionTests/WavesTuneSendTests.swift` |
| 1 | `app/Tests/OrionTests/WindowParityTests.swift` |
| 1 | `app/icon/archive/make_icon-staff-key.swift` |

### Root-level and tools/ .py/.sh/.command files

Files checked: **87**. Files where neither the filename nor the module name appears in any other tracked file: **39** (label: 'no reference found by grep'). Columns: filename hits and module-name hits are counts of other tracked files containing the string (fixed-string grep, the file itself excluded).

| file | filename hits | module-name hits | module | label |
|---|---|---|---|---|
| `app_run.py` | 13 | 14 | `app_run` |  |
| `bpm.py` | 40 | 111 | `bpm` |  |
| `deps.sh` | 15 | 17 | `deps` |  |
| `downloader.py` | 10 | 17 | `downloader` |  |
| `dropped.py` | 4 | 25 | `dropped` |  |
| `install.command` | 5 | 27 | `install` |  |
| `midi_analyze.py` | 3 | 4 | `midi_analyze` |  |
| `run.command` | 9 | 86 | `run` |  |
| `run.sh` | 14 | 87 | `run` |  |
| `tempocnn_np.py` | 18 | 21 | `tempocnn_np` |  |
| `tools/build-old-mac/check-macho.sh` | 1 | 1 | `check-macho` |  |
| `tools/build-old-mac/essentia.sh` | 5 | 32 | `essentia` |  |
| `tools/build-old-mac/extract-tempocnn-weights.py` | 4 | 4 | `extract-tempocnn-weights` |  |
| `tools/build-old-mac/ffmpeg-arm64.sh` | 5 | 5 | `ffmpeg-arm64` |  |
| `tools/pt-harvest/attest.py` | 0 | 0 | `attest` | no reference found by grep |
| `tools/pt-harvest/audiocheck.py` | 2 | 6 | `audiocheck` |  |
| `tools/pt-harvest/axcheck.py` | 0 | 0 | `axcheck` | no reference found by grep |
| `tools/pt-harvest/axinserts.py` | 0 | 0 | `axinserts` | no reference found by grep |
| `tools/pt-harvest/axplugin.py` | 0 | 0 | `axplugin` | no reference found by grep |
| `tools/pt-harvest/axpress.py` | 0 | 0 | `axpress` | no reference found by grep |
| `tools/pt-harvest/axprobe.py` | 0 | 0 | `axprobe` | no reference found by grep |
| `tools/pt-harvest/axscroll.py` | 0 | 0 | `axscroll` | no reference found by grep |
| `tools/pt-harvest/axstrip.py` | 0 | 0 | `axstrip` | no reference found by grep |
| `tools/pt-harvest/axtempo.py` | 0 | 0 | `axtempo` | no reference found by grep |
| `tools/pt-harvest/axtree.py` | 0 | 0 | `axtree` | no reference found by grep |
| `tools/pt-harvest/axvis.py` | 0 | 0 | `axvis` | no reference found by grep |
| `tools/pt-harvest/backups_peek.py` | 0 | 0 | `backups_peek` | no reference found by grep |
| `tools/pt-harvest/beatfind.py` | 3 | 4 | `beatfind` |  |
| `tools/pt-harvest/bpmctx.py` | 0 | 0 | `bpmctx` | no reference found by grep |
| `tools/pt-harvest/btail.sh` | 0 | 0 | `btail` | no reference found by grep |
| `tools/pt-harvest/bypass_view.py` | 0 | 0 | `bypass_view` | no reference found by grep |
| `tools/pt-harvest/calib.py` | 1 | 1 | `calib` |  |
| `tools/pt-harvest/check_row.py` | 0 | 0 | `check_row` | no reference found by grep |
| `tools/pt-harvest/click_at.py` | 0 | 0 | `click_at` | no reference found by grep |
| `tools/pt-harvest/dialog_clicker.py` | 3 | 15 | `dialog_clicker` |  |
| `tools/pt-harvest/discover.py` | 2 | 7 | `discover` |  |
| `tools/pt-harvest/drag.py` | 1 | 22 | `drag` |  |
| `tools/pt-harvest/edldiag.py` | 0 | 0 | `edldiag` | no reference found by grep |
| `tools/pt-harvest/edlpeek.py` | 0 | 0 | `edlpeek` | no reference found by grep |
| `tools/pt-harvest/findprobe.py` | 0 | 0 | `findprobe` | no reference found by grep |
| `tools/pt-harvest/harvest.py` | 4 | 35 | `harvest` |  |
| `tools/pt-harvest/hlib.py` | 0 | 23 | `hlib` |  |
| `tools/pt-harvest/ilokcheck.sh` | 0 | 0 | `ilokcheck` | no reference found by grep |
| `tools/pt-harvest/infonames.py` | 0 | 0 | `infonames` | no reference found by grep |
| `tools/pt-harvest/keydiag.py` | 0 | 0 | `keydiag` | no reference found by grep |
| `tools/pt-harvest/lt_probe.py` | 0 | 0 | `lt_probe` | no reference found by grep |
| `tools/pt-harvest/manifest.py` | 0 | 9 | `manifest` |  |
| `tools/pt-harvest/manifest_ext.py` | 0 | 0 | `manifest_ext` | no reference found by grep |
| `tools/pt-harvest/manifest_mtime.py` | 1 | 1 | `manifest_mtime` |  |
| `tools/pt-harvest/ocrdump.py` | 0 | 0 | `ocrdump` | no reference found by grep |
| `tools/pt-harvest/ocrtest.py` | 0 | 0 | `ocrtest` | no reference found by grep |
| `tools/pt-harvest/outprobe.py` | 0 | 0 | `outprobe` | no reference found by grep |
| `tools/pt-harvest/pt_close.py` | 0 | 0 | `pt_close` | no reference found by grep |
| `tools/pt-harvest/pt_launch.py` | 2 | 2 | `pt_launch` |  |
| `tools/pt-harvest/pt_open_export.py` | 0 | 0 | `pt_open_export` | no reference found by grep |
| `tools/pt-harvest/ptkill.sh` | 1 | 1 | `ptkill` |  |
| `tools/pt-harvest/ptslcmds.sh` | 0 | 0 | `ptslcmds` | no reference found by grep |
| `tools/pt-harvest/rtail.sh` | 0 | 0 | `rtail` | no reference found by grep |
| `tools/pt-harvest/run_batch.sh` | 3 | 3 | `run_batch` |  |
| `tools/pt-harvest/soloprobe.py` | 0 | 0 | `soloprobe` | no reference found by grep |
| `tools/pt-harvest/step.py` | 0 | 35 | `step` |  |
| `tools/pt-harvest/stripnames.py` | 0 | 0 | `stripnames` | no reference found by grep |
| `tools/pt-harvest/sv.sh` | 2 | 3 | `sv` |  |
| `tools/pt-harvest/sync_from_sofia.sh` | 2 | 2 | `sync_from_sofia` |  |
| `tools/pt-harvest/tlprobe.py` | 0 | 0 | `tlprobe` | no reference found by grep |
| `tools/pt-harvest/treeshape.py` | 0 | 0 | `treeshape` | no reference found by grep |
| `tools/pt-harvest/usblist.sh` | 0 | 0 | `usblist` | no reference found by grep |
| `tools/pt-harvest/verify_beats.py` | 1 | 2 | `verify_beats` |  |
| `tools/pt-harvest/view.py` | 1 | 28 | `view` |  |
| `tools/pt-harvest/vocprobe.py` | 0 | 0 | `vocprobe` | no reference found by grep |
| `tools/pt-harvest/waitnew.sh` | 0 | 0 | `waitnew` | no reference found by grep |
| `tools/pt-harvest/watch.sh` | 1 | 16 | `watch` |  |
| `tools/pt-harvest/wins.py` | 0 | 20 | `wins` |  |
| `tools/publish.sh` | 6 | 16 | `publish` |  |
| `tools/train-tempocnn/check_npz.py` | 2 | 2 | `check_npz` |  |
| `tools/train-tempocnn/common.py` | 3 | 19 | `common` |  |
| `tools/train-tempocnn/eval.py` | 5 | 14 | `eval` |  |
| `tools/train-tempocnn/features.py` | 5 | 22 | `features` |  |
| `tools/train-tempocnn/key_baseline.py` | 3 | 3 | `key_baseline` |  |
| `tools/train-tempocnn/key_eval.py` | 1 | 1 | `key_eval` |  |
| `tools/train-tempocnn/labels_from_db.py` | 3 | 3 | `labels_from_db` |  |
| `tools/train-tempocnn/leakage_check.py` | 2 | 2 | `leakage_check` |  |
| `tools/train-tempocnn/model.py` | 1 | 37 | `model` |  |
| `tools/train-tempocnn/parity.py` | 2 | 21 | `parity` |  |
| `tools/train-tempocnn/retrain.sh` | 2 | 5 | `retrain` |  |
| `tools/train-tempocnn/train.py` | 4 | 23 | `train` |  |
| `tools/verify-labels/server.py` | 1 | 8 | `server` |  |

## Task 5: Duplicate constants

Commands (run from the worktree root; scratch files in the symphony-review folder):

```sh
grep -v -E '^(VERSION|PICKUP\.md|docs/|handoff/|\.remember/|vendor/)' all-tracked.txt > t5-files.txt   (second pass also dropped vendor/, docs/, handoff/, .remember/ prefixes)
xargs grep -n -I -E '0\.1\.[0-9]+' < t5-files.txt > t5-version.txt
xargs grep -n -I -o -E 'com\.jshriver\.[A-Za-z0-9.-]+' < t5-files.txt > t5-bundle.txt
xargs grep -n -I -E '9WTFGV63S2' < t5-files.txt > t5-team.txt
xargs grep -n -I -E '44100|48000|22050|11025|16000' < t5-files.txt > t5-rates.txt
```


### Version strings `0.1.N` (outside VERSION, PICKUP.md, docs/, handoff/, .remember/)

Lines matched: **37**. Distinct values: **21**. Occurrences: **48**.

| value | occurrences | file:line |
|---|---|---|
| `0.1.0` | 3 | `PROGRESS-TRACKER.html:27`, `PROGRESS-TRACKER.html:31`, `tracker.json:202` |
| `0.1.11` | 1 | `app/Sources/Orion/Faceplate/LCD.swift:274` |
| `0.1.15` | 3 | `PROGRESS-TRACKER.html:27`, `PROGRESS-TRACKER.html:31`, `tracker.json:203` |
| `0.1.16` | 6 | `PROGRESS-TRACKER.html:27`, `PROGRESS-TRACKER.html:31`, `THIRD-PARTY-LICENSES.md:11`, `THIRD-PARTY-LICENSES.md:20`, `models/README.md:26`, `tracker.json:203` |
| `0.1.18` | 6 | `PROGRESS-TRACKER.html:27`, `PROGRESS-TRACKER.html:31`, `friends-page/serve.py:19`, `tracker.json:201`, `tracker.json:202`, `tracker.json:203` |
| `0.1.22` | 1 | `archive/FROM-FLR-SITE-2026-11-02-beat-key-0.1.31-page.md:17` |
| `0.1.31` | 6 | `README.md:41`, `archive/FROM-FLR-SITE-2026-11-02-beat-key-0.1.31-page.md:1`, `archive/FROM-FLR-SITE-2026-11-02-beat-key-0.1.31-page.md:3`, `archive/FROM-FLR-SITE-2026-11-02-beat-key-0.1.31-page.md:8`, `archive/FROM-FLR-SITE-2026-11-02-beat-key-0.1.31-page.md:11`, `archive/FROM-FLR-SITE-2026-11-02-beat-key-0.1.31-page.md:15` |
| `0.1.32` | 2 | `archive/FROM-FLR-SITE-2026-11-02-beat-key-0.1.31-page.md:18`, `archive/FROM-FLR-SITE-2026-11-02-beat-key-0.1.31-page.md:22` |
| `0.1.33` | 2 | `archive/FROM-FLR-SITE-2026-11-02-beat-key-0.1.31-page.md:21`, `archive/FROM-FLR-SITE-2026-11-02-beat-key-0.1.31-page.md:22` |
| `0.1.34` | 1 | `app/RELEASING.md:31` |
| `0.1.37` | 1 | `app/Sources/Orion/Reading.swift:210` |
| `0.1.38` | 1 | `app/RELEASING.md:31` |
| `0.1.40` | 1 | `models/README.md:35` |
| `0.1.45` | 1 | `app/Tests/OrionTests/MiniTests.swift:6` |
| `0.1.46` | 1 | `app/Sources/Orion/Pocket/PocketView.swift:862` |
| `0.1.48` | 2 | `app/Sources/Orion/Faceplate/Theme.swift:196`, `app/Tests/OrionTests/MotionTests.swift:6` |
| `0.1.49` | 3 | `app/Tests/OrionTests/LiveTests.swift:301`, `app/Tests/OrionTests/MotionFrameTests.swift:26`, `app/Tests/OrionTests/MotionFrameTests.swift:331` |
| `0.1.50` | 4 | `app/Sources/Orion/Faceplate/Theme.swift:197`, `app/Sources/Orion/Live/LiveSession.swift:406`, `app/Tests/OrionTests/LiveTests.swift:300`, `app/Tests/OrionTests/MotionFrameTests.swift:7` |
| `0.1.52` | 1 | `app/Tests/OrionTests/FaceplateTests.swift:76` |
| `0.1.56` | 1 | `app/Tests/OrionTests/SpellingMenuBarTests.swift:6` |
| `0.1.59` | 1 | `tests/test_app_run.py:523` |

### Bundle id (`com.jshriver.*`)

Main app bundle id is `com.jshriver.orion` (app/Info.plist:9). Other values are sub-identifiers or a different product (`com.jshriver.beatkey-server` in friends-page/README.md).

| value | occurrences | file:line |
|---|---|---|
| `com.jshriver.beatkey-server` | 1 | `friends-page/README.md:3` |
| `com.jshriver.orion` | 13 | `app/Info.plist:9`, `app/RELEASING.md:49`, `app/RELEASING.md:50`, `app/Sources/Orion/AppLog.swift:6`, `app/Sources/Orion/AppLog.swift:15`, `app/Sources/Orion/Live/SongBoundary.swift:296`, `app/Sources/Orion/LoginItem.swift:7`, `app/Sources/Orion/LoginItem.swift:19`, `app/Tests/OrionTests/BeatKeyTests.swift:53`, `app/Tests/OrionTests/LoginItemTests.swift:14`, `app/Tests/OrionTests/LoginItemTests.swift:21`, `app/Tests/OrionTests/LoginItemTests.swift:61`, `archive/FROM-FLR-SITE-2026-11-02-beat-key-0.1.31-page.md:15` |
| `com.jshriver.orion.live-pipe` | 1 | `app/Sources/Orion/Live/LiveSession.swift:289` |
| `com.jshriver.orion.log` | 1 | `app/Sources/Orion/AppLog.swift:14` |
| `com.jshriver.orion.maintenance` | 1 | `app/Sources/Orion/Runtime.swift:97` |
| `com.jshriver.orion.now-playing` | 1 | `app/Sources/Orion/Live/SongBoundary.swift:346` |
| `com.jshriver.orion.open-at-login` | 2 | `app/Sources/Orion/LoginItem.swift:17`, `app/Tests/OrionTests/LoginItemTests.swift:20` |
| `com.jshriver.orion.system-audio` | 1 | `app/Sources/Orion/Live/SystemAudio.swift:18` |

### Team id `9WTFGV63S2`

Occurrences: **2**.

| value | occurrences | file:line |
|---|---|---|
| `9WTFGV63S2` | 2 | `app/build.sh:14`, `app/runtime.sh:15` |

### Sample rates

Lines matched: **62**. Each value's occurrences (distinct file:line per value) are listed; a few lines hold more than one value.

| value | occurrences | file:line |
|---|---|---|
| `11025` | 21 | `bpm.py:44`, `bpm.py:183`, `bpm.py:454`, `models/README.md:7`, `tempocnn_np.py:12`, `tests/test_bpm_extras.py:157`, `tests/test_bpm_extras.py:183`, `tools/pt-harvest/harvest.py:12`, `tools/pt-harvest/hlib.py:375`, `tools/train-tempocnn/README.md:33`, `tools/train-tempocnn/README.md:43`, `tools/train-tempocnn/features.py:5`, `tools/train-tempocnn/features.py:12`, `tools/train-tempocnn/features.py:35`, `tools/train-tempocnn/key_baseline.py:107`, `tools/train-tempocnn/key_baseline.py:114`, `tools/train-tempocnn/key_baseline.py:115`, `tools/train-tempocnn/key_baseline.py:202`, `tools/train-tempocnn/labels_from_db.py:5`, `tools/train-tempocnn/runs/key-baseline-2026-11-05/eval.md:13`, `tools/train-tempocnn/runs/key-baseline-2026-11-05/summary.md:43` |
| `16000` | 1 | `app/Sources/Orion/Live/SystemAudio.swift:179` |
| `22050` | 5 | `app/Tests/OrionTests/LiveTests.swift:251`, `app/Tests/OrionTests/LiveTests.swift:255`, `app/Tests/OrionTests/LiveTests.swift:379`, `tools/pt-harvest/audiocheck.py:2`, `tools/pt-harvest/audiocheck.py:20` |
| `44100` | 22 | `app/Sources/Orion/Live/LiveSession.swift:286`, `app/Tests/OrionTests/KeyTeachTests.swift:63`, `app/Tests/OrionTests/KeyTeachTests.swift:64`, `app/Tests/OrionTests/KeyTeachTests.swift:71`, `app/Tests/OrionTests/ListenLogTests.swift:50`, `app/Tests/OrionTests/ListenLogTests.swift:242`, `app/Tests/OrionTests/ListenLogTests.swift:248`, `app/Tests/OrionTests/LiveTests.swift:196`, `app/Tests/OrionTests/LiveTests.swift:200`, `app/Tests/OrionTests/LiveTests.swift:249`, `app/Tests/OrionTests/LiveTests.swift:402`, `bpm.py:22`, `bpm.py:43`, `bpm.py:183`, `bpm.py:783`, `tests/fixtures/make_click.sh:17`, `tests/test_bpm_extras.py:195`, `tests/test_bpm_extras.py:335`, `tests/test_bpm_stream.py:23`, `tests/test_bpm_tuning.py:27`, `tools/train-tempocnn/key_baseline.py:114`, `tools/train-tempocnn/key_baseline.py:115` |
| `48000` | 17 | `app/Sources/Orion/DAWSend/ProToolsDriver.swift:69`, `app/Sources/Orion/Live/SystemAudio.swift:179`, `app/Sources/Orion/Live/SystemAudio.swift:180`, `app/Tests/OrionTests/DAWSendTests.swift:288`, `app/Tests/OrionTests/DAWSendTests.swift:302`, `app/Tests/OrionTests/DAWSendTests.swift:316`, `app/Tests/OrionTests/DAWSendTests.swift:317`, `app/Tests/OrionTests/LiveTests.swift:187`, `app/Tests/OrionTests/LiveTests.swift:197`, `tests/test_bpm_stream.py:104`, `tests/test_bpm_stream.py:105`, `tools/pt-harvest/beatfind.py:86`, `tools/pt-harvest/findprobe.py:11`, `tools/pt-harvest/harvest.py:194`, `tools/pt-harvest/soloprobe.py:13`, `tools/pt-harvest/vocprobe.py:12`, `tools/pt-harvest/vocprobe.py:15` |

## Task 6: Fix-on-fix history

Commands (run from the worktree root; scratch files in the symphony-review folder):

```sh
git log --since=2026-10-01 --pretty='%h %ad %s' --date=short --name-only > t6-log.txt
git log --since=2026-10-01 --pretty='%h %ad %s' --date=short   (commit count: 290)
Parsing (awk over t6-log.txt): commit line = /^[0-9a-f]{7,} [0-9]{4}-[0-9]{2}-[0-9]{2} /; each following non-blank line = one changed file; per-file commit counts; fix subjects matched case-insensitively against fix|again|revert|actually|really|still|workaround|guard|fallback|retry
```


(a) The 15 files changed in the most commits since 2026-10-01 (290 commits, merges included; ties at the cut-off are noted):

| rank | commits | file |
|---|---|---|
| 1 | 83 | `PICKUP.md` |
| 2 | 60 | `VERSION` |
| 3 | 37 | `app/Sources/Orion/OrionApp.swift` |
| 4 | 30 | `app/Sources/Orion/Faceplate/FaceplateView.swift` |
| 5 | 25 | `app/Sources/Orion/MenuBar.swift` |
| 6 | 24 | `app/Sources/Orion/Faceplate/LCD.swift` |
| 7 | 22 | `app/Sources/Orion/Pocket/PocketView.swift` |
| 8 | 20 | `README.md` |
| 9 | 16 | `app/Sources/Orion/Engine.swift` |
| 10 | 16 | `app/Sources/Orion/Faceplate/FaceplateModel.swift` |
| 11 | 15 | `app/Sources/Orion/Live/LiveSession.swift` |
| 12 | 15 | `tools/pt-harvest/harvest.py` |
| 13 | 13 | `app/Sources/Orion/HarmonyView.swift` |
| 14 | 12 | `app_run.py` |
| 15 | 12 | `app/build.sh` |

Ties: 3 files have 12 commits, and the list above keeps only the first 15 in name order. Files with 12 commits: `app_run.py`, `app/build.sh`, `tests/test_app_run.py`.

(b) Commits whose subject contains fix, again, revert, actually, really, still, workaround, guard, fallback or retry (case-insensitive). Oldest first. Count: **24**.

| hash | date | subject | files touched |
|---|---|---|---|
| `27532be` | 2026-10-07 | pt-harvest: open closed folders for Auto-Tune strips, key-glyph voting, Beat-track fallback, silent-probe diagnosis, resumable batch rereads DB | `tools/pt-harvest/harvest.py, tools/pt-harvest/hlib.py, tools/pt-harvest/infonames.py, tools/pt-harvest/keydiag.py, tools/pt-harvest/sv.sh, tools/pt-harvest/view.py` |
| `a009cc8` | 2026-10-07 | pt-harvest: flat = one AX tempo event (EDL slope cross-check), tempo-table fallback, any-output fallback, gated approvals for new dialogs; TOC §1-§5 ticked | `docs/research/pt-ground-truth/crops/0012-tempo.png, docs/research/pt-ground-truth/logs/harvest-26-10-7.jsonl, docs/research/pt-ground-truth/pt-ground-truth.sqlite3, docs/superpowers/plans/2026-10-06-pt-bpm-harvest-and-train-TOC.md, tools/pt-harvest/dialog_clicker.py, tools/pt-harvest/harvest.py` |
| `af254d0` | 2026-10-07 | pt-harvest v2: smart beat finder (folders, output buses, names, plug-ins, clips) + listening checks, full-mix bounce + back-fill, ALL MIXES manifest with dedupe, batch rc fix | `docs/research/pt-ground-truth/crops/0002-tempo.png, docs/research/pt-ground-truth/logs/harvest-26-10-7.jsonl, docs/research/pt-ground-truth/pt-ground-truth.sqlite3, tools/pt-harvest/audiocheck.py, tools/pt-harvest/beatfind.py, tools/pt-harvest/btail.sh, tools/pt-harvest/calib.py, tools/pt-harvest/findprobe.py, tools/pt-harvest/harvest.py, tools/pt-harvest/hlib.py, tools/pt-harvest/manifest_ext.py, tools/pt-harvest/outprobe.py, tools/pt-harvest/ptslcmds.sh, tools/pt-harvest/soloprobe.py, tools/pt-harvest/tlprobe.py, tools/pt-harvest/treeshape.py, tools/pt-harvest/verify_beats.py, tools/pt-harvest/vocprobe.py, tools/train-tempocnn/labels_from_db.py` |
| `8d46498` | 2026-10-07 | pt-harvest: finder v5 - when the finder's beat set fails the ears, fallback sets (all non-vocal tracks; minus the failed set) are tried by ear; v1 Beat/Instrumental tracks outrank inference; short-beat skip status; DB snapshot | `docs/research/pt-ground-truth/crops/0014-tempo.png, docs/research/pt-ground-truth/crops/0015-tempo.png, docs/research/pt-ground-truth/crops/0017-tempo.png, docs/research/pt-ground-truth/crops/0018-tempo.png, docs/research/pt-ground-truth/crops/0019-tempo.png, docs/research/pt-ground-truth/crops/0020-tempo.png, docs/research/pt-ground-truth/crops/0021-tempo.png, docs/research/pt-ground-truth/crops/0022-tempo.png, docs/research/pt-ground-truth/crops/0023-tempo.png, docs/research/pt-ground-truth/crops/0025-tempo.png, docs/research/pt-ground-truth/logs/harvest-26-10-7.jsonl, docs/research/pt-ground-truth/pt-ground-truth.sqlite3, tools/pt-harvest/beatfind.py, tools/pt-harvest/harvest.py` |
| `e0a190a` | 2026-10-07 | pt-harvest: hung-PT recovery actually kills the versioned app (pkill pattern), waits for PTSL after relaunch; dialog_clicker closes the PT Dashboard (Cancel) after a relaunch (approved-dialogs.txt); ptkill.sh | `tools/pt-harvest/dialog_clicker.py, tools/pt-harvest/harvest.py, tools/pt-harvest/ptkill.sh` |
| `2a84f2b` | 2026-10-27 | app_run: guard post-download steps, per-file analyze, top-level terminal-event guard | `app_run.py, tests/test_app_run.py` |
| `2faf4b0` | 2026-10-27 | State sweep: fix stale status lines (Orion spec, PT harvest TOC, tracker, PICKUP old blocks, README) | `PICKUP.md, PROGRESS-TRACKER.html, README.md, docs/superpowers/plans/2026-10-06-pt-bpm-harvest-and-train-TOC.md, docs/superpowers/specs/2026-09-12-menubar-key-bpm-listener-design.md, docs/superpowers/specs/2026-10-27-beat-dl-mac-app-design.md, tracker.json` |
| `86ccb56` | 2026-10-27 | Orion faceplate fix round 1: audio-only drops, safe texture lookup, macOS 12 | `VERSION, app/Package.swift, app/Sources/Orion/Faceplate/FaceplateModel.swift, app/Sources/Orion/Faceplate/FaceplateView.swift, app/Sources/Orion/Faceplate/LCD.swift, app/Sources/Orion/Faceplate/Theme.swift, app/Tests/OrionTests/FaceplateTests.swift` |
| `d1ceef4` | 2026-10-27 | Fix round 0.1.5: dead links stop before cookies, yt-dlp timeouts, app-owned yt-dlp for -U, serial maintenance queue, folder usage strings, partial-analyze caption, scripts always rebuilt | `VERSION, app/Info.plist, app/Sources/Orion/Engine.swift, app/Sources/Orion/Event.swift, app/Sources/Orion/Faceplate/FaceplateModel.swift, app/Sources/Orion/Faceplate/FaceplateView.swift, app/Sources/Orion/Faceplate/LCD.swift, app/Sources/Orion/OrionApp.swift, app/Sources/Orion/Runtime.swift, app/Tests/OrionTests/BeatKeyTests.swift, app/Tests/OrionTests/EngineTests.swift, app/build.sh, app/runtime.sh, app_run.py, downloader.py, tests/stub/yt-dlp, tests/test_app_run.py` |
| `dedfafb` | 2026-10-28 | One window: permission flow on the faceplate, sheet gone; fix the loop; 0.1.12 | `VERSION, app/Sources/Orion/Access.swift, app/Sources/Orion/Engine.swift, app/Sources/Orion/Faceplate/AccessSheet.swift, app/Sources/Orion/Faceplate/FaceplateModel.swift, app/Sources/Orion/Faceplate/FaceplateView.swift, app/Sources/Orion/Faceplate/LCD.swift, app/Sources/Orion/OrionApp.swift, app/Tests/OrionTests/AccessTests.swift` |
| `80386c4` | 2026-10-28 | Fallback readout: DOWNLOAD stays unlit for a link that needs a login | `app/Sources/Orion/Faceplate/FaceplateView.swift` |
| `330b5c5` | 2026-11-01 | Send to DAW: Accessibility drivers for Pro Tools, Logic, Studio One (tempo + key), MIDI file fallback (plan 4.2) | `app/Sources/Orion/DAWSend/AXDriver.swift, app/Sources/Orion/DAWSend/AXRoutes.swift, app/Sources/Orion/DAWSend/DAWSend.swift, app/Sources/Orion/DAWSend/MidiFileDriver.swift, app/Sources/Orion/DAWSend/ProToolsDriver.swift, app/Tests/OrionTests/AXDriverTests.swift, docs/research/send-to-daw.md` |
| `c770111` | 2026-11-02 | Live keys fix (SCK delivers 48 kHz, resample to 44.1) + click a top-3 key to make it the key | `VERSION, app/Sources/Orion/Faceplate/LCD.swift, app/Sources/Orion/KeySpelling.swift, app/Sources/Orion/Live/SystemAudio.swift, app/Sources/Orion/MenuBar.swift, app/Sources/Orion/OrionApp.swift, app/Sources/Orion/Pocket/PocketView.swift, app/Tests/OrionTests/KeyChoiceTests.swift` |
| `baaec43` | 2026-11-02 | Menu bar: fixed width, coloured key after the reading, no stale reading at launch; live.log | `VERSION, app/Sources/Orion/Live/LiveSession.swift, app/Sources/Orion/Live/SystemAudio.swift, app/Sources/Orion/MenuBar.swift, app/Tests/OrionTests/AccessibilityTests.swift, app/Tests/OrionTests/PocketTests.swift` |
| `29ef036` | 2026-11-02 | Menu bar: just the key when there's no reading; fixed width only for readings | `VERSION, app/Sources/Orion/MenuBar.swift` |
| `cb32594` | 2026-11-02 | Save state: 0.1.28 test build, live key fix, logs, Waves Tune send | `PICKUP.md` |
| `4799b63` | 2026-11-02 | PICKUP: Waves Tune preset not working, fix plan | `PICKUP.md` |
| `7d0e7a3` | 2026-11-02 | PICKUP: Waves Tune automatic fix plan | `PICKUP.md` |
| `015ee56` | 2026-11-02 | PICKUP: harvest relaunch fix, 10:03 numbers | `PICKUP.md` |
| `10d40cd` | 2026-11-05 | Deep sweep 2026-11-05: close decided/done items, fix harvest and release facts, sweep log | `PICKUP.md, docs/plans/session-key-parity-TOC.md, docs/superpowers/plans/2026-10-06-pt-bpm-harvest-and-train-TOC.md` |
| `207ceef` | 2026-11-08 | Live readings via Event.reading; tuning line up to +-50 and against the set A | `app/Sources/Orion/Faceplate/FaceplateView.swift, app/Sources/Orion/Live/LiveSession.swift, app/Sources/Orion/Reading.swift, app/Tests/OrionTests/ReadingTests.swift` |
| `d7a8f72` | 2026-11-09 | PICKUP: Studio D Listen cause + fix in flight (listen-helper-fix) | `PICKUP.md, handoff/FROM-FLR-SITE-2026-11-09-studio-d-listen-heard-chrome-only.md, handoff/studio-d-beat-key-logs-2026-11-09/running.marker` |
| `30d6a60` | 2026-11-09 | Merge branch 'listen-helper-fix' | (none listed) |
| `c2d11ab` | 2026-11-09 | 0.1.59: Listen logs what it hears; silence guard; every silent failure logs a line | `README.md, VERSION, app/Sources/Orion/AppLog.swift, app/Sources/Orion/AutoTuneSend.swift, app/Sources/Orion/DAWSend/DAWSend.swift, app/Sources/Orion/Engine.swift, app/Sources/Orion/Faceplate/FaceplateView.swift, app/Sources/Orion/Live/AudioInput.swift, app/Sources/Orion/Live/ListenLog.swift, app/Sources/Orion/Live/LiveSession.swift, app/Sources/Orion/Live/SystemAudio.swift, app/Sources/Orion/MenuBar.swift, app/Sources/Orion/MidiExport.swift, app/Sources/Orion/Mini.swift, app/Sources/Orion/Runtime.swift, app/Sources/Orion/YouTubeLogin.swift, app/Tests/OrionTests/ListenLogTests.swift, app_run.py, tests/test_app_run.py` |

(c) Files that appear in three or more of those fix commits:

Files: **16**.

| count | file |
|---|---|
| 7 | `PICKUP.md` |
| 7 | `VERSION` |
| 6 | `app/Sources/Orion/Faceplate/FaceplateView.swift` |
| 5 | `tools/pt-harvest/harvest.py` |
| 4 | `app/Sources/Orion/Faceplate/LCD.swift` |
| 4 | `app/Sources/Orion/MenuBar.swift` |
| 3 | `app/Sources/Orion/Engine.swift` |
| 3 | `app/Sources/Orion/Faceplate/FaceplateModel.swift` |
| 3 | `app/Sources/Orion/Live/LiveSession.swift` |
| 3 | `app/Sources/Orion/Live/SystemAudio.swift` |
| 3 | `app/Sources/Orion/OrionApp.swift` |
| 3 | `app_run.py` |
| 3 | `docs/research/pt-ground-truth/logs/harvest-26-10-7.jsonl` |
| 3 | `docs/research/pt-ground-truth/pt-ground-truth.sqlite3` |
| 3 | `docs/superpowers/plans/2026-10-06-pt-bpm-harvest-and-train-TOC.md` |
| 3 | `tests/test_app_run.py` |

## Run log

Commands that errored or were refused, and anything skipped. Nothing is dropped silently.

- **Refused by the worktree guard, never ran.** Bash calls whose text combined `git` with other shell steps, or used `cd` with a redirect or brace group, were refused with "too complex to verify it stays inside the worktree". Several calls were refused this way (exact count not recorded). Each was re-run as a plain command with absolute paths, and only the re-run output is used here. The refused calls were for: the task 1 and task 2 `git grep` attempts, the tracked-file list chains, and the report-writing steps.
- **Zero matches, exit 1:** `xargs grep -n -I -E '^\s*except\s*:' < py-files.txt` (bare `except:`): no lines. Recorded as 0 in task 2.
- **Zero matches:** `Task.sleep` (checked with grep -c on t3-raw.txt: 0).
- **Catch-body check:** the Swift `catch {` check used a brace-count heuristic over the worktree source. Results are labelled as heuristic; the two lines after each catch were also read by grep -A2.
- **Skipped by spec:** vendor/, .git/; task 1 also skipped archive/, docs/, handoff/; task 5 also skipped PICKUP.md, VERSION, docs/, handoff/, .remember/ (for the version grep only).
- **Not scanned:** tests/ and friends-page/ for task 4 (task 4 covers root and tools/ scripts only, per the brief). Binary files (png, npz, sqlite3) excluded by grep -I.
- **Scope limit, task 4:** grep is a string match. A type named the same as a stdlib or SwiftUI type may show a reference that is not this type's; a type used only through reflection or the test runner shows zero.
- **Scope limit, task 5:** the bundle-id grep pattern is `com\.jshriver\.[A-Za-z0-9.-]+`; any bundle id outside that prefix is not in the table.
- **Error found and fixed in task 4:** the first type-name extraction kept generic parameters (e.g. `CapBodyLabel` for `CapBody<Label: View>`), so those names were searched wrongly. The extraction was corrected (cut at `<`, `:`, `{`, `(`) and the whole zero-reference loop was re-run; only the corrected run is reported.
- **Not verified:** the commit subject keyword match is literal, so 'fixed' and 'prefix' also count. No commit diff was read.
