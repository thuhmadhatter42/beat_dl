import AppKit
import SwiftUI
import XCTest
@testable import Orion

/// Manual Key Selection (J 2026-11-09 15:19): one state (SpellingSettings.manualKey) that every
/// path sets and clears; white instead of the display colour on the wheel, the top 3 and the dial.
final class ManualKeySelectionTests: XCTestCase {
    /// The analyzer's own reading: Ebm 80 %, F#, Bbm.
    let raw = Result(file: URL(fileURLWithPath: "/x/Beats/Beat A.wav"), name: "Beat A.wav", bpm: "141.98",
                     keys: [("Ebm", 80), ("F#", 12), ("Bbm", 8)], bpmExact: 141.98, tuningCents: 12)

    private func settings() -> SpellingSettings { SpellingSettings() }

    /// The state both surfaces draw for `raw` under `s`'s selection (what PocketState.make does).
    private func state(_ s: SpellingSettings, advanced: Bool = false) -> PocketState {
        var p = PocketState()
        let shown = raw.respelled(choice: s.manualKey)
        p.readout = .result(shown, page: nil, download: true, options: ResultOptions(
            factor: .one, tuning: Tuning.meter(12, reference: 440), onCycleTempo: {}))
        p.manualKey = ManualKey.of(s.manualKey, raw: raw)
        p.advanced = advanced
        return p
    }

    // MARK: setting it, from each path

    func testEverySetPathWritesTheOneState() {
        for source in [ManualKeySource.wheel, .topKeys, .dropdown, .keyboard] {
            let s = settings()
            XCTAssertTrue(s.setManualKey("Am", of: raw, from: source), source.rawValue)
            XCTAssertEqual(s.manualKey, KeyChoice(file: raw.file, name: raw.name, pitchClass: 9, minor: true), source.rawValue)
        }
    }

    func testWheelClickSetsAndMovesTheSelection() {
        let s = settings()
        // Am = slot 0, inner: section 1
        HarmonyPanel.wheel(state(s), settings: s).click(1)
        XCTAssertEqual(s.manualKey?.pitchClass, 9)
        XCTAssertEqual(s.manualKey?.minor, true)
        // another key moves it there (G = slot 1, outer: section 2)
        let w = HarmonyPanel.wheel(state(s), settings: s)
        XCTAssertEqual(w.manualSection, 1)
        w.click(2)
        XCTAssertEqual(s.manualKey?.pitchClass, 7)
        XCTAssertEqual(s.manualKey?.minor, false)
    }

    func testTopThreeClickSets() {
        let s = settings()
        let t = KeyStrip.topKeys(state(s), settings: s)
        t.onChoose?("F#")
        XCTAssertEqual(s.manualKey?.pitchClass, 6)
        XCTAssertEqual(s.manualKey?.minor, false)
    }

    func testAKeyThatDoesNotResolveChangesNothing() {
        let s = settings()
        XCTAssertFalse(s.setManualKey("H#", of: raw, from: .dropdown))
        XCTAssertNil(s.manualKey)
        s.setManualKey("Am", of: raw, from: .wheel)
        XCTAssertFalse(s.setManualKey("", of: raw, from: .keyboard))
        XCTAssertEqual(s.manualKey?.pitchClass, 9)                       // unchanged
        HarmonyPanel.wheel(state(s), settings: s).click(99)              // no such section
        XCTAssertEqual(s.manualKey?.pitchClass, 9)
    }

    // MARK: clearing it

    func testWheelReClickClears() {
        let s = settings()
        s.setManualKey("Am", of: raw, from: .wheel)
        let w = HarmonyPanel.wheel(state(s), settings: s)
        XCTAssertEqual(w.manualSection, 1)
        w.click(1)
        XCTAssertNil(s.manualKey)
        XCTAssertEqual(state(s).result?.keys.first?.0, "Ebm")           // detection is back
    }

    func testDialClickClears() {
        let s = settings()
        s.setManualKey("Am", of: raw, from: .topKeys)
        let d = Dial(state: state(s))
        XCTAssertTrue(d.manual)
        d.resetManual(s)
        XCTAssertNil(s.manualKey)
    }

    func testDialClickWithoutManualDoesNothing() {
        let s = settings()
        let d = Dial(state: state(s))
        XCTAssertFalse(d.manual)
        d.resetManual(s)
        XCTAssertNil(s.manualKey)
    }

