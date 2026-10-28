import Foundation

/// What the doctor found, as the LCD shows it.
struct DoctorReport: Equatable {
    enum Outcome: Equatable { case ok, fixed, failed }
    let outcome: Outcome
    let title: String     // "DOCTOR OK" | "DOCTOR FIXED IT" | "DOCTOR FOUND A PROBLEM"
    let line: String      // one line: the yt-dlp version, what it fixed, or the one thing to do
}

/// Runs a command and returns (status, output). Injected so tests never spawn anything.
protocol CommandRunner {
    func run(_ exe: URL, _ args: [String], environment: [String: String]?, timeout: TimeInterval) -> (status: Int32, output: String)
}

struct RealRunner: CommandRunner {
    func run(_ exe: URL, _ args: [String], environment: [String: String]?, timeout: TimeInterval) -> (status: Int32, output: String) {
        Runtime.run(exe, args, environment: environment, timeout: timeout)
    }
}

/// Beat Key › Run Doctor: re-checks and repairs the bundled tools, one step at a time.
///   1 yt-dlp: force `-U` (ignores the weekly stamp), re-seed from the bundle if it won't run
///   2 ffmpeg / ffprobe: `-version` from the bin dir the Runtime picks
///   3 python: `import essentia, numpy` in the bundled python
///   4 the downloads folder is writable
struct Doctor {
    static let stages = ["doctor-ytdlp", "doctor-ffmpeg", "doctor-python", "doctor-downloads"]
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

    /// The version line of `yt-dlp --version`, or nil when it does not run.
    private func ytdlpVersion() -> String? {
        let r = runner.run(runtime.ytdlp, ["--version"], environment: nil, timeout: 120)
        guard r.status == 0 else { return nil }
        let v = r.output.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? nil : v
    }

    /// Runs every step, calling `progress` with each stage name first. Blocking: call off main.
    func run(progress: (String) -> Void) -> DoctorReport {
        var fixed: [String] = []
        var problem: String?
        var note: String?

        // 1 yt-dlp
        progress(Doctor.stages[0])
        let before = ytdlpVersion()
        if before == nil {
            if (try? reseed()) != nil { fixed.append("RESTORED YT-DLP") }
        }
        _ = runner.run(runtime.ytdlp, ["-U"], environment: nil, timeout: 300)
        var after = ytdlpVersion()
        if after == nil {
            if (try? reseed()) != nil, !fixed.contains("RESTORED YT-DLP") { fixed.append("RESTORED YT-DLP") }
            after = ytdlpVersion()
        }
        if let v = after {
            if let b = before, b != v { note = "YT-DLP UPDATED TO \(v)" } else { note = "YT-DLP \(v)" }
            Doctor.touchStamp(runtime)
        } else {
            problem = "YT-DLP WON'T RUN · REINSTALL \(Brand.wordmark)"
        }

        // 2 ffmpeg / ffprobe
        progress(Doctor.stages[1])
        for tool in ["ffmpeg", "ffprobe"] {
            let r = runner.run(runtime.binDir.appendingPathComponent(tool), ["-version"], environment: nil, timeout: 60)
            if r.status != 0, problem == nil { problem = "\(tool.uppercased()) WON'T RUN · REINSTALL \(Brand.wordmark)" }
        }

        // 3 python + essentia
        progress(Doctor.stages[2])
        let py = runner.run(runtime.python, ["-c", "import essentia, numpy"],
                            environment: runtime.environment(), timeout: 120)
        if py.status != 0, problem == nil { problem = "PYTHON WON'T START · REINSTALL \(Brand.wordmark)" }

        // 4 downloads folder
        progress(Doctor.stages[3])
        if !downloadsWritable(), problem == nil { problem = Doctor.permissionHint.uppercased() }

        if let p = problem { return DoctorReport(outcome: .failed, title: "DOCTOR FOUND A PROBLEM", line: p) }
        if !fixed.isEmpty {
            let v = note.map { " · \($0)" } ?? ""
            return DoctorReport(outcome: .fixed, title: "DOCTOR FIXED IT", line: fixed.joined(separator: " · ") + v)
        }
        return DoctorReport(outcome: .ok, title: "DOCTOR OK", line: (note ?? "YT-DLP OK") + " · ALL CHECKS PASSED")
    }

    static func touchStamp(_ rt: Runtime) {
        let fm = FileManager.default
        try? fm.createDirectory(at: rt.support, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: rt.stamp.path) { fm.createFile(atPath: rt.stamp.path, contents: Data()) }
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: rt.stamp.path)
    }
}
