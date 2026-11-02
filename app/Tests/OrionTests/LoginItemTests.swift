import XCTest
@testable import Orion

final class LoginItemTests: XCTestCase {
    func tempFolder() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("orion-la-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: u) }
        return u
    }

    // MARK: 2.3 open at login

    func testLaunchAgentWritesAndRemovesItsPlist() throws {
        let agent = LaunchAgentLoginItem(folder: tempFolder(), bundleID: "com.jshriver.orion")
        XCTAssertFalse(agent.isEnabled)
        try agent.setEnabled(true)
        XCTAssertTrue(agent.isEnabled)
        let data = try Data(contentsOf: agent.plist)
        let p = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertEqual(p?["Label"] as? String, "com.jshriver.orion.open-at-login")
        XCTAssertEqual(p?["ProgramArguments"] as? [String], ["/usr/bin/open", "-b", "com.jshriver.orion"])
        XCTAssertEqual(p?["RunAtLoad"] as? Bool, true)
        try agent.setEnabled(false)
        XCTAssertFalse(agent.isEnabled)
        try agent.setEnabled(false)              // off twice is fine
    }

    final class FakeBackend: LoginItemBackend {
        var isEnabled = false
        var needsApproval = false
        var fail = false
        func setEnabled(_ on: Bool) throws {
            if fail { throw NSError(domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: "nope"]) }
            isEnabled = on
        }
    }

    func testSettingsFollowTheBackend() {
        let b = FakeBackend()
        let s = LoginItemSettings(backend: b)
        XCTAssertFalse(s.enabled)
        s.set(true)
        XCTAssertTrue(s.enabled)
        XCTAssertNil(s.message)
        b.needsApproval = true
        s.refresh()
        XCTAssertEqual(s.message, LoginItemSettings.approvalText)
        XCTAssertTrue(s.canOpenSystemSettings)
    }

    func testFailureIsSaid() {
        let b = FakeBackend()
        b.fail = true
        let s = LoginItemSettings(backend: b)
        s.set(true)
        XCTAssertFalse(s.enabled)
        XCTAssertEqual(s.message, "Couldn't change Open at Login: nope")
    }

    func testOldAgentIsReplacedAfterAnUpgrade() throws {
        let legacy = LaunchAgentLoginItem(folder: tempFolder(), bundleID: "com.jshriver.orion")
        try legacy.setEnabled(true)
        let b = FakeBackend()
        let s = LoginItemSettings(backend: b, legacy: legacy)
        XCTAssertTrue(s.enabled)                 // the 12 agent still opens it: say so
        s.set(true)
        XCTAssertTrue(b.isEnabled)
        XCTAssertFalse(legacy.isEnabled)         // one login item, not two
    }
}
