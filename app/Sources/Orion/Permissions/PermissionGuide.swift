import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

/// The three macOS privacy permissions Beat Key can need. One owner for how each is checked,
/// asked for and opened in System Settings (J, 2026-11-13: "if it needs permissions, walk the user
/// through them, nobody should have to look anything up").
enum PermissionKind: String, CaseIterable {
    /// Listen on Mac audio (ScreenCaptureKit).
    case screen
    /// Listen on an audio input / interface only.
    case microphone
    /// Send to DAW.
    case accessibility

    var title: String {
        switch self {
        case .screen: return "Screen & System Audio Recording"
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        }
    }

    /// Why Beat Key asks, one line.
    var why: String {
        switch self {
        case .screen: return "So Beat Key can hear the audio your Mac plays."
        case .microphone: return "So Beat Key can hear a mic or audio interface."
        case .accessibility: return "So Beat Key can type the tempo and key into your DAW."
        }
    }

    /// The plain instruction under the button.
    var instruction: String { "Turn on Beat Key in the list." }

    var skipLabel: String {
        self == .microphone ? "Skip — I only listen to Mac audio" : "Skip for now"
    }

    /// The pane's anchor in System Settings.
    var settingsAnchor: String {
        switch self {
        case .screen: return "Privacy_ScreenCapture"
        case .microphone: return "Privacy_Microphone"
        case .accessibility: return "Privacy_Accessibility"
        }
    }

    /// Legacy form: opens the pane in System Preferences (macOS 12) and still works in System Settings.
    var legacyURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)")!
    }

    /// Modern form (System Settings, macOS 13 and later).
    var modernURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(settingsAnchor)")!
    }

    /// Tried in this order: the modern one first on macOS 13+, then the legacy one.
    var settingsURLs: [URL] {
        if #available(macOS 13.0, *) { return [modernURL, legacyURL] }
        return [legacyURL]
    }
}

enum PermissionState: Equatable {
    case granted
    /// The OS has never been asked (microphone only): its own dialog is the best path.
    case notDetermined
    /// Not granted (denied, or not yet toggled on in Settings).
    case denied
}

/// How the guide asks the system. The real one is `SystemPermissions`; tests inject a fake.
protocol PermissionChecking: AnyObject {
    func state(_ kind: PermissionKind) -> PermissionState
    /// Shows the OS's own prompt where there is one (screen: adds Beat Key to the list; microphone:
    /// the Allow dialog; Accessibility: the one-per-launch prompt). Never blocks.
    func prompt(_ kind: PermissionKind)
    /// Opens the pane. False = it did not open.
    func openSettings(_ kind: PermissionKind) -> Bool
    /// Quits and opens Beat Key again. False = could not (an unbundled `swift run`).
    func relaunch() -> Bool
}

/// The real checks, and the one place every call site asks the system. SystemAudio, InputCapture,
/// the AX send routes and the guide all come through here.
final class SystemPermissions: PermissionChecking {
    static let shared = SystemPermissions()

    static func isGranted(_ kind: PermissionKind) -> Bool { shared.state(kind) == .granted }

    func state(_ kind: PermissionKind) -> PermissionState {
        switch kind {
        case .screen:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        }
    }

    func prompt(_ kind: PermissionKind) {
        switch kind {
        case .screen:
            _ = CGRequestScreenCaptureAccess()
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                AppLog.log("permissions: microphone prompt answered: \(ok ? "allowed" : "denied")")
            }
        case .accessibility:
            if !AXTrust.promptOnce() { AppLog.log("permissions: accessibility prompt already shown this launch") }
        }
    }

    func openSettings(_ kind: PermissionKind) -> Bool {
        for u in kind.settingsURLs where NSWorkspace.shared.open(u) { return true }
        return false
    }

    func relaunch() -> Bool { AppRelaunch.now(why: "permissions") }
}

enum StepStatus: Equatable {
    case needed, granted, skipped
}

/// The walkthrough's logic, with no UI: the steps in order, one current step, a ~1 s poll that
/// confirms a grant and moves on to the next missing one, Skip, and progress kept in UserDefaults.
final class PermissionGuideModel: ObservableObject {
    static let skippedKey = "permissionGuide.skipped"
    static let resumeKey = "permissionGuide.resumeAfterRelaunch"

    /// Order of the walkthrough.
    static let order: [PermissionKind] = [.screen, .microphone, .accessibility]

    private let checker: PermissionChecking
    private let defaults: UserDefaults

    @Published private(set) var status: [PermissionKind: StepStatus] = [:]
    /// The step open now; nil = nothing missing (or all skipped).
    @Published private(set) var current: PermissionKind?
    /// The step just granted: shown as Granted for one poll before the guide moves on.
    @Published private(set) var confirming: PermissionKind?
    /// The user pressed Open System Settings for this step.
    @Published private(set) var settingsOpened: Set<PermissionKind> = []
    /// The last Open System Settings did not open anything.
    @Published private(set) var openFailed = false
    /// The microphone step is waiting for the OS dialog to be answered.
    @Published private(set) var awaitingPrompt = false

    private var prompted: Set<PermissionKind> = []

    init(checker: PermissionChecking = SystemPermissions.shared, defaults: UserDefaults = .standard) {
        self.checker = checker
        self.defaults = defaults
        for k in Self.order { status[k] = .needed }
    }

