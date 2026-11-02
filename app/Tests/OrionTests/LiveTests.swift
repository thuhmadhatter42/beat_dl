import AVFoundation
import ScreenCaptureKit
import XCTest
@testable import Orion

final class LiveTests: XCTestCase {
    func reading(_ key: String = "Ebm", _ pct: Int = 85, bpm: String? = "128.0") -> Result {
        Result(file: LiveSession.placeholderFile, name: "LIVE", bpm: bpm,
               keys: [(key, pct), ("Gb", 8), ("Bbm", 4)], bpmExact: bpm == nil ? nil : 128.02)
    }
    func defaults() -> UserDefaults {
        let name = "orion-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: 3.3 the analyzer's lines

    func testParsesStreamLines() {
        XCTAssertEqual(LiveEvent.parse(line: #"{"event":"ready"}"#), .ready)
        XCTAssertEqual(LiveEvent.parse(line: #"{"event":"reset"}"#), .reset)
        XCTAssertEqual(LiveEvent.parse(line: #"{"event":"error","message":"x"}"#), .error("x"))
        let line = #"{"event":"reading","bpm":"128.0","bpm_exact":128.02,"keys":[["Ebm",85],["Gb",8],["Bbm",4]],"secs":14.0}"#
        XCTAssertEqual(LiveEvent.parse(line: line), .reading(reading()))
        let early = #"{"event":"reading","bpm":null,"bpm_exact":null,"keys":[["Ebm",85],["Gb",8],["Bbm",4]],"secs":4.0}"#
        guard case .reading(let r)? = LiveEvent.parse(line: early) else { return XCTFail() }
        XCTAssertNil(r.bpm)
        XCTAssertNil(LiveEvent.parse(line: "garbage"))
        XCTAssertNil(LiveEvent.parse(line: #"{"event":"reading","keys":[["Ebm"]]}"#))
        XCTAssertNil(LiveEvent.parse(line: #"{"stage":"done"}"#))
    }

    // MARK: 3.3 auto-lock and start over

    func testAutoLocksAfterSixSecondsOfTheSameConfidentKey() {
        var s = LiveSession()
        s.begin()
        XCTAssertEqual(s.state, .listening)
        s.feed(.reading(reading()), now: t0)
        XCTAssertEqual(s.state, .reading(reading()))
        s.feed(.reading(reading()), now: t0 + 4)
        XCTAssertEqual(s.state.lamp, .locked)               // green, not yet held
        guard case .reading = s.state else { return XCTFail() }
        s.feed(.reading(reading()), now: t0 + 6)
        XCTAssertEqual(s.state, .locked(reading()))
        // held: later readings don't move it
        s.feed(.reading(reading("Am", 90)), now: t0 + 8)
        XCTAssertEqual(s.state, .locked(reading()))
    }

    func testUnsureOrChangedKeyRestartsTheClock() {
        var s = LiveSession()
        s.begin()
        s.feed(.reading(reading()), now: t0)
        s.feed(.reading(reading("Ebm", 50)), now: t0 + 2)  // amber
        XCTAssertEqual(s.state.lamp, .unsure)
        s.feed(.reading(reading()), now: t0 + 4)
        s.feed(.reading(reading()), now: t0 + 8)
        guard case .reading = s.state else { return XCTFail("locked too early") }
        s.feed(.reading(reading("Gb", 80)), now: t0 + 10)  // another key
        s.feed(.reading(reading("Gb", 80)), now: t0 + 14)
        guard case .reading = s.state else { return XCTFail("locked on a fresh key too early") }
        s.feed(.reading(reading("Gb", 80)), now: t0 + 16)
        XCTAssertEqual(s.state, .locked(reading("Gb", 80)))
    }

    func testNoLockWithoutABpm() {
        var s = LiveSession()
        s.begin()
        s.feed(.reading(reading(bpm: nil)), now: t0)
        s.feed(.reading(reading(bpm: nil)), now: t0 + 10)
        guard case .reading = s.state else { return XCTFail() }
    }

    func testGapStartsOver() {
        var s = LiveSession()
        s.begin()
        s.feed(.reading(reading()), now: t0)
        s.feed(.reading(reading()), now: t0 + 6)
        XCTAssertEqual(s.state, .locked(reading()))
        s.feed(.reset, now: t0 + 10)
        XCTAssertEqual(s.state, .listening)
        s.feed(.reading(reading("Am", 90)), now: t0 + 12)
        XCTAssertEqual(s.state, .reading(reading("Am", 90)))   // the clock started over too
    }

    func testErrorsAndOffIgnoreReadings() {
        var s = LiveSession()
        s.feed(.reading(reading()), now: t0)
        XCTAssertEqual(s.state, .off)
        s.begin()
        s.feed(.error("boom"), now: t0)
        XCTAssertEqual(s.state, .failed("boom"))
        s.feed(.reading(reading()), now: t0)
        XCTAssertEqual(s.state, .failed("boom"))
    }

    func testLampsAndCaptions() {
        XCTAssertEqual(LiveState.listening.lamp, .listening)
        XCTAssertEqual(LiveState.listening.status(source: "System Audio"), "LISTENING · SYSTEM AUDIO")
        XCTAssertEqual(LiveState.reading(reading("Cm", 41)).lamp, .unsure)
        XCTAssertEqual(LiveState.reading(reading()).status(source: "x"), "LOCKED 85%")
        XCTAssertEqual(LiveState.locked(reading()).status(source: "x"), "LOCKED 85% · HELD")
        XCTAssertNil(LiveState.off.lamp)
        XCTAssertFalse(LiveState.failed("x").isActive)
    }

    func testLcdReadoutWhileListening() {
        XCTAssertNil(Faceplate.liveReadout(.off, source: "x", factor: .one))
        guard case .listening(let status)? = Faceplate.liveReadout(.listening, source: "Mic", factor: .one)
        else { return XCTFail() }
        XCTAssertEqual(status, "LISTENING · MIC")
        guard case .result(let r, nil, false, nil, let o)? = Faceplate.liveReadout(.locked(reading()), source: "Mic", factor: .double)
        else { return XCTFail() }
        XCTAssertEqual(r, reading())
        XCTAssertEqual(o.factor, .double)
        XCTAssertEqual(o.live?.lamp, .locked)
        XCTAssertEqual(o.live?.status, "LOCKED 85% · HELD")
        XCTAssertEqual(o.live?.source, "Mic")
        guard case .error(let m, false, let hint)? = Faceplate.liveReadout(.failed("NO"), source: "Mic", factor: .one)
        else { return XCTFail() }
        XCTAssertEqual(m, "NO")
        XCTAssertEqual(hint, Faceplate.liveRetryHint)
    }

    func testMenuBarWhileListening() {
        XCTAssertNil(MenuBarReadout.of(live: .off, source: "x", factor: .one))
        XCTAssertEqual(MenuBarReadout.of(live: .listening, source: "Mic", factor: .one)?.lamp, .listening)
        let m = MenuBarReadout.of(live: .locked(reading()), source: "Mic", factor: .one)
        XCTAssertEqual(m?.text, "Ebm 128.0")
        XCTAssertEqual(m?.lamp, .locked)
        XCTAssertEqual(MenuBarReadout.of(live: .reading(reading("Cm", 41)), source: "Mic", factor: .one)?.lamp, .unsure)
    }

    // MARK: 3.1 / 3.2 sources

    func testSourceStorageRoundTrips() {
        for s in [LiveSource.system, .input(uid: nil, channel: 0), .input(uid: "AppleUSB:1:2", channel: 3)] {
            XCTAssertEqual(LiveSource.from(stored: s.stored), s)
        }
        XCTAssertNil(LiveSource.from(stored: "input:x:y"))
        XCTAssertNil(LiveSource.from(stored: nil))
    }

    func testSettingsDefaultsAndMacOS12() {
        let d = defaults()
        XCTAssertEqual(LiveSettings(defaults: d, systemAvailable: true).source, .system)
        XCTAssertEqual(LiveSettings(defaults: d, systemAvailable: false).source, .input(uid: nil, channel: 0))
        let s = LiveSettings(defaults: d, systemAvailable: true)
        s.source = .system
        XCTAssertEqual(LiveSettings(defaults: d, systemAvailable: false).source, .input(uid: nil, channel: 0))
        s.source = .input(uid: "u1", channel: 2)
        s.gap = 5
        let again = LiveSettings(defaults: d, systemAvailable: true)
        XCTAssertEqual(again.source, .input(uid: "u1", channel: 2))
        XCTAssertEqual(again.gap, 5)
        XCTAssertEqual(LiveSettings(defaults: defaults()).gap, 3)
    }

    func testSourceNames() {
        let s = LiveSettings(defaults: defaults(), systemAvailable: true)
        let devs = [InputDevice(id: 7, uid: "u1", name: "Scarlett 4i4", channels: 4)]
        s.source = .system
        XCTAssertEqual(s.sourceName(devices: devs), "System Audio")
        s.source = .input(uid: "u1", channel: 3)
        XCTAssertEqual(s.sourceName(devices: devs), "Scarlett 4i4 · Ch 3")
        s.source = .input(uid: nil, channel: 0)
        XCTAssertEqual(s.sourceName(devices: devs), "Default Input")
        s.source = .input(uid: "gone", channel: 0)
        XCTAssertEqual(s.sourceName(devices: devs), "Missing Input")
    }

    func testMonoMixAndChannelPick() {
        let a: [Float] = [1, 1, 1], b: [Float] = [0, 0.5, 1]
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                XCTAssertEqual(PCM.mono([pa, pb], channel: 0), [0.5, 0.75, 1])
                XCTAssertEqual(PCM.mono([pa, pb], channel: 2), [0, 0.5, 1])
                XCTAssertEqual(PCM.mono([pa, pb], channel: 9), [0.5, 0.75, 1])   // missing channel: the mix
            }
        }
    }

    func testMonoFromAnAVAudioBuffer() {
        let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
        let buf = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: 4)!
        buf.frameLength = 4
        for i in 0..<4 { buf.floatChannelData![0][i] = 1; buf.floatChannelData![1][i] = 0 }
        XCTAssertEqual(PCM.mono(buf, channel: 0), [0.5, 0.5, 0.5, 0.5])
        XCTAssertEqual(PCM.mono(buf, channel: 1), [1, 1, 1, 1])
    }

    func testResamplerTo44k() {
        XCTAssertEqual(Resampler(from: 44100)!.process([1, 2, 3]), [1, 2, 3])   // pass-through
        let r = Resampler(from: 48000)!
        var total = 0
        for _ in 0..<10 { total += r.process([Float](repeating: 0.1, count: 4800)).count }
        XCTAssertEqual(Double(total), 44100, accuracy: 600)                      // 1 s in, ~1 s out
    }

    @available(macOS 13.0, *)
    func testSystemAudioBuffersToMono() {
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(list.unsafeMutablePointer) }
        var l: [Float] = [1, 1, 1, 1], r: [Float] = [0, 0, 1, 1]
        l.withUnsafeMutableBytes { lp in
            r.withUnsafeMutableBytes { rp in
                list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: lp.baseAddress)
                list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: rp.baseAddress)
                XCTAssertEqual(SystemAudioCapture.mono(list), [0.5, 0.5, 1, 1])
            }
        }
        let one = AudioBufferList.allocate(maximumBuffers: 1)
        defer { free(one.unsafeMutablePointer) }
        var inter: [Float] = [1, 0, 1, 0, 1, 1]          // L R interleaved, 3 frames
        inter.withUnsafeMutableBytes { p in
            one[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 24, mData: p.baseAddress)
            XCTAssertEqual(SystemAudioCapture.mono(one), [0.5, 0.5, 1])
        }
    }

    @available(macOS 13.0, *)
    func testSystemAudioPermissionErrorSaysWhereToAllow() {
        let declined = NSError(domain: SCStreamErrorDomain, code: SCStreamError.userDeclined.rawValue)
        XCTAssertEqual(SystemAudioCapture.text(declined), SystemAudioCapture.permissionText)
        XCTAssertTrue(SystemAudioCapture.permissionText.hasPrefix("ALLOW BEAT KEY IN SYSTEM SETTINGS"))
        XCTAssertTrue(LiveController.realCapture(.system) is SystemAudioCapture)
        XCTAssertTrue(LiveController.realCapture(.input(uid: nil, channel: 0)) is InputCapture)
    }

    func testUsageStringsAndEntitlementForListening() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()      // app/
        let plist = try XCTUnwrap(NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")))
        XCTAssertTrue((plist["NSMicrophoneUsageDescription"] as? String)?.contains("Nothing is recorded") == true)
        XCTAssertNotNil(plist["NSAudioCaptureUsageDescription"] as? String)
        let ents = try XCTUnwrap(NSDictionary(contentsOf: app.appendingPathComponent("entitlements-app.plist")))
        XCTAssertEqual(ents["com.apple.security.device.audio-input"] as? Bool, true)
        // the app is signed with it, the runtime's binaries are not
        let build = try String(contentsOf: app.appendingPathComponent("build.sh"), encoding: .utf8)
        XCTAssertTrue(build.contains(#"--entitlements "$APP/entitlements-app.plist""#))
        let runtime = try String(contentsOf: app.appendingPathComponent("runtime.sh"), encoding: .utf8)
        XCTAssertFalse(runtime.contains("entitlements-app.plist"))
    }

    func testSilenceFiller() {
        var f = SilenceFiller(rate: 44100, tick: 0.5, now: t0)
        XCTAssertEqual(f.zeros(at: t0 + 0.4), 0)
        XCTAssertEqual(f.zeros(at: t0 + 0.6), 22050)
        XCTAssertEqual(f.zeros(at: t0 + 0.9), 0)          // a tick since the last fill
        f.heard(at: t0 + 1.0)
        XCTAssertEqual(f.zeros(at: t0 + 1.3), 0)
        XCTAssertEqual(f.zeros(at: t0 + 1.6), 22050)
    }

    // MARK: the controller, with a fake capture and analyzer

    final class FakePipe: LivePipe {
        var written = 0
        var closed = false
        func write(_ samples: [Float]) { written += samples.count }
        func close() { closed = true }
    }

    final class FakeCapture: AudioCapture {
        var onSamples: (([Float]) -> Void)?
        var onError: ((String) -> Void)?
        var stopped = false
        func start(onSamples: @escaping ([Float]) -> Void, onError: @escaping (String) -> Void) {
            self.onSamples = onSamples; self.onError = onError
        }
        func stop() { stopped = true }
    }

    func testControllerRunsAndStops() {
        let pipe = FakePipe(), cap = FakeCapture()
        var lineOut: ((String) -> Void)?
        var gapAsked: Double?
        let c = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: { gap, onLine, _ in gapAsked = gap; lineOut = onLine; return pipe },
                               makeCapture: { _ in cap })
        c.start()
        XCTAssertEqual(c.state, .listening)
        XCTAssertEqual(gapAsked, 3)
        cap.onSamples?([0, 0, 0])
        XCTAssertEqual(pipe.written, 3)
        lineOut?(#"{"event":"reading","bpm":"128.0","bpm_exact":128.02,"keys":[["Ebm",85],["Gb",8],["Bbm",4]]}"#)
        let exp = expectation(description: "main hop")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(c.state, .reading(reading()))
        c.stop()
        XCTAssertEqual(c.state, .off)
        XCTAssertTrue(pipe.closed)
        XCTAssertTrue(cap.stopped)
    }

    /// New Song: a locked reading is dropped at once, a fresh analyzer and capture start, the lamp
    /// goes back to red LISTENING. With Listen off it does nothing.
    func testNewSongResetsALock() {
        var pipes: [FakePipe] = [], caps: [FakeCapture] = []
        let c = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: { _, _, _ in let p = FakePipe(); pipes.append(p); return p },
                               makeCapture: { _ in let k = FakeCapture(); caps.append(k); return k })
        c.reset()
        XCTAssertEqual(c.state, .off)
        XCTAssertTrue(pipes.isEmpty)
        c.start()
        c.handle(.reading(reading()), gen: nil)
        c.handle(.reading(reading()), gen: nil)
        XCTAssertEqual(c.state, .reading(reading()))
        c.reset()
        XCTAssertEqual(c.state, .listening)
        XCTAssertEqual(c.state.lamp, .listening)
        XCTAssertEqual(pipes.count, 2)
        XCTAssertTrue(pipes[0].closed)
        XCTAssertTrue(caps[0].stopped)
        XCTAssertFalse(pipes[1].closed)
        c.stop()
    }

    func testControllerFailures() {
        let c = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: { _, _, _ in nil }, makeCapture: { _ in FakeCapture() })
        c.start()
        XCTAssertEqual(c.state, .failed("THE ANALYZER WOULDN'T START"))
        let none = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                                  launch: { _, _, _ in FakePipe() }, makeCapture: { _ in nil })
        none.start()
        guard case .failed = none.state else { return XCTFail() }
        // a capture error stops everything
        let pipe = FakePipe(), cap = FakeCapture()
        let d = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: { _, _, _ in pipe }, makeCapture: { _ in cap })
        d.start()
        cap.onError?(InputCapture.deniedText)
        let exp = expectation(description: "main hop")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(d.state, .failed(InputCapture.deniedText))
        XCTAssertTrue(pipe.closed)
        XCTAssertTrue(cap.stopped)
    }

    func testSilenceIsFilledWhenTheCaptureGoesQuiet() {
        let pipe = FakePipe()
        var clock = t0
        let c = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: { _, _, _ in pipe }, makeCapture: { _ in FakeCapture() }, now: { clock })
        c.start()
        clock = t0 + 0.6
        c.fillSilence()
        XCTAssertEqual(pipe.written, 22050)
        c.stop()
    }

    // MARK: 3.3 end to end: Swift's pipe into the real `bpm.py --stream`

    func testRealAnalyzerReadsWhatThePipeWrites() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let script = repo.appendingPathComponent("bpm.py")
        let python = [repo.appendingPathComponent("bin/python/bin/python3"),
                      URL(fileURLWithPath: "/Users/jshriver/dev/beat_dl/bin/python/bin/python3")]
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        guard let py = python else { throw XCTSkip("no bundled Python (bin/python)") }
        var lines: [String] = []
        let lock = NSLock()
        let exited = expectation(description: "analyzer exits at EOF")
        guard let p = LiveProcess(executable: py, arguments: [script.path, "--stream", "--hop", "2"],
                                  environment: ["PATH": "/usr/bin:/bin"],
                                  onLine: { l in lock.lock(); lines.append(l); lock.unlock() },
                                  onExit: { _ in exited.fulfill() })
        else { return XCTFail("did not start") }
        // 14 s of a 120 BPM click over an A-minor drone, in 0.1 s pieces like a capture's
        let sr = 44100.0
        for piece in 0..<140 {
            let samples = (0..<4410).map { i -> Float in
                let t = Double(piece * 4410 + i) / sr
                let click = t.truncatingRemainder(dividingBy: 0.5) < 0.01 ? 0.9 * sin(2 * .pi * 1000 * t) : 0
                let drone = 0.08 * (sin(2 * .pi * 220 * t) + sin(2 * .pi * 261.63 * t) + sin(2 * .pi * 329.63 * t))
                return Float(click + drone)
            }
            p.write(samples)
        }
        p.close(grace: 100)   // let it finish the backlog (the app's Stop gives it 2 s)
        wait(for: [exited], timeout: 120)
        lock.lock(); let got = lines; lock.unlock()
        let events = got.compactMap(LiveEvent.parse)
        XCTAssertEqual(events.first, .ready)
        let readings = events.compactMap { e -> Result? in if case .reading(let r) = e { return r } else { return nil } }
        XCTAssertFalse(readings.isEmpty, got.joined(separator: "\n"))
        let last = try XCTUnwrap(readings.last)
        XCTAssertEqual(last.bpm.flatMap(Double.init).map { Int($0.rounded()) }, 120)
        XCTAssertTrue(last.keys.map(\.0).contains("Am"))
    }
}
