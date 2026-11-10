import AppKit
import SwiftUI
import XCTest
@testable import Orion

/// Marketing screenshots for the fourletterrecords.com /beat-key page, rendered offscreen at 2x with the
/// default amber accent (never the live app, never J's screen):
/// ORION_SNAPSHOT_DIR=<dir> swift test --filter MarketingRenderTests
/// A render failure is an XCTFail plus a stderr line naming the shot; nothing ships to customers.
final class MarketingRenderTests: XCTestCase {
    private func reading() -> Result {
        Result(file: URL(fileURLWithPath: "/x/Beats/Some Beat.mp3"), name: "Some Beat.mp3", bpm: "140.00",
               keys: [("Cm", 88), ("Eb", 7), ("Gm", 3)], bpmExact: 140.00, tuningCents: 3)
    }

    @MainActor
    func testRenderMarketingShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORION_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ORION_SNAPSHOT_DIR to write the marketing PNGs")
        }
        guard #available(macOS 13.0, *) else { throw XCTSkip("ImageRenderer is macOS 13+") }
        let shared = SpellingSettings.shared
        let savedManual = shared.manualKey
        Pocket.snapshot = true
        defer {
            Pocket.snapshot = false; Theme.accent = .amber
            shared.manualKey = savedManual
        }
        Theme.accent = .amber
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        func write<V: View>(_ v: V, _ name: String) {
            do {
                let r = ImageRenderer(content: v.environment(\.colorScheme, .dark))
                r.scale = 2
                guard let cg = r.cgImage else { throw NSError(domain: "marketing", code: 1) }
                let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
                try png.write(to: out.appendingPathComponent("\(name).png"))
            } catch {
                FileHandle.standardError.write(Data("MarketingRenderTests: shot \(name) FAILED: \(error)\n".utf8))
                XCTFail("shot \(name) failed: \(error)")
            }
        }
        func window(_ s: PocketState) -> FaceplateFace {
            FaceplateFace(state: s, picked: [], url: .constant(s.url), fieldFocused: .constant(false),
                          pickFocused: .constant(false))
        }

        let r = reading()
        var file = PocketState()
        file.source = "System Audio"
        file.daw = "Pro Tools"
        file.readout = .result(r, page: nil, download: true, options: ResultOptions(
            factor: .one, tuning: Tuning.meter(3, reference: 440), onCycleTempo: {}))
        file.recents = [Reading(r)]

        var adv = file
        adv.advanced = true

        var listening = PocketState()
        listening.source = "System Audio"
        listening.daw = "Pro Tools"
        let live = Result(file: LiveSession.songFile(1), name: "LIVE", bpm: "140.00",
                          keys: [("Cm", 88), ("Eb", 7), ("Gm", 3)], bpmExact: 140.00)
        listening.readout = .result(live, page: nil, download: false, options: ResultOptions(
            factor: .one, tuning: nil, onCycleTempo: {}, live: (.locked, "LOCKED 88%", "System Audio")))
        listening.listening = true
        listening.level = 0.62

        // Manual Key Selection: Eb, the runner-up
        let s = SpellingSettings()
        s.setManualKey("Eb", of: r, from: .topKeys)
        var manual = adv
        manual.readout = .result(r.respelled(choice: s.manualKey), page: nil, download: true,
                                 options: ResultOptions(factor: .one, tuning: Tuning.meter(3, reference: 440), onCycleTempo: {}))
        manual.manualKey = ManualKey.of(s.manualKey, raw: r)

        write(window(file), "window-default")
        write(window(adv), "window-advanced")
        write(window(listening), "window-listening")
        write(PocketView(state: file, url: .constant("")), "panel")
        write(MiniView(state: MiniViewState(key: "Cm", layout: MiniLayout(key: "Cm", quality: .triad))), "mini")
        write(window(manual), "window-manual")

        Theme.accent = Accent(80, 170, 255)
        write(window(file), "window-blue")
        Theme.accent = .amber
    }
}
