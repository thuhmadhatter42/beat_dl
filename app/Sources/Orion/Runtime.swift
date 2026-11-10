import Foundation

struct Runtime {
    let root: URL      // Contents/Resources/runtime
    let arch: String   // "arm64" | "x86_64"
    let support: URL   // ~/Library/Application Support/Orion
    var osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    static func detectArch() -> String {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &v, &size, nil, 0) == 0, v == 1 { return "arm64" }
        return "x86_64"
    }

    /// The bundle's runtime. A debug run (`swift run`, no bundle) points ORION_RUNTIME_ROOT at a
    /// locally built runtime (app/build/runtime); nothing else changes.
    static func appDefault(env: [String: String] = ProcessInfo.processInfo.environment) -> Runtime {
        let res = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
        let sup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Orion")
        let override = env["ORION_RUNTIME_ROOT"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        return Runtime(root: override ?? res.appendingPathComponent("runtime"), arch: detectArch(), support: sup)
    }

    /// arm64 on macOS 11 uses the older ffmpeg build.
    var binDir: URL {
        let legacy = arch == "arm64" && osMajor == 11
        return root.appendingPathComponent(arch).appendingPathComponent(legacy ? "bin-legacy" : "bin")
    }
    var python: URL { root.appendingPathComponent(arch).appendingPathComponent("python/bin/python3") }
    var script: URL { root.appendingPathComponent("scripts/app_run.py") }
    /// Live listening runs the analyzer itself (`bpm.py --stream`), not app_run.py.
    var analyzer: URL { root.appendingPathComponent("scripts/bpm.py") }
    var supportBin: URL { support.appendingPathComponent("bin") }
    var ytdlp: URL { supportBin.appendingPathComponent("yt-dlp") }
    var bundledYtDlp: URL { root.appendingPathComponent(arch).appendingPathComponent("bin/yt-dlp") }
    /// The JavaScript runtime yt-dlp solves YouTube's JS challenges with (deno). Its official
    /// builds need macOS 12, so it ships in bin/ only and macOS 11 gets none.
    var deno: URL { root.appendingPathComponent(arch).appendingPathComponent("bin/deno") }
    var hasJSRuntime: Bool { osMajor >= 12 }
    var stamp: URL { support.appendingPathComponent(".last-ytdlp-upgrade") }

    func environment(passing env: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var e = [
            "PATH": "\(supportBin.path):\(binDir.path):/usr/bin:/bin",
            "ORION_BIN": binDir.path,
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONNOUSERSITE": "1",
            "PIP_CONFIG_FILE": "/dev/null",
            // The one yt-dlp the helper may run and upgrade (never the copy inside the signed bundle).
            "ORION_YTDLP": ytdlp.path,
        ]
        // downloader.py hands it to yt-dlp as --js-runtimes deno:<path>.
        if hasJSRuntime { e["ORION_DENO"] = deno.path }
        // Test/debug override of the output folder, read by app_run.py; unset = ~/Downloads.
        if let d = env["ORION_DOWNLOADS"], !d.isEmpty { e["ORION_DOWNLOADS"] = d }
        return e
    }

    static let versionTimeout: TimeInterval = 120
    static let upgradeTimeout: TimeInterval = 300

    static func run(_ exe: URL, _ args: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval = 30) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        if let env = environment { p.environment = env.merging(["HOME": NSHomeDirectory()]) { a, _ in a } }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        var timedOut = false
        let lock = NSLock()
        let kill = DispatchWorkItem {
            lock.lock(); timedOut = true; lock.unlock()
            if p.isRunning { p.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: kill)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        kill.cancel()
        lock.lock(); let to = timedOut; lock.unlock()
        if to { return (-2, "timed out") }
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Every seed / upgrade / reseed / doctor run goes through this one serial queue, so the launch
    /// upgrade, Run Doctor and the first download never touch the App Support yt-dlp at once.
    static let maintenanceQueue = DispatchQueue(label: "com.jshriver.orion.maintenance")
    private static var seededPaths = Set<String>()   // touched only on maintenanceQueue

    /// Launch-time work, off the main thread and not tied to the Engine's busy state: seed yt-dlp,
    /// then the weekly self-update. Anything that needs yt-dlp waits behind it.
    func launchMaintenance() {
        Runtime.maintenanceQueue.async {
            self.ensureSeeded()
            self.warmJSRuntime()
            if self.needsWeeklyUpgrade {
                // repairYtDlp logs every step and the failure itself; Run Doctor shows it on the LCD.
                do { _ = try self.repairYtDlp() } catch {}
            }
        }
    }

    /// The first start of a fresh deno is slow while macOS checks the 100 MB binary (measured
    /// 60 s on the 2013 Intel Mac Pro, 0.2 s every time after). Pay it here, off the download.
    func warmJSRuntime() {
        guard hasJSRuntime else { return }
        _ = Runtime.run(deno, ["--version"], timeout: Runtime.versionTimeout)
    }

    /// Seed once per process (a `--version` run costs seconds on old Intel Macs). Call only on
    /// maintenanceQueue.
    func ensureSeeded() {
        guard Runtime.seededPaths.insert(ytdlp.path).inserted else { return }
        do { try seedYtDlp() } catch { AppLog.log("yt-dlp seed into \(ytdlp.path) failed: \(error); downloads will fail") }
    }

    /// Copy the bundle's yt-dlp (signature intact) to App Support if missing or broken. No -U.
    func seedYtDlp(runner: CommandRunner = RealRunner(), reseed: (() throws -> Void)? = nil) throws {
        let (_, restored) = try restoreIfBroken(runner, reseed ?? { try self.reseed() })
        // The bundled yt-dlp is as fresh as this build: the first weekly -U is 7 days from now.
        if restored { touchStamp() }
    }

    func reseed() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: supportBin, withIntermediateDirectories: true)
        if fm.fileExists(atPath: ytdlp.path) { try fm.removeItem(at: ytdlp) }
        try fm.copyItem(at: bundledYtDlp, to: ytdlp)
    }

    var needsWeeklyUpgrade: Bool {
        guard let m = (try? FileManager.default.attributesOfItem(atPath: stamp.path))?[.modificationDate] as? Date
        else { return true }
        return Date().timeIntervalSince(m) > 7 * 24 * 3600
    }

    /// The one "make yt-dlp work again" ladder, for the weekly upgrade and Run Doctor alike. Call
    /// only on maintenanceQueue. Each step runs only if the one before left yt-dlp not running:
    ///   1 it doesn't run → restore the bundled copy (-U needs a yt-dlp that runs)
    ///   2 `yt-dlp -U` (always; a failed -U on a yt-dlp that still runs is logged, not a failure)
    ///   3 the update doesn't run → ad-hoc sign it once (spec §6: a self-updated binary blocked
    ///     by code signing) and re-check, so a good update is kept
    ///   4 still doesn't run → restore the bundled copy
    ///   5 still doesn't run → throw .wontRun. Otherwise write the stamp (the one writer).
    /// A failed restore throws .reseedFailed at once. Every step that changes or fails logs here.
    func repairYtDlp(runner: CommandRunner = RealRunner(),
                     reseed: (() throws -> Void)? = nil) throws -> YtDlpRepair {
        let restore = reseed ?? { try self.reseed() }
        let (before, restoredFirst) = try restoreIfBroken(runner, restore)
        var restored = restoredFirst

        let up = runner.run(ytdlp, ["-U"], environment: nil, timeout: Runtime.upgradeTimeout)
        if up.status != 0 {
            AppLog.log("yt-dlp -U: status \(up.status): \(up.output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300))")
        }
        var after = ytdlpVersion(runner)
        if after == nil {
            AppLog.log("yt-dlp does not run after -U; ad-hoc signing it")
            let sign = runner.run(URL(fileURLWithPath: "/usr/bin/codesign"), ["-s", "-", "-f", ytdlp.path],
                                  environment: nil, timeout: 30)
            if sign.status != 0 {
                AppLog.log("yt-dlp ad-hoc sign: status \(sign.status): \(sign.output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300))")
            }
            after = ytdlpVersion(runner)
        }
        if after == nil {
            try restoreBundled(restore)
            restored = true
            after = ytdlpVersion(runner)
        }
        guard let now = after else {
            AppLog.log("yt-dlp still does not run; downloads will fail (Run Doctor)")
            throw YtDlpRepairError.wontRun
        }
        if before != now { AppLog.log("yt-dlp is now \(now) (was \(before ?? "not running"))") }
        touchStamp()
        return YtDlpRepair(restored: restored, before: before, after: now)
    }

    /// The version line of `yt-dlp --version`, or nil when it does not run. The only "does yt-dlp
    /// run" check. A PyInstaller one-file yt-dlp unpacks itself on every call: ~33 s on a 2013 Intel Mac.
    func ytdlpVersion(_ runner: CommandRunner) -> String? {
        let r = runner.run(ytdlp, ["--version"], environment: nil, timeout: Runtime.versionTimeout)
        guard r.status == 0 else { return nil }
        let v = r.output.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? nil : v
    }

    /// Step 1 of both seed and repair: (the version, nil if it didn't run; whether it was restored).
    private func restoreIfBroken(_ runner: CommandRunner,
                                 _ restore: () throws -> Void) throws -> (String?, Bool) {
        if let v = ytdlpVersion(runner) { return (v, false) }
        try restoreBundled(restore)
        return (nil, true)
    }

    private func restoreBundled(_ restore: () throws -> Void) throws {
        AppLog.log("yt-dlp does not run; restoring the bundled copy")
        do { try restore() } catch {
            AppLog.log("yt-dlp: restoring the bundled copy failed: \(error)")
            throw YtDlpRepairError.reseedFailed("\(error)")
        }
    }

    /// The one writer of the weekly-upgrade stamp.
    func touchStamp() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: support, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: stamp.path) { fm.createFile(atPath: stamp.path, contents: Data()) }
            try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: stamp.path)
        } catch {
            AppLog.log("yt-dlp upgrade stamp \(stamp.path) not written: \(error); the next launch upgrades again")
        }
    }
}

/// What Runtime.repairYtDlp did, for the log and Run Doctor's LCD line.
struct YtDlpRepair: Equatable {
    let restored: Bool     // the bundled copy was put back (step 1 or 4)
    let before: String?    // version before -U; nil = it did not run
    let after: String      // version now running
}

enum YtDlpRepairError: Error, Equatable {
    case reseedFailed(String)   // copying the bundled yt-dlp to App Support failed
    case wontRun                // every step tried, yt-dlp still does not run
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
