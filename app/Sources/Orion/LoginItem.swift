import AppKit
import ServiceManagement

/// Settings › Open at Login.
/// macOS 13+: SMAppService.mainApp (the app itself is the login item; listed in System Settings ›
/// General › Login Items, may need the user's approval there).
/// macOS 12: a per-user LaunchAgent that runs `open -b com.jshriver.orion` at login. It needs no
/// helper app inside the bundle (SMLoginItemSetEnabled would) and works the same signed or not.
protocol LoginItemBackend {
    var isEnabled: Bool { get }
    /// macOS wants the user to allow it in System Settings first.
    var needsApproval: Bool { get }
    func setEnabled(_ on: Bool) throws
}

struct LaunchAgentLoginItem: LoginItemBackend {
    static let label = "com.jshriver.orion.open-at-login"
    var folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    var bundleID = Bundle.main.bundleIdentifier ?? "com.jshriver.orion"

    var plist: URL { folder.appendingPathComponent("\(LaunchAgentLoginItem.label).plist") }
    var isEnabled: Bool { FileManager.default.fileExists(atPath: plist.path) }
    var needsApproval: Bool { false }

    /// What launchd reads at the next login. Nothing is loaded now: the app is already running.
    var contents: [String: Any] {
        ["Label": LaunchAgentLoginItem.label,
         "ProgramArguments": ["/usr/bin/open", "-b", bundleID],
         "RunAtLoad": true,
         "ProcessType": "Interactive"]
    }

    func setEnabled(_ on: Bool) throws {
        let fm = FileManager.default
        if on {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
            try data.write(to: plist, options: .atomic)
        } else if fm.fileExists(atPath: plist.path) {
            try fm.removeItem(at: plist)
        }
    }
}

@available(macOS 13.0, *)
struct AppServiceLoginItem: LoginItemBackend {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled || needsApproval }
    var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
    func setEnabled(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

final class LoginItemSettings: ObservableObject {
    @Published private(set) var enabled = false
    /// A problem or a step left to the user; nil = nothing to say.
    @Published private(set) var message: String?
    private let backend: LoginItemBackend
    /// The macOS 12 agent, still there after an upgrade to 13: replaced by the app service.
    private let legacy: LaunchAgentLoginItem?

    init(backend: LoginItemBackend? = nil, legacy: LaunchAgentLoginItem? = nil) {
        if let b = backend {
            self.backend = b
            self.legacy = legacy
        } else if #available(macOS 13.0, *) {
            self.backend = AppServiceLoginItem()
            self.legacy = LaunchAgentLoginItem()
        } else {
            self.backend = LaunchAgentLoginItem()
            self.legacy = nil
        }
        refresh()
    }

    func refresh() {
        enabled = backend.isEnabled || (legacy?.isEnabled ?? false)
        message = backend.needsApproval ? LoginItemSettings.approvalText : nil
    }

    static let approvalText = "Allow Beat Key in System Settings › General › Login Items."

    func set(_ on: Bool) {
        do {
            try backend.setEnabled(on)
            try legacy?.setEnabled(false)
            refresh()
        } catch {
            refresh()
            message = "Couldn't change Open at Login: \(error.localizedDescription)"
        }
    }

    var canOpenSystemSettings: Bool { backend.needsApproval }

    func openSystemSettings() {
        if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems() }
    }
}
