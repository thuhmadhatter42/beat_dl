import XCTest
@testable import Orion

/// A fake accessibility tree: enough of AXUIElement to drive the DAW routes.
final class FakeAX: AXNode {
    var role: String?
    var subrole: String?
    var title: String?
    var desc: String?
    var help: String?
    var identifier: String?
    var valueText: String?
    var settable = false
    var selected = false
    var focused = false
    var reportsFocus = true
    /// What the field shows after a set (a DAW that mangles "1|1|000" into "11000").
    var transform: ((String) -> String)?
    var frame: CGRect?
    weak var parentNode: FakeAX?
    var kids: [FakeAX] = []
    var wins: [FakeAX] = []
    var bar: FakeAX?
    var onPress: ((FakeAX) -> Void)?
    var pressed = 0

    init(_ role: String, title: String? = nil, desc: String? = nil, help: String? = nil, value: String? = nil,
         settable: Bool = false, _ kids: [FakeAX] = []) {
        self.role = role; self.title = title; self.desc = desc; self.help = help; valueText = value
        self.settable = settable
        add(kids)
    }

    @discardableResult func add(_ k: [FakeAX]) -> FakeAX { for c in k { c.parentNode = self; kids.append(c) }; return self }

    var children: [AXNode] { kids + wins.filter { _ in role == "AXApplication" } }
    var parent: AXNode? { parentNode }
    var isValueSettable: Bool { settable }
    var windows: [AXNode] { wins }
    var focusedWindow: AXNode? { wins.last }
    var menuBar: AXNode? { bar }
    var isFocused: Bool? { reportsFocus ? focused : nil }
    func setValue(_ text: String) -> Bool { guard settable else { return false }; valueText = transform?(text) ?? text; return true }
    func setBool(_ attribute: String, _ on: Bool) -> Bool {
        switch attribute {
        case kAXSelectedAttribute: selected = on; return role == "AXRow"
        case kAXFocusedAttribute: focused = on; return true
        default: return true
        }
    }
    @discardableResult func perform(_ action: String) -> Bool {
        guard action == kAXPressAction || action == kAXShowMenuAction || action == kAXRaiseAction else { return false }
        if action == kAXRaiseAction { return true }
        pressed += 1
        onPress?(self)
        return onPress != nil || ["AXButton", "AXMenuItem", "AXRadioButton", "AXCheckBox", "AXPopUpButton"].contains(role ?? "")
    }

    /// Depth-first search by any visible text (tests only).
    func find(_ text: String) -> FakeAX? {
        if [title, desc, valueText].contains(where: { $0 == text }) { return self }
        for k in kids + wins { if let f = k.find(text) { return f } }
        return nil
    }
}

final class FakeKeys: AXKeys {
    var typed: [String] = []
    var keys: [CGKeyCode] = []
    var clicks: [CGPoint] = []
    func type(_ text: String, pid: pid_t) { typed.append(text) }
    func key(_ code: CGKeyCode, flags: CGEventFlags, pid: pid_t) { keys.append(code) }
    func doubleClick(_ at: CGPoint) { clicks.append(at) }
}

final class AXDriverTests: XCTestCase {
    private func runner(_ app: FakeAX, _ keys: FakeKeys) -> () -> AXRunner {
        { AXRunner(app: app, pid: 1, keys: keys, timeout: 0.05, poll: 0.01) }
    }

    private func menuBar(_ menus: [(String, [FakeAX])]) -> FakeAX {
        FakeAX("AXMenuBar", menus.map { FakeAX("AXMenuBarItem", title: $0.0, [FakeAX("AXMenu", $0.1)]) })
    }

    // MARK: matching

    func testNormFoldsEllipsisAccidentalsColonsAndCase() {
        XCTAssertEqual(AXText.norm("Add Key Change…"), "add key change")
        XCTAssertEqual(AXText.norm("Add Key Change..."), "add key change")
        XCTAssertEqual(AXText.norm("  BPM: "), "bpm")
        XCTAssertEqual(AXText.norm("E♭  minor"), "eb minor")
        XCTAssertEqual(AXText.norm("F♯ major"), "f# major")
    }

