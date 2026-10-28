import AppKit
import Foundation

// MARK: The macOS permission a browser login needs
//
// macOS 27 guards Chrome/Brave/Edge/Firefox's own Application Support folders (and every macOS
// guards Safari's), and its TCC "does not allow prompting for unentitled binaries", so the bundled
// yt-dlp is silently refused. Beat Key is the responsible app of the yt-dlp it spawns, so Full
// Disk Access for Beat Key is what opens them. Beat Key walks the user there itself.

/// Whether Beat Key can read a protected place right now.
enum AccessStatus: Equatable { case granted, denied, unknown }

/// Opens protected folders from the app process (the process that gets the grant). Only
/// opendir + closedir: no content is ever read.
struct AccessProbe {
    var home: URL = URL(fileURLWithPath: NSHomeDirectory())
    /// Opens a path read-only and closes it. nil = it opened; else the errno.
    var open: (String) -> Int32? = AccessProbe.openDir

    /// Each browser's guarded data folder (the folder yt-dlp searches for the cookies).
    static let browserFolders: [String: String] = [
        "brave": "Library/Application Support/BraveSoftware/Brave-Browser",
        "chrome": "Library/Application Support/Google/Chrome",
        "chromium": "Library/Application Support/Chromium",
        "edge": "Library/Application Support/Microsoft Edge",
        "opera": "Library/Application Support/com.operasoftware.Opera",
        "vivaldi": "Library/Application Support/Vivaldi",
        "whale": "Library/Application Support/Naver/Whale",
        "firefox": "Library/Application Support/Firefox",
        "safari": "Library/Containers/com.apple.Safari/Data/Library/Cookies",
    ]

    /// Folders only Full Disk Access opens, and which never put up a prompt or a notification
    /// when refused. The first one that exists decides.
    static let fullDiskCanaries = ["Library/Safari", "Library/Mail", "Library/Messages"]

    static func openDir(_ path: String) -> Int32? {
        guard let d = opendir(path) else { return errno }
        closedir(d)
        return nil
    }

    private func status(_ rel: String) -> AccessStatus {
        let path = home.appendingPathComponent(rel).path
        switch open(path) {
        case nil: return .granted
        case EPERM?, EACCES?: return .denied
        default: return .unknown          // ENOENT and the rest: nothing to learn here
        }
    }

    /// The browser's own data folder. One open, the same refusal yt-dlp would get.
    func browserData(_ browser: String) -> AccessStatus {
        guard let rel = AccessProbe.browserFolders[browser] else { return .unknown }
        return status(rel)
    }

    /// Full Disk Access, from the canaries.
    func fullDisk() -> AccessStatus {
        for c in AccessProbe.fullDiskCanaries {
            let s = status(c)
            if s != .unknown { return s }
        }
        return .unknown
    }

    /// The check while the sheet waits. The Full Disk Access canary every time (refused
    /// silently); the browser's own folder only when `withBrowser` (every few checks, since a
    /// refusal there can post macOS's "Data Access Blocked" notice) or when no canary exists.
    func waitingCheck(_ browser: String, withBrowser: Bool = true) -> AccessStatus {
        let s = fullDisk()
        if s == .granted { return .granted }
        if s == .unknown || withBrowser {
            let b = browserData(browser)
            if b == .granted { return .granted }
            if s == .unknown { return b }
        }
        return s
    }
}

/// System Settings › Privacy & Security › Full Disk Access.
enum FullDiskAccessPane {
    /// macOS 13+ System Settings (SecurityPrivacyExtension, anchor Privacy_AllFiles).
    static let modern = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!
    /// macOS 12 System Preferences (Security.prefPane, same anchor).
    static let legacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    static func url(osMajor: Int) -> URL { osMajor >= 13 ? modern : legacy }

    static func open(osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        NSWorkspace.shared.open(url(osMajor: osMajor))
    }
}

/// The link to re-run with a browser login after the relaunch.
struct PendingRetry: Equatable {
    let url: String
    let browser: String
}

/// Persists one pending retry across the relaunch; `take()` reads and clears it (used once).
struct PendingRetryStore {
    var defaults: UserDefaults = .standard
    static let urlKey = "pendingRetryURL"
    static let browserKey = "pendingRetryBrowser"
    /// The last browser a login was tried with (Run Doctor checks it; nil = never tried).
    static let loginBrowserKey = "lastLoginBrowser"

    func save(_ p: PendingRetry) {
        defaults.set(p.url, forKey: PendingRetryStore.urlKey)
        defaults.set(p.browser, forKey: PendingRetryStore.browserKey)
    }

    func take() -> PendingRetry? {
        let u = defaults.string(forKey: PendingRetryStore.urlKey)
        let b = defaults.string(forKey: PendingRetryStore.browserKey)
        defaults.removeObject(forKey: PendingRetryStore.urlKey)
        defaults.removeObject(forKey: PendingRetryStore.browserKey)
        guard let url = u, !url.isEmpty, let browser = b, !browser.isEmpty else { return nil }
        return PendingRetry(url: url, browser: browser)
    }

