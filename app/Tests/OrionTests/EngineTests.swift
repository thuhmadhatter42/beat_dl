import XCTest
@testable import Orion

final class FakeLauncher: ProcessLauncher {
    var launches: [[String]] = []
    var lines: [(String) -> Void] = []
    var exits: [(Int32) -> Void] = []
    var onLine: ((String) -> Void)? { lines.last }
    var onExit: ((Int32) -> Void)? { exits.last }
    func launch(executable: URL, arguments: [String], environment: [String: String],
                onLine: @escaping (String) -> Void, onExit: @escaping (Int32) -> Void) {
        launches.append(arguments); lines.append(onLine); exits.append(onExit)
    }
}

final class EngineTests: XCTestCase {
    func rt(arch: String = "arm64", os: Int = 14) -> Runtime {
        Runtime(root: URL(fileURLWithPath: "/R/runtime"), arch: arch,
                support: URL(fileURLWithPath: "/S/Orion"), osMajor: os)
    }
    func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    /// A run starts after the maintenance queue has seeded yt-dlp: wait for the n-th launch.
    func waitLaunch(_ f: FakeLauncher, _ n: Int = 1) {
        let deadline = Date().addingTimeInterval(5)
        while f.launches.count < n && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    func testBusyIgnoresSecondDownload() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.download("https://a"); e.download("https://b"); e.analyze([URL(fileURLWithPath: "/x.mp3")])
        waitLaunch(f); spin()
        XCTAssertEqual(f.launches.count, 1)
        XCTAssertEqual(Array(f.launches[0].suffix(2)), ["download", "https://a"])
        XCTAssertEqual(e.state, .working(stage: "downloading"))
    }

