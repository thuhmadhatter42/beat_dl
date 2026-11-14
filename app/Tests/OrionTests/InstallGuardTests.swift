import XCTest
@testable import Orion

/// The launch-time twin check's decisions (the 5-second replaced-under-me poll is gone).
final class InstallGuardTests: XCTestCase {
    func testVersionCompareIsNumeric() {
        XCTAssertEqual(InstallVersion.compare("0.1.9", "0.1.10"), .orderedAscending)
        XCTAssertEqual(InstallVersion.compare("0.1.72", "0.1.8"), .orderedDescending)
        XCTAssertEqual(InstallVersion.compare("1.0", "1.0.0"), .orderedSame)
    }

    func testOnDiskReadsFreshVersion() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ig-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(InstallVersion.onDisk(bundle: dir))
        let plist: [String: Any] = ["CFBundleShortVersionString": "0.1.72"]
        try (plist as NSDictionary).write(to: dir.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(InstallVersion.onDisk(bundle: dir), "0.1.72")
    }

    func testTwinDecision() {
        let old = OtherInstance(pid: 10, path: "/Applications/Beat Key.app", version: "0.1.8")
        let new = OtherInstance(pid: 11, path: "/Volumes/x/Beat Key.app", version: "0.1.73")
        XCTAssertEqual(TwinCheck.decide(myVersion: "0.1.72", others: []), .none)
        XCTAssertEqual(TwinCheck.decide(myVersion: "0.1.72", others: [old]), .takeOver([old]))
        XCTAssertEqual(TwinCheck.decide(myVersion: "0.1.72", others: [old, new]), .yieldTo(new))
        // same version (an in-place replaced copy reads the new version from disk): take over
        let same = OtherInstance(pid: 12, path: "/Applications/Beat Key.app", version: "0.1.72")
        XCTAssertEqual(TwinCheck.decide(myVersion: "0.1.72", others: [same]), .takeOver([same]))
    }
}
