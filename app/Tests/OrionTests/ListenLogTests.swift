import XCTest
@testable import Orion

/// Listen logs what it hears (J, 2026-11-09 23:22: "a missing log is a failure"): the level once a
/// second, each reading change, why it stopped, and the NO SOUND notice after a silence.
final class ListenLogTests: XCTestCase {
    typealias FakePipe = LiveTests.FakePipe
    typealias FakeCapture = LiveTests.FakeCapture

    let t0 = Date(timeIntervalSince1970: 1_000_000)
    private var lines: [String] = []
    private let lock = NSLock()

    override func setUp() {
        super.setUp()
        AppLog.sink = { [weak self] l in
            guard let self = self else { return }
            self.lock.lock(); self.lines.append(l); self.lock.unlock()
        }
    }

    override func tearDown() {
        AppLog.sink = nil
        super.tearDown()
    }

    private func logged() -> [String] { lock.lock(); defer { lock.unlock() }; return lines }

    private func defaults() -> UserDefaults {
        let name = "orion-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    private func drainMain() {
        let exp = expectation(description: "main hop")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
    }

    // MARK: level aggregation and formatting

    func testLevelWindowPeakAndRms() {
        var w = LevelWindow()
        let sine = (0..<44100).map { Float(0.5 * sin(2 * Double.pi * 440 * Double($0) / 44100)) }
        w.add(Array(sine[..<20000]))
        w.add(Array(sine[20000...]))
        let s = w.take()
        XCTAssertEqual(Double(s.peakDB ?? 0), -6.02, accuracy: 0.05)      // 0.5 = -6.02 dBFS
        XCTAssertEqual(Double(s.rmsDB ?? 0), -9.03, accuracy: 0.05)       // a sine's rms is 3 dB under its peak
        XCTAssertEqual(s.text, "level -6.0 dBFS peak, -9.0 dBFS rms")
        // taken: the next second starts empty
        XCTAssertEqual(w.take(), LevelSecond(peakDB: nil, rmsDB: nil))
    }

    /// The level line is a measurement, never a verdict: silence is the analyzer's call.
    func testQuietLevelsAreMeasuredNotJudged() {
        XCTAssertEqual(LevelSecond(peakDB: nil, rmsDB: nil).text, "level none (no audio arriving)")
        var w = LevelWindow()
        w.add([Float](repeating: 0.0001, count: 100))          // -80 dBFS
        XCTAssertEqual(w.take().text, "level -80.0 dBFS peak, -80.0 dBFS rms")
        var z = LevelWindow()
        z.add([0, 0, 0])
        XCTAssertEqual(z.take().text, "level -inf dBFS peak, -inf dBFS rms")
    }

    func testWhatListenHearsIsNamedPerSource() {
        XCTAssertEqual(LiveController.hearing(.system, name: "System Audio"), "all apps except Beat Key")
        XCTAssertEqual(LiveController.hearing(.input(uid: "x", channel: 3), name: "Scarlett 4i4 · Ch 3"),
                       "input Scarlett 4i4 · Ch 3")
    }

    // MARK: reading changes, only on change

    func testChangeLineOnlyOnChange() {
        var c = ChangeLine()
        XCTAssertEqual(c.next("a"), "a")
        XCTAssertNil(c.next("a"))
        XCTAssertEqual(c.next("b"), "b")
        XCTAssertEqual(c.next("a"), "a")
    }

    func testSummaryCarriesKeyBpmAndLamp() {
        let r = Result(file: LiveSession.placeholderFile, name: "LIVE", bpm: "128.0",
                       keys: [("Ebm", 85), ("F#", 8), ("Bbm", 4)])
        XCTAssertEqual(LiveController.summary(.reading(r)), "reading Ebm 85%, F# 8%, Bbm 4% · bpm 128.0 · lamp green")
        XCTAssertEqual(LiveController.summary(.locked(r)), "locked Ebm 85%, F# 8%, Bbm 4% · bpm 128.0 · lamp green")
        XCTAssertEqual(LiveController.summary(.listening), "listening · lamp red")
    }