    var lastLoginBrowser: String? {
        get { defaults.string(forKey: PendingRetryStore.loginBrowserKey) }
        nonmutating set { defaults.set(newValue, forKey: PendingRetryStore.loginBrowserKey) }
    }
}

/// The permission sheet's states.
enum AccessPhase: Equatable {
    case closed
    /// Waiting for the user to turn on Full Disk Access.
    case asking(browser: String)
    /// macOS now lets Beat Key in: offer Restart & Try Again.
    case granted(browser: String)
    /// The retry is saved and Beat Key is relaunching.
    case restarting(PendingRetry)

    var isOpen: Bool { self != .closed }
    var browser: String? {
        switch self {
        case .closed: return nil
        case .asking(let b), .granted(let b): return b
        case .restarting(let p): return p.browser
        }
    }
}

/// The pure state machine behind the sheet.
struct AccessFlow: Equatable {
    private(set) var phase: AccessPhase = .closed
    private(set) var url = ""

    /// A login run found the browser's data blocked (or it is known blocked before the run).
    mutating func blocked(url: String, browser: String) {
        if case .restarting = phase { return }
        self.url = url
        phase = .asking(browser: browser)
    }

    /// One check while the sheet waits.
    mutating func checked(_ s: AccessStatus) {
        if case .asking(let b) = phase, s == .granted { phase = .granted(browser: b) }
    }

    /// Not now: the sheet closes, nothing is saved.
    mutating func dismiss() {
        if case .restarting = phase { return }
        phase = .closed
    }

    /// Restart & Try Again: returns the retry to persist before relaunching.
    mutating func restart() -> PendingRetry? {
        guard case .granted(let b) = phase else { return nil }
        let p = PendingRetry(url: url, browser: b)
        phase = .restarting(p)
        return p
    }
}

/// Relaunches the app: a tiny shell waits for this process to exit, then `open -n` starts the
/// bundle again (Full Disk Access applies to the new process).
enum Relauncher {
    static func command(pid: Int32, bundle: URL) -> [String] {
        let path = bundle.path.replacingOccurrences(of: "'", with: "'\\''")
        return ["/bin/sh", "-c",
                "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open -n '\(path)'"]
    }

    /// false when there is no .app to reopen (`swift run`).
    static func relaunch(bundle: URL = Bundle.main.bundleURL) -> Bool {
        guard bundle.pathExtension == "app" else { return false }
        let c = command(pid: getpid(), bundle: bundle)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: c[0])
        p.arguments = Array(c.dropFirst())
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        NSApp.terminate(nil)
        return true
    }
}

/// Runs the sheet: polls every ~2 s while it asks, then saves the retry and relaunches.
final class AccessController: ObservableObject {
    @Published private(set) var flow = AccessFlow()
    let probe: AccessProbe
    let store: PendingRetryStore
    private let interval: TimeInterval
    private let relaunch: () -> Bool
    /// Runs the retry in this process when there is nothing to relaunch (`swift run`).
    var retryHere: ((PendingRetry) -> Void)?
    /// Not now: the LCD goes back to idle, the link stays in the field.
    var onClose: (() -> Void)?
    private var timer: Timer?
    private var ticks = 0
    /// The browser's folder is opened on every n-th check (the canary on every one).
    static let browserEvery = 5
    /// ORION_FAKE_STATE pins the sheet: no polling.
    var pinned = false

    init(probe: AccessProbe = AccessProbe(), store: PendingRetryStore = PendingRetryStore(),
         interval: TimeInterval = 2, relaunch: @escaping () -> Bool = { Relauncher.relaunch() }) {
        self.probe = probe
        self.store = store
        self.interval = interval
        self.relaunch = relaunch
    }

    var phase: AccessPhase { flow.phase }

    func blocked(url: String, browser: String) {
        guard !pinned else { return }
        flow.blocked(url: url, browser: browser)
        startPolling()
    }

    /// For screenshots only.
    func pin(_ phase: AccessPhase, url: String) {
        pinned = true
        flow = AccessFlow()
        if let b = phase.browser { flow.blocked(url: url, browser: b) }
        if case .granted = phase { flow.checked(.granted) }
    }

    func check() {
        guard case .asking(let b) = flow.phase else { return }
        ticks += 1
        flow.checked(probe.waitingCheck(b, withBrowser: ticks % AccessController.browserEvery == 0))
        if case .granted = flow.phase { stopPolling() }
    }

    func dismiss() {
        guard flow.phase.isOpen else { return }
        flow.dismiss()
        stopPolling()
        if !flow.phase.isOpen { onClose?() }
    }

    func restart() {
        guard let p = flow.restart() else { return }
        stopPolling()
        store.save(p)
        if !relaunch() {
            // nothing to relaunch: retry now, once
            _ = store.take()
            flow = AccessFlow()
            retryHere?(p)
        }
    }

    private func startPolling() {
        stopPolling()
        ticks = 0
        guard !pinned else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        check()
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
