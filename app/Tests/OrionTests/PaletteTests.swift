import AppKit
import SwiftUI
import XCTest
@testable import Orion

/// The display colour and High Contrast come through the SwiftUI environment (`\.palette`), filled
/// at each surface's root from AccentSettings and DisplaySettings. A change redraws what reads them
/// and nothing is thrown away: no view loses its identity or its state (a held Mini pad stays held).
final class PaletteTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "PaletteTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: the colours themselves: identical to the values the old Theme statics gave

    /// sRGB components x 1000, rounded.
    private func q(_ c: Color) -> [Int] {
        let n = NSColor(c).usingColorSpace(.sRGB)!
        return [n.redComponent, n.greenComponent, n.blueComponent, n.alphaComponent].map { Int(($0 * 1000).rounded()) }
    }

    /// Pinned from Theme.amber / amber(a) / amberGlow / A.a1-a5 / A.ink / amberNS / accent.litCap,
    /// Lamp.unsure and ManualLook.white / glow with Theme.accent and Theme.highContrast set, before
    /// those statics went (2026-11-10). Every value must be the same through Palette.
    static let pinned: [(String, Bool, String, [Int])] = [
            ("amber", false, "amber", [1000, 690, 125, 1000]),
            ("amber", false, "amber(0.12)", [1000, 690, 125, 120]),
            ("amber", false, "amber(0.35)", [1000, 690, 125, 350]),
            ("amber", false, "amber(0.4)", [1000, 690, 125, 400]),
            ("amber", false, "amber(0.7)", [1000, 690, 125, 700]),
            ("amber", false, "amberGlow", [1000, 690, 125, 600]),
            ("amber", false, "a1", [1000, 690, 125, 1000]),
            ("amber", false, "a2", [1000, 690, 125, 750]),
            ("amber", false, "a3", [1000, 690, 125, 620]),
            ("amber", false, "a4", [1000, 690, 125, 160]),
            ("amber", false, "a5", [1000, 690, 125, 60]),
            ("amber", false, "ink", [102, 71, 24, 1000]),
            ("amber", false, "amberNS", [1000, 690, 125, 1000]),
            ("amber", false, "litTop", [1000, 894, 651, 1000]),
            ("amber", false, "litMid", [969, 702, 169, 1000]),
            ("amber", false, "litBottom", [753, 498, 71, 1000]),
            ("amber", false, "litLegend", [227, 165, 24, 1000]),
            ("amber", false, "unsureColor", [1000, 690, 125, 1000]),
            ("amber", false, "unsureText", [1000, 690, 125, 1000]),
            ("amber", false, "unsureNS", [1000, 690, 125, 1000]),
            ("amber", false, "manualWhite", [957, 957, 969, 1000]),
            ("amber", false, "manualGlow", [1000, 1000, 1000, 550]),
            ("amber", true, "amber", [1000, 690, 125, 1000]),
            ("amber", true, "amber(0.12)", [1000, 690, 125, 300]),
            ("amber", true, "amber(0.35)", [1000, 690, 125, 350]),
            ("amber", true, "amber(0.4)", [1000, 690, 125, 1000]),
            ("amber", true, "amber(0.7)", [1000, 690, 125, 1000]),
            ("amber", true, "amberGlow", [1000, 690, 125, 600]),
            ("amber", true, "a1", [1000, 690, 125, 1000]),
            ("amber", true, "a2", [1000, 690, 125, 1000]),
            ("amber", true, "a3", [1000, 690, 125, 1000]),
            ("amber", true, "a4", [1000, 690, 125, 300]),
            ("amber", true, "a5", [1000, 690, 125, 120]),
            ("amber", true, "ink", [102, 71, 24, 1000]),
            ("amber", true, "amberNS", [1000, 690, 125, 1000]),
            ("amber", true, "litTop", [1000, 894, 651, 1000]),
            ("amber", true, "litMid", [969, 702, 169, 1000]),
            ("amber", true, "litBottom", [753, 498, 71, 1000]),
            ("amber", true, "litLegend", [227, 165, 24, 1000]),
            ("amber", true, "unsureColor", [1000, 690, 125, 1000]),
            ("amber", true, "unsureText", [1000, 690, 125, 1000]),
            ("amber", true, "unsureNS", [1000, 690, 125, 1000]),
            ("amber", true, "manualWhite", [1000, 1000, 1000, 1000]),
            ("amber", true, "manualGlow", [0, 0, 0, 0]),
            ("blue", false, "amber", [314, 667, 1000, 1000]),
            ("blue", false, "amber(0.12)", [314, 667, 1000, 120]),
            ("blue", false, "amber(0.35)", [314, 667, 1000, 350]),
            ("blue", false, "amber(0.4)", [314, 667, 1000, 400]),
            ("blue", false, "amber(0.7)", [314, 667, 1000, 700]),
            ("blue", false, "amberGlow", [314, 667, 1000, 600]),
            ("blue", false, "a1", [314, 667, 1000, 1000]),
            ("blue", false, "a2", [314, 667, 1000, 750]),
            ("blue", false, "a3", [314, 667, 1000, 620]),
            ("blue", false, "a4", [314, 667, 1000, 160]),
            ("blue", false, "a5", [314, 667, 1000, 60]),
            ("blue", false, "ink", [31, 67, 100, 1000]),
            ("blue", false, "amberNS", [314, 667, 1000, 1000]),
            ("blue", false, "litTop", [725, 867, 1000, 1000]),
            ("blue", false, "litMid", [314, 667, 1000, 1000]),
            ("blue", false, "litBottom", [235, 500, 750, 1000]),
            ("blue", false, "litLegend", [72, 153, 230, 1000]),
            ("blue", false, "unsureColor", [314, 667, 1000, 1000]),
            ("blue", false, "unsureText", [314, 667, 1000, 1000]),
            ("blue", false, "unsureNS", [314, 667, 1000, 1000]),
            ("blue", false, "manualWhite", [957, 957, 969, 1000]),
            ("blue", false, "manualGlow", [1000, 1000, 1000, 550]),
            ("blue", true, "amber", [314, 667, 1000, 1000]),
            ("blue", true, "amber(0.12)", [314, 667, 1000, 300]),
            ("blue", true, "amber(0.35)", [314, 667, 1000, 350]),
            ("blue", true, "amber(0.4)", [314, 667, 1000, 1000]),
            ("blue", true, "amber(0.7)", [314, 667, 1000, 1000]),
            ("blue", true, "amberGlow", [314, 667, 1000, 600]),
            ("blue", true, "a1", [314, 667, 1000, 1000]),
            ("blue", true, "a2", [314, 667, 1000, 1000]),
            ("blue", true, "a3", [314, 667, 1000, 1000]),
            ("blue", true, "a4", [314, 667, 1000, 300]),
            ("blue", true, "a5", [314, 667, 1000, 120]),
            ("blue", true, "ink", [31, 67, 100, 1000]),
            ("blue", true, "amberNS", [314, 667, 1000, 1000]),
            ("blue", true, "litTop", [725, 867, 1000, 1000]),
            ("blue", true, "litMid", [314, 667, 1000, 1000]),
            ("blue", true, "litBottom", [235, 500, 750, 1000]),
            ("blue", true, "litLegend", [72, 153, 230, 1000]),
            ("blue", true, "unsureColor", [314, 667, 1000, 1000]),
            ("blue", true, "unsureText", [314, 667, 1000, 1000]),
            ("blue", true, "unsureNS", [314, 667, 1000, 1000]),
            ("blue", true, "manualWhite", [1000, 1000, 1000, 1000]),
            ("blue", true, "manualGlow", [0, 0, 0, 0]),
            ("green", false, "amber", [235, 882, 471, 1000]),
            ("green", false, "amber(0.12)", [235, 882, 471, 120]),
            ("green", false, "amber(0.35)", [235, 882, 471, 350]),
            ("green", false, "amber(0.4)", [235, 882, 471, 400]),
            ("green", false, "amber(0.7)", [235, 882, 471, 700]),
            ("green", false, "amberGlow", [235, 882, 471, 600]),
            ("green", false, "a1", [235, 882, 471, 1000]),
            ("green", false, "a2", [235, 882, 471, 750]),
            ("green", false, "a3", [235, 882, 471, 620]),
            ("green", false, "a4", [235, 882, 471, 160]),
            ("green", false, "a5", [235, 882, 471, 60]),
            ("green", false, "ink", [24, 88, 47, 1000]),
            ("green", false, "amberNS", [235, 882, 471, 1000]),
            ("green", false, "litTop", [694, 953, 788, 1000]),
            ("green", false, "litMid", [235, 882, 471, 1000]),
            ("green", false, "litBottom", [176, 662, 353, 1000]),
            ("green", false, "litLegend", [54, 203, 108, 1000]),
            ("green", false, "unsureColor", [235, 882, 471, 1000]),
            ("green", false, "unsureText", [235, 882, 471, 1000]),
            ("green", false, "unsureNS", [235, 882, 471, 1000]),
            ("green", false, "manualWhite", [957, 957, 969, 1000]),
            ("green", false, "manualGlow", [1000, 1000, 1000, 550]),
            ("green", true, "amber", [235, 882, 471, 1000]),
            ("green", true, "amber(0.12)", [235, 882, 471, 300]),
            ("green", true, "amber(0.35)", [235, 882, 471, 350]),
            ("green", true, "amber(0.4)", [235, 882, 471, 1000]),
            ("green", true, "amber(0.7)", [235, 882, 471, 1000]),
            ("green", true, "amberGlow", [235, 882, 471, 600]),
            ("green", true, "a1", [235, 882, 471, 1000]),
            ("green", true, "a2", [235, 882, 471, 1000]),
            ("green", true, "a3", [235, 882, 471, 1000]),
            ("green", true, "a4", [235, 882, 471, 300]),
            ("green", true, "a5", [235, 882, 471, 120]),
            ("green", true, "ink", [24, 88, 47, 1000]),
            ("green", true, "amberNS", [235, 882, 471, 1000]),
            ("green", true, "litTop", [694, 953, 788, 1000]),
            ("green", true, "litMid", [235, 882, 471, 1000]),
            ("green", true, "litBottom", [176, 662, 353, 1000]),
            ("green", true, "litLegend", [54, 203, 108, 1000]),
            ("green", true, "unsureColor", [235, 882, 471, 1000]),
            ("green", true, "unsureText", [235, 882, 471, 1000]),
            ("green", true, "unsureNS", [235, 882, 471, 1000]),
            ("green", true, "manualWhite", [1000, 1000, 1000, 1000]),
            ("green", true, "manualGlow", [0, 0, 0, 0]),
            ("light", false, "amber", [1000, 1000, 471, 1000]),
            ("light", false, "amber(0.12)", [1000, 1000, 471, 120]),
            ("light", false, "amber(0.35)", [1000, 1000, 471, 350]),
            ("light", false, "amber(0.4)", [1000, 1000, 471, 400]),
            ("light", false, "amber(0.7)", [1000, 1000, 471, 700]),
            ("light", false, "amberGlow", [1000, 1000, 471, 600]),
            ("light", false, "a1", [1000, 1000, 471, 1000]),
            ("light", false, "a2", [1000, 1000, 471, 750]),
            ("light", false, "a3", [1000, 1000, 471, 620]),
            ("light", false, "a4", [1000, 1000, 471, 160]),
            ("light", false, "a5", [1000, 1000, 471, 60]),
            ("light", false, "ink", [100, 100, 47, 1000]),
            ("light", false, "amberNS", [1000, 1000, 471, 1000]),
            ("light", false, "litTop", [1000, 1000, 788, 1000]),
            ("light", false, "litMid", [1000, 1000, 471, 1000]),
            ("light", false, "litBottom", [750, 750, 353, 1000]),
            ("light", false, "litLegend", [230, 230, 108, 1000]),
            ("light", false, "unsureColor", [1000, 1000, 471, 1000]),
            ("light", false, "unsureText", [1000, 1000, 471, 1000]),
            ("light", false, "unsureNS", [1000, 1000, 471, 1000]),
            ("light", false, "manualWhite", [957, 957, 969, 1000]),
            ("light", false, "manualGlow", [1000, 1000, 1000, 550]),
            ("light", true, "amber", [1000, 1000, 471, 1000]),
            ("light", true, "amber(0.12)", [1000, 1000, 471, 300]),
            ("light", true, "amber(0.35)", [1000, 1000, 471, 350]),
            ("light", true, "amber(0.4)", [1000, 1000, 471, 1000]),
            ("light", true, "amber(0.7)", [1000, 1000, 471, 1000]),
            ("light", true, "amberGlow", [1000, 1000, 471, 600]),
            ("light", true, "a1", [1000, 1000, 471, 1000]),
            ("light", true, "a2", [1000, 1000, 471, 1000]),
            ("light", true, "a3", [1000, 1000, 471, 1000]),
            ("light", true, "a4", [1000, 1000, 471, 300]),
            ("light", true, "a5", [1000, 1000, 471, 120]),
            ("light", true, "ink", [100, 100, 47, 1000]),
            ("light", true, "amberNS", [1000, 1000, 471, 1000]),
            ("light", true, "litTop", [1000, 1000, 788, 1000]),
            ("light", true, "litMid", [1000, 1000, 471, 1000]),
            ("light", true, "litBottom", [750, 750, 353, 1000]),
            ("light", true, "litLegend", [230, 230, 108, 1000]),
            ("light", true, "unsureColor", [1000, 1000, 471, 1000]),
            ("light", true, "unsureText", [1000, 1000, 471, 1000]),
            ("light", true, "unsureNS", [1000, 1000, 471, 1000]),
            ("light", true, "manualWhite", [1000, 1000, 1000, 1000]),
            ("light", true, "manualGlow", [0, 0, 0, 0]),
            ("navyLifted", false, "amber", [507, 569, 1000, 1000]),
            ("navyLifted", false, "amber(0.12)", [507, 569, 1000, 120]),
            ("navyLifted", false, "amber(0.35)", [507, 569, 1000, 350]),
            ("navyLifted", false, "amber(0.4)", [507, 569, 1000, 400]),
            ("navyLifted", false, "amber(0.7)", [507, 569, 1000, 700]),
            ("navyLifted", false, "amberGlow", [507, 569, 1000, 600]),
            ("navyLifted", false, "a1", [507, 569, 1000, 1000]),
            ("navyLifted", false, "a2", [507, 569, 1000, 750]),
            ("navyLifted", false, "a3", [507, 569, 1000, 620]),
            ("navyLifted", false, "a4", [507, 569, 1000, 160]),
            ("navyLifted", false, "a5", [507, 569, 1000, 60]),
            ("navyLifted", false, "ink", [51, 57, 100, 1000]),
            ("navyLifted", false, "amberNS", [507, 569, 1000, 1000]),
            ("navyLifted", false, "litTop", [803, 827, 1000, 1000]),
            ("navyLifted", false, "litMid", [507, 569, 1000, 1000]),
            ("navyLifted", false, "litBottom", [380, 426, 750, 1000]),
            ("navyLifted", false, "litLegend", [117, 131, 230, 1000]),
            ("navyLifted", false, "unsureColor", [507, 569, 1000, 1000]),
            ("navyLifted", false, "unsureText", [507, 569, 1000, 1000]),
            ("navyLifted", false, "unsureNS", [507, 569, 1000, 1000]),
            ("navyLifted", false, "manualWhite", [957, 957, 969, 1000]),
            ("navyLifted", false, "manualGlow", [1000, 1000, 1000, 550]),
            ("navyLifted", true, "amber", [507, 569, 1000, 1000]),
            ("navyLifted", true, "amber(0.12)", [507, 569, 1000, 300]),
            ("navyLifted", true, "amber(0.35)", [507, 569, 1000, 350]),
            ("navyLifted", true, "amber(0.4)", [507, 569, 1000, 1000]),
            ("navyLifted", true, "amber(0.7)", [507, 569, 1000, 1000]),
            ("navyLifted", true, "amberGlow", [507, 569, 1000, 600]),
            ("navyLifted", true, "a1", [507, 569, 1000, 1000]),
            ("navyLifted", true, "a2", [507, 569, 1000, 1000]),
            ("navyLifted", true, "a3", [507, 569, 1000, 1000]),
            ("navyLifted", true, "a4", [507, 569, 1000, 300]),
            ("navyLifted", true, "a5", [507, 569, 1000, 120]),
            ("navyLifted", true, "ink", [51, 57, 100, 1000]),
            ("navyLifted", true, "amberNS", [507, 569, 1000, 1000]),
            ("navyLifted", true, "litTop", [803, 827, 1000, 1000]),
            ("navyLifted", true, "litMid", [507, 569, 1000, 1000]),
            ("navyLifted", true, "litBottom", [380, 426, 750, 1000]),
            ("navyLifted", true, "litLegend", [117, 131, 230, 1000]),
            ("navyLifted", true, "unsureColor", [507, 569, 1000, 1000]),
            ("navyLifted", true, "unsureText", [507, 569, 1000, 1000]),
            ("navyLifted", true, "unsureNS", [507, 569, 1000, 1000]),
            ("navyLifted", true, "manualWhite", [1000, 1000, 1000, 1000]),
            ("navyLifted", true, "manualGlow", [0, 0, 0, 0]),
            ("dark", false, "amber", [78, 78, 549, 1000]),
            ("dark", false, "amber(0.12)", [78, 78, 549, 120]),
            ("dark", false, "amber(0.35)", [78, 78, 549, 350]),
            ("dark", false, "amber(0.4)", [78, 78, 549, 400]),
            ("dark", false, "amber(0.7)", [78, 78, 549, 700]),
            ("dark", false, "amberGlow", [78, 78, 549, 600]),
            ("dark", false, "a1", [78, 78, 549, 1000]),
            ("dark", false, "a2", [78, 78, 549, 750]),
            ("dark", false, "a3", [78, 78, 549, 620]),
            ("dark", false, "a4", [78, 78, 549, 160]),
            ("dark", false, "a5", [78, 78, 549, 60]),
            ("dark", false, "ink", [965, 957, 933, 1000]),
            ("dark", false, "amberNS", [78, 78, 549, 1000]),
            ("dark", false, "litTop", [631, 631, 820, 1000]),
            ("dark", false, "litMid", [78, 78, 549, 1000]),
            ("dark", false, "litBottom", [59, 59, 412, 1000]),
            ("dark", false, "litLegend", [965, 957, 933, 1000]),
            ("dark", false, "unsureColor", [78, 78, 549, 1000]),
            ("dark", false, "unsureText", [78, 78, 549, 1000]),
            ("dark", false, "unsureNS", [78, 78, 549, 1000]),
            ("dark", false, "manualWhite", [957, 957, 969, 1000]),
            ("dark", false, "manualGlow", [1000, 1000, 1000, 550]),
            ("dark", true, "amber", [78, 78, 549, 1000]),
            ("dark", true, "amber(0.12)", [78, 78, 549, 300]),
            ("dark", true, "amber(0.35)", [78, 78, 549, 350]),
            ("dark", true, "amber(0.4)", [78, 78, 549, 1000]),
            ("dark", true, "amber(0.7)", [78, 78, 549, 1000]),
            ("dark", true, "amberGlow", [78, 78, 549, 600]),
            ("dark", true, "a1", [78, 78, 549, 1000]),
            ("dark", true, "a2", [78, 78, 549, 1000]),
            ("dark", true, "a3", [78, 78, 549, 1000]),
            ("dark", true, "a4", [78, 78, 549, 300]),
            ("dark", true, "a5", [78, 78, 549, 120]),
            ("dark", true, "ink", [965, 957, 933, 1000]),
            ("dark", true, "amberNS", [78, 78, 549, 1000]),
            ("dark", true, "litTop", [631, 631, 820, 1000]),
            ("dark", true, "litMid", [78, 78, 549, 1000]),
            ("dark", true, "litBottom", [59, 59, 412, 1000]),
            ("dark", true, "litLegend", [965, 957, 933, 1000]),
            ("dark", true, "unsureColor", [78, 78, 549, 1000]),
            ("dark", true, "unsureText", [78, 78, 549, 1000]),
            ("dark", true, "unsureNS", [78, 78, 549, 1000]),
            ("dark", true, "manualWhite", [1000, 1000, 1000, 1000]),
            ("dark", true, "manualGlow", [0, 0, 0, 0]),
    ]

    static let accents: [String: Accent] = [
        "amber": .amber, "blue": Accent(80, 170, 255), "green": Accent(60, 225, 120),
        "light": Accent(255, 255, 120), "navyLifted": Accent(10, 20, 90).readable().accent, "dark": Accent(20, 20, 140),
    ]

    func testColoursMatchTheValuesPinnedBeforeTheChange() {
        XCTAssertEqual(PaletteTests.pinned.count, 264)
        for (name, hc, what, want) in PaletteTests.pinned {
            let a = PaletteTests.accents[name]!
            let p = Palette(accent: a, highContrast: hc)
            let got: Color
            switch what {
            case "amber": got = p.amber
            case "amber(0.12)": got = p.amber(0.12)
            case "amber(0.35)": got = p.amber(0.35)
            case "amber(0.4)": got = p.amber(0.4)
            case "amber(0.7)": got = p.amber(0.7)
            case "amberGlow": got = p.amberGlow
            case "a1": got = p.a1
            case "a2": got = p.a2
            case "a3": got = p.a3
            case "a4": got = p.a4
            case "a5": got = p.a5
            case "ink": got = p.ink
            case "amberNS": got = Color(p.amberNS)
            case "litTop": got = p.accent.litCap.top.color
            case "litMid": got = p.accent.litCap.mid.color
            case "litBottom": got = p.accent.litCap.bottom.color
            case "litLegend": got = p.accent.litCap.legend.color
            case "unsureColor": got = Lamp.unsure.color(p.accent)
            case "unsureText": got = Lamp.unsure.textColor(p.accent)
            case "unsureNS": got = Color(Lamp.unsure.nsColor(p.accent))
            case "manualWhite": got = p.manualWhite
            case "manualGlow": got = p.manualGlow
            default: XCTFail("unknown pinned value \(what)"); continue
            }
            XCTAssertEqual(q(got), want, "\(name) hc=\(hc) \(what)")
        }
    }

    func testTheDefaultIsAmberWithoutHighContrast() {
        XCTAssertEqual(EnvironmentValues().palette, Palette(accent: .amber, highContrast: false))
    }

    // MARK: a surface's root: a change redraws, nothing is rebuilt

    /// What a probe hosted under a surface's root saw.
    final class Log {
        var palettes: [Palette] = []
        var appears = 0
        var disappears = 0
        /// Releases fired by the probe's own onDisappear while "held" (MiniPadView's old pattern).
        var releases = 0
        /// The probe's @State as each body run saw it.
        var heldSeen: [Bool] = []
    }

    /// Stands in for any view on a surface: reads the palette, keeps @State, and (like a Mini
    /// pad) is "held" from the moment it appears and would release if it were thrown away.
    struct Probe: View {
        let log: Log
        @Environment(\.palette) private var palette
        @State private var held = false

        var body: some View {
            log.palettes.append(palette)
            log.heldSeen.append(held)
            return Color.clear.frame(width: 20, height: 20)
                .onAppear { log.appears += 1; held = true }
                .onDisappear { log.disappears += 1; if held { log.releases += 1 } }
        }
    }

    /// Hosts the probe under the root modifier every surface uses (`.paletteRoot(_:display:)`), laid
    /// out in a window that is never shown.
    @MainActor
    private func host(_ log: Log, accent: AccentSettings, display: DisplaySettings) -> (NSWindow, NSView) {
        let host = NSHostingView(rootView: Probe(log: log).paletteRoot(accent, display: display))
        host.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        settle(host) { log.appears >= 1 }
        return (win, host)
    }

    /// Lays out and turns the run loop until `done` holds (a condition, not a duration).
    @MainActor
    private func settle(_ host: NSView, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(30)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        } while !done() && Date() < deadline
    }

    @MainActor
    func testANewColourRedrawsWithoutRebuilding() {
        let accent = AccentSettings(defaults: defaults)
        let display = DisplaySettings(defaults: defaults)
        let log = Log()
        let (win, host) = host(log, accent: accent, display: display)
        defer { win.contentView = nil }
        XCTAssertEqual(log.appears, 1)
        XCTAssertEqual(log.palettes.last?.accent, .amber)

        let blue = Accent(80, 170, 255)
        accent.set(blue)
        settle(host) { log.palettes.last?.accent == blue && log.heldSeen.last == true }
        XCTAssertEqual(log.palettes.last?.accent, blue, "the view did not get the new colour")
        XCTAssertEqual(log.appears, 1, "a new colour rebuilt the view (it appeared again)")
        XCTAssertEqual(log.disappears, 0, "a new colour threw the view away")
        XCTAssertEqual(log.heldSeen.last, true, "the view's @State did not survive the new colour")
    }

    @MainActor
    func testHighContrastRedrawsWithoutRebuilding() {
        let accent = AccentSettings(defaults: defaults)
        let display = DisplaySettings(defaults: defaults)
        let log = Log()
        let (win, host) = host(log, accent: accent, display: display)
        defer { win.contentView = nil }
        XCTAssertEqual(log.palettes.last?.highContrast, false)

        display.highContrast = true
        settle(host) { log.palettes.last?.highContrast == true && log.heldSeen.last == true }
        XCTAssertEqual(log.palettes.last?.highContrast, true, "the view did not get High Contrast")
        XCTAssertEqual(log.appears, 1, "High Contrast rebuilt the view (it appeared again)")
        XCTAssertEqual(log.disappears, 0, "High Contrast threw the view away")
        XCTAssertEqual(log.heldSeen.last, true, "the view's @State did not survive High Contrast")
    }

    /// A Mini pad held while the colour wheel drags stays held: no release fires because of the
    /// colour (only the mouse coming up releases it).
    @MainActor
    func testAHeldPadIsNotReleasedByAColourChange() {
        let accent = AccentSettings(defaults: defaults)
        let display = DisplaySettings(defaults: defaults)
        let log = Log()
        let (win, host) = host(log, accent: accent, display: display)
        defer { win.contentView = nil }
        // the wheel drags through several colours while the pad is down
        for a in [Accent(255, 0, 0), Accent(0, 255, 0), Accent(120, 200, 255)] {
            accent.set(a)
            settle(host) { log.palettes.last?.accent == a.readable().accent && log.heldSeen.last == true }
        }
        XCTAssertEqual(log.releases, 0, "a colour change released the held pad")
        XCTAssertEqual(log.heldSeen.last, true, "the pad is no longer held after the colour change")
    }
}
