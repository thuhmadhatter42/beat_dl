import XCTest
@testable import Orion

/// A saved input device that is missing falls back to Mac audio (J, 2026-11-05 17:06).
final class LiveFallbackTests: XCTestCase {
    typealias FakePipe = LiveTests.FakePipe
    typealias FakeCapture = LiveTests.FakeCapture

    func defaults() -> UserDefaults {
        let name = "orion-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    func testPlanMissingDeviceFallsBackToSystem() {
        let p = LiveSourcePlan.plan(saved: .input(uid: "scarlett", channel: 3), connectedUIDs: ["builtin"],
                                    systemAvailable: true)
        XCTAssertEqual(p, .fallback(.system, missingUID: "scarlett", channel: 3))
        XCTAssertEqual(p.source, .system)
    }

    func testPlanPresentDeviceIsUsed() {
        let saved = LiveSource.input(uid: "scarlett", channel: 3)
        XCTAssertEqual(LiveSourcePlan.plan(saved: saved, connectedUIDs: ["scarlett", "builtin"], systemAvailable: true),
                       .use(saved))
        // the default input and System Audio are never "missing"
        XCTAssertEqual(LiveSourcePlan.plan(saved: .input(uid: nil, channel: 0), connectedUIDs: [], systemAvailable: true),
                       .use(.input(uid: nil, channel: 0)))
        XCTAssertEqual(LiveSourcePlan.plan(saved: .system, connectedUIDs: [], systemAvailable: true), .use(.system))
    }

    func testPlanWithoutSystemAudioKeepsTheInputError() {
        // macOS 12: nothing to fall back to; InputCapture's "not connected" error stands
        let saved = LiveSource.input(uid: "scarlett", channel: 0)
        XCTAssertEqual(LiveSourcePlan.plan(saved: saved, connectedUIDs: [], systemAvailable: false), .use(saved))
    }

    private func settings(_ source: LiveSource) -> LiveSettings {
        let s = LiveSettings(defaults: defaults(), systemAvailable: true)
        s.source = source
        return s
    }

    func testControllerMissingDeviceOpensMacAudioAndKeepsSavedChoice() {
        let saved = LiveSource.input(uid: "scarlett", channel: 2)
        let s = settings(saved)
        var asked: [LiveSource] = []
        let c = LiveController(settings: s, launch: { _, _, _ in FakePipe() },
                               makeCapture: { src in asked.append(src); return FakeCapture() },
                               devices: { [InputDevice(id: 1, uid: "builtin", name: "MacBook Pro Microphone", channels: 1)] })
        c.start()
        XCTAssertEqual(asked, [.system])
        XCTAssertEqual(c.state, .listening)
        XCTAssertEqual(c.sourceName, "System Audio")
        XCTAssertEqual(c.notice, LiveSourcePlan.fallbackNotice)
        XCTAssertEqual(s.source, saved, "the saved device choice is never overwritten")
        guard case .listening(let status)? = Faceplate.liveReadout(c.state, source: c.sourceName, factor: .one,
                                                                    notice: c.notice) else { return XCTFail() }
        XCTAssertEqual(status, "SAVED INPUT MISSING · USING MAC AUDIO")
        c.stop()
        XCTAssertNil(c.notice)
    }

    func testControllerPresentDeviceOpensTheDevice() {
        let saved = LiveSource.input(uid: "scarlett", channel: 2)
        var asked: [LiveSource] = []
        let c = LiveController(settings: settings(saved), launch: { _, _, _ in FakePipe() },
                               makeCapture: { src in asked.append(src); return FakeCapture() },
                               devices: { [InputDevice(id: 7, uid: "scarlett", name: "Scarlett 4i4", channels: 4)] })
        c.start()
        XCTAssertEqual(asked, [saved])
        XCTAssertEqual(c.sourceName, "Scarlett 4i4 · Ch 2")
        XCTAssertNil(c.notice)
        c.stop()
    }

    func testControllerMacAudioFailureKeepsTheErrorPath() {
        let cap = FakeCapture(), pipe = FakePipe()
        var asked: [LiveSource] = []
        let c = LiveController(settings: settings(.input(uid: "scarlett", channel: 0)), launch: { _, _, _ in pipe },
                               makeCapture: { src in asked.append(src); return cap }, devices: { [] })
        c.start()
        XCTAssertEqual(asked, [.system])
        let denied = "ALLOW BEAT KEY IN SYSTEM SETTINGS › PRIVACY & SECURITY › SCREEN RECORDING"
        cap.onError?(denied)
        let exp = expectation(description: "main hop")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(c.state, .failed(denied))
        XCTAssertTrue(pipe.closed)
        XCTAssertNil(c.notice)
    }
}
