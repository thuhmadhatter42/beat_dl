import AppKit
import SwiftUI
import XCTest
@testable import Orion

/// Help mode: the setting, the tip decision, the placement and the one table of help lines.
final class HelpTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "help-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: the setting

    func testHelpModeDefaultsOff() {
        XCTAssertFalse(HelpSettings(defaults: freshDefaults()).isOn)
        XCTAssertFalse(PocketState().help)
    }

    func testHelpModePersists() {
        let d = freshDefaults()
        let a = HelpSettings(defaults: d)
        a.toggle(from: "test")
        XCTAssertTrue(a.isOn)
        XCTAssertTrue(d.bool(forKey: HelpSettings.key))
        XCTAssertEqual(HelpSettings.key, "helpMode")
        XCTAssertTrue(HelpSettings(defaults: d).isOn, "a new launch reads it back")
        a.isOn = false
        XCTAssertFalse(HelpSettings(defaults: d).isOn)
    }

    func testJunkStoredValueStartsOff() {
        let d = freshDefaults()
        d.set("yes please", forKey: HelpSettings.key)
        XCTAssertFalse(HelpSettings(defaults: d).isOn)
    }

    // MARK: the decision

    func testTipIsInertWhenHelpIsOff() {
        for hovering in [false, true] {
            for forced in [false, true] {
                XCTAssertFalse(HelpTipLogic.shows(helpOn: false, hovering: hovering, forced: forced))
            }
        }
    }

    func testTipShowsOnHoverWhenHelpIsOn() {
        XCTAssertTrue(HelpTipLogic.shows(helpOn: true, hovering: true))
        XCTAssertFalse(HelpTipLogic.shows(helpOn: true, hovering: false))
        XCTAssertTrue(HelpTipLogic.shows(helpOn: true, hovering: false, forced: true))
    }

    func testNativeTooltipStepsAsideInHelpMode() {
        XCTAssertEqual(HelpTipLogic.nativeTooltip("New song · reset", helpOn: false), "New song · reset")
        XCTAssertEqual(HelpTipLogic.nativeTooltip("New song · reset", helpOn: true), "")
    }

    func testFaceplateHasNoBareNativeTooltips() throws {
        // every tooltip on the faceplate goes through .nativeHelp, so help mode can silence it
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/Orion").standardized
        for name in ["Pocket/PocketView.swift", "HarmonyView.swift", "Faceplate/FaceplateView.swift",
                     "Faceplate/LCD.swift", "Faceplate/Controls.swift", "Faceplate/Chassis.swift", "Help.swift"] {
            let text = try String(contentsOf: src.appendingPathComponent(name), encoding: .utf8)
            let bare = text.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix(".help(") }
            XCTAssertEqual(bare, [], "\(name) has a bare .help(")
        }
    }

    // MARK: the placement

    func testCardStaysInsideAndOffTheControl() {
        let size = CGSize(width: 552, height: 700)
        let w = HelpCard.width
        for r in [CGRect(x: 0, y: 40, width: 30, height: 14),          // far left
                  CGRect(x: 530, y: 40, width: 20, height: 14),        // far right
                  CGRect(x: 200, y: 660, width: 80, height: 16),       // the footer
                  CGRect(x: 100, y: 300, width: 300, height: 84)] {    // the keyboard
            let p = HelpTipLogic.place(r, in: size)
            XCTAssertGreaterThanOrEqual(p.x, HelpTipLogic.margin)
            XCTAssertLessThanOrEqual(p.x + w, size.width - HelpTipLogic.margin)
        }
        XCTAssertTrue(HelpTipLogic.place(CGRect(x: 200, y: 40, width: 80, height: 14), in: size).below)
        XCTAssertFalse(HelpTipLogic.place(CGRect(x: 200, y: 660, width: 80, height: 16), in: size).below,
                       "near the bottom the card goes above")
    }

    // MARK: the table

    func testEveryHelpLineIsShortAndFilled() {
        XCTAssertGreaterThanOrEqual(HelpText.all.count, 40)
        for t in HelpText.all {
            XCTAssertFalse(t.title.isEmpty)
            XCTAssertFalse(t.body.trimmingCharacters(in: .whitespaces).isEmpty, t.title)
            XCTAssertLessThanOrEqual(t.body.count, HelpTip.maxBody, t.title)
            XCTAssertLessThanOrEqual(t.body.count, 140, t.title)
        }
        XCTAssertEqual(HelpText.problems(), [])
    }

    func testProblemsAreCaught() {
        let bad = [HelpTip(title: "A", body: ""), HelpTip(title: "B", body: String(repeating: "x", count: 141)),
                   HelpTip(title: "C", body: "ok"), HelpTip(title: "C", body: "ok")]
        XCTAssertEqual(HelpText.problems(bad).count, 3)
    }

    /// Click-to-respell is gone (2026-11-10): the KEY tip promises no click on the key.
    func testKeyTipDoesNotOfferRespelling() {
        XCTAssertEqual(HelpText.keyDial.body, "The key Beat Key hears; the ring and the % under it show how sure it is.")
        for t in HelpText.all {
            XCTAssertFalse(t.body.lowercased().contains("respell"), t.title)
            XCTAssertFalse(t.body.lowercased().contains("sharp or flat"), t.title)
        }
    }

    func testChordsTipCarriesTheClickDragLine() {
        // the always-on "CLICK = HEAR · DRAG = MIDI" moved into the tip
        XCTAssertTrue(HelpText.chords.body.contains("Click one to hear it"))
        XCTAssertTrue(HelpText.chords.body.contains("MIDI"))
    }

    func testKeyboardTipMatchesMusicalTyping() {
        // A = C and Space toggles, as PlayToFind does
        XCTAssertEqual(MusicalTyping.action(keyCode: MusicalTyping.aKey, modifiers: []), .note(0))
        XCTAssertEqual(MusicalTyping.action(keyCode: MusicalTyping.space, modifiers: []), .toggleMode)
        XCTAssertTrue(HelpText.keyboard.body.contains("A W S E D F T G Y H U J K"))
        XCTAssertTrue(HelpText.keyboard.body.contains("Space"))
    }

    // MARK: offscreen renders (ORION_SNAPSHOT_DIR=<dir> swift test --filter HelpTests/testRender)

    @MainActor
    func testRenderHelpMode() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORION_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ORION_SNAPSHOT_DIR to write the help-mode PNGs")
        }
        guard #available(macOS 13.0, *) else { throw XCTSkip("ImageRenderer is macOS 13+") }
        Pocket.snapshot = true
        defer { Pocket.snapshot = false }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let r = Result(file: URL(fileURLWithPath: "/x/Beats/Beat A.wav"), name: "Beat A.wav", bpm: "142.0",
                       keys: [("Cm", 64), ("Eb", 18), ("Gm", 9)], bpmExact: 141.98, tuningCents: 12,
                       chroma: [1.0, 0.08, 0.42, 0.81, 0.06, 0.37, 0.1, 0.93, 0.62, 0.05, 0.48, 0.12])
        var s = PocketState()
        s.source = "System Audio"
        s.daw = "Pro Tools"
        s.readout = .result(r, page: nil, download: false, options: ResultOptions(
            factor: .one, tuning: Tuning.meter(12, reference: 440), onCycleTempo: {}))
        var off = s
        off.advanced = true
        off.harmony = HarmonyPrefs(quality: .seventh, voicing: .root, bars: 2, matchKey: "Am")
        var on = off
        on.help = true
        var plainOn = s
        plainOn.help = true

        func write<V: View>(_ v: V, _ name: String) throws {
            let rr = ImageRenderer(content: v.environment(\.colorScheme, .dark))
            rr.scale = 2
            guard let cg = rr.cgImage else { return XCTFail("no image for \(name)") }
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
            try png.write(to: out.appendingPathComponent("\(name).png"))
        }
        func window(_ st: PocketState, forced: HelpTip? = nil) -> some View {
            FaceplateFace(state: st, picked: [], url: .constant(""), fieldFocused: .constant(false),
                          pickFocused: .constant(false))
                .environment(\.helpTipForced, forced?.id)
        }
        try write(window(off), "window-advanced-help-off")
        try write(window(on), "window-advanced-help-on")
        try write(window(on, forced: HelpText.chords), "window-advanced-help-chords")
        try write(window(plainOn, forced: HelpText.keyboard), "window-default-help-keyboard")
        try write(window(plainOn, forced: HelpText.help), "window-default-help-chip")
        // the forced tip with help off: nothing shows (inert)
        try write(window(off, forced: HelpText.chords), "window-advanced-help-off-forced")
        try write(PocketView(state: plainOn, url: .constant("")).environment(\.helpTipForced, HelpText.bpm.id),
                  "pocket-help-bpm")
        try write(PocketView(state: plainOn, url: .constant("")).environment(\.helpTipForced, HelpText.sendDAW.id),
                  "pocket-help-send")
    }
}