    /// Click-to-respell is gone (2026-11-10): a black-key reading with no Manual Key Selection has
    /// nothing clickable on the key name. The dial's one click is the manual reset, and it is off;
    /// no action for the key exists on either surface; VoiceOver promises no click.
    func testBlackKeyNameIsPlainTextWithoutManual() {
        XCTAssertFalse(Mirror(reflecting: PocketActions()).children.contains { ($0.label ?? "").lowercased().contains("spell") })
        let s = settings()
        for key in ["Db", "Eb", "F#", "Ab", "Bb", "C#m", "Ebm", "F#m", "G#m", "Bbm"] {
            let r = Result(file: raw.file, name: raw.name, bpm: "120", keys: [(key, 80), ("C", 10)], bpmExact: 120)
            var p = PocketState()
            p.readout = .result(r.respelled(choice: nil), page: nil, download: true, options: ResultOptions())
            let d = Dial(state: p)
            XCTAssertFalse(d.manual, key)
            XCTAssertFalse(d.resetting, key)
            XCTAssertTrue(d.dialLabel.hasPrefix("Key \(KeyChoice.autoTuneName(key)), 80 percent"), d.dialLabel)
            XCTAssertFalse(d.dialLabel.contains("Click"), d.dialLabel)
            XCTAssertFalse(d.dialLabel.contains("sharp"), d.dialLabel)
            d.resetManual(s)                                       // a click: nothing to do
            XCTAssertNil(s.manualKey, key)
        }
        // manual: the label still offers the reset, and only that
        s.setManualKey("Eb", of: raw, from: .topKeys)
        XCTAssertEqual(Dial(state: state(s)).dialLabel, "Key Eb, selected manually. Click to reset manual selection")
    }

    func testClearWithNothingSetReportsFalse() {
        let s = settings()
        XCTAssertFalse(s.clearManualKey(of: raw, from: .dialReset))
    }

    func testClearOfAStaleSelectionStillClears() {
        let s = settings()
        let other = Result(file: URL(fileURLWithPath: "/x/other.wav"), name: "other.wav", bpm: "90", keys: [("C", 70)])
        s.setManualKey("Am", of: other, from: .wheel)
        XCTAssertTrue(s.clearManualKey(of: raw, from: .dialReset))   // logged as an error, still cleared
        XCTAssertNil(s.manualKey)
    }

    // MARK: what shows

    func testManualKeyForTheViews() {
        let s = settings()
        XCTAssertNil(ManualKey.of(nil, raw: raw))
        s.setManualKey("F#", of: raw, from: .topKeys)
        XCTAssertEqual(ManualKey.of(s.manualKey, raw: raw), ManualKey(pitchClass: 6, minor: false, detected: 12))
        s.setManualKey("Am", of: raw, from: .wheel)                      // not detected: no %
        XCTAssertEqual(ManualKey.of(s.manualKey, raw: raw), ManualKey(pitchClass: 9, minor: true, detected: nil))
        let other = Result(file: URL(fileURLWithPath: "/x/other.wav"), name: "other.wav", bpm: "90", keys: [("C", 70)])
        XCTAssertNil(ManualKey.of(s.manualKey, raw: other))              // another reading
    }

    func testTopThreeInManualKeepsTheDetectedPercents() {
        let s = settings()
        // a key the analyzer never listed: first, MANUAL, then the detected keys in order, real %
        s.setManualKey("Am", of: raw, from: .wheel)
        let p = state(s)
        let keys = p.result?.keys ?? []
        XCTAssertEqual(keys.map { $0.0 }, ["Am", "Ebm", "F#"])
        XCTAssertEqual((0..<3).map { TopKeys.label($0, keys: keys, manual: p.manualKey) }, ["MANUAL", "80%", "12%"])
        XCTAssertEqual(TopKeys.spoken(keys: keys, manual: p.manualKey),
                       "Top keys: Am, selected manually, Ebm 80 percent, F# 12 percent")
        // a detected key picked: it moves first as MANUAL, the 80 % key sits second with its %
        s.setManualKey("F#", of: raw, from: .topKeys)
        let q = state(s)
        let k2 = q.result?.keys ?? []
        XCTAssertEqual(k2.map { $0.0 }, ["F#", "Ebm", "Bbm"])
        XCTAssertEqual((0..<3).map { TopKeys.label($0, keys: k2, manual: q.manualKey) }, ["MANUAL", "80%", "8%"])
        // not manual: the % as always
        let n = state(settings())
        XCTAssertEqual((0..<3).map { TopKeys.label($0, keys: n.result?.keys ?? [], manual: nil) }, ["80%", "12%", "8%"])
        XCTAssertNil(TopKeys.label(3, keys: k2, manual: q.manualKey))
    }