    func testDoneFlow() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.download("u"); waitLaunch(f)
        f.onLine?(#"{"stage":"analyzing"}"#); spin()
        XCTAssertEqual(e.state, .working(stage: "analyzing"))
        f.onLine?(#"{"stage":"done","file":"/a.mp3","name":"a.mp3","bpm":"90.0","keys":[["Am",50]]}"#)
        f.onExit?(0); spin()
        if case .done(let r) = e.state { XCTAssertEqual(r.bpm, "90.0") } else { XCTFail("\(e.state)") }
    }

    func testAnalyzeCollectsAll() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.analyze([URL(fileURLWithPath: "/a.mp3"), URL(fileURLWithPath: "/b.mp3")]); waitLaunch(f)
        f.onLine?(#"{"stage":"analyzed","file":"/a.mp3","name":"a.mp3","bpm":null,"keys":[]}"#)
        f.onLine?(#"{"stage":"analyzed","file":"/b.mp3","name":"b.mp3","bpm":"100.0","keys":[]}"#)
        f.onExit?(0); spin()
        if case .analyzed(let rs) = e.state { XCTAssertEqual(rs.count, 2) } else { XCTFail("\(e.state)") }
        XCTAssertNil(e.note)
    }

    func testDownloadProbesDownloadsFirstAndDenialDoesNotLaunch() {
        let f = FakeLauncher()
        let gate = DispatchSemaphore(value: 0)
        var allow = false
        let e = Engine(runtime: rt(), launcher: f, downloadsProbe: { gate.wait(); return allow })
        e.download("https://a")
        XCTAssertEqual(e.state, .working(stage: "allow-downloads"))
        XCTAssertEqual(Faceplate.stageText("allow-downloads"), "ALLOW DOWNLOADS ACCESS")
        spin(); XCTAssertEqual(f.launches.count, 0)
        gate.signal(); spin(); spin()
        guard case .failed(let m) = e.state else { return XCTFail("\(e.state)") }
        XCTAssertTrue(Faceplate.isPermissionError(m))
        XCTAssertEqual(f.launches.count, 0)
        // granted: launches
        allow = true
        e.download("https://b"); gate.signal(); waitLaunch(f)
        XCTAssertEqual(f.launches.count, 1)
        XCTAssertNil(Engine.defaultProbe(env: ["ORION_DOWNLOADS": "/x"]))
    }

    func testDownloadShowsUpdatingWhileWaitingBehindMaintenance() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        let hold = DispatchSemaphore(value: 0), started = DispatchSemaphore(value: 0)
        Runtime.maintenanceQueue.async { started.signal(); hold.wait() }
        started.wait()
        e.download("https://a")
        XCTAssertEqual(e.state, .working(stage: "downloading"))
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        XCTAssertEqual(e.state, .working(stage: "updating"))
        hold.signal(); waitLaunch(f); spin()
        XCTAssertEqual(e.state, .working(stage: "downloading"))
    }

    func testPartialAnalyzeKeepsResultsAndCaptionsTheRest() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.analyze(["a", "b", "c"].map { URL(fileURLWithPath: "/\($0).mp3") }); waitLaunch(f)
        f.onLine?(#"{"stage":"analyzed","file":"/a.mp3","name":"a.mp3","bpm":"90.0","keys":[]}"#)
        f.onExit?(9); spin()
        if case .analyzed(let rs) = e.state { XCTAssertEqual(rs.count, 1) } else { XCTFail("\(e.state)") }
        XCTAssertEqual(e.note, "2 FILES COULDN'T BE READ · TRY BEAT KEY › RUN DOCTOR")
        XCTAssertEqual(Faceplate.partialNote(1), "1 FILE COULDN'T BE READ · TRY BEAT KEY › RUN DOCTOR")
    }

    func testUnreadableByPermissionShowsThePermissionHint() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.analyze([URL(fileURLWithPath: "/a.wav")]); waitLaunch(f)
        f.onLine?(#"{"stage":"analyzed","file":"/a.wav","name":"a.wav","bpm":null,"keys":[],"error":"permission"}"#)
        f.onExit?(0); spin()
        guard case .failed(let m) = e.state else { return XCTFail("\(e.state)") }
        XCTAssertTrue(Faceplate.isPermissionError(m))
        XCTAssertEqual(Faceplate.errorText(m), Doctor.permissionHint.uppercased())
    }

    func testStaleExitDoesNotClobberNewRun() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.download("a"); waitLaunch(f)
        f.lines[0](#"{"stage":"done","file":"/a.mp3","name":"a.mp3","bpm":null,"keys":[]}"#); spin()
        e.download("b"); waitLaunch(f, 2)
        XCTAssertEqual(f.launches.count, 2)
        f.exits[0](0); spin()
        XCTAssertEqual(e.state, .working(stage: "downloading"))
        f.lines[1](#"{"stage":"done","file":"/b.mp3","name":"b.mp3","bpm":null,"keys":[]}"#)
        f.exits[1](0); spin()
        if case .done(let r) = e.state { XCTAssertEqual(r.name, "b.mp3") } else { XCTFail("\(e.state)") }
    }

    func testCrashWithoutTerminalFails() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.download("u"); waitLaunch(f); f.onExit?(9); spin()
        if case .failed = e.state {} else { XCTFail("\(e.state)") }
    }

    func testEnvironmentHasNoPythonPath() {
        let env = rt().environment()
        XCTAssertNil(env["PYTHONPATH"]); XCTAssertNil(env["PYTHONHOME"])
        XCTAssertEqual(env["PYTHONDONTWRITEBYTECODE"], "1")
        XCTAssertEqual(env["PYTHONNOUSERSITE"], "1")
        XCTAssertEqual(env["PIP_CONFIG_FILE"], "/dev/null")
        XCTAssertEqual(env["ORION_BIN"], "/R/runtime/arm64/bin")
        XCTAssertEqual(env["PATH"], "/S/Orion/bin:/R/runtime/arm64/bin:/usr/bin:/bin")
        // -U and the downloads use this yt-dlp and no other
        XCTAssertEqual(env["ORION_YTDLP"], "/S/Orion/bin/yt-dlp")
    }

    func testLegacyBinOnArm64Macos11() {
        XCTAssertEqual(rt(os: 11).environment()["ORION_BIN"], "/R/runtime/arm64/bin-legacy")
        XCTAssertTrue(rt(os: 11).environment()["PATH"]!.contains("/R/runtime/arm64/bin-legacy:"))
        XCTAssertEqual(rt(os: 12).environment()["ORION_BIN"], "/R/runtime/arm64/bin")
        XCTAssertEqual(rt(arch: "x86_64", os: 11).environment()["ORION_BIN"], "/R/runtime/x86_64/bin")
    }

    func testSeedCopiesBundledYtDlp() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("orion-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bin = tmp.appendingPathComponent("runtime/arm64/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let src = bin.appendingPathComponent("yt-dlp")
        try "#!/bin/sh\necho 2099.01.01\n".write(to: src, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: src.path)
        let r = Runtime(root: tmp.appendingPathComponent("runtime"), arch: "arm64",
                        support: tmp.appendingPathComponent("support"), osMajor: 14)
        XCTAssertTrue(r.needsWeeklyUpgrade)
        try r.seedYtDlp()
        XCTAssertFalse(r.needsWeeklyUpgrade)     // a fresh seed is as new as the build
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: r.ytdlp.path))
        r.upgradeYtDlpSync()
        XCTAssertFalse(r.needsWeeklyUpgrade)
    }
}
