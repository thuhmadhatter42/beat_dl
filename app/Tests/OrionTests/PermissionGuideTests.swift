import XCTest
@testable import Orion

/// The permission walkthrough's logic, with the system checks injected (no real TCC).
final class PermissionGuideTests: XCTestCase {
    final class Fake: PermissionChecking {
        var states: [PermissionKind: PermissionState] = [.screen: .denied, .microphone: .notDetermined, .accessibility: .denied]
        var prompts: [PermissionKind] = []
        var opened: [PermissionKind] = []
        var openWorks = true
        var relaunchWorks = true
        var relaunched = 0
        func state(_ k: PermissionKind) -> PermissionState { states[k] ?? .denied }
        func prompt(_ k: PermissionKind) { prompts.append(k) }
        func openSettings(_ k: PermissionKind) -> Bool { opened.append(k); return openWorks }
        func relaunch() -> Bool { relaunched += 1; return relaunchWorks }
    }

    private var lines: [String] = []
    private let lock = NSLock()

    override func setUp() {
        super.setUp()
        AppLog.sink = { [weak self] l in
            guard let self = self else { return }
            self.lock.lock(); self.lines.append(l); self.lock.unlock()
        }
    }

    override func tearDown() { AppLog.sink = nil; super.tearDown() }

    private func logged() -> [String] { lock.lock(); defer { lock.unlock() }; return lines }

    private func defaults() -> UserDefaults {
        let name = "orion-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    private func make(_ f: Fake = Fake(), _ d: UserDefaults? = nil) -> (PermissionGuideModel, Fake, UserDefaults) {
        let dd = d ?? defaults()
        return (PermissionGuideModel(checker: f, defaults: dd), f, dd)
    }

    func testOrderIsScreenMicrophoneAccessibility() {
        XCTAssertEqual(PermissionGuideModel.order, [.screen, .microphone, .accessibility])
    }

    func testBeginOpensFirstMissingAndAsksTheSystemOnce() {
        let (m, f, _) = make()
        XCTAssertTrue(m.begin(why: "test"))
        XCTAssertEqual(m.current, .screen)
        XCTAssertEqual(f.prompts, [.screen])
        m.tick()
        XCTAssertEqual(f.prompts, [.screen], "polling never prompts again")
    }

    func testGrantIsConfirmedForOneTickThenAdvances() {
        let (m, f, _) = make()
        m.begin(why: "test")
        f.states[.screen] = .granted
        m.tick()
        XCTAssertEqual(m.confirming, .screen)
        XCTAssertEqual(m.current, .screen)
        XCTAssertEqual(m.status[.screen], .granted)
        m.tick()
        XCTAssertNil(m.confirming)
        XCTAssertEqual(m.current, .microphone)
        XCTAssertTrue(logged().contains { $0.contains("screen granted") })
    }

    func testMicrophoneAsksTheOSDialogFirstAndOnlyThenSettings() {
        let (m, f, _) = make()
        f.states[.screen] = .granted
        m.begin(why: "test")
        XCTAssertEqual(m.current, .microphone)
        XCTAssertEqual(f.prompts, [.microphone])
        XCTAssertTrue(m.awaitingPrompt)
        f.states[.microphone] = .denied   // answered No in the dialog
        m.tick()
        XCTAssertFalse(m.awaitingPrompt)
        XCTAssertEqual(m.current, .microphone, "denied stays open: Settings is the way")
        m.openSettings()
        XCTAssertEqual(f.opened, [.microphone])
    }

    func testDeniedMicrophoneIsNeverPrompted() {
        let (m, f, _) = make()
        f.states = [.screen: .granted, .microphone: .denied, .accessibility: .granted]
        m.begin(why: "test")
        XCTAssertEqual(m.current, .microphone)
        XCTAssertTrue(f.prompts.isEmpty)
        XCTAssertFalse(m.awaitingPrompt)
    }

