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

    func testFlowNeedsAccessGrantedRestartPending() {
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
        f.leave(); f.blocked(url: "https://b", browser: "chrome")   // locked while restarting
        XCTAssertEqual(f.phase, .restarting(p!))
    }

    func testFlowSameLinkAgainChangesNothingANewOneAsksAgain() {
        var f = AccessFlow()
        f.blocked(url: "https://a", browser: "brave"); f.checked(.granted)
        f.blocked(url: "https://a", browser: "brave")
        XCTAssertEqual(f.phase, .granted(browser: "brave"))
        f.blocked(url: "https://b", browser: "brave")
        XCTAssertEqual(f.phase, .asking(browser: "brave"))
        XCTAssertEqual(f.url, "https://b")
    }

    func testFlowLeavingReturnsToNormal() {
        var f = AccessFlow()
        f.blocked(url: "https://a", browser: "brave")
        f.leave()
        XCTAssertEqual(f.phase, .closed)
        f.blocked(url: "https://a", browser: "brave"); f.checked(.granted); f.leave()
        XCTAssertEqual(f.phase, .closed)
    }

    func testControllerWaitsUntilGrantedThenRelaunchesWithTheRetrySavedAndRetriesOnce() {
        var answer = AccessStatus.denied
        let lock = NSLock()
        var opened: [String] = []
        let probe = AccessProbe(home: URL(fileURLWithPath: "/H"), open: { path in
            lock.lock(); defer { lock.unlock() }
            opened.append(path)
            switch answer { case .granted: return nil; case .denied: return EPERM; case .unknown: return ENOENT }
        })
        let store = PendingRetryStore(defaults: freshDefaults())
        var relaunches = 0
        let c = AccessController(probe: probe, store: store, interval: 0.05, relaunch: { relaunches += 1; return true })
        var published: [AccessPhase] = []
        let sub = c.$phase.dropFirst().sink { published.append($0) }
        c.blocked(url: "https://a", browser: "brave")
        XCTAssertEqual(c.phase, .asking(browser: "brave"))
        XCTAssertTrue(c.isWatching)
        spin(0.4)
        XCTAssertEqual(c.phase, .asking(browser: "brave"))
        XCTAssertGreaterThan(c.checks, 3, "it keeps checking while it asks")
        XCTAssertEqual(published, [.asking(browser: "brave")], "a denied tick publishes nothing")
        lock.lock(); XCTAssertEqual(opened.first, "/H/Library/Safari"); lock.unlock()   // the silent canary first
        c.blocked(url: "https://a", browser: "brave")       // the same prompt again: no restart, no publish
        XCTAssertEqual(published.count, 1)
        lock.lock(); answer = .granted; lock.unlock()
        spin(0.4)
        XCTAssertEqual(c.phase, .granted(browser: "brave"))
        XCTAssertEqual(published, [.asking(browser: "brave"), .granted(browser: "brave")])
        XCTAssertFalse(c.isWatching, "the wait stops once granted")
        lock.lock(); let n = opened.count; lock.unlock()
        spin(0.2)
        lock.lock(); XCTAssertEqual(opened.count, n); lock.unlock()
        c.restart()
        XCTAssertEqual(relaunches, 1)
        XCTAssertEqual(c.phase, .restarting(PendingRetry(url: "https://a", browser: "brave")))
        // the relaunched app takes it once: the auto-retry runs once
        XCTAssertEqual(store.take(), PendingRetry(url: "https://a", browser: "brave"))
        XCTAssertNil(store.take())
        sub.cancel()
    }

    func testControllerChecksWhenTheAppBecomesActive() {
        let c = AccessController(probe: AccessProbe(home: URL(fileURLWithPath: "/H"), open: { _ in EPERM }),
                                 store: PendingRetryStore(defaults: freshDefaults()), interval: 60)
        c.blocked(url: "https://a", browser: "brave")
        spin(0.1)
        XCTAssertEqual(c.checks, 1)                         // the first check, at once
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        spin(0.1)
        XCTAssertEqual(c.checks, 2)                         // back from System Settings
        c.leave()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        spin(0.1)
        XCTAssertEqual(c.checks, 2, "no checks after leaving")
        XCTAssertFalse(c.isWatching)
    }

    func testControllerWithoutABundleRetriesHereOnce() {
        let store = PendingRetryStore(defaults: freshDefaults())
        let c = AccessController(probe: AccessProbe(home: URL(fileURLWithPath: "/H"), open: { _ in nil }),
                                 store: store, interval: 10, relaunch: { false })
        var retried: [PendingRetry] = []
        c.retryHere = { retried.append($0) }
        c.blocked(url: "https://a", browser: "chrome")     // checks at once: granted
        spin(0.2)
        XCTAssertEqual(c.phase, .granted(browser: "chrome"))
        c.restart()
        XCTAssertEqual(retried, [PendingRetry(url: "https://a", browser: "chrome")])
        XCTAssertEqual(c.phase, .closed)
        XCTAssertNil(store.take())
        c.restart()
        XCTAssertEqual(retried.count, 1)
    }

    func testLeavingStopsTheWait() {
        let c = AccessController(probe: AccessProbe(home: URL(fileURLWithPath: "/H"), open: { _ in EPERM }),
                                 store: PendingRetryStore(defaults: freshDefaults()), interval: 0.05)
        c.leave()
        XCTAssertEqual(c.phase, .closed)                  // nothing open: nothing happens
        c.blocked(url: "https://a", browser: "brave")
        c.leave()
        XCTAssertEqual(c.phase, .closed)
        XCTAssertFalse(c.isWatching)
        let n = c.checks
        spin(0.2)
        XCTAssertEqual(c.checks, n)
    }

    func testPinnedNeverChecks() {
        let c = AccessController(probe: AccessProbe(home: URL(fileURLWithPath: "/H"), open: { _ in nil }),
                                 store: PendingRetryStore(defaults: freshDefaults()), interval: 0.05)
        c.pin(.asking(browser: "brave"), url: "https://a")
        c.blocked(url: "https://a", browser: "brave")
        spin(0.2)
        XCTAssertEqual(c.phase, .asking(browser: "brave"))
        XCTAssertEqual(c.checks, 0)
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

    func testFaceplateCopy() {
        XCTAssertEqual(AccessCopy.lines(.asking(browser: "brave")).0, "TURN ON FULL DISK ACCESS")
        XCTAssertEqual(AccessCopy.lines(.asking(browser: "brave")).1, "SO BEAT KEY CAN USE YOUR BROWSER LOGIN")
        XCTAssertEqual(AccessCopy.lines(.asking(browser: "brave")).2,
                       "SYSTEM SETTINGS › PRIVACY & SECURITY › FULL DISK ACCESS › BEAT KEY")
        XCTAssertEqual(AccessCopy.lines(.granted(browser: "brave")).0, "ACCESS ON")
        XCTAssertEqual(AccessCopy.lines(.granted(browser: "brave")).1, "RESTART TO USE IT")
        XCTAssertNil(AccessCopy.lines(.granted(browser: "brave")).2)
        XCTAssertEqual(AccessCopy.cap(.asking(browser: "brave")).label, "OPEN SETTINGS")
        XCTAssertTrue(AccessCopy.cap(.asking(browser: "brave")).lit)
        XCTAssertEqual(AccessCopy.cap(.granted(browser: "brave")).label, "RESTART & RETRY")
        XCTAssertTrue(AccessCopy.cap(.granted(browser: "brave")).lit)
        XCTAssertFalse(AccessCopy.cap(.restarting(PendingRetry(url: "https://a", browser: "brave"))).lit)
        for s in [AccessCopy.lcdFirst, AccessCopy.lcdSecond, AccessCopy.lcdPath, Doctor.accessLine("brave")] {
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

    private func spin(_ t: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }

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