    func testMatchUsesRoleLabelAndHelp() {
        let b = FakeAX("AXButton", title: "OK")
        XCTAssertTrue(AXMatch(roles: ["AXButton"], labels: ["ok"]).hit(b))
        XCTAssertFalse(AXMatch(roles: ["AXTextField"], labels: ["OK"]).hit(b))
        let t = FakeAX("AXSlider", help: "Indicates the playback or recording speed. Drag vertically…")
        XCTAssertTrue(AXMatch().helped("indicates the playback or recording speed").hit(t))
        XCTAssertFalse(AXMatch(labels: ["Tempo"]).hit(t))
    }

    func testMenuPathAcceptsEitherEllipsis() {
        let app = FakeAX("AXApplication")
        app.bar = menuBar([("File", [FakeAX("AXMenuItem", title: "Save")]),
                           ("Event", [FakeAX("AXMenuItem", title: "Tempo Operations"), FakeAX("AXMenuItem", title: "Add Key Change...")])])
        XCTAssertEqual(AXFind.menuItem([["Event"], ["Add Key Change…"]], in: app)?.title, "Add Key Change...")
        XCTAssertNil(AXFind.menuItem([["Event"], ["Add Meter Change…"]], in: app))
        XCTAssertNil(AXFind.menuItem([["Edit"], ["Add Key Change…"]], in: app))
    }

    func testFieldFoundByNeighbouringLabel() {
        let loc = FakeAX("AXTextField", value: "2|1|000")
        let bpm = FakeAX("AXTextField", value: "120.0000")
        let w = FakeAX("AXWindow", title: "Tempo Change", [
            FakeAX("AXCheckBox", title: "Snap To Bar", value: "1"),
            FakeAX("AXGroup", [FakeAX("AXStaticText", value: "Location:"), loc]),
            FakeAX("AXGroup", [FakeAX("AXStaticText", value: "BPM:"), FakeAX("AXGroup", [bpm])]),
        ])
        XCTAssertTrue(AXFind.field(["Location"], in: w) === loc)
        XCTAssertTrue(AXFind.field(["BPM"], in: w) === bpm)
        XCTAssertNil(AXFind.field(["Resolution"], in: w))
        let own = FakeAX("AXTextField", desc: "Tempo")
        XCTAssertTrue(AXFind.field(["Tempo"], in: FakeAX("AXGroup", [own])) === own)
    }

    func testKeyNamesSpellLikeDAWLists() {
        XCTAssertEqual(AXKeyNames.names(3, minor: true).prefix(2), ["Eb minor", "D# minor"])
        XCTAssertEqual(AXKeyNames.names(1, minor: false).first, "Db major")
        XCTAssertEqual(AXKeyNames.names(8, minor: true).first, "G# minor")
        XCTAssertEqual(AXKeyNames.names(6, minor: false).prefix(2), ["F# major", "Gb major"])
        XCTAssertEqual(AXPlans.bpmText(140.0), "140")
        XCTAssertEqual(AXPlans.bpmText(140.82), "140.82")
    }

    // MARK: Pro Tools

