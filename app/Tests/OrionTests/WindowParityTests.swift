import AppKit
import SwiftUI
import XCTest
@testable import Orion

/// The window does what the popover does, with the popover's own state and controls.
final class WindowParityTests: XCTestCase {
    func result(_ keys: [(String, Int)] = [("Ebm", 86), ("Gb", 9), ("Bbm", 5)], bpm: String? = "128.0",
                exact: Double? = 128.04, name: String = "Beat A.wav") -> Result {
        Result(file: URL(fileURLWithPath: "/x/Beats/\(name)"), name: name, bpm: bpm, keys: keys, bpmExact: exact)
    }

    func testRailSaysLiveWhileListening() {
        var s = PocketState()
        XCTAssertEqual(FaceplateFace.railStatus(s), .ready)
        s.readout = .working(stage: "downloading", download: true)
        XCTAssertEqual(FaceplateFace.railStatus(s), .working)
        s.readout = .error("x", download: true)
        XCTAssertEqual(FaceplateFace.railStatus(s), .failed)
        s.readout = .doctor(DoctorReport(outcome: .failed, title: "T", line: "L"))
        XCTAssertEqual(FaceplateFace.railStatus(s), .failed)
        s.listening = true
        s.source = "System Audio"
        XCTAssertEqual(FaceplateFace.railStatus(s), .live("SYSTEM AUDIO"))
    }

    func testDownloadPressedTakesLoginThenFieldThenClipboard() {
        var log: [String] = []
        var a = PocketActions()
        a.openLogin = { log.append("login") }
        a.download = { log.append("download") }
        a.pasteAndDownload = { log.append("paste \($0)") }
        var s = PocketState()
        s.needsLogin = true
        a.downloadPressed(s)
        s.needsLogin = false
        s.url = "https://youtu.be/x"
        a.downloadPressed(s)
        s.url = ""
        s.clipboardLink = "https://youtu.be/y"
        a.downloadPressed(s)
        XCTAssertEqual(log, ["login", "download", "paste https://youtu.be/y"])
    }

    func testClipboardLineOnlyForANewLinkWhileIdle() {
        var s = PocketState()
        XCTAssertFalse(ClipboardLine.shows(s, url: ""))
        s.clipboardLink = "https://youtu.be/y"
        XCTAssertTrue(ClipboardLine.shows(s, url: ""))
        XCTAssertFalse(ClipboardLine.shows(s, url: " https://youtu.be/y\n"))
        s.busy = true
        XCTAssertFalse(ClipboardLine.shows(s, url: ""))
    }

    // MARK: offscreen renders (ORION_SNAPSHOT_DIR=<dir> swift test --filter WindowParityTests/testRender)

    @MainActor
    func testRenderWindowStates() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORION_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ORION_SNAPSHOT_DIR to write the window PNGs")
        }
        guard #available(macOS 13.0, *) else { throw XCTSkip("ImageRenderer is macOS 13+") }
        Pocket.snapshot = true
        defer { Pocket.snapshot = false; Theme.highContrast = false }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        var idle = PocketState()
        idle.source = "System Audio"
        idle.clipboardLink = "https://www.youtube.com/watch?v=xxxxxxxxxxx"

        var locked = idle
        let l = result()
        locked.readout = .result(l, page: nil, download: true, options: ResultOptions(
            factor: .one, tuning: Tuning.line(12, reference: 440), onCycleTempo: {}))
        locked.clipboardLink = nil
        locked.daw = "Pro Tools"
        locked.recents = [Reading(l)]

        var multi = locked
        let m = result([("F#m", 61), ("A", 18), ("C#m", 9)], bpm: "120.0", exact: 120.0, name: "Beat B.wav")
        multi.readout = .result(m, page: "2 OF 3", download: false, options: ResultOptions(
            factor: .double, tuning: nil, onCycleTempo: {}))

        var listening = idle
        listening.readout = .listening(status: "LISTENING · SYSTEM AUDIO")
        listening.listening = true
        listening.level = 0.62
        listening.clipboardLink = nil

        var held = listening
        let h = Result(file: LiveSession.placeholderFile, name: "LIVE", bpm: "93.0",
                       keys: [("Cm", 78), ("Eb", 14), ("Gm", 8)], bpmExact: 92.97)
        held.readout = .result(h, page: nil, download: false, options: ResultOptions(
            factor: .one, tuning: nil, onCycleTempo: {}, live: (.locked, "HELD · LOCKED 78%", "System Audio")))
        held.held = true
        held.level = 0.7
        held.daw = "Ableton Live"

        var login = idle
        login.url = "https://www.youtube.com/watch?v=xxxxxxxxxxx"
        login.needsLogin = true
        login.clipboardLink = nil
        login.readout = .login("THIS VIDEO IS AGE-RESTRICTED", Faceplate.loginNextLine, caption: nil)

        var drop = idle
        drop.readout = .drop

        let states: [(String, PocketState, [URL])] = [
            ("idle", idle, []), ("locked", locked, []), ("multi", multi, []), ("listening", listening, []),
            ("held", held, []), ("login", login, []), ("drop", drop, [URL(fileURLWithPath: "/x/Beat A.wav")])]
        for (name, s, picked) in states {
            Theme.highContrast = s.highContrast
            let view = FaceplateFace(state: s, picked: picked, url: .constant(s.url), fieldFocused: .constant(false),
                                     pickFocused: .constant(false))
                .environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: view)
            r.scale = 2
            guard let cg = r.cgImage else { return XCTFail("no image for \(name)") }
            let rep = NSBitmapImageRep(cgImage: cg)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: out.appendingPathComponent("window-\(name).png"))
        }
    }
}
