import AppKit
import SwiftUI
import XCTest
@testable import Orion

final class PocketTests: XCTestCase {
    func result(_ keys: [(String, Int)] = [("Ebm", 85), ("Gb", 8), ("Bbm", 4)], bpm: String? = "128.0",
                exact: Double? = 128.04, cents: Double? = nil) -> Result {
        Result(file: URL(fileURLWithPath: "/x/Night Drive.wav"), name: "Night Drive.wav", bpm: bpm, keys: keys,
               bpmExact: exact, tuningCents: cents)
    }

    // MARK: scale

    func testScaleOfMinorAndMajor() {
        let ebm = Scale.of("Ebm")!
        XCTAssertEqual(ebm.tonic, 3)
        XCTAssertTrue(ebm.minor)
        XCTAssertEqual(ebm.notes, [3, 5, 6, 8, 10, 11, 1])
        XCTAssertFalse(ebm.sharps)
        XCTAssertEqual(ebm.spelled, ["E♭", "F", "G♭", "A♭", "B♭", "C♭", "D♭"])
        let d = Scale.of("D")!
        XCTAssertEqual(d.notes, [2, 4, 6, 7, 9, 11, 1])
        XCTAssertTrue(d.sharps)
        XCTAssertEqual(d.name(6), "F♯")
        XCTAssertEqual(Scale.of("C")!.notes, [0, 2, 4, 5, 7, 9, 11])
        XCTAssertNil(Scale.of("H"))
    }

    // MARK: meter, clipboard

    func testLevelMeter() {
        XCTAssertEqual(LevelMeter.scale(0), 0)
        XCTAssertEqual(LevelMeter.scale(1), 1)
        XCTAssertEqual(LevelMeter.scale(2), 1)                       // clipped
        XCTAssertEqual(LevelMeter.scale(0.001), 0)                   // -60 dB, under the floor
        XCTAssertEqual(LevelMeter.scale(pow(10, -27 / 20)), 0.5, accuracy: 0.001)   // -27 dB = half
        XCTAssertEqual(LevelMeter.lit(0.5, count: 12), 6)
        XCTAssertEqual(LevelMeter.lit(-1, count: 12), 0)
        XCTAssertEqual(LevelMeter.lit(9, count: 12), 12)
    }

    func testClipboardLink() {
        XCTAssertEqual(Clipboard.link("  https://youtu.be/abc\n"), "https://youtu.be/abc")
        XCTAssertEqual(Clipboard.link("http://www.youtube.com/watch?v=x"), "http://www.youtube.com/watch?v=x")
        XCTAssertNil(Clipboard.link("youtube.com/watch?v=x"))
        XCTAssertNil(Clipboard.link("look at https://youtu.be/abc"))
        XCTAssertNil(Clipboard.link("file:///x.mp3"))
        XCTAssertNil(Clipboard.link(nil))
        XCTAssertEqual(PocketText.shortLink("https://www.youtube.com/watch?v=x"), "youtube.com/watch?v=x")
    }

    // MARK: state

    func testStateFromAReading() {
        var s = PocketState()
        s.readout = .result(result(), page: nil, download: true)
        XCTAssertEqual(s.lamp, .locked)
        XCTAssertEqual(s.confidence, 0.85)
        XCTAssertEqual(s.scale?.tonic, 3)
        XCTAssertEqual(s.lampWord, "LOCKED")
        XCTAssertTrue(s.canSend)
        XCTAssertTrue(s.canAutoTune)
        s.readout = .result(result([("Cm", 41), ("Eb", 22)]), page: nil, download: false)
        XCTAssertEqual(s.lamp, .unsure)
        s.readout = .listening(status: "LISTENING")
        XCTAssertEqual(s.lamp, .listening)
        XCTAssertNil(s.confidence)
        XCTAssertFalse(s.canSend)
        s.readout = .idle
        XCTAssertNil(s.lamp)
    }

    func testDownloadLit() {
        var s = PocketState()
        XCTAssertFalse(s.downloadLit)
        s.url = "https://youtu.be/x"
        XCTAssertTrue(s.downloadLit)
        s.busy = true
        XCTAssertFalse(s.downloadLit)
        s.busy = false
        s.needsLogin = true
        XCTAssertFalse(s.downloadLit)
        // an empty field with a link on the clipboard: DOWNLOAD takes the clipboard's link
        var c = PocketState()
        c.clipboardLink = "https://youtu.be/y"
        XCTAssertTrue(c.clipboardReady)
        c.url = "https://youtu.be/x"
        XCTAssertFalse(c.clipboardReady)
    }

    func testShownFollowsPagerAndListen() {
        let a = result(), b = result([("Am", 80)])
        var p = Pager()
        p.reset(count: 2)
        XCTAssertEqual(PocketState.shown(.analyzed([a, b]), live: .off, page: p), b)
        p.previous()
        XCTAssertEqual(PocketState.shown(.analyzed([a, b]), live: .off, page: p), a)
        XCTAssertEqual(PocketState.shown(.done(a), live: .locked(b), page: p), b)
        XCTAssertNil(PocketState.shown(.idle, live: .listening, page: p))
    }

