import AppKit
import SwiftUI
import XCTest
@testable import Orion

/// J 2026-11-09 14:23: the footer's actions all one chip, the readout bigger and centred in its
/// band. Offscreen renders for docs/research/footer-readout-2026-11-09/
/// (ORION_SNAPSHOT_DIR=<dir> swift test --filter FooterReadoutRenderTests).
final class FooterReadoutRenderTests: XCTestCase {
    private func result(_ name: String = "Beat A.wav") -> Result {
        Result(file: URL(fileURLWithPath: "/x/Beats/\(name)"), name: name, bpm: "141.98",
               keys: [("Ebm", 86), ("Gb", 9), ("Bbm", 5)], bpmExact: 141.98, tuningCents: 12)
    }

    @MainActor
    func testRenderFooterAndReadout() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORION_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ORION_SNAPSHOT_DIR to write the footer / readout PNGs")
        }
        guard #available(macOS 13.0, *) else { throw XCTSkip("ImageRenderer is macOS 13+") }
        Pocket.snapshot = true
        defer { Pocket.snapshot = false; Theme.accent = .amber }
        Theme.accent = .amber
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func write<V: View>(_ v: V, _ name: String, crop bottom: CGFloat? = nil) throws {
            let r = ImageRenderer(content: v.environment(\.colorScheme, .dark))
            r.scale = 2
            guard var cg = r.cgImage else { return XCTFail("no image for \(name)") }
            if let b = bottom, let c = cg.cropping(to: CGRect(x: 0, y: CGFloat(cg.height) - b * 2,
                                                             width: CGFloat(cg.width), height: b * 2)) { cg = c }
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
            try png.write(to: out.appendingPathComponent("\(name).png"))
        }
        func window(_ s: PocketState) -> FaceplateFace {
            FaceplateFace(state: s, picked: [], url: .constant(s.url), fieldFocused: .constant(false),
                          pickFocused: .constant(false))
        }

        var idle = PocketState()
        idle.source = "System Audio"
        idle.daw = "Pro Tools"

        var file = idle
        let r = result()
        file.readout = .result(r, page: nil, download: true, options: ResultOptions(
            factor: .one, tuning: Tuning.meter(12, reference: 440), onCycleTempo: {}))
        file.recents = [Reading(r)]

        // live, a reading in: no file line under the readout
        var listening = idle
        let h = Result(file: LiveSession.songFile(1), name: "LIVE", bpm: "141.98",
                       keys: [("Ebm", 86), ("Gb", 9), ("Bbm", 5)], bpmExact: 141.98)
        listening.readout = .result(h, page: nil, download: false, options: ResultOptions(
            factor: .one, tuning: nil, onCycleTempo: {}, live: (.locked, "LOCKED 86%", "System Audio")))
        listening.listening = true
        listening.level = 0.62

        var adv = file
        adv.advanced = true

        try write(window(idle), "window-idle")
        try write(window(file), "window-file")
        try write(window(listening), "window-listening")
        try write(window(adv), "window-advanced")
        try write(window(file), "window-footer", crop: 44)
        try write(PocketView(state: file, url: .constant("")), "pocket-full")
        try write(PocketView(state: file, url: .constant("")), "pocket-footer", crop: 40)
        var helpOn = file
        helpOn.help = true
        try write(PocketView(state: helpOn, url: .constant("")), "pocket-footer-help-on", crop: 40)
        try write(window(helpOn), "window-footer-help-on", crop: 44)
    }
}
