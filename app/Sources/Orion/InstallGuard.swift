import AppKit

/// An old Beat Key outliving an install: another Beat Key process is running when this one
/// launches (TwinCheck, once, at launch; nothing polls). The installer (.pkg) makes the user quit
/// a running Beat Key first and Sparkle quits it itself; this covers copies started by hand, e.g.
/// one left open from a DMG or an old Orion.app. Every line in beatkey.log starts "install guard:".

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
    /// Bundle.main's cached copy). nil = could not read.
    static func onDisk(bundle: URL) -> String? {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let d = try? Data(contentsOf: plist),
              let o = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any]
        else { return nil }
        return o["CFBundleShortVersionString"] as? String
    }
}

// MARK: - Two copies

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
            let v = url.flatMap { InstallVersion.onDisk(bundle: $0) } ?? "?"
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
