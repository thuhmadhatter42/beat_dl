import XCTest
@testable import Orion

/// A video YouTube wants a login for: Beat Key has no login, it just says it can't download it.
final class LoginTests: XCTestCase {
    private func rt() -> Runtime {
        Runtime(root: URL(fileURLWithPath: "/R/runtime"), arch: "arm64",
                support: URL(fileURLWithPath: "/S/Orion"), osMajor: 14)
    }

    func testReadoutCopy() {
        let age = Faceplate.blockedLines(LoginPrompt(url: "u", reason: "age"))
        XCTAssertEqual(age.0, "THIS VIDEO IS AGE-RESTRICTED"); XCTAssertEqual(age.1, "BEAT KEY CAN'T DOWNLOAD IT")
        let bot = Faceplate.blockedLines(LoginPrompt(url: "u", reason: "bot"))
        XCTAssertEqual(bot.0, "YOUTUBE BLOCKED THIS DOWNLOAD"); XCTAssertEqual(bot.1, "TRY AGAIN LATER")
        let mem = Faceplate.blockedLines(LoginPrompt(url: "u", reason: "members"))
        XCTAssertEqual(mem.0, "THIS VIDEO IS FOR MEMBERS"); XCTAssertEqual(mem.1, "BEAT KEY CAN'T DOWNLOAD IT")
        // anything unknown reads as the age line
        XCTAssertEqual(Faceplate.blockedLines(LoginPrompt(url: "u", reason: "x")).0, "THIS VIDEO IS AGE-RESTRICTED")
    }

    func testReadoutOnlyForItsLink() {
        let st = ViewState.needsLogin(LoginPrompt(url: "https://a", reason: "bot"))
        XCTAssertNotNil(Faceplate.loginPrompt(st, url: " https://a "))
        XCTAssertNil(Faceplate.loginPrompt(st, url: "https://b"))
        XCTAssertNil(Faceplate.loginPrompt(.idle, url: "https://a"))
        XCTAssertFalse(st.isBusy)
    }

    func testEngineNeverPassesALogin() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.download("https://a")
        let deadline = Date().addingTimeInterval(5)
        while f.launches.count < 1 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(Array(f.launches[0].suffix(2)), ["download", "https://a"])
        XCTAssertFalse(f.launches[0].contains { $0.hasPrefix("--cookies") || $0 == "--browser" })
        f.onLine?(#"{"stage":"needs_login","reason":"age","message":"m"}"#); f.onExit?(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(e.state, .needsLogin(LoginPrompt(url: "https://a", reason: "age")))
        XCTAssertEqual(f.launches.count, 1)   // no second try of any kind
        e.clearLogin()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(e.state, .idle)
    }

    func testClearLoginLeavesOtherStates() {
        let e = Engine(runtime: rt(), launcher: FakeLauncher())
        e.state = .failed("x"); e.clearLogin()
        XCTAssertEqual(e.state, .failed("x"))
    }

    func testSuccessfulDownloadClearsReadout() {
        let e = Engine(runtime: rt(), launcher: FakeLauncher())
        e.state = .needsLogin(LoginPrompt(url: "u", reason: "age"))
        e.handle(.done(Result(file: URL(fileURLWithPath: "/a.mp3"), name: "a.mp3", bpm: "90.0", keys: [])))
        if case .done = e.state {} else { XCTFail("\(e.state)") }
    }

    func testNoBrowserDataNoLoginFile() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let plist = try XCTUnwrap(NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")))
        XCTAssertNil(plist["NSSystemPolicyAppDataDetailedUsageDescription"])
        // no source file reads browser data, opens a login window or keeps cookies
        let src = app.appendingPathComponent("Sources/Orion")
        let files = FileManager.default.enumerator(at: src, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for f in files {
            let text = try String(contentsOf: f)
            for banned in ["WKWebView", "cookies-file", "cookies-from-browser", "Full Disk Access", "HTTPCookie"] {
                XCTAssertFalse(text.contains(banned), "\(f.lastPathComponent) mentions \(banned)")
            }
        }
    }
}
