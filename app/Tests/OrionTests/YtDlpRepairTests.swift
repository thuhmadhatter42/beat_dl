import XCTest
@testable import Orion

/// The one yt-dlp repair ladder (Runtime.repairYtDlp), as the weekly upgrade and Run Doctor see it.
/// Commands go to a FakeRunner; the stamp lands in a temp App Support folder.
final class YtDlpRepairTests: XCTestCase {
    struct Boom: Error, CustomStringConvertible { var description: String { "disk full" } }
    final class Counter { var n = 0 }

    var tmp: URL!
    var rt: Runtime!
    var logged: [String] = []

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("orion-repair-\(UUID().uuidString)")
        rt = Runtime(root: tmp.appendingPathComponent("runtime"), arch: "arm64",
                     support: tmp.appendingPathComponent("support"), osMajor: 14)
        logged = []
        AppLog.sink = { [weak self] l in self?.logged.append(l) }
    }

    override func tearDown() {
        AppLog.sink = nil
        try? FileManager.default.removeItem(at: tmp)
    }

    var stampWritten: Bool { FileManager.default.fileExists(atPath: rt.stamp.path) }

    func doctor(_ r: FakeRunner, reseed: @escaping () throws -> Void) -> Doctor {
        Doctor(runtime: rt, runner: r, reseed: reseed, downloadsWritable: { true })
    }

    // 1 yt-dlp runs: -U, no restore, stamp written.
    func testFineNoReseedStampWritten() throws {
        let r = FakeRunner()
        r.answers["yt-dlp --version"] = [(0, "2026.10.26\n")]
        let n = Counter()
        let out = try rt.repairYtDlp(runner: r, reseed: { n.n += 1 })
        XCTAssertEqual(out, YtDlpRepair(restored: false, before: "2026.10.26", after: "2026.10.26"))
        XCTAssertEqual(n.n, 0)
        XCTAssertEqual(r.calls, ["yt-dlp --version", "yt-dlp -U", "yt-dlp --version"])
        XCTAssertTrue(stampWritten)
        XCTAssertFalse(rt.needsWeeklyUpgrade)

        let r2 = FakeRunner(); r2.answers["yt-dlp --version"] = [(0, "2026.10.26\n")]
        XCTAssertEqual(doctor(r2, reseed: {}).run { _ in },
                       DoctorReport(outcome: .ok, title: "DOCTOR OK", line: "YT-DLP 2026.10.26 · ALL CHECKS PASSED"))
    }

    // 2 missing before -U: the bundled copy is restored first, then -U runs on it.
    func testMissingThenRestored() throws {
        let r = FakeRunner()
        r.answers["yt-dlp --version"] = [(-1, "no such file"), (0, "2026.08.19")]
        let n = Counter()
        let out = try rt.repairYtDlp(runner: r, reseed: { n.n += 1 })
        XCTAssertEqual(out, YtDlpRepair(restored: true, before: nil, after: "2026.08.19"))
        XCTAssertEqual(n.n, 1)
        XCTAssertEqual(r.calls, ["yt-dlp --version", "yt-dlp -U", "yt-dlp --version"])
        XCTAssertTrue(stampWritten)
        XCTAssertTrue(logged.contains { $0.contains("restoring the bundled copy") })

        let r2 = FakeRunner(); r2.answers["yt-dlp --version"] = [(-1, ""), (0, "2026.08.19")]
        XCTAssertEqual(doctor(r2, reseed: {}).run { _ in },
                       DoctorReport(outcome: .fixed, title: "DOCTOR FIXED IT", line: "RESTORED YT-DLP · YT-DLP 2026.08.19"))
    }

    // 3 -U breaks a working yt-dlp: ad-hoc sign the updated file, still broken, restore the bundled copy.
    func testUpgradeBreaksItReseedRestores() throws {
        let r = FakeRunner()
        r.answers["yt-dlp --version"] = [(0, "2026.10.01"), (1, ""), (1, ""), (0, "2026.10.01")]
        let n = Counter()
        let out = try rt.repairYtDlp(runner: r, reseed: { n.n += 1 })
        XCTAssertEqual(out, YtDlpRepair(restored: true, before: "2026.10.01", after: "2026.10.01"))
        XCTAssertEqual(n.n, 1)
        XCTAssertEqual(r.calls, ["yt-dlp --version", "yt-dlp -U", "yt-dlp --version",
                                 "codesign -s", "yt-dlp --version", "yt-dlp --version"])
        XCTAssertTrue(stampWritten)

        let r2 = FakeRunner()
        r2.answers["yt-dlp --version"] = [(0, "2026.10.01"), (1, ""), (1, ""), (0, "2026.10.01")]
        XCTAssertEqual(doctor(r2, reseed: {}).run { _ in },
                       DoctorReport(outcome: .fixed, title: "DOCTOR FIXED IT", line: "RESTORED YT-DLP · YT-DLP 2026.10.01"))
    }

    // 3b the ad-hoc signature is enough: no restore, the update is kept.
    func testUpgradeBlockedAdHocSignFixesIt() throws {
        let r = FakeRunner()
        r.answers["yt-dlp --version"] = [(0, "2026.10.01"), (-1, "Killed: 9"), (0, "2026.10.26")]
        let n = Counter()
        let out = try rt.repairYtDlp(runner: r, reseed: { n.n += 1 })
        XCTAssertEqual(out, YtDlpRepair(restored: false, before: "2026.10.01", after: "2026.10.26"))
        XCTAssertEqual(n.n, 0)
        XCTAssertTrue(logged.contains { $0.contains("ad-hoc signing") })

        let r2 = FakeRunner()
        r2.answers["yt-dlp --version"] = [(0, "2026.10.01"), (-1, "Killed: 9"), (0, "2026.10.26")]
        XCTAssertEqual(doctor(r2, reseed: {}).run { _ in },
                       DoctorReport(outcome: .ok, title: "DOCTOR OK", line: "YT-DLP UPDATED TO 2026.10.26 · ALL CHECKS PASSED"))
    }

    // 4 nothing works: thrown to the background caller, logged, no stamp; Doctor shows its won't-run line.
    func testNothingWorksSurfacedToBothCallers() {
        let r = FakeRunner()
        r.answers["yt-dlp --version"] = [(-2, "timed out")]
        XCTAssertThrowsError(try rt.repairYtDlp(runner: r, reseed: {})) { e in
            XCTAssertEqual(e as? YtDlpRepairError, .wontRun)
        }
        XCTAssertFalse(stampWritten)
        XCTAssertTrue(logged.contains { $0.contains("yt-dlp still does not run; downloads will fail") })

        let r2 = FakeRunner(); r2.answers["yt-dlp --version"] = [(-2, "timed out")]
        let rep = doctor(r2, reseed: {}).run { _ in }
        XCTAssertEqual(rep, DoctorReport(outcome: .failed, title: "DOCTOR FOUND A PROBLEM",
                                         line: "YT-DLP WON'T RUN · REINSTALL BEAT KEY"))
    }

    // 5 the restore itself throws: reported (thrown + logged), never swallowed; nothing more is tried.
    func testReseedThrowingIsReported() {
        let r = FakeRunner()
        r.answers["yt-dlp --version"] = [(-1, "")]
        XCTAssertThrowsError(try rt.repairYtDlp(runner: r, reseed: { throw Boom() })) { e in
            XCTAssertEqual(e as? YtDlpRepairError, .reseedFailed("disk full"))
        }
        XCTAssertEqual(r.calls, ["yt-dlp --version"])        // no -U on a yt-dlp that is not there
        XCTAssertFalse(stampWritten)
        XCTAssertTrue(logged.contains { $0.contains("restoring the bundled copy failed: disk full") })

        let r2 = FakeRunner(); r2.answers["yt-dlp --version"] = [(-1, "")]
        let rep = doctor(r2, reseed: { throw Boom() }).run { _ in }
        XCTAssertEqual(rep.outcome, .failed)
        XCTAssertEqual(rep.line, "YT-DLP WON'T RUN · REINSTALL BEAT KEY")
    }

    // The stamp has one writer: a fresh seed and a repair both go through Runtime.touchStamp.
    func testSeedWritesStampOnlyWhenItRestores() throws {
        let r = FakeRunner(); r.answers["yt-dlp --version"] = [(0, "2026.10.26")]
        let n = Counter()
        try rt.seedYtDlp(runner: r, reseed: { n.n += 1 })
        XCTAssertEqual(n.n, 0)
        XCTAssertFalse(stampWritten)
        let r2 = FakeRunner(); r2.answers["yt-dlp --version"] = [(1, "")]
        try rt.seedYtDlp(runner: r2, reseed: { n.n += 1 })
        XCTAssertEqual(n.n, 1)
        XCTAssertTrue(stampWritten)
    }
}
