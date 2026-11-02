import AppKit
import SwiftUI

/// Beat Key › Settings… (⌘,): global shortcuts, Open at Login, listening, display.
struct SettingsView: View {
    @ObservedObject var shortcuts: ShortcutStore

    var body: some View {
        Form {
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