    /// Edit window with the Tempo ruler's Add Tempo Change button, the Event menu, and the two
    /// dialogs from the Reference Guide's pictures.
    private func proTools(addTempoButton: Bool = true, okInKeyDialog: Bool = true, pitchedOn: Bool = true) -> (FakeAX, tempo: () -> FakeAX?, key: () -> FakeAX?) {
        let app = FakeAX("AXApplication", title: "Pro Tools")
        let edit = FakeAX("AXWindow", title: "Edit: Session")
        app.wins = [edit]
        var tempoWin: FakeAX?, keyWin: FakeAX?
        func closeOnOK(_ w: FakeAX) -> FakeAX {
            FakeAX("AXButton", title: "OK").also { $0.onPress = { _ in app.wins.removeAll { $0 === w } } }
        }
        if addTempoButton {
            edit.add([FakeAX("AXGroup", title: "Tempo Ruler", [FakeAX("AXButton", desc: "Add Tempo Change").also { b in
                b.onPress = { _ in
                    let w = FakeAX("AXWindow", title: "Tempo Change")
                    w.add([FakeAX("AXCheckBox", title: "Snap To Bar", value: "1"),
                           FakeAX("AXStaticText", value: "Location:"), FakeAX("AXTextField", value: "3|1|000", settable: true),
                           FakeAX("AXStaticText", value: "BPM:"), FakeAX("AXTextField", value: "120.0000", settable: true),
                           FakeAX("AXButton", title: "Cancel"), closeOnOK(w)])
                    tempoWin = w; app.wins.append(w)
                }
            }])])
        }
        let addKey = FakeAX("AXMenuItem", title: "Add Key Change…")
        addKey.onPress = { _ in
            let w = FakeAX("AXWindow", title: "Key Change")
            let sharps = ["C", "G", "D", "A", "E", "B", "F#", "C#"], flats = ["C", "F", "Bb", "Eb", "Ab", "Db", "Gb", "Cb"]
            let minorSharps = ["A", "E", "B", "F#", "C#", "G#", "D#", "A#"], minorFlats = ["A", "D", "G", "C", "F", "Bb", "Eb", "Ab"]
            func table(_ name: String, _ roots: [String], _ mode: String) -> FakeAX {
                FakeAX("AXScrollArea", [FakeAX("AXTable", desc: name, roots.map { FakeAX("AXRow", [FakeAX("AXCell", [FakeAX("AXStaticText", value: "\($0) \(mode)")])]) })])
            }
            let tables = FakeAX("AXGroup", [table("Sharps", sharps, "major"), table("Flats", flats, "major")])
            let minor = FakeAX("AXRadioButton", title: "Minor Keys", value: "0")
            minor.onPress = { _ in tables.kids = []; tables.add([table("Sharps", minorSharps, "minor"), table("Flats", minorFlats, "minor")]) }
            w.add([tables, FakeAX("AXRadioButton", title: "Major Keys", value: "1"), minor,
                   FakeAX("AXStaticText", value: "From"), FakeAX("AXTextField", value: "5|1|000", settable: true),
                   FakeAX("AXCheckBox", title: "Edit Pitched Tracks:", value: pitchedOn ? "1" : "0").also { c in c.onPress = { $0.valueText = $0.valueText == "1" ? "0" : "1" } },
                   FakeAX("AXButton", title: "Cancel")])
            if okInKeyDialog { w.add([closeOnOK(w)]) }
            keyWin = w; app.wins.append(w)
        }
        app.bar = menuBar([("Event", [FakeAX("AXMenuItem", title: "Tempo Operations"), addKey])])
        return (app, { tempoWin }, { keyWin })
    }

    func testProToolsTempoAndKeyGoThroughTheirDialogs() {
        let (app, tempo, key) = proTools()
        let keys = FakeKeys()
        let r = AXSend.run(AXPlans.plan(.proTools, bpm: 140.82, tonic: (3, true)), runner: runner(app, keys))
        XCTAssertTrue(r.tempoSet, r.log.joined(separator: "\n"))
        XCTAssertTrue(r.keySet, r.log.joined(separator: "\n"))
        XCTAssertEqual(tempo()?.find("1|1|000")?.role, "AXTextField")      // Location replaced the default
        XCTAssertNotNil(tempo()?.find("140.82"))
        let k = key()!
        XCTAssertTrue((k.find("Eb minor")?.parentNode?.parentNode)?.selected ?? false, "the Eb minor row is selected")
        XCTAssertEqual(k.find("Edit Pitched Tracks:")?.valueText, "0", "no MIDI notes get transposed")
        XCTAssertNotNil(k.find("1|1|000"))
        XCTAssertEqual(app.wins.count, 1, "both dialogs closed")
        XCTAssertEqual(keys.keys, [], "no Escape needed")
    }

