import AppKit

/// Two ways an old Beat Key can outlive an install, both found by the app itself (Finder's
/// drag-install cannot be hooked). Sparkle updates already quit and relaunch; this is for the rest.
///  1. Replaced under me: the bundle on disk now has another version than the one running.
///  2. Two copies: another Beat Key process is running when this one launches.
/// Every line in beatkey.log starts "install guard:".

// MARK: - Versions

enum InstallVersion {
    /// Numeric, dotted compare ("0.1.9" < "0.1.10"). Missing parts count as 0; junk parts as 0.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
    private static func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }

    /// CFBundleShortVersionString read fresh from the bundle's Info.plist on disk (never from
    /// Bundle.main's cached copy), plus that file's inode. nil fields = could not read.
    static func onDisk(bundle: URL) -> BundleSnapshot {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        var inode: UInt64?
        if let a = try? FileManager.default.attributesOfItem(atPath: plist.path) {
            inode = (a[.systemFileNumber] as? NSNumber)?.uint64Value
        }
        var version: String?
        if let d = try? Data(contentsOf: plist),
           let o = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] {
            version = o["CFBundleShortVersionString"] as? String
        }
        return BundleSnapshot(version: version, inode: inode)
    }
}

struct BundleSnapshot: Equatable {
    var version: String?
    var inode: UInt64?
}

// MARK: - 1. Replaced under me

/// What one check of the bundle on disk decided.
enum InstallVerdict: Equatable {
    case unreadable              // Info.plist missing or unreadable: mid-copy, or gone. Wait.
    case same                    // nothing changed
    case replacedSameVersion     // new file at the same path, same version: nothing to offer
    case newVersion(String)      // ask once for this version
    case alreadyAsked(String)    // this version was already offered
}

final class InstallGuard {
    static let shared = InstallGuard()

    /// How often the bundle is looked at. A timer, not a file watch: a replaced bundle is a new
    /// directory entry, which a watch on the old inode never reports.
    static let interval: TimeInterval = 5

    /// Listen or a download running: the prompt still shows, and says so; nothing quits by itself.
    var isBusy: () -> Bool = { false }

    private let running: String
    private let read: () -> BundleSnapshot
    private let ask: (_ newVersion: String, _ busy: Bool) -> Void
    private var firstInode: UInt64?
    private var askedFor = Set<String>()
    private var loggedUnreadable = false
    private var timer: Timer?

    init(running: String = AppLog.version,
         read: @escaping () -> BundleSnapshot = { InstallVersion.onDisk(bundle: Bundle.main.bundleURL) },
         ask: @escaping (String, Bool) -> Void = InstallGuard.showPrompt) {
        self.running = running
        self.read = read
        self.ask = ask
        self.firstInode = read().inode
    }

    /// Starts the 5 s check. Only for a real .app bundle. Idempotent.
    func start() {
        guard timer == nil else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            AppLog.log("install guard: not an .app bundle, replaced-under-me check off")
            return
        }
        AppLog.log("install guard: watching \(Bundle.main.bundleURL.path) every \(Int(InstallGuard.interval)) s, running \(running)")
        let t = Timer(timeInterval: InstallGuard.interval, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// One look at the disk. Returns the verdict (tests read it); acts on it.
    @discardableResult
    func check() -> InstallVerdict {
        let snap = read()
        let verdict = InstallGuard.decide(running: running, snapshot: snap, firstInode: firstInode, asked: askedFor)
        if verdict != .unreadable { loggedUnreadable = false }
        switch verdict {
        case .unreadable:
            if !loggedUnreadable {
                AppLog.log("install guard: Info.plist on disk unreadable (mid-install or removed); waiting")
                loggedUnreadable = true
            }
        case .same, .alreadyAsked:
            break
        case .replacedSameVersion:
            firstInode = snap.inode
            AppLog.log("install guard: bundle on disk was replaced, same version \(running); nothing to do")
        case .newVersion(let v):
            askedFor.insert(v)
            let busy = isBusy()
            AppLog.log("install guard: version mismatch: running \(running), on disk \(v); asking (busy: \(busy))")
            ask(v, busy)
        }
        return verdict
    }

    /// The decision, with nothing touched. Once per detected version.
    static func decide(running: String, snapshot: BundleSnapshot, firstInode: UInt64?, asked: Set<String>) -> InstallVerdict {
        guard let v = snapshot.version, !v.isEmpty else { return .unreadable }
        if InstallVersion.compare(v, running) != .orderedSame {
            return asked.contains(v) ? .alreadyAsked(v) : .newVersion(v)
        }
        if let first = firstInode, let now = snapshot.inode, first != now { return .replacedSameVersion }
        return .same
    }

    /// The pop-up. Relaunch Now → the shared relaunch. Later → nothing until another version shows.
    static func showPrompt(newVersion: String, busy: Bool) {
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = "Beat Key \(newVersion) was installed."
            a.informativeText = busy
                ? "Relaunch to use it. Listen or a download is running right now, so nothing quits until you choose."
                : "Relaunch to use it."
            a.alertStyle = .informational
            a.window.appearance = NSAppearance(named: .darkAqua)
            a.addButton(withTitle: "Relaunch Now")
            a.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if a.runModal() == .alertFirstButtonReturn {
                AppLog.log("install guard: Relaunch Now chosen for \(newVersion)")
                if !AppRelaunch.now(why: "install guard") { AppLog.log("install guard: FAILED to relaunch") }
            } else {
                AppLog.log("install guard: Later chosen for \(newVersion)")
            }
        }
    }
}

