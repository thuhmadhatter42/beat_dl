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

    func testBusyIgnoresSecondDownload() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.download("https://a"); e.download("https://b"); e.analyze([URL(fileURLWithPath: "/x.mp3")])
        XCTAssertEqual(f.launches.count, 1)
        XCTAssertEqual(Array(f.launches[0].suffix(2)), ["download", "https://a"])
        XCTAssertEqual(e.state, .working(stage: "downloading"))
    }

    func testDoneFlow() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.download("u")
        f.onLine?(#"{"stage":"analyzing"}"#); spin()
        XCTAssertEqual(e.state, .working(stage: "analyzing"))
        f.onLine?(#"{"stage":"done","file":"/a.mp3","name":"a.mp3","bpm":"90.0","keys":[["Am",50]]}"#)
        f.onExit?(0); spin()
        if case .done(let r) = e.state { XCTAssertEqual(r.bpm, "90.0") } else { XCTFail("\(e.state)") }
    }

    func testAnalyzeCollectsAll() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.analyze([URL(fileURLWithPath: "/a.mp3"), URL(fileURLWithPath: "/b.mp3")])
        f.onLine?(#"{"stage":"analyzed","file":"/a.mp3","name":"a.mp3","bpm":null,"keys":[]}"#)
        f.onLine?(#"{"stage":"analyzed","file":"/b.mp3","name":"b.mp3","bpm":"100.0","keys":[]}"#)
        f.onExit?(0); spin()
        if case .analyzed(let rs) = e.state { XCTAssertEqual(rs.count, 2) } else { XCTFail("\(e.state)") }
    }

    func testStaleExitDoesNotClobberNewRun() {
        let f = FakeLauncher()
        let e = Engine(runtime: rt(), launcher: f)
        e.download("a")
        f.lines[0](#"{"stage":"done","file":"/a.mp3","name":"a.mp3","bpm":null,"keys":[]}"#); spin()
        e.download("b")
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
        e.download("u"); f.onExit?(9); spin()
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
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: r.ytdlp.path))
        r.upgradeYtDlpSync()
        XCTAssertFalse(r.needsWeeklyUpgrade)
    }
}
