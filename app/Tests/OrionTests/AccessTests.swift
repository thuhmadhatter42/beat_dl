import XCTest
@testable import Orion

final class AccessTests: XCTestCase {
    // MARK: event

    func testParseNeedsAccess() {
        XCTAssertEqual(Event.parse(line: #"{"stage":"needs_access","browser":"brave","message":"m"}"#),
                       .needsAccess(browser: "brave", message: "m"))
        XCTAssertNil(Event.parse(line: #"{"stage":"needs_access"}"#))
    }

    func testEngineTurnsNeedsAccessIntoItsState() {
        let f = FakeLauncher()
        let e = Engine(runtime: Runtime(root: URL(fileURLWithPath: "/R"), arch: "arm64",
                                        support: URL(fileURLWithPath: "/S"), osMajor: 27), launcher: f)
        e.download("https://a", browser: "brave")
        let deadline = Date().addingTimeInterval(5)
        while f.launches.isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(Array(f.launches[0].suffix(4)), ["download", "https://a", "--browser", "brave"])
        f.onLine?(#"{"stage":"needs_access","browser":"brave","message":"m"}"#)
        f.onExit?(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(e.state, .needsAccess(AccessPrompt(url: "https://a", browser: "brave")))
        XCTAssertFalse(e.state.isBusy)
        e.clearAccess()
        XCTAssertEqual(e.state, .idle)
    }

    func testKnownBlockedAsksBeforeTheRun() {
        let f = FakeLauncher()
        var noted: [String] = []
        let e = Engine(runtime: Runtime(root: URL(fileURLWithPath: "/R"), arch: "arm64",
                                        support: URL(fileURLWithPath: "/S"), osMajor: 27), launcher: f,
                       accessCheck: { _ in .denied }, noteLogin: { noted.append($0) })
        e.download("https://a", browser: "chrome")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(f.launches.isEmpty)
        XCTAssertEqual(e.state, .needsAccess(AccessPrompt(url: "https://a", browser: "chrome")))
        XCTAssertEqual(noted, ["chrome"])
        // a plain download never checks
        e.clearAccess()
        e.download("https://a")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(noted, ["chrome"])
    }

    func testUnknownOrGrantedRunsNormally() {
        for s in [AccessStatus.granted, .unknown] {
            let f = FakeLauncher()
            let e = Engine(runtime: Runtime(root: URL(fileURLWithPath: "/R"), arch: "arm64",
                                            support: URL(fileURLWithPath: "/S"), osMajor: 27), launcher: f,
                           accessCheck: { _ in s })
            e.download("https://a", browser: "brave")
            let deadline = Date().addingTimeInterval(5)
            while f.launches.isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            XCTAssertEqual(f.launches.count, 1, "\(s)")
        }
    }

    // MARK: state machine

    func testFlowBlockedOpenGrantedRestart() {
        var f = AccessFlow()
        XCTAssertFalse(f.phase.isOpen)
        f.checked(.granted)                       // nothing to grant while closed
        XCTAssertEqual(f.phase, .closed)
        f.blocked(url: "https://a", browser: "brave")
        XCTAssertEqual(f.phase, .asking(browser: "brave"))
        XCTAssertNil(f.restart())                 // no restart before access
        f.checked(.denied); f.checked(.unknown)
        XCTAssertEqual(f.phase, .asking(browser: "brave"))
        f.checked(.granted)
        XCTAssertEqual(f.phase, .granted(browser: "brave"))
        let p = f.restart()
        XCTAssertEqual(p, PendingRetry(url: "https://a", browser: "brave"))
        XCTAssertEqual(f.phase, .restarting(p!))
        f.dismiss(); f.blocked(url: "https://b", browser: "chrome")   // locked while restarting
        XCTAssertEqual(f.phase, .restarting(p!))
    }

    func testFlowNotNowCloses() {
        var f = AccessFlow()
        f.blocked(url: "https://a", browser: "brave")
        f.dismiss()
        XCTAssertEqual(f.phase, .closed)
        f.blocked(url: "https://a", browser: "brave"); f.checked(.granted); f.dismiss()
        XCTAssertEqual(f.phase, .closed)
    }

    func testControllerPollsUntilGrantedThenRelaunchesWithTheRetrySaved() {
        var answer = AccessStatus.denied
        var opened: [String] = []
        let probe = AccessProbe(home: URL(fileURLWithPath: "/H"), open: { path in
            opened.append(path)
            switch answer { case .granted: return nil; case .denied: return EPERM; case .unknown: return ENOENT }
        })
        let store = PendingRetryStore(defaults: freshDefaults())
        var relaunches = 0
        let c = AccessController(probe: probe, store: store, interval: 0.05, relaunch: { relaunches += 1; return true })
        var closed = 0
        c.onClose = { closed += 1 }
        c.blocked(url: "https://a", browser: "brave")
        XCTAssertEqual(c.phase, .asking(browser: "brave"))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(c.phase, .asking(browser: "brave"))
        XCTAssertEqual(opened.first, "/H/Library/Safari")     // the silent canary first
        answer = .granted
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(c.phase, .granted(browser: "brave"))
        let n = opened.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(opened.count, n, "polling stops once granted")
        c.restart()
        XCTAssertEqual(relaunches, 1)
        XCTAssertEqual(closed, 0)
        // the relaunched app takes it once
        XCTAssertEqual(store.take(), PendingRetry(url: "https://a", browser: "brave"))
        XCTAssertNil(store.take())
    }

    func testControllerWithoutABundleRetriesHereOnce() {
        let store = PendingRetryStore(defaults: freshDefaults())
        let c = AccessController(probe: AccessProbe(home: URL(fileURLWithPath: "/H"), open: { _ in nil }),
                                 store: store, interval: 10, relaunch: { false })
        var retried: [PendingRetry] = []
        c.retryHere = { retried.append($0) }
        c.blocked(url: "https://a", browser: "chrome")     // checks at once: granted
        XCTAssertEqual(c.phase, .granted(browser: "chrome"))
        c.restart()
        XCTAssertEqual(retried, [PendingRetry(url: "https://a", browser: "chrome")])
        XCTAssertEqual(c.phase, .closed)
        XCTAssertNil(store.take())
    }

    func testNotNowTellsTheFaceplate() {
        let c = AccessController(probe: AccessProbe(home: URL(fileURLWithPath: "/H"), open: { _ in EPERM }),
                                 store: PendingRetryStore(defaults: freshDefaults()), interval: 10)
        var closed = 0
        c.onClose = { closed += 1 }
        c.dismiss()
        XCTAssertEqual(closed, 0)          // nothing open
        c.blocked(url: "https://a", browser: "brave")
        c.dismiss()
        XCTAssertEqual(closed, 1)
        XCTAssertEqual(c.phase, .closed)
    }

    // MARK: probe

    func testProbePaths() {
        var opened: [String] = []
        let p = AccessProbe(home: URL(fileURLWithPath: "/H"), open: { opened.append($0); return EPERM })
        XCTAssertEqual(p.browserData("brave"), .denied)
        XCTAssertEqual(opened, ["/H/Library/Application Support/BraveSoftware/Brave-Browser"])
        XCTAssertEqual(p.browserData("nope"), .unknown)
        opened = []
        XCTAssertEqual(p.browserData("safari"), .denied)
        XCTAssertEqual(opened, ["/H/Library/Containers/com.apple.Safari/Data/Library/Cookies"])
    }

    func testCanaryFallsBackToTheBrowserFolderWhenAbsent() {
        // no canary exists: the browser's folder decides
        let p = AccessProbe(home: URL(fileURLWithPath: "/H"), open: { $0.contains("Brave") ? nil : ENOENT })
        XCTAssertEqual(p.fullDisk(), .unknown)
        XCTAssertEqual(p.waitingCheck("brave", withBrowser: false), .granted)
        // canary denied; the browser folder is only opened on its tick
        var opened: [String] = []
        let q = AccessProbe(home: URL(fileURLWithPath: "/H"), open: { opened.append($0); return $0.hasSuffix("Safari") ? EPERM : nil })
        XCTAssertEqual(q.waitingCheck("brave", withBrowser: false), .denied)
        XCTAssertEqual(opened, ["/H/Library/Safari"])
        XCTAssertEqual(q.waitingCheck("brave", withBrowser: true), .granted)   // a per-folder grant
    }

    func testRealProbeOnAMissingPathIsUnknown() {
        let p = AccessProbe(home: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("no-such-home-\(getpid())"))
        XCTAssertEqual(p.browserData("brave"), .unknown)
        XCTAssertEqual(p.fullDisk(), .unknown)
        let tmp = AccessProbe(home: URL(fileURLWithPath: "/"))
        XCTAssertNil(AccessProbe.openDir(tmp.home.path))
    }

    // MARK: persistence

    func testPendingRetryIsUsedOnce() {
        let d = freshDefaults()
        let s = PendingRetryStore(defaults: d)
        XCTAssertNil(s.take())
        s.save(PendingRetry(url: "https://a", browser: "brave"))
        XCTAssertEqual(PendingRetryStore(defaults: d).take(), PendingRetry(url: "https://a", browser: "brave"))
        XCTAssertNil(d.string(forKey: PendingRetryStore.urlKey))
        XCTAssertNil(d.string(forKey: PendingRetryStore.browserKey))
        XCTAssertNil(s.take())
        d.set("https://a", forKey: PendingRetryStore.urlKey)          // half a retry is none
        XCTAssertNil(s.take())
        XCTAssertNil(d.string(forKey: PendingRetryStore.urlKey))
    }

    // MARK: deep link

    func testSettingsURLPerMacOSMajor() {
        XCTAssertEqual(FullDiskAccessPane.url(osMajor: 12).absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        for v in [13, 14, 15, 26, 27] {
            XCTAssertEqual(FullDiskAccessPane.url(osMajor: v).absoluteString,
                           "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
        }
    }

    func testRelaunchCommandWaitsThenOpensANewInstance() {
        let c = Relauncher.command(pid: 42, bundle: URL(fileURLWithPath: "/Applications/Beat Key.app"))
        XCTAssertEqual(c[0], "/bin/sh")
        XCTAssertEqual(c[2], "while /bin/kill -0 42 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open -n '/Applications/Beat Key.app'")
        XCTAssertFalse(Relauncher.relaunch(bundle: URL(fileURLWithPath: "/usr/bin")))   // swift run: no .app
    }

    // MARK: copy

    func testCopy() {
        XCTAssertEqual(AccessCopy.title, "Let Beat Key read your YouTube login")
        XCTAssertEqual(AccessCopy.sentence("brave"),
                       "macOS keeps other apps' data private. To use your Brave login, turn on Full Disk Access for Beat Key.")
        XCTAssertEqual(AccessCopy.steps, ["Click Open System Settings", "Turn on Beat Key", "Come back here"])
        XCTAssertEqual(AccessCopy.notListed, "If it's not in the list: click +, choose Beat Key in Applications")
        for s in [AccessCopy.title, AccessCopy.sentence("chrome"), AccessCopy.lcdSecond, Doctor.accessLine("brave")] {
            XCTAssertFalse(s.lowercased().contains("files"), s)
        }
    }

    func testDoctorLineOnlyAfterALogin() {
        let rt = Runtime(root: URL(fileURLWithPath: "/R"), arch: "arm64", support: URL(fileURLWithPath: "/S"), osMajor: 27)
        let ok = AlwaysOK()
        let never = Doctor(runtime: rt, runner: ok, reseed: {}, downloadsWritable: { true }, loginBlocked: { nil })
        XCTAssertEqual(never.run { _ in }.outcome, .ok)
        let tried = Doctor(runtime: rt, runner: ok, reseed: {}, downloadsWritable: { true }, loginBlocked: { "brave" })
        let r = tried.run { _ in }
        XCTAssertEqual(r.outcome, .failed)
        XCTAssertEqual(r.line, "TURN ON FULL DISK ACCESS FOR BEAT KEY TO USE YOUR BRAVE LOGIN")
    }

    private func freshDefaults() -> UserDefaults {
        let name = "orion-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
}

private struct AlwaysOK: CommandRunner {
    func run(_ exe: URL, _ args: [String], environment: [String: String]?, timeout: TimeInterval) -> (status: Int32, output: String) {
        (0, "2026.10.26\n")
    }
}
