import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A global shortcut: a virtual key code plus Carbon modifier bits (what RegisterEventHotKey
/// takes), and the key's printed name for the menus ("K", "F5", "Space").
struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    /// "⌃⌥⌘K": modifiers in the order macOS menus print them.
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    static func carbonModifiers(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    /// A key typed in the recorder, or nil when it can't be a global shortcut: it needs ⌘, ⌃ or ⌥
    /// (Shift alone would steal ordinary typing everywhere).
    static func recorded(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> Shortcut? {
        let m = carbonModifiers(flags)
        guard m & UInt32(cmdKey | controlKey | optionKey) != 0 else { return nil }
        guard let name = keyName(keyCode: keyCode, characters: characters) else { return nil }
        return Shortcut(keyCode: UInt32(keyCode), modifiers: m, key: name)
    }

    private static let named: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    static func keyName(keyCode: UInt16, characters: String?) -> String? {
        if let n = named[Int(keyCode)] { return n }
        guard let c = characters?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), c.count == 1,
              let u = c.unicodeScalars.first, !(0xF700...0xF8FF).contains(u.value) else { return nil }
        return c
    }

    /// The same keys as a SwiftUI menu shortcut, when the key is a plain character.
    var menuShortcut: KeyboardShortcut? {
        guard key.count == 1, let ch = key.lowercased().first else { return nil }
        var m: SwiftUI.EventModifiers = []
        if modifiers & UInt32(controlKey) != 0 { m.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { m.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { m.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { m.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(ch), modifiers: m)
    }
}

/// What a global shortcut does. Send to DAW joins this list with plan §4.
enum HotkeyAction: String, CaseIterable, Identifiable {
    // new actions go at the end: hotKeyID is the position in this list
    case listen, analyzeFile, newSong, hold, analyzeSelection
    var id: String { rawValue }

    var title: String {
        switch self {
        case .listen: return "Start / Stop Listening"
        case .analyzeFile: return "Analyze a File…"
        case .newSong: return "New Song (Reset Listening)"
        case .hold: return "Hold / Release Reading"
        case .analyzeSelection: return "Analyze Selection in DAW"
        }
    }

    /// nil = no keys until the user sets some in Settings › Shortcuts.
    var defaultShortcut: Shortcut? {
        let ctrlOptCmd = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .listen: return Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: ctrlOptCmd, key: "K")
        case .analyzeFile: return Shortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: ctrlOptCmd, key: "F")
        case .newSong: return Shortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: ctrlOptCmd, key: "R")
        case .hold: return Shortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: ctrlOptCmd, key: "H")
        // Unassigned by default: ⌃⌥⌘L (J, 2026-11-05) and ⌥⌘B (J, 2026-11-08, Bounce) are Pro Tools' own.
        case .analyzeSelection: return nil
        }
    }

    var hotKeyID: UInt32 { UInt32(HotkeyAction.allCases.firstIndex(of: self)! + 1) }
}

/// The shortcuts, remembered between launches. Never set = the default; cleared = off.
final class ShortcutStore: ObservableObject {
    private let defaults: UserDefaults
    @Published private(set) var shortcuts: [HotkeyAction: Shortcut] = [:]

    static func key(_ a: HotkeyAction) -> String { "hotkey.\(a.rawValue)" }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for a in HotkeyAction.allCases { shortcuts[a] = load(a) }
    }

    private func load(_ a: HotkeyAction) -> Shortcut? {
        guard let data = defaults.data(forKey: ShortcutStore.key(a)) else { return a.defaultShortcut }
        return (try? JSONDecoder().decode(Shortcut?.self, from: data)) ?? nil
    }

    func shortcut(_ a: HotkeyAction) -> Shortcut? { shortcuts[a] ?? nil }

    /// The other action already on these keys, if any (a key does one thing).
    func conflict(_ s: Shortcut, for a: HotkeyAction) -> HotkeyAction? {
        HotkeyAction.allCases.first { $0 != a && shortcut($0).map { $0.keyCode == s.keyCode && $0.modifiers == s.modifiers } == true }
    }

    /// nil turns the shortcut off. False = refused (another action has those keys).
    @discardableResult
    func set(_ s: Shortcut?, for a: HotkeyAction) -> Bool {
        if let s = s, conflict(s, for: a) != nil { return false }
        shortcuts[a] = s
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: ShortcutStore.key(a)) }
        return true
    }

    func reset(_ a: HotkeyAction) {
        defaults.removeObject(forKey: ShortcutStore.key(a))
        shortcuts[a] = a.defaultShortcut
        if let d = a.defaultShortcut, conflict(d, for: a) != nil { set(nil, for: a) }
    }
}

/// Registers the shortcuts system-wide with Carbon's RegisterEventHotKey (works in any app,
/// needs no Accessibility permission). Main thread only.
final class HotkeyCenter {
    static let shared = HotkeyCenter()
    static let signature: OSType = 0x424B_6579   // 'BKey'

    var actions: [HotkeyAction: () -> Void] = [:]
    private var refs: [HotkeyAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    /// Keys another app holds: RegisterEventHotKey said no.
    private(set) var failed: Set<HotkeyAction> = []

    /// Registers every shortcut in `store` (unregistering the old ones first).
    func apply(_ store: ShortcutStore) {
        installHandler()
        unregisterAll()
        failed = []
        for a in HotkeyAction.allCases {
            guard let s = store.shortcut(a) else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: HotkeyCenter.signature, id: a.hotKeyID)
            let st = RegisterEventHotKey(s.keyCode, s.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if st == noErr, let r = ref {
                refs[a] = r
                AppLog.log("hotkey \(a.rawValue) \(s.display): registered")
            } else {
                failed.insert(a)
                AppLog.log("hotkey \(a.rawValue) \(s.display): FAILED (OSStatus \(st)), another app holds it")
            }
        }
    }

    /// While the Settings recorder listens for new keys, the old ones must not fire.
    func unregisterAll() {
        for r in refs.values { UnregisterEventHotKey(r) }
        refs = [:]
    }

    func fire(_ id: UInt32) {
        guard let a = HotkeyAction.allCases.first(where: { $0.hotKeyID == id }) else { return }
        if let go = actions[a] { go() } else { NSSound.beep() }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let st = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard st == noErr, id.signature == HotkeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { HotkeyCenter.shared.fire(id.id) }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}

extension View {
    /// `.keyboardShortcut` when there is one (a cleared shortcut leaves the menu item bare).
    @ViewBuilder func optionalShortcut(_ s: KeyboardShortcut?) -> some View {
        if let s = s { keyboardShortcut(s) } else { self }
    }
}
