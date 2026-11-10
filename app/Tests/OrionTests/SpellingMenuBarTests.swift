import AppKit
import SwiftUI
import XCTest
@testable import Orion

/// 0.1.56 (J 2026-11-09): one key, one name across the window and the pocket (the key wheel spells
/// a key exactly as the dial and the top 3 do), and the menu-bar item in Manual Key Selection
/// (the manual key, a white key glyph, no UNSURE / LOCKED lamp).
final class SpellingMenuBarTests: XCTestCase {
    /// The analyzer's own reading: Ebm 80 %, Gb, Bbm.
    let raw = Result(file: URL(fileURLWithPath: "/x/Beats/Beat A.wav"), name: "Beat A.wav", bpm: "141.98",
                     keys: [("Ebm", 80), ("F#", 12), ("Bbm", 8)], bpmExact: 141.98, tuningCents: 12)

    private func settings(_ pref: KeySpelling? = nil) -> SpellingSettings {
        let d = UserDefaults(suiteName: "SpellingMenuBarTests")!
        d.removePersistentDomain(forName: "SpellingMenuBarTests")
        let s = SpellingSettings(defaults: d)
        s.preference = pref
        return s
    }

    /// What PocketState.make draws for `raw` under `s` (spelling and selection).
    private func state(_ s: SpellingSettings, raw r: Result? = nil, advanced: Bool = false) -> PocketState {
        let raw = r ?? self.raw
        var p = PocketState()
        let shown = raw.respelled(s.preference, choice: s.manualKey)
        p.readout = .result(shown, page: nil, download: true, options: ResultOptions(
            factor: .one, tuning: Tuning.meter(12, reference: 440), onCycleTempo: {}))
        p.manualKey = ManualKey.of(s.manualKey, raw: raw)
        p.advanced = advanced
        return p
    }

    // MARK: the wheel spells like the dial

    func testWheelMatchesTheDialForAll24KeysInBothSpellings() {
        for pref in [KeySpelling.sharps, .flats] {
            for key in KeyChoice.allKeys {
                let s = settings(pref)
                XCTAssertTrue(s.setManualKey(key, of: raw, from: .wheel))
                let q = state(s)
                let w = HarmonyPanel.wheel(q, settings: s)
                let dial = try! XCTUnwrap(q.result?.keys.first?.0)
                let k = AutoTuneSend.keyClass(key)!
                XCTAssertEqual(w.name(k.pitchClass, minor: k.minor), dial, "\(key) \(pref)")
                // the hover card names it the same way
                let tip = w.tip(for: try! XCTUnwrap(w.manualSection))
                XCTAssertTrue(tip.title == dial || tip.title.hasPrefix(dial + " · "), "\(tip.title) vs \(dial)")
                // every top-3 key is named on the wheel as in the top-3 row
                for (name, _) in q.result?.keys.prefix(3) ?? [] {
                    let c = AutoTuneSend.keyClass(name)!
                    XCTAssertEqual(w.name(c.pitchClass, minor: c.minor), name, "\(key) \(pref) top-3")
                }
                // and every one of the 24 labels follows the chosen spelling
                for (pc, minor) in (0..<12).flatMap({ pc in [(pc, false), (pc, true)] }) {
                    XCTAssertEqual(w.name(pc, minor: minor),
                                   KeySpelling.respell(KeyChoice.keyName(pc, minor: minor), to: pref), "\(pc) \(minor) \(pref)")
                }
            }
        }
    }

    /// The renders' case (dial Gb, wheel F#): the analyzer's own spelling (no preference) and a
    /// reading that spells its key Gb. The wheel says Gb too, in its label, card and click.
    func testWheelUsesTheReadingsOwnSpellingWithNoPreference() {
        let s = settings(nil)
        s.setManualKey("F#", of: raw, from: .topKeys)
        let q = state(s)
        XCTAssertEqual(q.result?.keys.first?.0, "F#")
        let w = HarmonyPanel.wheel(q, settings: s)
        XCTAssertEqual(w.name(6, minor: false), "F#")
        XCTAssertTrue(w.tip(for: w.manualSection!).title.hasPrefix("F# · "))
        // not manual either: the runner-up Gb is Gb on the wheel
        let n = settings(nil)
        let w2 = HarmonyPanel.wheel(state(n), settings: n)
        XCTAssertEqual(w2.name(6, minor: false), "F#")
        XCTAssertTrue(w2.tip(for: 2 * 6).title.hasPrefix("F# · "), w2.tip(for: 12).title)   // slot 6 = Gb/F#
        XCTAssertTrue(w2.info(3, minor: true).title.hasPrefix("Ebm"))
        // a key the reading does not list: the analyzer's own (Auto-Tune's) name
        XCTAssertEqual(w2.name(1, minor: true), "C#m")
    }

