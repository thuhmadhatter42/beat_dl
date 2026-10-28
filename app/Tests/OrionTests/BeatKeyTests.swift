import XCTest
@testable import Orion

/// Answers each command by tool name + first argument, in order; records every call.
final class FakeRunner: CommandRunner {
    var answers: [String: [(Int32, String)]] = [:]
    var calls: [String] = []
    func run(_ exe: URL, _ args: [String], environment: [String: String]?, timeout: TimeInterval) -> (status: Int32, output: String) {
        let key = "\(exe.lastPathComponent) \(args.first ?? "")"
        calls.append(key)
        guard var q = answers[key], !q.isEmpty else { return (0, "") }
        let a = q.removeFirst()
        if !q.isEmpty { answers[key] = q }   // the last answer repeats
        return a
    }
}

final class BeatKeyTests: XCTestCase {
    let rt = Runtime(root: URL(fileURLWithPath: "/R/runtime"), arch: "arm64",
                     support: URL(fileURLWithPath: "/nonexistent-orion-test/Orion"), osMajor: 14)

    // MARK: second row

    func testPickLabel() {
        XCTAssertNil(Faceplate.pickLabel([]))
        XCTAssertEqual(Faceplate.pickLabel([URL(fileURLWithPath: "/a/x.wav")]), "x.wav")
        XCTAssertEqual(Faceplate.pickLabel(["a", "b", "c"].map { URL(fileURLWithPath: "/a/\($0).mp3") }), "3 files")
    }

    func testFindCapLitRule() {
        let one = [URL(fileURLWithPath: "/a/x.wav")]
        XCTAssertFalse(Faceplate.isFindLit([], busy: false))
        XCTAssertTrue(Faceplate.isFindLit(one, busy: false))
        XCTAssertFalse(Faceplate.isFindLit(one, busy: true))
    }

    // MARK: public name

