import XCTest
@testable import Orion

final class LoginTests: XCTestCase {
    private var tmp: URL!
    /// HTTPCookie caps an expiry at 400 days, so a near one
    static let soon = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 86400).rounded(.down) * 86400 + 30 * 86400)
    private var soonText: String { String(Int(LoginTests.soon.timeIntervalSince1970)) }

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("orion-login-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        YouTubeLogin.inApp = true
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        YouTubeLogin.inApp = true
    }

    private func rt() -> Runtime {
        Runtime(root: URL(fileURLWithPath: "/R/runtime"), arch: "arm64",
                support: URL(fileURLWithPath: "/S/Orion"), osMajor: 14)
    }

    private func cookie(_ domain: String, _ name: String, value: String = "v", secure: Bool = true,
                        httpOnly: Bool = false, expires: Date? = LoginTests.soon) -> HTTPCookie {
        var p: [HTTPCookiePropertyKey: Any] = [.domain: domain, .path: "/", .name: name, .value: value]
        if secure { p[.secure] = "TRUE" }
        if let e = expires { p[.expires] = e }
        if httpOnly { p[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return HTTPCookie(properties: p)!
    }

    private func wait(_ f: FakeLauncher, _ n: Int) {
        let deadline = Date().addingTimeInterval(5)
        while f.launches.count < n && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    // MARK: the cookie file

    func testNetscapeFormat() {
        let text = CookieFile.netscape([
            cookie(".youtube.com", "SAPISID", value: "abc"),
            cookie("www.youtube.com", "HOST", value: "h", secure: false, expires: nil),
            cookie(".google.com", "SID", value: "s", httpOnly: true),
        ])
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines[0], "# Netscape HTTP Cookie File")
        XCTAssertTrue(lines.contains(".youtube.com\tTRUE\t/\tTRUE\t\(soonText)\tSAPISID\tabc"))
        XCTAssertTrue(lines.contains("www.youtube.com\tFALSE\t/\tFALSE\t0\tHOST\th"))
        XCTAssertTrue(lines.contains("#HttpOnly_.google.com\tTRUE\t/\tTRUE\t\(soonText)\tSID\ts"))
        // every cookie line has yt-dlp's seven fields
        for l in lines where !l.isEmpty && (!l.hasPrefix("#") || l.hasPrefix("#HttpOnly_")) {
            XCTAssertEqual(l.split(separator: "\t", omittingEmptySubsequences: false).count, 7, l)
        }
    }

    func testOnlyYouTubeAndGoogleDomains() {
        let text = CookieFile.netscape([
            cookie(".youtube.com", "A"), cookie("accounts.google.com", "B"), cookie("google.com", "C"),
            cookie(".notyoutube.com", "X1"), cookie("youtube.com.evil.net", "X2"), cookie(".doubleclick.net", "X3"),
            cookie(".googleusercontent.com", "X4"), cookie(".google.co.uk", "X5"),
        ])
        for keep in ["\tA\t", "\tB\t", "\tC\t"] { XCTAssertTrue(text.contains(keep), keep) }
        for drop in ["X1", "X2", "X3", "X4", "X5"] { XCTAssertFalse(text.contains(drop), drop) }
    }

    func testFieldWithTabOrNewlineIsSkipped() {
        let text = CookieFile.netscape([cookie(".youtube.com", "OK"), cookie(".youtube.com", "BAD", value: "a\tb")])
        XCTAssertTrue(text.contains("\tOK\t"))
        XCTAssertFalse(text.contains("BAD"))
    }

    func testWriteIsOwnerOnlyAndReplaces() throws {
        let f = CookieFile(url: tmp.appendingPathComponent("sub/youtube-cookies.txt"))
        XCTAssertFalse(f.exists)
        try f.write([cookie(".youtube.com", "ONE")])
        XCTAssertTrue(f.exists)
        let mode = try FileManager.default.attributesOfItem(atPath: f.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        try f.write([cookie(".youtube.com", "TWO")])
        let text = try String(contentsOf: f.url)
        XCTAssertTrue(text.contains("\tTWO\t")); XCTAssertFalse(text.contains("\tONE\t"))
        let left = try FileManager.default.contentsOfDirectory(atPath: f.url.deletingLastPathComponent().path)
        XCTAssertEqual(left, ["youtube-cookies.txt"])   // no temp file left behind
        f.delete()
        XCTAssertFalse(f.exists)
    }

    func testDefaultPath() {
        XCTAssertEqual(CookieFile.appDefault().url.lastPathComponent, "youtube-cookies.txt")
        XCTAssertEqual(CookieFile.appDefault().url.deletingLastPathComponent().lastPathComponent, "Orion")
    }

    func testLoggedInMatchesYtDlp() {
        XCTAssertTrue(YouTubeLogin.isLoggedIn([cookie(".youtube.com", "LOGIN_INFO"), cookie(".youtube.com", "SAPISID")]))
        XCTAssertTrue(YouTubeLogin.isLoggedIn([cookie(".youtube.com", "LOGIN_INFO"), cookie(".youtube.com", "__Secure-3PAPISID")]))
        XCTAssertFalse(YouTubeLogin.isLoggedIn([cookie(".youtube.com", "SAPISID")]))            // rotated: no LOGIN_INFO
        XCTAssertFalse(YouTubeLogin.isLoggedIn([cookie(".youtube.com", "LOGIN_INFO")]))
        XCTAssertFalse(YouTubeLogin.isLoggedIn([cookie(".google.com", "LOGIN_INFO"), cookie(".google.com", "SAPISID")]))
        XCTAssertFalse(YouTubeLogin.isLoggedIn([]))
    }

    func testDomainMatch() {
        XCTAssertTrue(YouTubeLogin.domainIs("www.youtube.com", "youtube.com"))
        XCTAssertTrue(YouTubeLogin.domainIs(".YouTube.com", "youtube.com"))
        XCTAssertFalse(YouTubeLogin.domainIs("fakeyoutube.com", "youtube.com"))
    }

    func testSafariUserAgent() {
        let ua = YouTubeLogin.userAgent(osMajor: 27)
        XCTAssertTrue(ua.contains("Version/27.0 Safari/605.1.15"), ua)
        XCTAssertTrue(YouTubeLogin.userAgent(osMajor: 12).contains("Version/15.0"))
    }

    func testSessionLogOut() throws {
        let s = YouTubeSession(file: CookieFile(url: tmp.appendingPathComponent("c.txt")))
        XCTAssertFalse(s.loggedIn); XCTAssertNil(s.savedLogin)
        try s.file.write([cookie(".youtube.com", "A")])
        s.refresh()
        XCTAssertTrue(s.loggedIn); XCTAssertEqual(s.savedLogin, s.file.url)
        YouTubeLogin.inApp = false
        XCTAssertNil(s.savedLogin)   // the switch off: never used
        YouTubeLogin.inApp = true
        s.logOut()
        XCTAssertFalse(s.loggedIn); XCTAssertFalse(s.file.exists)
    }

    // MARK: faceplate copy

    func testLcdCopy() {
        let next = "LOG IN TO YOUTUBE ONCE TO DOWNLOAD IT"
        let age = Faceplate.loginLines(LoginPrompt(url: "u", reason: "age"), inApp: true)
        XCTAssertEqual(age.0, "THIS VIDEO IS AGE-RESTRICTED"); XCTAssertEqual(age.1, next)
        XCTAssertEqual(Faceplate.loginLines(LoginPrompt(url: "u", reason: "bot"), inApp: true).0, "YOUTUBE WANTS A LOGIN")
        XCTAssertEqual(Faceplate.loginLines(LoginPrompt(url: "u", reason: "members"), inApp: true).0, "THIS VIDEO IS FOR MEMBERS")
        // the fallback: a plain readout
        let off = Faceplate.loginLines(LoginPrompt(url: "u", reason: "age"), inApp: false)
        XCTAssertEqual(off.0, "THIS VIDEO IS AGE-RESTRICTED"); XCTAssertEqual(off.1, "BEAT KEY CAN'T DOWNLOAD IT")
    }

    func testCap() {
        XCTAssertEqual(Faceplate.loginCap(busy: false, inApp: true)?.label, "LOG IN TO YOUTUBE")
        XCTAssertEqual(Faceplate.loginCap(busy: false, inApp: true)?.lit, true)
        XCTAssertEqual(Faceplate.loginCap(busy: true, inApp: true)?.lit, false)
        XCTAssertNil(Faceplate.loginCap(busy: false, inApp: false))   // fallback: no button
    }

    func testPromptOnlyForItsLink() {
        let st = ViewState.needsLogin(LoginPrompt(url: "https://a", reason: "bot"))
        XCTAssertNotNil(Faceplate.loginPrompt(st, url: " https://a "))
        XCTAssertNil(Faceplate.loginPrompt(st, url: "https://b"))
        XCTAssertNil(Faceplate.loginPrompt(.idle, url: "https://a"))
        XCTAssertFalse(st.isBusy)
    }

    // MARK: the engine's login state machine

    func testFirstBlockAsksForLogin() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.download("https://a")
        wait(f, 1)
        XCTAssertFalse(f.launches[0].contains("--cookies-file"))
        XCTAssertFalse(f.launches[0].contains("--browser"))
        f.onLine?(#"{"stage":"needs_login","reason":"age","message":"m"}"#); f.onExit?(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(e.state, .needsLogin(LoginPrompt(url: "https://a", reason: "age")))
        XCTAssertEqual(f.launches.count, 1)
        e.clearLogin()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(e.state, .idle)
    }

    func testAfterLoginRunsWithCookiesFile() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f, savedLogin: { URL(fileURLWithPath: "/S/Orion/youtube-cookies.txt") })
        e.download("https://a", useLogin: true)
        wait(f, 1)
        XCTAssertEqual(Array(f.launches[0].suffix(4)), ["download", "https://a", "--cookies-file", "/S/Orion/youtube-cookies.txt"])
    }

    func testUseLoginWithoutSavedLoginAsksAgain() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.download("https://a", useLogin: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(f.launches.count, 0)
        XCTAssertEqual(e.state, .needsLogin(LoginPrompt(url: "https://a", reason: "age")))
    }

    func testLaterBlockUsesSavedLoginWithoutWindow() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f, savedLogin: { URL(fileURLWithPath: "/c.txt") })
        e.download("https://b")
        wait(f, 1)
        XCTAssertFalse(f.launches[0].contains("--cookies-file"))   // a normal video never carries the login
        f.onLine?(#"{"stage":"needs_login","reason":"age","message":"m"}"#)
        wait(f, 2)
        XCTAssertEqual(Array(f.launches[1].suffix(4)), ["download", "https://b", "--cookies-file", "/c.txt"])
        XCTAssertTrue(e.state.isBusy)
        f.exits[0](0)   // the first process ending late changes nothing
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(e.state.isBusy)
        f.onLine?(#"{"stage":"done","file":"/d/b.mp3","name":"b.mp3","bpm":"90.0","keys":[]}"#); f.onExit?(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        if case .done = e.state {} else { XCTFail("\(e.state)") }
    }

    func testStaleLoginIsDeletedAndAsksAgain() {
        let f = FakeLauncher()
        var dropped = 0
        var saved: URL? = URL(fileURLWithPath: "/c.txt")
        let e = Engine(runtime: rt(), launcher: f, savedLogin: { saved }, dropLogin: { dropped += 1; saved = nil })
        e.download("https://a", useLogin: true)
        wait(f, 1)
        f.onLine?(#"{"stage":"needs_login","reason":"age","message":"m","stale":true}"#); f.onExit?(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(e.state, .needsLogin(LoginPrompt(url: "https://a", reason: "age")))
        XCTAssertEqual(f.launches.count, 1)   // no loop
    }

    func testRefusedEvenWithLoginDropsItNoLoop() {
        // the saved login ran and YouTube still asked: drop it, show the prompt, never re-run
        let f = FakeLauncher()
        var dropped = 0
        let e = Engine(runtime: rt(), launcher: f, savedLogin: { URL(fileURLWithPath: "/c.txt") }, dropLogin: { dropped += 1 })
        e.download("https://a")
        wait(f, 1)
        f.onLine?(#"{"stage":"needs_login","reason":"age","message":"m"}"#)
        wait(f, 2)
        f.onLine?(#"{"stage":"needs_login","reason":"age","message":"m"}"#); f.onExit?(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(f.launches.count, 2)
        XCTAssertEqual(e.state, .needsLogin(LoginPrompt(url: "https://a", reason: "age")))
    }

    func testSwitchOffNeverUsesLogin() {
        YouTubeLogin.inApp = false
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f, savedLogin: { URL(fileURLWithPath: "/c.txt") })
        e.download("https://a")
        wait(f, 1)
        f.onLine?(#"{"stage":"needs_login","reason":"age","message":"m"}"#); f.onExit?(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(f.launches.count, 1)
        XCTAssertEqual(e.state, .needsLogin(LoginPrompt(url: "https://a", reason: "age")))
    }

    func testClearLoginLeavesOtherStates() {
        let e = Engine(runtime: rt(), launcher: FakeLauncher())
        e.state = .failed("x"); e.clearLogin()
        XCTAssertEqual(e.state, .failed("x"))
    }

    func testSuccessfulDownloadClearsLogin() {
        let e = Engine(runtime: rt(), launcher: FakeLauncher())
        e.state = .needsLogin(LoginPrompt(url: "u", reason: "age"))
        e.handle(.done(Result(file: URL(fileURLWithPath: "/a.mp3"), name: "a.mp3", bpm: "90.0", keys: [])))
        if case .done = e.state {} else { XCTFail("\(e.state)") }
    }

    func testInfoPlistAsksForNoBrowserData() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let plist = try XCTUnwrap(NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")))
        XCTAssertNil(plist["NSSystemPolicyAppDataDetailedUsageDescription"])
    }

    /// Google gets no WebAuthn: every frame, before the page's own scripts.
    func testHideWebAuthnScript() {
        let s = YouTubeLogin.hideWebAuthnScript()
        XCTAssertEqual(s.injectionTime, .atDocumentStart)
        XCTAssertFalse(s.isForMainFrameOnly)
        for needle in ["delete window.PublicKeyCredential", "isUserVerifyingPlatformAuthenticatorAvailable = no",
                       "isConditionalMediationAvailable = no", "'get'", "'create'"] {
            XCTAssertTrue(s.source.contains(needle), needle)
        }
        XCTAssertTrue(YouTubeLogin.userAgent(osMajor: 15).contains("Version/15.0 Safari/605.1.15"))
    }
}
