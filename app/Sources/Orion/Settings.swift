import AppKit
import SwiftUI

/// Beat Key › Settings… (⌘,): global shortcuts, Open at Login, listening, display.
struct SettingsView: View {
    @ObservedObject var shortcuts: ShortcutStore
    @ObservedObject var loginItem: LoginItemSettings
    @ObservedObject var live: LiveSettings
    @ObservedObject var display: DisplaySettings
    @State private var devices: [InputDevice] = []

    var body: some View {
        Form {
            Section(header: Text("Display").font(.headline)) {
                Toggle("High Contrast Readout", isOn: $display.highContrast)
                Text("Brighter LCD text on pure black, no glow. The lamps always carry a shape too: octagon = locked, triangle = unsure, circle = listening.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider().padding(.vertical, 6)
            Section(header: Text("Listen").font(.headline)) {
                Picker("Listen to", selection: deviceBinding) {
                    if LiveSource.systemAvailable { Text("System Audio (everything the Mac plays)").tag("system") }
                    Text("Default Input").tag("default")
                    ForEach(devices) { d in Text(d.name).tag("uid:\(d.uid)") }
                }
                if case .input(let uid, _) = live.source {
                    let count = uid.flatMap { u in devices.first { $0.uid == u }?.channels } ?? 2
                    if count > 1 {
                        Picker("Channel", selection: channelBinding) {
                            Text("All channels").tag(0)
                            ForEach(1...count, id: \.self) { Text("Channel \($0)").tag($0) }
                        }
                    }
                }
                Picker("Start over after", selection: $live.gap) {
                    ForEach(LiveSettings.gaps, id: \.self) { Text("\(Int($0)) s of silence").tag($0) }
                }
                Text(LiveSource.systemAvailable
                     ? "Nothing is recorded or saved. System Audio needs Screen & System Audio Recording permission; inputs need Microphone permission."
                     : "Nothing is recorded or saved. Inputs need Microphone permission. System Audio needs macOS 13 or newer.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .onAppear { devices = InputDevice.all() }
            Divider().padding(.vertical, 6)
            Section(header: Text("General").font(.headline)) {
                Toggle("Open at Login", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.set($0) }))
                if let m = loginItem.message {
                    HStack {
                        Text(m).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        if loginItem.canOpenSystemSettings {
                            Button("Open System Settings") { loginItem.openSystemSettings() }
                        }
                    }
                }
            }
            .onAppear { loginItem.refresh() }
            Divider().padding(.vertical, 6)
            Section(header: Text("Global shortcuts").font(.headline)) {
                ForEach(HotkeyAction.allCases) { a in
                    HStack {
                        Text(a.title).frame(width: 170, alignment: .leading)
                        ShortcutRecorder(action: a, store: shortcuts)
                    }
                }
                Text("Work in any app. Click a shortcut, then type the new keys (with ⌘, ⌃ or ⌥). Delete turns it off, Esc cancels.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    /// "system" | "default" | "uid:<device uid>"; a new device starts on all channels.
    private var deviceBinding: Binding<String> {
        Binding(get: {
            switch live.source {
            case .system: return "system"
            case .input(nil, _): return "default"
            case .input(let uid?, _): return "uid:\(uid)"
            }
        }, set: { tag in
            if tag == "system" { live.source = .system }
            else if tag == "default" { live.source = .input(uid: nil, channel: 0) }
            else { live.source = .input(uid: String(tag.dropFirst(4)), channel: 0) }
        })
    }

    private var channelBinding: Binding<Int> {
        Binding(get: {
            if case .input(_, let ch) = live.source { return ch }
            return 0
        }, set: { ch in
            if case .input(let uid, _) = live.source { live.source = .input(uid: uid, channel: ch) }
        })
    }
}

/// One shortcut: shows the keys; click, then type new ones.
struct ShortcutRecorder: View {
    let action: HotkeyAction
    @ObservedObject var store: ShortcutStore
    @State private var recording = false
    @State private var monitor: Any?
    @State private var note: String?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Text(recording ? "Type the keys…" : (store.shortcut(action)?.display ?? "Off"))
                    .frame(width: 110)
            }
            .accessibility(label: Text("\(action.title) shortcut, \(store.shortcut(action)?.display ?? "off")"))
            Button("Default") { store.reset(action); HotkeyCenter.shared.apply(store); note = nil }
                .disabled(store.shortcut(action) == action.defaultShortcut)
            if let n = note ?? (HotkeyCenter.shared.failed.contains(action) ? "In use by another app" : nil) {
                Text(n).font(.caption).foregroundColor(.red)
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        note = nil
        recording = true
        HotkeyCenter.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            switch Int(e.keyCode) {
            case 53:                       // Esc
                stop()
            case 51, 117:                  // Delete, Forward Delete
                store.set(nil, for: action); stop()
            default:
                guard let s = Shortcut.recorded(keyCode: e.keyCode, flags: e.modifierFlags,
                                                characters: e.charactersIgnoringModifiers) else {
                    note = "Add ⌘, ⌃ or ⌥"; NSSound.beep(); return nil
                }
                if let other = store.conflict(s, for: action) {
                    note = "Used by \(other.title)"; NSSound.beep(); return nil
                }
                store.set(s, for: action); stop()
            }
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        if recording { recording = false; HotkeyCenter.shared.apply(store) }
    }
}

/// High Contrast Readout (Settings and the View menu), remembered between launches. Theme reads
/// it through `Theme.highContrast`; views that observe this object redraw when it flips.
final class DisplaySettings: ObservableObject {
    static let key = "highContrast"
    private let defaults: UserDefaults

    @Published var highContrast: Bool {
        didSet {
            Theme.highContrast = highContrast
            defaults.set(highContrast, forKey: DisplaySettings.key)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        highContrast = defaults.bool(forKey: DisplaySettings.key)
        Theme.highContrast = highContrast
    }
}

/// Opens the Settings window from outside the app menu (the menu-bar item). The SwiftUI
/// selectors changed name between macOS releases, so the app menu's own ⌘, item is clicked.
enum SettingsOpener {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let i = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command })
        else { NSSound.beep(); return }
        appMenu.performActionForItem(at: i)
    }
}