    func testProToolsMajorKeyStaysInMajorList() {
        let (app, _, key) = proTools(pitchedOn: false)
        let r = AXSend.run(AXPlans.plan(.proTools, bpm: nil, tonic: (1, false)), runner: runner(app, FakeKeys()))
        XCTAssertTrue(r.keySet)
        XCTAssertFalse(r.tempoSet)
        XCTAssertNil(r.tempoError, "no tempo asked")
        XCTAssertTrue((key()!.find("Db major")?.parentNode?.parentNode)?.selected ?? false)
        XCTAssertEqual(key()!.find("Edit Pitched Tracks:")?.valueText, "0")
    }

    func testProToolsManualTempoFieldIsTheSecondRoute() {
        let (app, _, _) = proTools(addTempoButton: false)
        let manual = FakeAX("AXTextField", desc: "Tempo", value: "120", settable: true)
        app.wins.append(FakeAX("AXWindow", title: "Transport", [FakeAX("AXGroup", [manual])]))
        let r = AXSend.run(AXPlans.plan(.proTools, bpm: 92, tonic: nil), runner: runner(app, FakeKeys()))
        XCTAssertTrue(r.tempoSet)
        XCTAssertEqual(manual.valueText, "92")
    }

    func testStuckDialogIsEscapedAndReported() {
        let (app, _, _) = proTools(okInKeyDialog: false)
        let keys = FakeKeys()
        let r = AXSend.run(AXPlans.plan(.proTools, bpm: nil, tonic: (0, false)), runner: runner(app, keys))
        XCTAssertFalse(r.keySet)
        XCTAssertTrue(r.keyError?.contains("OK") ?? false, r.keyError ?? "")
        XCTAssertEqual(keys.keys, [KeyCode.escape], "the half-filled Key Change dialog is cancelled")
    }