    // MARK: persisted progress

    var skipped: Set<PermissionKind> {
        get { Set((defaults.stringArray(forKey: Self.skippedKey) ?? []).compactMap(PermissionKind.init(rawValue:))) }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: Self.skippedKey) }
    }

    /// Set just before Quit & Reopen: the next launch opens the guide again.
    var resumePending: Bool {
        get { defaults.bool(forKey: Self.resumeKey) }
        set { defaults.set(newValue, forKey: Self.resumeKey) }
    }

    // MARK: reading the system

    /// Re-reads all three. A skipped step stays skipped while it is still missing.
    func refresh() {
        let skip = skipped
        for k in Self.order {
            if checker.state(k) == .granted { status[k] = .granted }
            else { status[k] = skip.contains(k) ? .skipped : .needed }
        }
    }

    /// Anything missing and not skipped: launch opens the guide only then.
    var hasMissing: Bool {
        refresh()
        return Self.order.contains { status[$0] == .needed }
    }

    var isComplete: Bool { current == nil && confirming == nil }

    /// Starts (or restarts) the walkthrough. `at` is the step a feature needs now: its Skip is
    /// forgotten and it goes first. False = nothing to show.
    @discardableResult
    func begin(at kind: PermissionKind? = nil, why: String) -> Bool {
        if let k = kind, skipped.contains(k) {
            skipped.remove(k)
            AppLog.log("permissions: \(k.rawValue) skip cleared (\(why))")
        }
        refresh()
        confirming = nil
        openFailed = false
        let first: PermissionKind?
        if let k = kind, status[k] == .needed { first = k } else { first = nextNeeded(after: nil) }
        AppLog.log("permissions: guide begins (\(why)); "
                   + Self.order.map { "\($0.rawValue)=\(Self.word(status[$0]))" }.joined(separator: " "))
        show(first)
        return first != nil
    }

    private func nextNeeded(after k: PermissionKind?) -> PermissionKind? {
        Self.order.first { status[$0] == .needed && $0 != k }
    }

    private func show(_ k: PermissionKind?) {
        current = k
        awaitingPrompt = false
        guard let k = k else {
            AppLog.log("permissions: nothing left to ask for")
            return
        }
        let st = checker.state(k)
        AppLog.log("permissions: step \(k.rawValue) shown (state \(st))")
        // The OS's own prompt first: screen adds Beat Key to the list, Accessibility shows its
        // dialog, the microphone dialog is the best path and only exists while undecided.
        let promptable = k == .microphone ? st == .notDetermined : st != .granted
        if promptable, !prompted.contains(k) {
            prompted.insert(k)
            AppLog.log("permissions: asking the system for \(k.rawValue)")
            checker.prompt(k)
        }
        awaitingPrompt = (k == .microphone && st == .notDetermined)
    }

    // MARK: the poll

    /// One tick (about every second). A grant shows as Granted for one tick, then the next
    /// missing step opens.
    func tick() {
        if let done = confirming {
            confirming = nil
            AppLog.log("permissions: moving on from \(done.rawValue)")
            show(nextNeeded(after: done))
            return
        }
        guard let k = current else { return }
        let st = checker.state(k)
        if st == .granted {
            status[k] = .granted
            confirming = k
            awaitingPrompt = false
            if resumePending { resumePending = false }
            AppLog.log("permissions: \(k.rawValue) granted (checked)")
            return
        }
        let waiting = (k == .microphone && st == .notDetermined)
        if waiting != awaitingPrompt {
            awaitingPrompt = waiting
            AppLog.log("permissions: microphone \(waiting ? "waiting for the OS dialog" : "dialog answered, not granted: Settings is the way")")
        }
    }

    // MARK: the buttons

    func openSettings() {
        guard let k = current else { return }
        let ok = checker.openSettings(k)
        settingsOpened.insert(k)
        openFailed = !ok
        AppLog.log(ok ? "permissions: opened System Settings for \(k.rawValue)"
                      : "permissions: FAILED to open System Settings for \(k.rawValue) (\(k.legacyURL.absoluteString))")
    }

    func skip() {
        guard let k = current else { return }
        skipped.insert(k)
        status[k] = .skipped
        AppLog.log("permissions: \(k.rawValue) skipped")
        show(nextNeeded(after: k))
    }

    /// macOS often reports Screen Recording only after Beat Key restarts, so once the user has
    /// been to Settings for it the step also offers Quit & Reopen.
    var offersRelaunch: Bool {
        current == .screen && settingsOpened.contains(.screen)
    }

    /// Remembers to resume, then quits and reopens. If it cannot, logs it and stays.
    func relaunch() {
        resumePending = true
        AppLog.log("permissions: quit & reopen requested at \(current?.rawValue ?? "-")")
        if !checker.relaunch() {
            resumePending = false
            AppLog.log("permissions: FAILED to relaunch (not running from a .app bundle)")
        }
    }

    static func word(_ s: StepStatus?) -> String {
        switch s {
        case .granted?: return "granted"
        case .skipped?: return "skipped"
        default: return "needed"
        }
    }

    /// A step row's one-line state, for the window.
    func rowText(_ k: PermissionKind) -> String {
        switch status[k] {
        case .granted?: return "Granted"
        case .skipped?: return "Skipped"
        default: return current == k ? "Waiting for you" : "Needed"
        }
    }
}
