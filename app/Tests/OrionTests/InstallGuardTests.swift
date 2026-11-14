import XCTest
@testable import Orion

/// The install guard's decisions, with the disk and the process list injected.
final class InstallGuardTests: XCTestCase {
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

    func testVersionCompareIsNumeric() {
        XCTAssertEqual(InstallVersion.compare("0.1.9", "0.1.10"), .orderedAscending)
        XCTAssertEqual(InstallVersion.compare("0.1.72", "0.1.8"), .orderedDescending)
        XCTAssertEqual(InstallVersion.compare("1.0", "1.0.0"), .orderedSame)
    }

    func testDecideCases() {
        let s = { (v: String?, i: UInt64?) in BundleSnapshot(version: v, inode: i) }
        XCTAssertEqual(InstallGuard.decide(running: "0.1.8", snapshot: s(nil, nil), firstInode: 1, asked: []), .unreadable)
        XCTAssertEqual(InstallGuard.decide(running: "0.1.8", snapshot: s("0.1.8", 1), firstInode: 1, asked: []), .same)
        XCTAssertEqual(InstallGuard.decide(running: "0.1.8", snapshot: s("0.1.8", 2), firstInode: 1, asked: []), .replacedSameVersion)
        XCTAssertEqual(InstallGuard.decide(running: "0.1.8", snapshot: s("0.1.72", 2), firstInode: 1, asked: []), .newVersion("0.1.72"))
        XCTAssertEqual(InstallGuard.decide(running: "0.1.8", snapshot: s("0.1.72", 2), firstInode: 1, asked: ["0.1.72"]), .alreadyAsked("0.1.72"))
    }

    func testPromptsOncePerVersionAndAgainForTheNext() {
        var snap = BundleSnapshot(version: "0.1.8", inode: 1)
        var asks: [(String, Bool)] = []
        let g = InstallGuard(running: "0.1.8", read: { snap }, ask: { asks.append(($0, $1)) })
        g.isBusy = { true }
        XCTAssertEqual(g.check(), .same)
        snap = BundleSnapshot(version: nil, inode: nil)          // mid-copy
        XCTAssertEqual(g.check(), .unreadable)
        XCTAssertEqual(g.check(), .unreadable)
        snap = BundleSnapshot(version: "0.1.72", inode: 5)
        XCTAssertEqual(g.check(), .newVersion("0.1.72"))
        XCTAssertEqual(g.check(), .alreadyAsked("0.1.72"))
        XCTAssertEqual(asks.count, 1)
        XCTAssertEqual(asks.first?.0, "0.1.72")
        XCTAssertEqual(asks.first?.1, true, "busy is passed on, never auto-relaunched")
        snap = BundleSnapshot(version: "0.1.73", inode: 6)
        XCTAssertEqual(g.check(), .newVersion("0.1.73"))
        XCTAssertEqual(asks.count, 2)
        let l = logged().filter { $0.contains("install guard:") }
        XCTAssertEqual(l.filter { $0.contains("unreadable") }.count, 1, "unreadable logged once per spell")
        XCTAssertTrue(l.contains { $0.contains("version mismatch: running 0.1.8, on disk 0.1.72") })
    }

    func testReplacedSameVersionIsLoggedNotAsked() {
        var snap = BundleSnapshot(version: "0.1.8", inode: 1)
        var asks = 0
        let g = InstallGuard(running: "0.1.8", read: { snap }, ask: { _, _ in asks += 1 })
        snap = BundleSnapshot(version: "0.1.8", inode: 9)
        XCTAssertEqual(g.check(), .replacedSameVersion)
        XCTAssertEqual(g.check(), .same)
        XCTAssertEqual(asks, 0)
    }

    func testOnDiskReadsFreshVersion() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ig-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(InstallVersion.onDisk(bundle: dir).version)
        let plist: [String: Any] = ["CFBundleShortVersionString": "0.1.72"]
        try (plist as NSDictionary).write(to: dir.appendingPathComponent("Contents/Info.plist"))
        let s = InstallVersion.onDisk(bundle: dir)
        XCTAssertEqual(s.version, "0.1.72")
        XCTAssertNotNil(s.inode)
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
