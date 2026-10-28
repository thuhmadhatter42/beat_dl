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

    static func appDefault() -> Runtime {
        let res = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
        let sup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Orion")
        return Runtime(root: res.appendingPathComponent("runtime"), arch: detectArch(), support: sup)
    }

    /// arm64 on macOS 11 uses the older ffmpeg build.
    var binDir: URL {
        let legacy = arch == "arm64" && osMajor == 11
        return root.appendingPathComponent(arch).appendingPathComponent(legacy ? "bin-legacy" : "bin")
    }
    var python: URL { root.appendingPathComponent(arch).appendingPathComponent("python/bin/python3") }
    var script: URL { root.appendingPathComponent("scripts/app_run.py") }
    var supportBin: URL { support.appendingPathComponent("bin") }
    var ytdlp: URL { supportBin.appendingPathComponent("yt-dlp") }
    var bundledYtDlp: URL { root.appendingPathComponent(arch).appendingPathComponent("bin/yt-dlp") }
    var stamp: URL { support.appendingPathComponent(".last-ytdlp-upgrade") }

    func environment() -> [String: String] {
        [
            "PATH": "\(supportBin.path):\(binDir.path):/usr/bin:/bin",
            "ORION_BIN": binDir.path,
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONNOUSERSITE": "1",
            "PIP_CONFIG_FILE": "/dev/null",
        ]
    }

    private func runs(_ exe: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: exe.path) else { return false }
        return Runtime.run(exe, ["--version"], timeout: 30).status == 0
    }

    static func run(_ exe: URL, _ args: [String], timeout: TimeInterval = 30) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
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

    /// Copy the bundle's yt-dlp (signature intact) to App Support if missing or broken.
    func seedYtDlp() throws {
        if runs(ytdlp) { return }
        try reseed()
    }

    private func reseed() throws {
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

    func upgradeYtDlp() async {
        await Task.detached { self.upgradeYtDlpSync() }.value
    }

    func upgradeYtDlpSync() {
        _ = Runtime.run(ytdlp, ["-U"], timeout: 120)
        if !runs(ytdlp) {
            try? reseed()
        }
        if !runs(ytdlp) {
            // Blocked case: ad-hoc sign once and re-check.
            _ = Runtime.run(URL(fileURLWithPath: "/usr/bin/codesign"), ["-s", "-", "-f", ytdlp.path])
            if !runs(ytdlp) { try? reseed() }
        }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: stamp.path, contents: Data())
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: stamp.path)
    }
}
