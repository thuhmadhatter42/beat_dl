import AppKit
import Darwin
import os

/// Beat Key's own log: ~/Library/Logs/Beat Key/beatkey.log (also in Console under subsystem
/// com.jshriver.orion). Every launch, quit, crash, engine and Listen state change lands here, and
/// a run that ended without a clean quit (crash, force quit, kill) is named at the next launch.
/// Rotates at 5 MB to beatkey.1.log. The analyzer's own stderr goes to analyzer.log beside it.
enum AppLog {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Beat Key")
    static let url = dir.appendingPathComponent("beatkey.log")
    static let analyzerURL = dir.appendingPathComponent("analyzer.log")
    private static let marker = dir.appendingPathComponent("running.marker")
    private static let queue = DispatchQueue(label: "com.jshriver.orion.log")
    private static let os = Logger(subsystem: "com.jshriver.orion", category: "app")
    /// Pre-opened for the crash handler (only async-signal-safe calls there).
    private static var crashFD: Int32 = -1

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// Unit tests never write to the user's log.
    private static let testing: Bool = {
        let p = ProcessInfo.processInfo
        return NSClassFromString("XCTestCase") != nil || p.environment["XCTestConfigurationFilePath"] != nil
            || p.environment["XCTestBundlePath"] != nil || p.processName.lowercased().contains("xctest")
            || p.processName.hasSuffix("PackageTests")
    }()

    private static let sinkLock = NSLock()
    private static var _sink: ((String) -> Void)?
    /// Tests only: every line ("[Tag] text") also goes here, so a test can assert what would be
    /// logged. Unit tests still never write the user's log file.
    static var sink: ((String) -> Void)? {
        get { sinkLock.lock(); defer { sinkLock.unlock() }; return _sink }
        set { sinkLock.lock(); _sink = newValue; sinkLock.unlock() }
    }

    /// Waits until every line logged so far is on disk (before the app exits).
    static func flush() { queue.sync {} }

    static func log(_ line: String, file: String = #fileID) {
        let tag = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
        sink?("[\(tag)] \(line)")
        guard !testing else { return }
        let text = "\(stamp.string(from: Date())) [\(tag)] \(line)\n"
        os.log("\(line, privacy: .public)")
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if let a = try? fm.attributesOfItem(atPath: url.path), (a[.size] as? Int ?? 0) > 5_000_000 {
                let old = dir.appendingPathComponent("beatkey.1.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            guard let h = try? FileHandle(forWritingTo: url) else { return }
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        }
    }

    /// The analyzer's / helper's stderr (failure lines, warnings, Python tracebacks), appended,
    /// after a timestamped "---- <header>" line so it lines up with beatkey.log. Tests: no file.
    static func analyzerHandle(header: String) -> FileHandle? {
        guard !testing else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let a = try? fm.attributesOfItem(atPath: analyzerURL.path), (a[.size] as? Int ?? 0) > 5_000_000 {
            try? fm.removeItem(at: analyzerURL)
        }
        if !fm.fileExists(atPath: analyzerURL.path) { fm.createFile(atPath: analyzerURL.path, contents: nil) }
        guard let h = try? FileHandle(forWritingTo: analyzerURL) else {
            log("analyzer.log could not be opened; the helper's stderr is lost this run")
            return nil
        }
        h.seekToEndOfFile()
        h.write(Data("---- \(stamp.string(from: Date())) \(header)\n".utf8))
        return h
    }

    /// At launch: name an unclean end of the previous run, start this one, catch crashes.
    static func launched() {
        guard !testing else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let prev = try? String(contentsOf: marker, encoding: .utf8) {
            log("PREVIOUS RUN DID NOT QUIT CLEANLY (crash, force quit or kill): \(prev)")
        }
        let info = ProcessInfo.processInfo
        let me = "version \(version), pid \(info.processIdentifier), started \(stamp.string(from: Date()))"
        try? me.write(to: marker, atomically: true, encoding: .utf8)
        log("LAUNCH \(me), macOS \(info.operatingSystemVersionString)")
        installCrashHandlers()
    }

    static func quitting(_ why: String) {
        log("QUIT (\(why))")
        queue.sync {}
        try? FileManager.default.removeItem(at: marker)
    }

    private static func installCrashHandlers() {
        crashFD = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        NSSetUncaughtExceptionHandler { e in
            AppLog.log("CRASH uncaught exception \(e.name.rawValue): \(e.reason ?? "")\n" + e.callStackSymbols.joined(separator: "\n"))
            AppLog.queue.sync {}
        }
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE, SIGTRAP] {
            signal(sig) { s in
                let fd = AppLog.crashFD
                if fd >= 0 {
                    var head = Array("\n!!! CRASH signal ".utf8)
                    write(fd, &head, head.count)
                    var n = s, digits = [UInt8]()
                    repeat { digits.insert(UInt8(48 + n % 10), at: 0); n /= 10 } while n > 0
                    write(fd, &digits, digits.count)
                    var nl = Array(" — backtrace:\n".utf8)
                    write(fd, &nl, nl.count)
                    var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
                    let c = backtrace(&frames, 64)
                    backtrace_symbols_fd(&frames, c, fd)
                }
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }
}