    func testNothingToFindFailsInsideTheTimeout() {
        let app = FakeAX("AXApplication"); app.wins = [FakeAX("AXWindow", title: "Edit")]
        let t0 = Date()
        let r = AXSend.run(AXPlans.plan(.proTools, bpm: 100, tonic: (0, false)), runner: runner(app, FakeKeys()))
        XCTAssertFalse(r.tempoSet); XCTAssertFalse(r.keySet)
        XCTAssertNotNil(r.tempoError); XCTAssertNotNil(r.keyError)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2)
    }

    // MARK: Logic Pro

    private func logic(tempoSettable: Bool) -> (FakeAX, tempo: FakeAX, keyMenu: FakeAX, start: FakeAX) {
        let app = FakeAX("AXApplication", title: "Logic Pro")
        let tempo = FakeAX("AXSlider", desc: "Tempo", help: "Indicates the playback or recording speed. Drag vertically to speed up or slow down the tempo, or double-click and enter a new value.", value: "120", settable: tempoSettable)
        tempo.frame = CGRect(x: 600, y: 40, width: 60, height: 20)
        let menu = FakeAX("AXMenu", [FakeAX("AXMenuItem", title: "C major"), FakeAX("AXMenuItem", title: "E♭ minor"), FakeAX("AXMenuItem", title: "A minor")])
        let key = FakeAX("AXPopUpButton", help: "Indicates the key signature of the project. Choose a major or minor key signature from the pop-up menu.", value: "Cmaj")
        key.onPress = { k in if !k.kids.contains(where: { $0 === menu }) { k.add([menu]) } }
        let start = FakeAX("AXButton", desc: "Go to Beginning")
        app.wins = [FakeAX("AXWindow", title: "Untitled - Tracks", [FakeAX("AXGroup", desc: "Control Bar", [start, FakeAX("AXGroup", desc: "LCD", [tempo, key])])])]
        return (app, tempo, menu, start)
    }

    func testLogicSetsTheLCDTempoAndPicksTheKeyFromItsPopUp() {
        let (app, tempo, menu, start) = logic(tempoSettable: true)
        let keys = FakeKeys()
        let r = AXSend.run(AXPlans.plan(.logic, bpm: 128, tonic: (3, true)), runner: runner(app, keys))
        XCTAssertTrue(r.tempoSet); XCTAssertTrue(r.keySet, r.log.joined(separator: "\n"))
        XCTAssertEqual(tempo.valueText, "128")
        XCTAssertEqual(start.pressed, 1, "playhead to the project start first")
        XCTAssertEqual(menu.kids[1].pressed, 1, "E♭ minor picked")
        XCTAssertTrue(keys.clicks.isEmpty)
    }

    func testLogicTempoFallsBackToDoubleClickAndTyping() {
        let (app, _, _, _) = logic(tempoSettable: false)
        let keys = FakeKeys()
        let r = AXSend.run(AXPlans.plan(.logic, bpm: 97.5, tonic: nil), runner: runner(app, keys))
        XCTAssertTrue(r.tempoSet)
        XCTAssertEqual(keys.clicks, [CGPoint(x: 630, y: 50)], "the element's own centre")
        XCTAssertEqual(keys.typed, ["97.50"])
        XCTAssertEqual(keys.keys.last, KeyCode.return)
    }

    func testLogicMissingKeyInMenuEscapesTheMenu() {
        let (app, _, _, _) = logic(tempoSettable: true)
        let keys = FakeKeys()
        let r = AXSend.run(AXPlans.plan(.logic, bpm: nil, tonic: (6, false)), runner: runner(app, keys))
        XCTAssertFalse(r.keySet)
        XCTAssertTrue(keys.keys.contains(KeyCode.escape))
    }

    // MARK: Studio One

    func testStudioOneTransportTempoAndKey() {
        let app = FakeAX("AXApplication", title: "Studio One")
        let tempo = FakeAX("AXTextField", title: "Tempo", value: "120.00", settable: true)
        let key = FakeAX("AXPopUpButton", title: "Key", value: "C")
        key.add([FakeAX("AXMenu", [FakeAX("AXMenuItem", title: "G major"), FakeAX("AXMenuItem", title: "Bb minor")])])
        app.wins = [FakeAX("AXWindow", title: "Song", [FakeAX("AXGroup", desc: "Transport", [tempo, key])])]
        let r = AXSend.run(AXPlans.plan(.studioOne, bpm: 150, tonic: (10, true)), runner: runner(app, FakeKeys()))
        XCTAssertTrue(r.tempoSet); XCTAssertTrue(r.keySet)
        XCTAssertEqual(tempo.valueText, "150")
        XCTAssertEqual((key.kids[0].kids[1]).pressed, 1)
    }

    func testStudioOneSongSetupIsTheSecondTempoRoute() {
        let app = FakeAX("AXApplication", title: "Studio Pro")
        app.wins = [FakeAX("AXWindow", title: "Song")]
        let field = FakeAX("AXTextField", value: "120", settable: true)
        let setup = FakeAX("AXMenuItem", title: "Song Setup...")
        setup.onPress = { _ in
            let w = FakeAX("AXWindow", title: "Song Setup")
            w.add([FakeAX("AXStaticText", value: "Tempo"), field, FakeAX("AXButton", title: "OK").also { b in b.onPress = { _ in app.wins.removeAll { $0 === w } } }])
            app.wins.append(w)
        }
        app.bar = menuBar([("Song", [setup])])
        let r = AXSend.run(AXPlans.plan(.studioOne, bpm: 88, tonic: nil), runner: runner(app, FakeKeys()))
        XCTAssertTrue(r.tempoSet, r.log.joined(separator: "\n"))
        XCTAssertEqual(field.valueText, "88")
    }

    // MARK: report

    func testReportAllSet() throws {
        let p = SendPayload(bpm: 140.82, key: "Ebm")
        let s = try AXDAWDriver.report(.proTools, p, AXResult(tempoSet: true, keySet: true), readBack: 140.82)
        XCTAssertEqual(s, "Set in Pro Tools: tempo 140.82 (read back), key Eb minor.")
    }

    func testReportPartialSaysWhatMissedAndWritesNoMidi() throws {
        let p = SendPayload(bpm: 120, key: "C")
        let s = try AXDAWDriver.report(.logic, p, AXResult(tempoSet: true, keySet: false, keyError: "no pop-up \"Key Signature\""), readBack: nil)
        XCTAssertEqual(s, "Set in Logic Pro: tempo 120.00. Could not set key (no pop-up \"Key Signature\").")
        XCTAssertFalse(s.contains(".mid"))
    }

    func testReportNothingSetThrowsOneLine() {
        XCTAssertThrowsError(try AXDAWDriver.report(.proTools, SendPayload(bpm: 140, key: nil), AXResult(tempoSet: true), readBack: 120)) { e in
            XCTAssertEqual("\(e)", "Could not set tempo (Pro Tools reads 120.00 after the change).")
        }
    }

    // MARK: no BPM, field safety, cancel (J's 2026-11-05 17:20 report)

    func testNoBPMPayloadNeverTouchesTempo() throws {
        let r = Result(file: URL(fileURLWithPath: "/x"), name: "LIVE", bpm: nil, keys: [("D", 85)])
        let p = SendPayload(r)
        XCTAssertNil(p.bpm)
        XCTAssertEqual(DAWSendController.plan(p), "key only (no BPM yet)")
        XCTAssertNil(DAWSendController.plan(SendPayload(bpm: nil, key: nil)), "no BPM and no key: nothing sent")
        XCTAssertTrue(AXPlans.plan(.proTools, bpm: nil, tonic: p.tonic).tempo.isEmpty)
        let (app, tempo, _) = proTools()
        let x = AXSend.run(AXPlans.plan(.proTools, bpm: nil, tonic: p.tonic), runner: runner(app, FakeKeys()))
        XCTAssertTrue(x.keySet); XCTAssertNil(tempo(), "the Tempo Change dialog never opened")
        let s = try AXDAWDriver.report(.proTools, p, x, readBack: nil)
        XCTAssertEqual(s, "Set in Pro Tools: key D major. No BPM yet; tempo left alone.")
    }

    /// A Tempo Change dialog whose Location may not be an editable field (shown as text): the
    /// "Location:" label must never hand back the BPM field after it.
    private func tempoDialog(locationField: FakeAX?, bpm: FakeAX, cancelCloses: Bool = true) -> FakeAX {
        let app = FakeAX("AXApplication", title: "Pro Tools")
        let edit = FakeAX("AXWindow", title: "Edit: Session")
        app.wins = [edit]
        edit.add([FakeAX("AXButton", desc: "Add Tempo Change").also { b in
            b.onPress = { _ in
                let w = FakeAX("AXWindow", title: "Tempo Change")
                w.add([FakeAX("AXStaticText", value: "Location:")])
                w.add([locationField ?? FakeAX("AXStaticText", value: "3| 1| 000")])
                w.add([FakeAX("AXStaticText", value: "BPM:"), bpm,
                       FakeAX("AXButton", title: "Cancel").also { c in if cancelCloses { c.onPress = { _ in app.wins.removeAll { $0 === w } } } },
                       FakeAX("AXButton", title: "OK").also { o in o.onPress = { _ in app.wins.removeAll { $0 === w } } }])
                app.wins.append(w)
            }
        }])
        return app
    }

    func testLocationLabelNeverFallsThroughToTheBPMField() {
        let bpm = FakeAX("AXTextField", value: "120.0000", settable: true)
        let w = FakeAX("AXWindow", title: "Tempo Change", [FakeAX("AXStaticText", value: "Location:"), FakeAX("AXStaticText", value: "3| 1| 000"),
                                                           FakeAX("AXStaticText", value: "BPM:"), bpm])
        XCTAssertNil(AXFind.field(["Location"], in: w, accept: AXFieldKind.time.accepts))
        XCTAssertNil(AXFind.field(["Location"], in: w), "never walks past the BPM: label")
        XCTAssertTrue(AXFind.field(["BPM"], in: w, accept: AXFieldKind.tempo(88).accepts) === bpm)
        // a "Location" field that holds a tempo number is refused
        let bad = FakeAX("AXWindow", [FakeAX("AXStaticText", value: "Location:"), FakeAX("AXTextField", value: "120.0000")])
        XCTAssertNil(AXFind.field(["Location"], in: bad, accept: AXFieldKind.time.accepts))
        XCTAssertNotNil(AXFind.field(["Location"], in: bad))
    }

    func testMissingLocationCancelsTheDialogAndLeavesBPMAlone() {
        let bpm = FakeAX("AXTextField", value: "120.0000", settable: true)
        let app = tempoDialog(locationField: nil, bpm: bpm)
        let keys = FakeKeys()
        let r = AXSend.run(AXPlans.plan(.proTools, bpm: 88.12, tonic: nil), runner: runner(app, keys))
        XCTAssertFalse(r.tempoSet)
        XCTAssertEqual(bpm.valueText, "120.0000", "BPM untouched")
        XCTAssertEqual(app.wins.count, 1, "Tempo Change cancelled")
        XCTAssertTrue(r.log.contains { $0.hasPrefix("pressed Cancel") }, r.log.joined(separator: "\n"))
        XCTAssertTrue(keys.typed.isEmpty, "nothing typed anywhere")
        XCTAssertTrue(r.tempoError?.contains("no field \"Location\"") ?? false, r.tempoError ?? "")
    }

    func testMangledLocationReadBackAborts() {
        let loc = FakeAX("AXTextField", value: "3|1|000", settable: true)
        loc.transform = { $0.filter(\.isNumber) }     // "1|1|000" -> "11000"
        let bpm = FakeAX("AXTextField", value: "120.0000", settable: true)
        let app = tempoDialog(locationField: loc, bpm: bpm)
        let r = AXSend.run(AXPlans.plan(.proTools, bpm: 88, tonic: nil), runner: runner(app, FakeKeys()))
        XCTAssertFalse(r.tempoSet)
        XCTAssertEqual(bpm.valueText, "120.0000")
        XCTAssertEqual(app.wins.count, 1)
    }

    func testBPMReadBackMustMatchAndBeInRange() {
        XCTAssertNil(AXFieldKind.tempo(88.12).refusal("88.1200", typed: "88.12"))
        XCTAssertNotNil(AXFieldKind.tempo(88.12).refusal("8812", typed: "88.12"))
        XCTAssertNotNil(AXFieldKind.tempo(88.12).refusal("88.2", typed: "88.12"))
        XCTAssertNotNil(AXFieldKind.tempo(88.12).refusal(nil, typed: "88.12"))
        XCTAssertNotNil(AXFieldKind.tempo(1100).refusal("1100", typed: "1100"))
        XCTAssertNil(AXFieldKind.time.refusal("1| 1| 000", typed: "1|1|000"))
        XCTAssertNotNil(AXFieldKind.time.refusal("11000", typed: "1|1|000"))
        // a field that drops the decimal point: never OK'd, dialog cancelled
        let bpm = FakeAX("AXTextField", value: "120.0000", settable: true)
        bpm.transform = { $0.filter(\.isNumber) }
        let app = tempoDialog(locationField: FakeAX("AXTextField", value: "3|1|000", settable: true), bpm: bpm)
        let r = AXSend.run(AXPlans.plan(.proTools, bpm: 88.12, tonic: nil), runner: runner(app, FakeKeys()))
        XCTAssertFalse(r.tempoSet)
        XCTAssertEqual(app.wins.count, 1)
        XCTAssertTrue(r.tempoError?.contains("8812") ?? false, r.tempoError ?? "")
        // out of range: refused before anything is typed
        let bpm2 = FakeAX("AXTextField", value: "120.0000", settable: true)
        let app2 = tempoDialog(locationField: FakeAX("AXTextField", value: "3|1|000", settable: true), bpm: bpm2)
        let r2 = AXSend.run(AXPlans.plan(.proTools, bpm: 1100, tonic: nil), runner: runner(app2, FakeKeys()))
        XCTAssertFalse(r2.tempoSet); XCTAssertEqual(bpm2.valueText, "120.0000"); XCTAssertEqual(app2.wins.count, 1)
    }

    func testFieldThatDoesNotReportFocusGetsNoKeystrokes() {
        let loc = FakeAX("AXTextField", value: "3|1|000")          // not settable: would need typing
        loc.reportsFocus = false
        let app = tempoDialog(locationField: loc, bpm: FakeAX("AXTextField", value: "120.0000", settable: true))
        let keys = FakeKeys()
        let r = AXSend.run(AXPlans.plan(.proTools, bpm: 90, tonic: nil), runner: runner(app, keys))
        XCTAssertFalse(r.tempoSet)
        XCTAssertTrue(keys.typed.isEmpty); XCTAssertFalse(keys.keys.contains(KeyCode.a))
        XCTAssertEqual(app.wins.count, 1)
    }

    func testDialogLeftOpenFromBeforeRunsNothing() {
        let (app, tempo, _) = proTools()
        app.wins.append(FakeAX("AXWindow", title: "Tempo Change", [FakeAX("AXButton", title: "OK")]))
        let keys = FakeKeys()
        let r = AXSend.run(AXPlans.plan(.proTools, bpm: 90, tonic: (0, false)), runner: runner(app, keys))
        XCTAssertFalse(r.tempoSet); XCTAssertFalse(r.keySet)
        XCTAssertTrue(r.tempoError?.contains("already open") ?? false, r.tempoError ?? "")
        XCTAssertNil(tempo()); XCTAssertTrue(keys.keys.isEmpty); XCTAssertTrue(keys.typed.isEmpty)
    }

    func testStuckDialogStopsTheKeyJob() {
        let bpm = FakeAX("AXTextField", value: "120.0000", settable: true)
        let app = tempoDialog(locationField: nil, bpm: bpm, cancelCloses: false)
        let keys = FakeKeys()
        let r = AXSend.run(AXPlans.plan(.proTools, bpm: 90, tonic: (0, false)), runner: runner(app, keys))
        XCTAssertFalse(r.tempoSet); XCTAssertFalse(r.keySet)
        XCTAssertEqual(keys.keys, [KeyCode.escape], "Cancel did not close it: one Escape, then stop")
        XCTAssertTrue(r.keyError?.contains("would not close") ?? false, r.keyError ?? "")
    }

    func testDriversRouteLogicAndStudioOneThroughAccessibility() {
        XCTAssertTrue(DAWDrivers.driver(.logic) is AXDAWDriver)
        XCTAssertTrue(DAWDrivers.driver(.studioOne) is AXDAWDriver)
        XCTAssertTrue(DAWDrivers.driver(.flStudio) is MidiFileDriver)
        XCTAssertTrue(DAWDrivers.driver(.proTools) is ProToolsDriver)
        XCTAssertTrue(AXPlans.plan(.reaper, bpm: 100, tonic: (0, false)).tempo.isEmpty)
    }
}

private extension FakeAX {
    func also(_ f: (FakeAX) -> Void) -> FakeAX { f(self); return self }
}