    func testWheelHoverCardOnTheManualKey() {
        let s = settings()
        s.setManualKey("F#", of: raw, from: .topKeys)
        let w = HarmonyPanel.wheel(state(s), settings: s)
        let id = try! XCTUnwrap(w.manualSection)
        let tip = w.tip(for: id)
        XCTAssertTrue(tip.title.hasSuffix("12% SURE"), tip.title)        // still says how sure, the real %
        XCTAssertTrue(tip.body.contains("Locked to this key because it was selected manually."))
        XCTAssertTrue(tip.body.contains("again to reset"))
        // a key that was never detected: its name, no made-up %
        s.setManualKey("Am", of: raw, from: .wheel)
        let w2 = HarmonyPanel.wheel(state(s), settings: s)
        let t2 = w2.tip(for: try! XCTUnwrap(w2.manualSection))
        XCTAssertFalse(t2.title.contains("%"), t2.title)
        XCTAssertTrue(t2.body.hasPrefix(HelpText.manualLocked))
        // other keys keep their cards
        XCTAssertFalse(w2.tip(for: 0).body.contains("Locked"))
    }

    func testDialHoverCardText() {
        XCTAssertEqual(HelpText.manualReset.body, "Click to reset manual selection.")
        XCTAssertTrue(HelpText.all.contains(HelpText.manualReset))
        XCTAssertEqual(HelpText.problems(), [])
    }

    func testManualWhiteReadsInHighContrast() {
        for hc in [false, true] {
            let c = NSColor(Palette(highContrast: hc).manualWhite).usingColorSpace(.sRGB)!
            XCTAssertGreaterThan(c.redComponent, 0.94)
            XCTAssertEqual(c.alphaComponent, 1, accuracy: 0.001)
        }
        XCTAssertEqual(NSColor(Palette(highContrast: true).manualGlow).alphaComponent, 0, accuracy: 0.001)   // no halo in High Contrast
    }

    // MARK: offscreen renders (ORION_SNAPSHOT_DIR=<dir> swift test --filter ManualKeySelectionTests/testRender)

    @MainActor
    func testRenderManualKeySelection() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORION_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ORION_SNAPSHOT_DIR to write the Manual Key Selection PNGs")
        }
        guard #available(macOS 13.0, *) else { throw XCTSkip("ImageRenderer is macOS 13+") }
        Pocket.snapshot = true
        defer { Pocket.snapshot = false }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func write<V: View>(_ v: V, _ name: String) throws {
            let r = ImageRenderer(content: v.environment(\.colorScheme, .dark))
            r.scale = 2
            guard let cg = r.cgImage else { return XCTFail("no image for \(name)") }
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
            try png.write(to: out.appendingPathComponent("\(name).png"))
        }
        func window(_ s: PocketState, hover: String? = nil) -> some View {
            FaceplateFace(state: s, picked: [], url: .constant(s.url), fieldFocused: .constant(false),
                          pickFocused: .constant(false))
                .environment(\.manualHoverForced, hover)
        }
        let s = settings()
        var detect = state(s, advanced: true)
        detect.source = "System Audio"
        try write(window(detect), "window-advanced-not-manual")

        s.setManualKey("F#", of: raw, from: .topKeys)
        var manual = state(s, advanced: true)
        manual.source = "System Audio"
        try write(window(manual), "window-advanced-manual")
        try write(window(manual, hover: "wheel"), "window-advanced-manual-wheel-hover")
        try write(window(manual, hover: "dial"), "window-advanced-manual-dial-hover")

        var pocket = state(s)
        pocket.source = "System Audio"
        try write(PocketView(state: pocket, url: .constant("")), "pocket-manual")
        try write(PocketView(state: pocket, url: .constant("")).environment(\.manualHoverForced, "dial"),
                  "pocket-manual-dial-hover")

        try write(window(manual).environment(\.palette, Palette(highContrast: true)), "window-advanced-manual-high-contrast")
    }
}
