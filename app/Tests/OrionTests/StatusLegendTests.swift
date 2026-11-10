import SwiftUI
import XCTest
@testable import Orion

/// The status legend has one owner (AppStatus): the window's rail and the pocket's header both
/// draw StatusLegend(status: AppStatus.of(state)), so one table pins both surfaces.
final class StatusLegendTests: XCTestCase {
    private let r = Result(file: URL(fileURLWithPath: "/x/a.wav"), name: "a.wav", bpm: "120.0", keys: [("Am", 80)])

    private func doctor(_ o: DoctorReport.Outcome) -> Readout {
        .doctor(DoctorReport(outcome: o, title: "T", line: "L"))
    }

    /// Every readout the app can show, listening or not: status, word, lamp shape, colours.
    func testOneTableForBothSurfaces() {
        let p = Palette()
        let ready = AppStatus.Look(text: Theme.greenText, lamp: Theme.green, glow: Theme.greenGlow)
        let working = AppStatus.Look(text: p.amber, lamp: p.amber, glow: p.amberGlow)
        let red = AppStatus.Look(text: Theme.redText, lamp: Theme.red, glow: Theme.red.opacity(0.7))
        let table: [(String, Readout, Bool, AppStatus, String, Lamp, AppStatus.Look)] = [
            ("idle", .idle, false, .ready, "READY", .locked, ready),
            ("drop", .drop, false, .ready, "READY", .locked, ready),
            ("working", .working(stage: "downloading", download: true), false, .working, "WORKING", .listening, working),
            ("result", .result(r, page: nil, download: true), false, .ready, "READY", .locked, ready),
            ("error", .error("x", download: true), false, .failed, "FAILED", .listening, red),
            ("doctor ok", doctor(.ok), false, .ready, "READY", .locked, ready),
            ("doctor fixed", doctor(.fixed), false, .ready, "READY", .locked, ready),
            ("doctor failed", doctor(.failed), false, .failed, "FAILED", .listening, red),
            ("login", .login("A", "B", caption: nil), false, .ready, "READY", .locked, ready),
            ("listening", .listening(status: "LISTENING"), true, .live("SYSTEM AUDIO"), "LIVE · SYSTEM AUDIO", .listening, red),
            ("live reading", .result(r, page: nil, download: false), true, .live("SYSTEM AUDIO"), "LIVE · SYSTEM AUDIO", .listening, red),
            // Listen wins over whatever the engine shows
            ("live over doctor failed", doctor(.failed), true, .live("SYSTEM AUDIO"), "LIVE · SYSTEM AUDIO", .listening, red),
        ]
        for (name, readout, listening, status, word, shape, look) in table {
            var s = PocketState()
            s.readout = readout
            s.listening = listening
            s.source = "System Audio"
            let got = AppStatus.of(s)
            XCTAssertEqual(got, status, name)
            XCTAssertEqual(got.word, word, name)
            XCTAssertEqual(got.shape, shape, name)
            XCTAssertEqual(got.look(p), look, name)
        }
    }

    /// High Contrast: the same words and fills, no glow (the palette's rule: "glows go").
    func testHighContrastDropsTheGlowOnly() {
        let hc = Palette(accent: .amber, highContrast: true)
        for s in [AppStatus.ready, .working, .failed, .live("X")] {
            XCTAssertEqual(s.look(hc).glow, .clear)
            XCTAssertEqual(s.look(hc).text, s.look(Palette()).text)
            XCTAssertEqual(s.look(hc).lamp, s.look(Palette()).lamp)
        }
    }

    /// The two surfaces differ only in size.
    func testMetricsAreTheSurfacesSizes() {
        XCTAssertEqual(StatusLegend.Metrics.regular,
                       .init(lampSide: 8, gap: Theme.S.s, maxWidth: 250, glowRadius: 4))
        XCTAssertEqual(StatusLegend.Metrics.compact, .init(lampSide: 7, gap: 6, maxWidth: 200, glowRadius: 3))
        XCTAssertEqual(StatusLegend(status: .ready).metrics, .regular)
    }
}
