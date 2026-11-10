import AppKit
import SwiftUI
import XCTest
@testable import Orion

/// COLOR (the display colour) and the per-surface ADVANCED box (J 2026-11-09).
final class AccentTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "AccentTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: colour

    func testAmberIsTheDefaultAndMatchesTheDesign() {
        let a = AccentSettings(defaults: defaults)
        XCTAssertEqual(a.picked, .amber)
        XCTAssertEqual(a.effective, .amber)
        XCTAssertFalse(a.clamped)
        // the design numbers: amber reads 10.8:1 on the LCD, its ink is #1a1206
        XCTAssertEqual(Accent.amber.contrast(with: .lcd), 10.8, accuracy: 0.1)
        XCTAssertEqual(Accent.amber.ink, Accent.amberInk)
        XCTAssertEqual(Palette().accent.r, 255); XCTAssertEqual(Palette().accent.g, 176); XCTAssertEqual(Palette().accent.b, 32)
    }

    func testPersistenceRoundTrip() {
        let a = AccentSettings(defaults: defaults)
        let blue = Accent(80, 170, 255)
        a.set(blue)
        XCTAssertEqual(defaults.array(forKey: AccentSettings.key) as? [Double], [80, 170, 255])
        XCTAssertEqual(a.effective, blue)
        let b = AccentSettings(defaults: defaults)      // the next launch
        XCTAssertEqual(b.picked, blue)
        XCTAssertEqual(b.effective, blue)
    }

    func testUnreadableStoredValueFallsBackToAmber() {
        defaults.set("purple", forKey: AccentSettings.key)
        XCTAssertEqual(AccentSettings(defaults: defaults).picked, .amber)
        defaults.set([1.0, 2.0], forKey: AccentSettings.key)
        XCTAssertEqual(AccentSettings(defaults: defaults).picked, .amber)
    }

    func testReset() {
        let a = AccentSettings(defaults: defaults)
        a.set(Accent(60, 220, 120))
        a.reset()
        XCTAssertEqual(a.picked, .amber)
        XCTAssertEqual(a.effective, .amber)
        XCTAssertNil(defaults.object(forKey: AccentSettings.key))
        XCTAssertEqual(AccentSettings(defaults: defaults).picked, .amber)
    }

    func testInkFollowsLuminance() {
        // light fills take dark ink (the colour at a tenth), dark fills take light ink
        for light in [Accent(255, 255, 120), Accent(120, 255, 160), Accent(160, 200, 255)] {
            XCTAssertLessThan(light.ink.luminance, 0.05, "\(light.described)")
            XCTAssertGreaterThan(light.contrast(with: light.ink), 7)
        }
        for dark in [Accent(20, 20, 140), Accent(90, 0, 40), Accent(30, 30, 30)] {
            XCTAssertEqual(dark.ink, Accent.lightInk, "\(dark.described)")
        }
        // every step derives from the accent; ink too
        XCTAssertEqual(NSColor(Palette(accent: Accent(255, 255, 120)).ink).usingColorSpace(.sRGB)!.redComponent, 25.5 / 255, accuracy: 0.01)
    }

    func testDarkPickIsLiftedToReadOnTheLCD() {
        let a = AccentSettings(defaults: defaults)
        let navy = Accent(10, 20, 90)
        a.set(navy)
        XCTAssertTrue(a.clamped)
        XCTAssertEqual(a.picked, navy, "the wheel keeps what J picked")
        XCTAssertGreaterThanOrEqual(a.effective.contrast(with: .lcd), Accent.minContrast - 0.01)
        XCTAssertLessThan(a.effective.contrast(with: .lcd), Accent.minContrast + 0.2, "lifted just enough")
        // the hue survives the lift
        XCTAssertEqual(a.effective.hsb.0, navy.hsb.0, accuracy: 0.01)
        // pure blue cannot get there on brightness alone: it goes paler instead
        let (b, clamped) = Accent(0, 0, 255).readable()
        XCTAssertTrue(clamped)
        XCTAssertGreaterThanOrEqual(b.contrast(with: .lcd), Accent.minContrast - 0.01)
        XCTAssertEqual(b.b, 255, accuracy: 0.5)
        // black lifts too (no hue: a grey)
        XCTAssertGreaterThanOrEqual(Accent(0, 0, 0).readable().accent.contrast(with: .lcd), Accent.minContrast - 0.01)
        // a readable pick is left alone
        XCTAssertFalse(Accent(120, 255, 160).readable().clamped)
        a.set(.amber)
        XCTAssertFalse(a.clamped)
    }

    func testStepsAndHighContrastFollowTheAccent() {
        var p = Palette(accent: Accent(60, 220, 120))
        let a2 = NSColor(p.a2).usingColorSpace(.sRGB)!
        XCTAssertEqual(a2.greenComponent, 220 / 255, accuracy: 0.01)
        XCTAssertEqual(a2.alphaComponent, 0.75, accuracy: 0.01)
        p.highContrast = true
        XCTAssertEqual(NSColor(p.a2).usingColorSpace(.sRGB)!.alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(NSColor(p.amber(0.62)).usingColorSpace(.sRGB)!.alphaComponent, 1, accuracy: 0.01)
    }

    func testDragIsCoalescedAndTheLastPickLands() {
        let a = AccentSettings(defaults: defaults)
        a.set(.amber)                              // just applied: the next drags wait their turn
        a.drag(Accent(255, 0, 0))
        a.drag(Accent(0, 255, 0))
        a.drag(Accent(120, 200, 255))
        let end = Date().addingTimeInterval(0.3)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(a.picked, Accent(120, 200, 255))
    }

    func testPanelColourConvertsToSRGB() {
        let c = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.9, alpha: 1)
        XCTAssertNotNil(Accent(c))
        XCTAssertEqual(Accent(NSColor(srgbRed: 1, green: 176 / 255, blue: 32 / 255, alpha: 1)), .amber)
    }

    func testHelpLines() {
        XCTAssertTrue(HelpText.all.contains { $0.title == "COLOR" })
        XCTAssertTrue(HelpText.all.contains { $0.title == "ADVANCED" })
        XCTAssertEqual(HelpText.problems(), [])
    }

    // MARK: ADVANCED: first change this launch sets both, later ones only their own

    func testOldAdvancedSettingMigratesIntoBoth() {
        defaults.set(true, forKey: DisplaySettings.advancedKey)
        let d = DisplaySettings(defaults: defaults)
        XCTAssertTrue(d.advanced)
        XCTAssertTrue(d.pocketAdvanced)
        XCTAssertEqual(defaults.object(forKey: DisplaySettings.pocketAdvancedKey) as? Bool, true)
    }

    func testFirstToggleSetsBothThenEachOnItsOwn() {
        let d = DisplaySettings(defaults: defaults)
        XCTAssertFalse(d.advanced); XCTAssertFalse(d.pocketAdvanced)
        d.pocketAdvanced.toggle()                         // first change, from the menu bar
        XCTAssertTrue(d.advanced); XCTAssertTrue(d.pocketAdvanced)
        d.pocketAdvanced.toggle()                         // second: the menu bar only
        XCTAssertTrue(d.advanced); XCTAssertFalse(d.pocketAdvanced)
        d.advanced.toggle()                               // third, from the window: the window only
        XCTAssertFalse(d.advanced); XCTAssertFalse(d.pocketAdvanced)
        d.advanced.toggle()
        XCTAssertTrue(d.advanced); XCTAssertFalse(d.pocketAdvanced)
        // both persisted on their own
        XCTAssertEqual(defaults.bool(forKey: DisplaySettings.advancedKey), true)
        XCTAssertEqual(defaults.bool(forKey: DisplaySettings.pocketAdvancedKey), false)

        // the next launch starts over: its first change links again
        let next = DisplaySettings(defaults: defaults)
        XCTAssertTrue(next.advanced); XCTAssertFalse(next.pocketAdvanced)
        XCTAssertFalse(next.advancedLinkUsed)
        next.advanced.toggle()                            // window (also ⌥⌘A, Settings): both off
        XCTAssertFalse(next.advanced); XCTAssertFalse(next.pocketAdvanced)
        next.pocketAdvanced.toggle()
        XCTAssertFalse(next.advanced); XCTAssertTrue(next.pocketAdvanced)
    }

    func testFirstChangeSetsBothToTheNewValueEvenWhenTheyDiffered() {
        defaults.set(true, forKey: DisplaySettings.advancedKey)
        defaults.set(false, forKey: DisplaySettings.pocketAdvancedKey)
        let d = DisplaySettings(defaults: defaults)
        d.pocketAdvanced = true                           // the window is on already: both on
        XCTAssertTrue(d.advanced); XCTAssertTrue(d.pocketAdvanced)
        XCTAssertTrue(d.advancedLinkUsed)
    }

    func testSettingTheSameValueIsNotAChange() {
        let d = DisplaySettings(defaults: defaults)
        d.advanced = false
        XCTAssertFalse(d.advancedLinkUsed)
    }

    // MARK: offscreen renders (ORION_SNAPSHOT_DIR=<dir> swift test --filter AccentTests/testRender)

    @MainActor
    func testRenderColours() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORION_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ORION_SNAPSHOT_DIR to write the colour PNGs")
        }
        guard #available(macOS 13.0, *) else { throw XCTSkip("ImageRenderer is macOS 13+") }
        Pocket.snapshot = true
        defer { Pocket.snapshot = false }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var palette = Palette()
        func write<V: View>(_ v: V, _ name: String, crop bottom: CGFloat? = nil) throws {
            let r = ImageRenderer(content: v.environment(\.palette, palette).environment(\.colorScheme, .dark))
            r.scale = 2
            guard var cg = r.cgImage else { return XCTFail("no image for \(name)") }
            if let b = bottom, let c = cg.cropping(to: CGRect(x: 0, y: CGFloat(cg.height) - b * 2,
                                                             width: CGFloat(cg.width), height: b * 2)) { cg = c }
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
            try png.write(to: out.appendingPathComponent("\(name).png"))
        }

        let chroma = [0.2, 0.05, 0.3, 0.9, 0.1, 0.4, 0.08, 0.7, 0.15, 0.3, 0.85, 0.1]
        let r = Result(file: URL(fileURLWithPath: "/x/Beats/Beat A.wav"), name: "Beat A.wav", bpm: "128.0",
                       keys: [("Ebm", 86), ("Gb", 9), ("Bbm", 5)], bpmExact: 128.04, tuningCents: 12, chroma: chroma)
        var s = PocketState()
        s.source = "System Audio"
        s.daw = "Pro Tools"
        s.readout = .result(r, page: nil, download: true, options: ResultOptions(
            factor: .one, tuning: Tuning.meter(12, reference: 440), onCycleTempo: {}))
        s.recents = [Reading(r)]
        s.harmony = HarmonyPrefs(matchKey: "Fm")
        var adv = s
        adv.advanced = true

        let picks: [(String, Accent)] = [("amber", .amber), ("blue", Accent(70, 150, 255)), ("green", Accent(60, 225, 120))]
        for (name, a) in picks {
            palette.accent = a.readable().accent
            try write(FaceplateFace(state: s, picked: [], url: .constant(""), fieldFocused: .constant(false),
                                    pickFocused: .constant(false)), "window-\(name)")
            try write(PocketView(state: s, url: .constant("")), "pocket-\(name)")
        }
        palette.accent = .amber
        try write(FaceplateFace(state: adv, picked: [], url: .constant(""), fieldFocused: .constant(false),
                                pickFocused: .constant(false)), "window-advanced-amber")
        try write(FaceplateFace(state: s, picked: [], url: .constant(""), fieldFocused: .constant(false),
                                pickFocused: .constant(false)), "window-footer", crop: 44)
        try write(PocketView(state: s, url: .constant("")), "pocket-advanced-off")
        try write(PocketView(state: adv, url: .constant("")), "pocket-advanced-on")
        try write(PocketView(state: s, url: .constant("")), "pocket-footer", crop: 40)
        palette.accent = Accent(70, 150, 255).readable().accent
        try write(PocketView(state: adv, url: .constant("")), "pocket-advanced-on-blue")
        // a too-dark pick as shown (navy, lifted)
        palette.accent = Accent(10, 20, 90).readable().accent
        try write(FaceplateFace(state: s, picked: [], url: .constant(""), fieldFocused: .constant(false),
                                pickFocused: .constant(false)), "window-navy-lifted")
    }
}