    func testSkipAdvancesAndPersists() {
        let (m, f, d) = make()
        m.begin(why: "test")
        m.skip()
        XCTAssertEqual(m.status[.screen], .skipped)
        XCTAssertEqual(m.current, .microphone)
        XCTAssertEqual(m.skipped, [.screen])
        let again = PermissionGuideModel(checker: f, defaults: d)
        XCTAssertEqual(again.skipped, [.screen])
        XCTAssertTrue(again.hasMissing, "microphone and accessibility still missing")
        again.refresh()
        XCTAssertEqual(again.status[.screen], .skipped)
    }

    func testAllSkippedOrGrantedMeansNothingMissingAtLaunch() {
        let (m, f, _) = make()
        f.states[.accessibility] = .granted
        m.skipped = [.screen, .microphone]
        XCTAssertFalse(m.hasMissing)
    }

    func testFeatureNeedBringsBackASkippedStepAndGoesToItFirst() {
        let (m, _, _) = make()
        m.skipped = [.accessibility]
        XCTAssertTrue(m.begin(at: .accessibility, why: "Send to DAW"))
        XCTAssertEqual(m.current, .accessibility)
        XCTAssertEqual(m.skipped, [])
    }

    func testFeatureNeedForGrantedStepOpensFirstMissingInstead() {
        let (m, f, _) = make()
        f.states[.accessibility] = .granted
        m.begin(at: .accessibility, why: "Send to DAW")
        XCTAssertEqual(m.current, .screen)
    }

    func testFinishedWhenEverythingGranted() {
        let (m, f, _) = make()
        m.begin(why: "test")
        for k in PermissionKind.allCases { f.states[k] = .granted }
        for _ in 0..<(PermissionKind.allCases.count * 2) { m.tick() }
        XCTAssertNil(m.current)
        XCTAssertTrue(m.isComplete)
        XCTAssertFalse(m.hasMissing)
    }

    func testOpenSettingsFailureIsShownAndLogged() {
        let (m, f, _) = make()
        f.openWorks = false
        m.begin(why: "test")
        m.openSettings()
        XCTAssertTrue(m.openFailed)
        XCTAssertTrue(logged().contains { $0.contains("FAILED to open System Settings for screen") })
    }

    func testRelaunchOnlyOffersAfterSettingsForScreen() {
        let (m, f, _) = make()
        m.begin(why: "test")
        XCTAssertFalse(m.offersRelaunch)
        m.openSettings()
        XCTAssertTrue(m.offersRelaunch)
        m.relaunch()
        XCTAssertEqual(f.relaunched, 1)
        XCTAssertTrue(m.resumePending)
        f.states[.screen] = .granted
        m.tick()
        XCTAssertFalse(m.resumePending, "a grant clears the pending resume")
    }

    func testFailedRelaunchClearsResume() {
        let (m, f, _) = make()
        f.relaunchWorks = false
        m.begin(why: "test")
        m.relaunch()
        XCTAssertFalse(m.resumePending)
        XCTAssertTrue(logged().contains { $0.contains("FAILED to relaunch") })
    }

    func testResumeAfterRelaunchContinuesWithNextMissing() {
        let (m, f, d) = make()
        m.begin(why: "test")
        m.openSettings()
        m.relaunch()
        // new launch: Screen Recording now reads granted
        f.states[.screen] = .granted
        let next = PermissionGuideModel(checker: f, defaults: d)
        XCTAssertTrue(next.resumePending)
        next.begin(why: "relaunch resume")
        XCTAssertEqual(next.current, .microphone)
    }

    func testSettingsURLs() {
        XCTAssertEqual(PermissionKind.screen.legacyURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        XCTAssertEqual(PermissionKind.microphone.legacyURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        XCTAssertEqual(PermissionKind.accessibility.legacyURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        XCTAssertTrue(PermissionKind.screen.modernURL.absoluteString.hasSuffix(".extension?Privacy_ScreenCapture"))
        XCTAssertEqual(PermissionKind.screen.settingsURLs.last, PermissionKind.screen.legacyURL)
    }

    func testEveryStepShownIsLogged() {
        let (m, _, _) = make()
        m.begin(why: "test")
        XCTAssertTrue(logged().contains { $0.contains("step screen shown") })
        XCTAssertTrue(logged().contains { $0.contains("guide begins (test)") })
    }
}