    func testPublicNameComesFromOnePlace() throws {
        XCTAssertEqual(Brand.name, "Beat Key")
        XCTAssertEqual(Brand.wordmark, "BEAT KEY")
        XCTAssertEqual(Brand.about, "About Beat Key")
        XCTAssertEqual(Brand.hide, "Hide Beat Key")
        XCTAssertEqual(Brand.quit, "Quit Beat Key")
        // the plist and build.sh carry the same string
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()      // app/
        let plist = try XCTUnwrap(NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")))
        XCTAssertEqual(plist["CFBundleName"] as? String, Brand.name)
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, Brand.name)
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "Orion")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.jshriver.orion")
        let build = try String(contentsOf: app.appendingPathComponent("build.sh"), encoding: .utf8)
        XCTAssertTrue(build.contains("APP_NAME=\"\(Brand.name)\""))
    }

    // MARK: failure hints

    func testFailureHint() {
        XCTAssertEqual(Faceplate.failureHint(download: false), "TRY BEAT KEY › RUN DOCTOR")
        XCTAssertEqual(Faceplate.failureHint(download: true), "TRY BEAT KEY › RUN DOCTOR OR CHECK THE LINK")
    }

    func testPermissionRefusalSaysWhereToAllowIt() {
        let m = "Download failed: [Errno 1] Operation not permitted: '/Users/x/Downloads/a.mp3'"
        XCTAssertTrue(Faceplate.isPermissionError(m))
        XCTAssertEqual(Faceplate.errorText(m),
                       "ALLOW DOWNLOADS ACCESS IN SYSTEM SETTINGS › PRIVACY & SECURITY › FILES AND FOLDERS")
        XCTAssertFalse(Faceplate.isPermissionError("That video is private or was removed."))
        XCTAssertEqual(Faceplate.errorText("That video is private or was removed."),
                       "THAT VIDEO IS PRIVATE OR WAS REMOVED")
    }

    // MARK: doctor

    final class Counter { var n = 0 }
    func doctor(_ r: FakeRunner, reseeds: Counter = Counter(), writable: Bool = true) -> Doctor {
        Doctor(runtime: rt, runner: r, reseed: { reseeds.n += 1 }, downloadsWritable: { writable })
    }

    func testDoctorAllGood() {
        let r = FakeRunner()
        r.answers["yt-dlp --version"] = [(0, "2026.10.26\n")]
        var stages: [String] = []
        let rep = doctor(r).run { stages.append($0) }
        XCTAssertEqual(stages, Doctor.stages)
        XCTAssertEqual(rep, DoctorReport(outcome: .ok, title: "DOCTOR OK", line: "YT-DLP 2026.10.26 · ALL CHECKS PASSED"))
        XCTAssertEqual(r.calls, ["yt-dlp --version", "yt-dlp -U", "yt-dlp --version",
                                 "ffmpeg -version", "ffprobe -version", "python3 -c"])
    }

    func testDoctorReportsAnUpdate() {
        let r = FakeRunner()
        r.answers["yt-dlp --version"] = [(0, "2026.10.01"), (0, "2026.10.26")]
        let rep = doctor(r).run { _ in }
        XCTAssertEqual(rep.outcome, .ok)
        XCTAssertEqual(rep.line, "YT-DLP UPDATED TO 2026.10.26 · ALL CHECKS PASSED")
    }

    func testDoctorReseedsABrokenYtDlp() {
        let r = FakeRunner()
        // won't run before, still won't after -U, runs after the re-seed
        r.answers["yt-dlp --version"] = [(1, ""), (1, ""), (0, "2026.08.19")]
        let n = Counter()
        let rep = doctor(r, reseeds: n).run { _ in }
        XCTAssertEqual(n.n, 2)
        XCTAssertEqual(rep, DoctorReport(outcome: .fixed, title: "DOCTOR FIXED IT", line: "RESTORED YT-DLP · YT-DLP 2026.08.19"))
    }

    func testDoctorYtDlpBeyondRepair() {
        let r = FakeRunner()
        r.answers["yt-dlp --version"] = [(-2, "timed out")]
        let rep = doctor(r).run { _ in }
        XCTAssertEqual(rep.outcome, .failed)
        XCTAssertEqual(rep.line, "YT-DLP WON'T RUN · REINSTALL BEAT KEY")
    }

    func testDoctorFfmpegPythonAndDownloadsFailures() {
        let ff = FakeRunner(); ff.answers["yt-dlp --version"] = [(0, "1")]; ff.answers["ffprobe -version"] = [(1, "")]
        XCTAssertEqual(doctor(ff).run { _ in }.line, "FFPROBE WON'T RUN · REINSTALL BEAT KEY")
        let py = FakeRunner(); py.answers["yt-dlp --version"] = [(0, "1")]; py.answers["python3 -c"] = [(1, "ImportError")]
        XCTAssertEqual(doctor(py).run { _ in }.line, "PYTHON WON'T START · REINSTALL BEAT KEY")
        let dl = FakeRunner(); dl.answers["yt-dlp --version"] = [(0, "1")]
        let rep = doctor(dl, writable: false).run { _ in }
        XCTAssertEqual(rep.outcome, .failed)
        XCTAssertEqual(rep.line, Doctor.permissionHint.uppercased())
    }

    func testDoctorStageTextAndLights() {
        XCTAssertEqual(Faceplate.stageText("doctor-ytdlp"), "DOCTOR · YT-DLP")
        XCTAssertEqual(Faceplate.stageText("doctor-ffmpeg"), "DOCTOR · FFMPEG")
        XCTAssertEqual(Faceplate.stageText("doctor-python"), "DOCTOR · PYTHON")
        XCTAssertEqual(Faceplate.doctorSteps("doctor-python").map { $0.1 }, [.done, .done, .on, .off])
    }

    func testEngineRunsDoctorOffMainAndIgnoresDownloads() {
        let f = FakeLauncher()
        let gate = DispatchSemaphore(value: 0)
        let r = FakeRunner(); r.answers["yt-dlp --version"] = [(0, "2026.10.26")]
        let e = Engine(runtime: rt, launcher: f, doctor: { rt in
            Doctor(runtime: rt, runner: r, reseed: {}, downloadsWritable: { gate.wait(); return true })
        })
        e.runDoctor()
        XCTAssertTrue(e.state.isBusy)
        e.download("https://a"); e.analyze([URL(fileURLWithPath: "/x.mp3")]); e.runDoctor()
        XCTAssertEqual(f.launches.count, 0)        // ignored while the doctor runs
        gate.signal()
        let deadline = Date().addingTimeInterval(3)
        while e.state.isBusy && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(e.state, .doctor(DoctorReport(outcome: .ok, title: "DOCTOR OK",
                                                     line: "YT-DLP 2026.10.26 · ALL CHECKS PASSED")))
        XCTAssertEqual(r.calls.filter { $0 == "yt-dlp -U" }.count, 1)   // the second runDoctor was ignored
    }

    func testYtDlpTimeoutsSuitSlowIntelMacs() {
        XCTAssertEqual(Runtime.versionTimeout, 120)
        XCTAssertEqual(Runtime.upgradeTimeout, 300)
    }
}
