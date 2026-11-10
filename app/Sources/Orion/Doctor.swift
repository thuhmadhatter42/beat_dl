import Foundation

/// What the doctor found, as the LCD shows it.
struct DoctorReport: Equatable {
    enum Outcome: Equatable { case ok, fixed, failed }
    let outcome: Outcome
    let title: String     // "DOCTOR OK" | "DOCTOR FIXED IT" | "DOCTOR FOUND A PROBLEM"
    let line: String      // one line: the yt-dlp version, what it fixed, or the one thing to do
}

/// Beat Key › Run Doctor: re-checks and repairs the bundled tools, one step at a time.
///   1 yt-dlp: Runtime.repairYtDlp now (ignores the weekly stamp); the LCD line comes from its result
///   2 ffmpeg / ffprobe: `-version` from the bin dir the Runtime picks
///   3 JS: `deno --version`, the JavaScript runtime yt-dlp needs for YouTube (none on macOS 11)
///   4 python: `import essentia, numpy` in the bundled python
///   5 the downloads folder is writable
struct Doctor {
    static let stages = ["doctor-ytdlp", "doctor-ffmpeg", "doctor-js", "doctor-python", "doctor-downloads"]
    static let permissionHint = "Allow Downloads access in System Settings › Privacy & Security › Files and Folders"

    let runtime: Runtime
    var runner: CommandRunner = RealRunner()
    /// Copy the bundle's yt-dlp over the App Support one.
    var reseed: () throws -> Void
    /// Write and remove a probe file in the downloads folder.
    var downloadsWritable: () -> Bool

    init(runtime: Runtime, runner: CommandRunner = RealRunner(),
         reseed: (() throws -> Void)? = nil, downloadsWritable: (() -> Bool)? = nil,
         downloads: URL = Doctor.downloadsFolder()) {
        self.runtime = runtime
        self.runner = runner
        self.reseed = reseed ?? { try runtime.reseed() }
        self.downloadsWritable = downloadsWritable ?? { Doctor.probeWritable(downloads) }
    }

    static func downloadsFolder(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let d = env["ORION_DOWNLOADS"], !d.isEmpty { return URL(fileURLWithPath: d) }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    static func probeWritable(_ dir: URL) -> Bool {
        let probe = dir.appendingPathComponent(".beatkey-doctor-\(getpid())")
        guard FileManager.default.createFile(atPath: probe.path, contents: Data()) else { return false }
        try? FileManager.default.removeItem(at: probe)
        return true
    }

    /// Runs every step, calling `progress` with each stage name first. Blocking: call off main.
    func run(progress: (String) -> Void) -> DoctorReport {
        var fixed: [String] = []
        var problem: String?
        var note: String?

        // 1 yt-dlp
        progress(Doctor.stages[0])
        do {
            let r = try runtime.repairYtDlp(runner: runner, reseed: reseed)
            if r.restored { fixed.append("RESTORED YT-DLP") }
            if let b = r.before, b != r.after { note = "YT-DLP UPDATED TO \(r.after)" } else { note = "YT-DLP \(r.after)" }
        } catch {
            // repairYtDlp logged the step that failed (.reseedFailed or .wontRun)
            problem = "YT-DLP WON'T RUN · REINSTALL \(Brand.wordmark)"
        }

        // 2 ffmpeg / ffprobe
        progress(Doctor.stages[1])
        for tool in ["ffmpeg", "ffprobe"] {
            let r = runner.run(runtime.binDir.appendingPathComponent(tool), ["-version"], environment: nil, timeout: 60)
            if r.status != 0, problem == nil { problem = "\(tool.uppercased()) WON'T RUN · REINSTALL \(Brand.wordmark)" }
        }

        // 3 the JavaScript runtime (V8 needs its JIT entitlements to start at all)
        progress(Doctor.stages[2])
        if runtime.hasJSRuntime {
            let js = runner.run(runtime.deno, ["--version"], environment: nil, timeout: Runtime.versionTimeout)
            if js.status != 0, problem == nil { problem = "JS RUNTIME WON'T RUN · REINSTALL \(Brand.wordmark)" }
        }

        // 4 python + essentia
        progress(Doctor.stages[3])
        let py = runner.run(runtime.python, ["-c", "import essentia, numpy"],
                            environment: runtime.environment(), timeout: 120)
        if py.status != 0, problem == nil { problem = "PYTHON WON'T START · REINSTALL \(Brand.wordmark)" }

        // 5 downloads folder
        progress(Doctor.stages[4])
        if !downloadsWritable(), problem == nil { problem = Doctor.permissionHint.uppercased() }

        if let p = problem { return DoctorReport(outcome: .failed, title: "DOCTOR FOUND A PROBLEM", line: p) }
        if !fixed.isEmpty {
            let v = note.map { " · \($0)" } ?? ""
            return DoctorReport(outcome: .fixed, title: "DOCTOR FIXED IT", line: fixed.joined(separator: " · ") + v)
        }
        return DoctorReport(outcome: .ok, title: "DOCTOR OK", line: (note ?? "YT-DLP OK") + " · ALL CHECKS PASSED")
    }
}
