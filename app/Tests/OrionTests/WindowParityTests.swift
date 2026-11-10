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
        XCTAssertEqual(AppStatus.of(s), .ready)
        s.readout = .working(stage: "downloading", download: true)
        XCTAssertEqual(AppStatus.of(s), .working)
        s.readout = .error("x", download: true)
        XCTAssertEqual(AppStatus.of(s), .failed)
        s.readout = .doctor(DoctorReport(outcome: .failed, title: "T", line: "L"))
        XCTAssertEqual(AppStatus.of(s), .failed)
        s.listening = true
        s.source = "System Audio"
        XCTAssertEqual(AppStatus.of(s), .live("SYSTEM AUDIO"))
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

    /// The clipboard line is gone: the download cap says what a press does instead.
    func testDownloadTitleEmptyFieldPastesTypedLinkDownloads() {
        XCTAssertEqual(PocketState.downloadTitle(url: ""), "PASTE + DOWNLOAD")
        XCTAssertEqual(PocketState.downloadTitle(url: "  \n"), "PASTE + DOWNLOAD")
        XCTAssertEqual(PocketState.downloadTitle(url: "https://youtu.be/x"), "DOWNLOAD")
        XCTAssertEqual(PocketState.downloadTitle(url: "https://youtu.be/x", needsLogin: true), "LOG IN…")
        var s = PocketState()
        XCTAssertEqual(s.downloadTitle, "PASTE + DOWNLOAD")
        s.clipboardLink = "https://youtu.be/y"
        XCTAssertEqual(s.downloadTitle, "PASTE + DOWNLOAD")
        s.url = "https://youtu.be/x"            // a typed link wins over the clipboard
        XCTAssertEqual(s.downloadTitle, "DOWNLOAD")
    }

    /// Lit for a typed link, or for an empty field with a link on the clipboard; dim with neither.
    func testDownloadCapLitRules() {
        var s = PocketState()
        XCTAssertFalse(s.downloadLit || s.clipboardReady)
        s.clipboardLink = "https://youtu.be/y"
        XCTAssertTrue(s.clipboardReady)
        s.clipboardLink = nil
        s.url = "https://youtu.be/x"
        XCTAssertTrue(s.downloadLit)
        s.busy = true
        XCTAssertFalse(s.downloadLit || s.clipboardReady)
    }

    /// An empty field and no link on the clipboard: the press still reaches download (it beeps).
    func testDownloadPressedWithNothingToPasteFallsToDownload() {
        var log: [String] = []
        var a = PocketActions()
        a.download = { log.append("download") }
        a.pasteAndDownload = { log.append("paste \($0)") }
        a.downloadPressed(PocketState())
        XCTAssertEqual(log, ["download"])
    }

    // MARK: offscreen renders (ORION_SNAPSHOT_DIR=<dir> swift test --filter WindowParityTests/testRender)

    @MainActor
    func testRenderWindowStates() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORION_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ORION_SNAPSHOT_DIR to write the window PNGs")
        }
        guard #available(macOS 13.0, *) else { throw XCTSkip("ImageRenderer is macOS 13+") }
        Pocket.snapshot = true
        defer { Pocket.snapshot = false }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        var idle = PocketState()
        idle.source = "System Audio"
        idle.clipboardLink = "https://www.youtube.com/watch?v=xxxxxxxxxxx"

        var locked = idle
        let l = result()
        locked.readout = .result(l, page: nil, download: true, options: ResultOptions(
            factor: .one, tuning: Tuning.meter(12, reference: 440), onCycleTempo: {}))
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
        let h = Result(file: LiveSession.songFile(1), name: "LIVE", bpm: "93.0",
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

        var doctorFailed = idle
        doctorFailed.readout = .doctor(DoctorReport(outcome: .failed, title: "DOWNLOADS BROKEN",
                                                    line: "Reinstall Beat Key from the website"))

        let states: [(String, PocketState, [URL])] = [
            ("idle", idle, []), ("locked", locked, []), ("multi", multi, []), ("listening", listening, []),
            ("held", held, []), ("login", login, []), ("drop", drop, [URL(fileURLWithPath: "/x/Beat A.wav")]),
            ("doctor-failed", doctorFailed, [])]
        for (name, s, picked) in states {
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