    func testControllerLogsReadingsOnlyWhenTheyChangeAndWhyItStopped() {
        let r = Result(file: LiveSession.placeholderFile, name: "LIVE", bpm: "128.0",
                       keys: [("Cm", 41), ("Eb", 30), ("Gm", 10)])
        let c = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: { _, _, _ in FakePipe() }, makeCapture: { _ in FakeCapture() },
                               devices: { [] })
        c.start()
        c.handle(.reading(r))
        c.handle(.reading(r))
        c.handle(.reading(r))
        c.stop(reason: "user stop")
        let listen = logged().filter { $0.hasPrefix("[LiveSession] listen:") }
        XCTAssertEqual(listen.filter { $0.contains("reading Cm 41%") }.count, 1, listen.joined(separator: "\n"))
        XCTAssertTrue(listen.contains { $0.contains("reading Cm 41%, Eb 30%, Gm 10% · bpm 128.0 · lamp amber") })
        XCTAssertTrue(listen.contains { $0.contains("listen: start · source Default Input") })
        XCTAssertTrue(listen.contains { $0.contains("listen: hearing input Default Input") })
        XCTAssertTrue(listen.contains("[LiveSession] listen: stopped (user stop)"))
        // already off: no second stop line
        c.stop(reason: "again")
        XCTAssertFalse(logged().contains { $0.contains("stopped (again)") })
    }

    func testNewSongIsTheStopReason() {
        let c = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: { _, _, _ in FakePipe() }, makeCapture: { _ in FakeCapture() },
                               devices: { [] })
        c.start()
        c.reset()
        XCTAssertTrue(logged().contains("[LiveSession] listen: stopped (new song)"))
        c.stop()
    }

    // MARK: NO SOUND comes from the analyzer's silence events, and only from them

    func testNoSoundGoesUpOnTheAnalyzersSilenceAndClearsOnItsSoundBack() {
        var clock = t0
        let cap = FakeCapture()
        let s = LiveSettings(defaults: defaults(), systemAvailable: true)
        s.source = .system
        let c = LiveController(settings: s, launch: { _, _, _ in FakePipe() }, makeCapture: { _ in cap },
                               now: { clock }, devices: { [] })
        c.start()
        for _ in 0..<15 { clock += 1; c.tickLevel() }            // nothing arriving: the app judges nothing
        XCTAssertNil(c.notice)
        c.handle(.silence(db: -120))
        XCTAssertEqual(c.notice, LiveController.noSoundNotice)
        guard case .listening(let status)? = Faceplate.liveReadout(c.state, source: c.sourceName, factor: .one,
                                                                    notice: c.notice) else { return XCTFail() }
        XCTAssertEqual(status, "NO SOUND · CHECK SOURCE")
        cap.onSamples?([Float](repeating: 0.3, count: 4410))      // loud samples alone change nothing
        for _ in 0..<5 { clock += 1; c.tickLevel() }
        XCTAssertEqual(c.notice, LiveController.noSoundNotice)
        c.handle(.sound(db: -14.2, after: 4.5))                   // the analyzer hears it back
        XCTAssertNil(c.notice)
        c.stop(reason: "user stop")
        let got = logged().filter { $0.hasPrefix("[LiveSession]") }
        let text = got.joined(separator: "\n")
        XCTAssertTrue(got.contains("[LiveSession] listen: hearing all apps except Beat Key"), text)
        XCTAssertEqual(got.filter { $0 == "[LiveSession] listen: analyzer says silence (it measured -120.0 dB rms) from all apps except Beat Key; LCD says \"NO SOUND · CHECK SOURCE\"" }.count, 1, text)
        XCTAssertEqual(got.filter { $0 == "[LiveSession] listen: analyzer says sound back (it measured -14.2 dB rms) after 4.5 s silent; NO SOUND cleared" }.count, 1, text)
        XCTAssertEqual(got.filter { $0 == "[LiveSession] listen: level none (no audio arriving)" }.count, 15 + 4, text)
        XCTAssertTrue(got.contains { $0.hasPrefix("[LiveSession] listen: level -10.5 dBFS peak") }, text)
    }

    /// The owner's complaint (2026-11-10): a source at -60 dB peaks over the app's old -70 dB line,
    /// so the app said nothing while the analyzer restarted the reading. The app no longer judges
    /// levels; the analyzer's silence puts NO SOUND up, with the reset it causes.
    func testQuietButNotDigitalSilenceShowsNoSoundWhenTheAnalyzerSaysSo() {
        var clock = t0
        let cap = FakeCapture()
        let c = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: { _, _, _ in FakePipe() }, makeCapture: { _ in cap }, now: { clock },
                               devices: { [] })
        c.start()
        c.handle(.reading(Result(file: LiveSession.placeholderFile, name: "LIVE", bpm: "128.0",
                                 keys: [("Cm", 41), ("Eb", 30), ("Gm", 10)])))
        let quiet = [Float](repeating: 0.001, count: 4410)       // -60 dBFS
        for _ in 0..<10 { cap.onSamples?(quiet); clock += 1; c.tickLevel() }
        XCTAssertNil(c.notice)                                     // the app's own meter decides nothing
        c.handle(.silence(db: -60))
        c.handle(.reset)
        XCTAssertEqual(c.notice, LiveController.noSoundNotice)
        XCTAssertEqual(c.state, .listening)
        c.stop()
    }

    /// A stale silence after Stop shows nothing.
    func testSilenceAfterStopShowsNothing() {
        let c = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: { _, _, _ in FakePipe() }, makeCapture: { _ in FakeCapture() },
                               devices: { [] })
        c.start()
        c.stop()
        c.handle(.silence(db: -120))
        XCTAssertNil(c.notice)
    }

    /// The 20 Hz meter never logs: only a full second does.
    func testMeterTicksLogOncePerSecond() {
        var clock = t0
        let cap = FakeCapture()
        let c = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: { _, _, _ in FakePipe() }, makeCapture: { _ in cap }, now: { clock },
                               devices: { [] })
        c.start()
        for _ in 0..<65 { cap.onSamples?([0.1, -0.2]); clock += 0.05; c.tickLevel() }   // 3.25 s at 20 Hz
        c.stop()
        let levels = logged().filter { $0.hasPrefix("[LiveSession] listen: level") }
        XCTAssertEqual(levels.count, 3, levels.joined(separator: "\n"))
    }

    // MARK: proof: a synthetic song through the real live path → the log lines

    /// A 120 BPM click over an A-minor drone, fed like a capture into the real `bpm.py --stream`
    /// through LiveController: the log gets a level line each second and the readings as they change.
    func testSyntheticStreamThroughTheLivePathLogsLevelsAndReadings() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let script = repo.appendingPathComponent("bpm.py")
        let python = [repo.appendingPathComponent("bin/python/bin/python3"),
                      URL(fileURLWithPath: "/Users/jshriver/dev/beat_dl/bin/python/bin/python3")]
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        guard let py = python else { throw XCTSkip("no bundled Python (bin/python)") }
        var clock = t0
        let cap = FakeCapture()
        let launch: LiveLauncher = { gap, onLine, onExit in
            LiveProcess(executable: py, arguments: [script.path, "--stream", "--rate", "44100", "--gap", String(gap)],
                        environment: ["PATH": "/usr/bin:/bin"], onLine: onLine, onExit: onExit)
        }
        let c = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: launch, makeCapture: { _ in cap }, now: { clock }, devices: { [] })
        c.start()
        let sr = 44100.0
        for piece in 0..<160 {                                   // 16 s in 0.1 s pieces
            let samples = (0..<4410).map { i -> Float in
                let t = Double(piece * 4410 + i) / sr
                let click = t.truncatingRemainder(dividingBy: 0.5) < 0.01 ? 0.6 * sin(2 * .pi * 1000 * t) : 0
                let drone = 0.08 * (sin(2 * .pi * 220 * t) + sin(2 * .pi * 261.63 * t) + sin(2 * .pi * 329.63 * t))
                return Float(click + drone)
            }
            cap.onSamples?(samples)
            clock += 0.1
            c.tickLevel()
        }
        let deadline = Date().addingTimeInterval(120)
        func bpms() -> [Double] {
            logged().compactMap { l -> Double? in
                guard l.contains("listen: reading") || l.contains("listen: locked"),
                      let r = l.range(of: "· bpm ") else { return nil }
                return Double(l[r.upperBound...].prefix { $0.isNumber || $0 == "." })
            }
        }
        while Date() < deadline, !bpms().contains(where: { Int($0.rounded()) == 120 }) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        c.stop(reason: "user stop")
        let got = logged().filter { $0.hasPrefix("[LiveSession] listen:") }
        let text = got.joined(separator: "\n")
        print("---- beatkey.log lines from the synthetic stream ----\n" + text + "\n----")
        XCTAssertGreaterThanOrEqual(got.filter { $0.contains("dBFS peak") }.count, 15, text)
        XCTAssertTrue(got.contains { $0.contains("listen: reading") || $0.contains("listen: locked") }, text)
        XCTAssertTrue(bpms().contains { Int($0.rounded()) == 120 }, text)
        XCTAssertTrue(got.contains { $0.contains("Am") && $0.contains("· bpm ") }, text)
        XCTAssertTrue(got.contains("[LiveSession] listen: stopped (user stop)"), text)
        XCTAssertFalse(got.contains { $0.hasPrefix("[LiveSession] listen: off · source ") && $0 == got.first }, text)
    }

    /// The owner's complaint through the real `bpm.py --stream`: music, then a -60 dB RMS tone
    /// (peaks at -57 dBFS, over the app's old -70 dB line, under the analyzer's -50 dB one). The
    /// analyzer's silence reaches the LCD as NO SOUND, with the reset, and music clears it.
    func testQuietSourceThroughTheRealAnalyzerShowsNoSound() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let script = repo.appendingPathComponent("bpm.py")
        let python = [repo.appendingPathComponent("bin/python/bin/python3"),
                      URL(fileURLWithPath: "/Users/jshriver/dev/beat_dl/bin/python/bin/python3")]
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        guard let py = python else { throw XCTSkip("no bundled Python (bin/python)") }
        let cap = FakeCapture()
        let launch: LiveLauncher = { gap, onLine, onExit in
            LiveProcess(executable: py, arguments: [script.path, "--stream", "--rate", "44100", "--gap", String(gap)],
                        environment: ["PATH": "/usr/bin:/bin"], onLine: onLine, onExit: onExit)
        }
        let c = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: launch, makeCapture: { _ in cap }, devices: { [] })
        c.start()
        let sr = 44100.0
        func music(_ piece: Int) -> [Float] {
            (0..<4410).map { i -> Float in
                let t = Double(piece * 4410 + i) / sr
                let click = t.truncatingRemainder(dividingBy: 0.5) < 0.01 ? 0.6 * sin(2 * .pi * 1000 * t) : 0
                return Float(click + 0.08 * (sin(2 * .pi * 220 * t) + sin(2 * .pi * 261.63 * t)))
            }
        }
        let quiet = (0..<4410).map { Float(0.001 * 2.0.squareRoot() * sin(2 * .pi * 1000 * Double($0) / sr)) }
        for piece in 0..<50 { cap.onSamples?(music(piece)) }           // 5 s of music
        for _ in 0..<60 { cap.onSamples?(quiet) }                       // 6 s at -60 dB RMS
        func wait(until ok: () -> Bool) {
            let deadline = Date().addingTimeInterval(120)
            while Date() < deadline, !ok() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        }
        wait { c.notice != nil }
        XCTAssertEqual(c.notice, LiveController.noSoundNotice, logged().joined(separator: "\n"))
        for piece in 0..<10 { cap.onSamples?(music(piece)) }           // music again
        wait { c.notice == nil }
        XCTAssertNil(c.notice)
        c.stop(reason: "user stop")
        let got = logged().filter { $0.hasPrefix("[LiveSession] listen:") }
        let text = got.joined(separator: "\n")
        print("---- beatkey.log lines from the quiet source ----\n" + text + "\n----")
        XCTAssertTrue(got.contains { $0.hasPrefix("[LiveSession] listen: analyzer says silence (it measured -60.0 dB rms)") }, text)
        XCTAssertTrue(got.contains { $0.hasPrefix("[LiveSession] listen: analyzer says sound back") }, text)
    }
}