    func testAReadingKeyThatDoesNotResolveFallsBack() {
        let odd = Result(file: raw.file, name: raw.name, bpm: "120", keys: [("H", 50), ("F#", 30)], bpmExact: 120)
        XCTAssertEqual(KeyWheel.name(6, minor: false, keys: odd.keys, spelling: nil), "F#")
        XCTAssertEqual(KeyWheel.name(11, minor: false, keys: odd.keys, spelling: .flats), "B")
        XCTAssertEqual(KeyWheel.name(1, minor: false, keys: odd.keys, spelling: .sharps), "C#")
    }

    /// Auto-Tune still gets its own spelling, whatever the wheel shows.
    func testAutoTuneSendIsUnchanged() {
        XCTAssertEqual(KeyChoice.keyName(6, minor: false), "F#")
        XCTAssertEqual(KeyChoice.keyName(1, minor: false), "Db")
    }

    // MARK: the menu-bar item in Manual Key Selection

    func testMenuBarManualDetectedKey() {
        let s = settings()
        s.setManualKey("F#", of: raw, from: .topKeys)
        let m = MenuBarReadout.of(raw, choice: s.manualKey)
        XCTAssertEqual(m.text, "F# 142.0")
        XCTAssertTrue(m.manual)
        XCTAssertNil(m.lamp)                                       // no UNSURE (12 %) lamp
        XCTAssertTrue(m.detail.hasSuffix("Manual"), m.detail)
        XCTAssertFalse(m.detail.uppercased().contains("UNSURE"))
        XCTAssertTrue(m.accessibilityLabel.hasSuffix(", selected manually"), m.accessibilityLabel)
        // in the chosen spelling
        XCTAssertEqual(MenuBarReadout.of(raw, spelling: .sharps, choice: s.manualKey).text, "F# 142.0")
    }

    func testMenuBarManualUndetectedKey() {
        let s = settings()
        s.setManualKey("Am", of: raw, from: .wheel)
        let m = MenuBarReadout.of(.done(raw), page: 0, factor: .one, choice: s.manualKey)
        XCTAssertEqual(m.text, "Am 142.0")
        XCTAssertTrue(m.manual)
        XCTAssertNil(m.lamp)                                       // was UNSURE at 0 %
        XCTAssertFalse(m.detail.contains("0%"), m.detail)
        XCTAssertNotNil(MenuBarImage.make(m.lamp, manual: m.manual))
    }

    func testMenuBarNotManualIsUnchanged() {
        let m = MenuBarReadout.of(raw, choice: nil)
        XCTAssertEqual(m.text, "Ebm 142.0")
        XCTAssertFalse(m.manual)
        XCTAssertEqual(m.lamp, Lamp.of(raw.keys))
        // a selection that belongs to another reading: not manual here
        let other = Result(file: URL(fileURLWithPath: "/x/other.wav"), name: "other.wav", bpm: "90", keys: [("Am", 70)], bpmExact: 90)
        let s = settings()
        s.setManualKey("F#", of: other, from: .wheel)
        let n = MenuBarReadout.of(raw, choice: s.manualKey)
        XCTAssertFalse(n.manual)
        XCTAssertEqual(n.text, "Ebm 142.0")
    }

    func testMenuBarManualWhileListeningShowsTheKeyAtOnce() {
        let live = Result(file: LiveSession.songFile(1), name: "LIVE", bpm: "128.0",
                          keys: [("Cm", 41), ("Eb", 20)], bpmExact: 128.02)
        // unsure, not manual: no key yet
        XCTAssertNil(MenuBarReadout.of(live: .reading(live), source: "Mic", factor: .one, choice: nil)?.text)
        let s = settings()
        s.setManualKey("F#", of: live, from: .keyboard)
        let m = MenuBarReadout.of(live: .reading(live), source: "Mic", factor: .one, choice: s.manualKey)
        XCTAssertEqual(m?.text, "F# 128.0")   // not in the reading: the analyzer's own name, as the dial
        XCTAssertEqual(m?.manual, true)
        XCTAssertNil(m?.lamp)
    }