    func testIdleStatusItemShowsNoOldReading() {
        let m = MenuBarReadout.of(.idle, page: 0, factor: .one)
        XCTAssertEqual(m, .idle)
        XCTAssertNil(m.text)
    }

    func testSharedReadoutMatchesWindow() {
        var p = Pager()
        p.reset(count: 1)
        let r = Faceplate.readout(.done(result(cents: 12)), live: .off, liveSource: "", page: p, factor: .double,
                                  lastAction: .download, note: nil, reference: 440, onCycleTempo: nil)
        guard case .result(_, _, true, _, let o) = r else { return XCTFail() }
        XCTAssertEqual(o.factor, .double)
        XCTAssertEqual(o.tuning, "TUNING +12¢ · A=440")
        guard case .listening = Faceplate.readout(.done(result()), live: .listening, liveSource: "Mic", page: p,
                                                  factor: .one, lastAction: .download, note: nil, reference: 440,
                                                  onCycleTempo: nil) else { return XCTFail() }
    }

    func testKeyImageAndGlyph() {
        let img = MenuBarImage.key()
        XCTAssertEqual(img.size.height, 12)
        XCTAssertFalse(img.isTemplate)
        XCTAssertFalse(KeyGlyphShape().path(in: CGRect(x: 0, y: 0, width: 22, height: 12)).isEmpty)
    }

    // MARK: offscreen renders (ORION_SNAPSHOT_DIR=<dir> swift test --filter PocketTests/testRender)

    @MainActor
    func testRenderPopoverStates() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORION_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ORION_SNAPSHOT_DIR to write the popover PNGs")
        }
        guard #available(macOS 13.0, *) else { throw XCTSkip("ImageRenderer is macOS 13+") }
        Pocket.snapshot = true
        defer { Pocket.snapshot = false; Theme.highContrast = false }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        var idle = PocketState()
        idle.source = "System Audio"
        idle.clipboardLink = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        idle.daw = "Pro Tools"

        var working = idle
        working.readout = .working(stage: "downloading", download: true)
        working.busy = true
        working.url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        working.clipboardLink = nil

        var listening = idle
        listening.readout = .listening(status: "LISTENING · SYSTEM AUDIO")
        listening.listening = true
        listening.level = 0.62
        listening.clipboardLink = nil
        listening.newSongKeys = "⌃⌥⌘R"

        var unsure = listening
        let u = Result(file: LiveSession.placeholderFile, name: "LIVE", bpm: "93.0",
                       keys: [("Cm", 48), ("Eb", 31), ("Gm", 14)], bpmExact: 92.97)
        unsure.readout = .result(u, page: nil, download: false, options: ResultOptions(
            factor: .one, tuning: nil, onCycleTempo: {}, live: (.unsure, "UNSURE · Cm 48 · Eb 31 · Gm 14", "System Audio")))
        unsure.level = 0.78

        var locked = idle
        let l = result([("Ebm", 86), ("Gb", 9), ("Bbm", 5)], exact: 128.04, cents: 12)
        locked.readout = .result(l, page: nil, download: true, options: ResultOptions(
            factor: .one, tuning: Tuning.line(12, reference: 440), onCycleTempo: {}))
        locked.clipboardLink = nil

        var hc = locked
        hc.highContrast = true

        var failed = idle
        failed.readout = .error("That video is private or was removed.", download: true)
        failed.url = "https://youtu.be/xxxxxxxxxxx"

        // live, locked and HELD (the caption and the lit HOLD key)
        var held = listening
        let h = Result(file: LiveSession.placeholderFile, name: "LIVE", bpm: "128.0",
                       keys: [("Ebm", 86), ("Gb", 9), ("Bbm", 5)], bpmExact: 128.04)
        held.readout = .result(h, page: nil, download: false, options: ResultOptions(
            factor: .one, tuning: nil, onCycleTempo: {}, live: (.locked, "HELD · LOCKED 86%", "System Audio")))
        held.held = true
        held.holdKeys = "⌃⌥⌘H"
        held.level = 0.7

        // the same reading after a click on the key: D#m, F#, A#m, and the scale in sharps
        var sharps = held
        sharps.held = false
        let hs = h.respelled(.sharps)
        sharps.readout = .result(hs, page: nil, download: false, options: ResultOptions(
            factor: .one, tuning: nil, onCycleTempo: {}, live: (.locked, "LOCKED 86%", "System Audio")))

        let states: [(String, PocketState)] = [("idle", idle), ("downloading", working), ("listening", listening),
                                               ("unsure", unsure), ("locked", locked), ("high-contrast", hc),
                                               ("error", failed), ("held", held), ("sharps", sharps)]
        for (name, s) in states {
            Theme.highContrast = s.highContrast
            let view = PocketView(state: s, url: .constant(s.url))
                .environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: view)
            r.scale = 2
            guard let cg = r.cgImage else { return XCTFail("no image for \(name)") }
            let rep = NSBitmapImageRep(cgImage: cg)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: out.appendingPathComponent("popover-\(name).png"))
        }
    }
}