// MARK: - 2. Two copies

struct OtherInstance: Equatable {
    var pid: Int32
    var path: String
    var version: String
}

enum TwinAction: Equatable {
    case none
    /// Ask these to quit (terminate, then force after a few seconds); this one carries on.
    case takeOver([OtherInstance])
    /// Another copy is newer: this one quits and brings that one forward.
    case yieldTo(OtherInstance)
}

enum TwinCheck {
    static let forceAfter: TimeInterval = 3

    /// A newer other copy wins; otherwise this one (the one just launched) takes over.
    static func decide(myVersion: String, others: [OtherInstance]) -> TwinAction {
        guard !others.isEmpty else { return .none }
        if let newer = others.filter({ InstallVersion.compare($0.version, myVersion) == .orderedDescending })
            .max(by: { InstallVersion.compare($0.version, $1.version) == .orderedAscending }) {
            return .yieldTo(newer)
        }
        return .takeOver(others)
    }

    /// At launch. An other copy's version = its bundle's Info.plist on disk (if it was replaced in
    /// place, that is the new version: it then counts as equal and is simply taken over).
    static func run(bundleID: String? = Bundle.main.bundleIdentifier,
                    myPID: Int32 = ProcessInfo.processInfo.processIdentifier,
                    myVersion: String = AppLog.version) {
        guard let id = bundleID else { return }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != myPID }
        let others = apps.map { app -> OtherInstance in
            let url = app.bundleURL
            let v = url.flatMap { InstallVersion.onDisk(bundle: $0).version } ?? "?"
            return OtherInstance(pid: app.processIdentifier, path: url?.path ?? "?", version: v)
        }
        AppLog.log("install guard: launch check: \(others.count) other Beat Key running")
        switch decide(myVersion: myVersion, others: others) {
        case .none:
            return
        case .yieldTo(let o):
            AppLog.log("install guard: other copy is newer (pid \(o.pid), \(o.version), \(o.path)) than this \(myVersion); quitting this one")
            apps.first { $0.processIdentifier == o.pid }?.activate(options: [.activateIgnoringOtherApps])
            AppLog.flush()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        case .takeOver(let list):
            for o in list {
                guard let app = apps.first(where: { $0.processIdentifier == o.pid }) else { continue }
                AppLog.log("install guard: taking over from pid \(o.pid), version \(o.version), \(o.path): terminate")
                if !app.terminate() { AppLog.log("install guard: terminate request for pid \(o.pid) was refused") }
                DispatchQueue.main.asyncAfter(deadline: .now() + forceAfter) {
                    if app.isTerminated {
                        AppLog.log("install guard: pid \(o.pid) quit")
                    } else {
                        let ok = app.forceTerminate()
                        AppLog.log("install guard: pid \(o.pid) still alive after \(Int(forceAfter)) s; forceTerminate \(ok ? "sent" : "FAILED")")
                    }
                }
            }
        }
    }
}