    func testMenuBarManualSwitchLogLines() {
        let s = settings()
        s.setManualKey("F#", of: raw, from: .topKeys)
        XCTAssertEqual(StatusItemController.manualSwitchLine(MenuBarReadout.of(raw, choice: s.manualKey)),
                       "menu-bar item: manual key F# 142.0 (white key, no lamp)")
        XCTAssertTrue(StatusItemController.manualSwitchLine(MenuBarReadout.of(raw, choice: nil))
            .hasPrefix("menu-bar item: manual off; showing Ebm 142.0"))
    }

    func testManualInkIsNeutral() {
        let w = MenuBarImage.manualInk(dark: true)
        XCTAssertGreaterThan(w.redComponent, 0.94)
        XCTAssertEqual(w.redComponent, w.blueComponent, accuracy: 0.02)
        let b = MenuBarImage.manualInk(dark: false)
        XCTAssertLessThan(b.redComponent, 0.2)
    }

    // MARK: renders (ORION_SNAPSHOT_DIR=<dir> swift test --filter SpellingMenuBarTests/testRender)

    @MainActor
    func testRenderSpellingAndMenuBar() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORION_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ORION_SNAPSHOT_DIR to write the spelling / menu-bar PNGs")
        }
        guard #available(macOS 13.0, *) else { throw XCTSkip("ImageRenderer is macOS 13+") }
        let shared = SpellingSettings.shared
        let (savedPref, savedManual) = (shared.preference, shared.manualKey)
        Pocket.snapshot = true
        defer {
            Pocket.snapshot = false; Theme.accent = .amber
            shared.preference = savedPref; shared.manualKey = savedManual
        }
        Theme.accent = .amber
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
        // the window, Advanced, manual Gb (a black-key major), in each spelling
        for (pref, tag) in [(KeySpelling?.none, "own"), (.flats, "flats"), (.sharps, "sharps")] {
            shared.preference = pref
            let s = settings(pref)
            s.setManualKey("F#", of: raw, from: .topKeys)
            var q = state(s, advanced: true)
            q.source = "System Audio"
            try write(window(q), "window-advanced-manual-Gb-\(tag)")
            try write(window(q, hover: "wheel"), "window-advanced-manual-Gb-\(tag)-wheel-hover")
        }
        shared.preference = savedPref

        // the menu-bar item: not manual, manual (detected), manual (never detected), on a dark and a light bar
        let s = settings()
        let rows: [(String, MenuBarReadout)] = [
            ("not-manual", MenuBarReadout.of(raw, choice: nil)),
            ("manual-detected", { s.setManualKey("F#", of: raw, from: .topKeys); return MenuBarReadout.of(raw, choice: s.manualKey) }()),
            ("manual-undetected", { s.setManualKey("Am", of: raw, from: .wheel); return MenuBarReadout.of(raw, choice: s.manualKey) }()),
        ]
        for dark in [true, false] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            let rowH: CGFloat = 24, width = StatusItemController.fixedWidth(font: font) + 150
            let size = NSSize(width: width, height: rowH * CGFloat(rows.count))
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            appearance.performAsCurrentDrawingAppearance {
                (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                NSRect(origin: .zero, size: size).fill()
                for (i, row) in rows.enumerated() {
                    let y = size.height - rowH * CGFloat(i + 1)
                    let ink = dark ? NSColor.white : NSColor.black
                    let quiet = row.1.text == nil
                    let text = NSAttributedString(string: (row.1.text ?? "") + " ", attributes: [
                        .font: font, .foregroundColor: quiet ? ink.withAlphaComponent(0.5) : ink])
                    text.draw(at: NSPoint(x: 8, y: y + 4))
                    let img = MenuBarImage.make(row.1.lamp, manual: row.1.manual)!
                    img.draw(in: NSRect(x: 8 + text.size().width, y: y + 6, width: img.size.width, height: img.size.height))
                    NSAttributedString(string: row.0, attributes: [.font: NSFont.systemFont(ofSize: 10),
                                                                    .foregroundColor: ink.withAlphaComponent(0.6)])
                        .draw(at: NSPoint(x: StatusItemController.fixedWidth(font: font) + 20, y: y + 6))
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: out.appendingPathComponent("menubar-item-\(dark ? "dark" : "light").png"))
        }
    }
}
