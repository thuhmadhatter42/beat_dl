import XCTest
@testable import Orion

final class LoginTests: XCTestCase {
    private func rt() -> Runtime {
        Runtime(root: URL(fileURLWithPath: "/R/runtime"), arch: "arm64",
                support: URL(fileURLWithPath: "/S/Orion"), osMajor: 14)
    }

    func testBundleMapping() {
        let m = [("com.brave.Browser", "brave"), ("com.google.Chrome", "chrome"),
                 ("org.chromium.Chromium", "chromium"), ("com.microsoft.edgemac", "edge"),
                 ("org.mozilla.firefox", "firefox"), ("com.operasoftware.Opera", "opera"),
                 ("com.apple.Safari", "safari"), ("com.vivaldi.Vivaldi", "vivaldi"),
                 ("com.naver.Whale", "whale")]
        for (id, name) in m { XCTAssertEqual(LoginBrowser.forBundle(id)?.name, name) }
        XCTAssertEqual(LoginBrowser.forBundle("com.brave.Browser")?.display, "Brave")
        XCTAssertNil(LoginBrowser.forBundle("company.thebrowser.Browser"))   // Arc
    }

    func testResolveUsesSupportedDefault() {
        XCTAssertEqual(LoginBrowser.resolve(defaultBundleID: "com.brave.Browser") { _ in false }?.name, "brave")
    }

    func testResolveFallbackOrder() {
        let installed: Set<String> = ["com.apple.Safari", "com.microsoft.edgemac", "org.mozilla.firefox"]
        XCTAssertEqual(LoginBrowser.resolve(defaultBundleID: "company.thebrowser.Browser") { installed.contains($0) }?.name, "edge")
        XCTAssertEqual(LoginBrowser.resolve(defaultBundleID: nil) { $0 == "com.apple.Safari" }?.name, "safari")
        XCTAssertEqual(LoginBrowser.resolve(defaultBundleID: nil) { $0 == "com.google.Chrome" || $0 == "com.brave.Browser" }?.name, "chrome")
        XCTAssertNil(LoginBrowser.resolve(defaultBundleID: "x") { _ in false })
    }

    func testLcdCopy() {
        let second = "NEXT TRY USES A LOGIN COOKIE FROM YOUR BROWSER"
        let b = LoginBrowser.named("brave")
        let age = Faceplate.loginLines(LoginPrompt(url: "u", reason: "age", tried: nil), browser: b)
        XCTAssertEqual(age.0, "THIS VIDEO IS AGE-RESTRICTED"); XCTAssertEqual(age.1, second)
        let bot = Faceplate.loginLines(LoginPrompt(url: "u", reason: "bot", tried: nil), browser: b)
        XCTAssertEqual(bot.0, "YOUTUBE WANTS A LOGIN"); XCTAssertEqual(bot.1, second)
        let mem = Faceplate.loginLines(LoginPrompt(url: "u", reason: "members", tried: nil), browser: b)
        XCTAssertEqual(mem.0, "THIS VIDEO IS FOR MEMBERS")
        let none = Faceplate.loginLines(LoginPrompt(url: "u", reason: "age", tried: nil), browser: nil)
        XCTAssertEqual(none.1, "BEAT KEY CAN USE A YOUTUBE LOGIN FROM CHROME, BRAVE, EDGE, FIREFOX OR SAFARI.")
        let retry = Faceplate.loginLines(LoginPrompt(url: "u", reason: "age", tried: "brave"), browser: b)
        XCTAssertEqual(retry.0, "LOG IN TO YOUTUBE IN BRAVE"); XCTAssertEqual(retry.1, "THEN PRESS TRY AGAIN")
    }

    func testCapLabelAndLit() {
        let first = LoginPrompt(url: "u", reason: "age", tried: nil)
        let retry = LoginPrompt(url: "u", reason: "age", tried: "brave")
        let b = LoginBrowser.named("brave")
        XCTAssertEqual(Faceplate.loginCap(first, browser: b, busy: false).label, "OPEN YOUTUBE.COM & LOGIN")
        XCTAssertTrue(Faceplate.loginCap(first, browser: b, busy: false).lit)
        XCTAssertFalse(Faceplate.loginCap(first, browser: nil, busy: false).lit)
        XCTAssertFalse(Faceplate.loginCap(first, browser: b, busy: true).lit)
        XCTAssertEqual(Faceplate.loginCap(retry, browser: nil, busy: false).label, "TRY AGAIN")
        XCTAssertTrue(Faceplate.loginCap(retry, browser: nil, busy: false).lit)
        XCTAssertFalse(Faceplate.loginCap(retry, browser: nil, busy: true).lit)
    }

    func testPromptOnlyForItsLink() {
        let st = ViewState.needsLogin(LoginPrompt(url: "https://a", reason: "bot", tried: nil))
        XCTAssertNotNil(Faceplate.loginPrompt(st, url: " https://a "))
        XCTAssertNil(Faceplate.loginPrompt(st, url: "https://b"))
        XCTAssertNil(Faceplate.loginPrompt(.idle, url: "https://a"))
        XCTAssertFalse(st.isBusy)
    }

    func testEngineNeedsLoginPassesBrowserAndClears() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.download("https://a")
        let deadline = Date().addingTimeInterval(5)
        while f.launches.count < 1 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertFalse(f.launches[0].contains("--browser"))
        f.onLine?(#"{"stage":"needs_login","reason":"age","message":"m"}"#); f.onExit?(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(e.state, .needsLogin(LoginPrompt(url: "https://a", reason: "age", tried: nil)))
        e.download("https://a", browser: "brave")
        while f.launches.count < 2 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(Array(f.launches[1].suffix(4)), ["download", "https://a", "--browser", "brave"])
        f.onLine?(#"{"stage":"needs_login","reason":"age","message":"m","tried":"brave"}"#); f.onExit?(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(e.state, .needsLogin(LoginPrompt(url: "https://a", reason: "age", tried: "brave")))
        e.clearLogin()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(e.state, .idle)
    }

    func testClearLoginLeavesOtherStates() {
        let e = Engine(runtime: rt(), launcher: FakeLauncher())
        e.state = .failed("x"); e.clearLogin()
        XCTAssertEqual(e.state, .failed("x"))
    }

    func testSuccessfulDownloadClearsLogin() {
        let e = Engine(runtime: rt(), launcher: FakeLauncher())
        e.state = .needsLogin(LoginPrompt(url: "u", reason: "age", tried: nil))
        e.handle(.done(Result(file: URL(fileURLWithPath: "/a.mp3"), name: "a.mp3", bpm: "90.0", keys: [])))
        if case .done = e.state {} else { XCTFail("\(e.state)") }
    }
}
