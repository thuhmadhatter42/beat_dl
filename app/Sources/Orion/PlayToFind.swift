import AppKit
import AVFoundation

// Play to find the key: while Beat Key's window or popover is in front (and no text field has
// the caret), the computer keyboard is a piano, laid out like Logic's Musical Typing:
//   A W S E D F T G Y H U J = C C# D D# E F F# G G# A A# B, K = the C above; Z / X = octave down / up.
// Each press sounds the note. The LAST note pressed is the root; major or minor is whichever the
// analyzer scored higher for that root; SPACE flips major / minor. The result becomes THE key
// through KeyChoice (the one override path, same as a click on key 2 or 3). ⇧⌘A = Send to Auto-Tune.

enum MusicalTyping {
    /// What a key press does.
    enum Action: Equatable {
        /// Semitones above the current octave's C (0...12).
        case note(Int)
        case octaveDown, octaveUp, toggleMode, sendAutoTune
    }

    /// Physical keys (ANSI virtual key codes), so the layout follows the keycaps' positions as
    /// Logic's does, whatever the keyboard language.
    static let noteKeys: [UInt16: Int] = [
        0: 0,    // A  C
        13: 1,   // W  C#
        1: 2,    // S  D
        14: 3,   // E  D#
        2: 4,    // D  E
        3: 5,    // F  F
        17: 6,   // T  F#
        5: 7,    // G  G
        16: 8,   // Y  G#
        4: 9,    // H  A
        32: 10,  // U  A#
        38: 11,  // J  B
        40: 12,  // K  C above
    ]
    static let zKey: UInt16 = 6, xKey: UInt16 = 7, space: UInt16 = 49, aKey: UInt16 = 0

    /// The action for a key press; nil = not ours (let it through). Command / Control / Option
    /// combinations are never notes; ⇧⌘A is the one shortcut.
    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Action? {
        let m = modifiers.intersection([.command, .control, .option, .shift])
        if keyCode == aKey && m == [.command, .shift] { return .sendAutoTune }
        guard m.isDisjoint(with: [.command, .control, .option]) else { return nil }
        if let n = noteKeys[keyCode] { return .note(n) }
        switch keyCode {
        case zKey: return .octaveDown
        case xKey: return .octaveUp
        case space: return .toggleMode
        default: return nil
        }
    }

    /// Major or minor for `root`: whichever of the two the analyzer scored higher (its keys as
    /// listed); neither listed = the mode of its top key; no keys = major.
    static func minor(forRoot root: Int, keys: [(String, Int)]) -> Bool {
        let scored = keys.compactMap { k -> (minor: Bool, score: Int)? in
            guard let c = AutoTuneSend.keyClass(k.0), c.pitchClass == root else { return nil }
            return (c.minor, k.1)
        }
        if let best = scored.max(by: { $0.score < $1.score }) { return best.minor }
        return keys.first.flatMap { AutoTuneSend.keyClass($0.0)?.minor } ?? false
    }
}

/// The keyboard's state: octave, the last root and mode. Pure, so it can be tested.
struct PlayState: Equatable {
    /// MIDI note of the octave's C (60 = middle C).
    var octaveC = 60
    var root: Int?
    var minor = false

    static let lowestC = 24, highestC = 96

    /// A note pressed: returns its MIDI number, and the root (pitch class) and mode it sets.
    mutating func press(_ semitone: Int, keys: [(String, Int)]) -> Int {
        let midi = octaveC + semitone
        let pc = ((midi % 12) + 12) % 12
        root = pc
        minor = MusicalTyping.minor(forRoot: pc, keys: keys)
        return midi
    }

    mutating func octave(_ up: Bool) {
        octaveC = max(PlayState.lowestC, min(PlayState.highestC, octaveC + (up ? 12 : -12)))
    }

    /// SPACE: flip major / minor of the root; no root yet = flip the key on show (`shownKey`).
    /// False = nothing to flip.
    mutating func toggle(shownKey: String?) -> Bool {
        if root == nil {
            guard let k = shownKey.flatMap(AutoTuneSend.keyClass) else { return false }
            root = k.pitchClass; minor = k.minor
        }
        minor.toggle()
        return true
    }

    /// The key it makes, spelled like Auto-Tune's menu ("Fm", "Ab"); nil = no root yet.
    var key: String? { root.map { KeyChoice.keyName($0, minor: minor) } }
}

/// The key monitor: one local monitor for the window and the popover.
final class PlayToFind {
    static let shared = PlayToFind()
    private(set) var state = PlayState()
    private var monitor: Any?
    /// The reading on show (respelled, with any choice), and Send to Auto-Tune's own action.
    private var shown: () -> Result? = { nil }
    private var sendAutoTune: () -> Bool = { false }
    private var lastReading: (URL, String)?

    func install(shown: @escaping () -> Result?, sendAutoTune: @escaping () -> Bool) {
        self.shown = shown
        self.sendAutoTune = sendAutoTune
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e) ?? e
        }
        AppLog.log("play-to-find: keyboard installed")
    }

    /// Whether a key press is the keyboard's. The window and the popover both open with the
    /// (empty) link field holding the caret, and the old check refused every key whenever any
    /// text field was first responder, so no note ever played (J, 2026-11-05 17:41). Now only a
    /// field that already holds text keeps the keys; an empty one gives them to the keyboard
    /// (a link is pasted with ⌘V, which is never a note). ⇧⌘A works whatever has the caret.
    enum Decision: Equatable {
        case play
        case ignore(String)
    }

    static func decide(action: MusicalTyping.Action, ourWindow: Bool, windowIsKey: Bool, editingText: String?) -> Decision {
        guard ourWindow else { return .ignore("not Beat Key's window or popover") }
        guard windowIsKey else { return .ignore("window not key") }
        if action == .sendAutoTune { return .play }
        if let t = editingText, !t.isEmpty { return .ignore("text field has text") }
        return .play
    }

    /// Beat Key's own window (titled Brand.name) or its popover; never a panel, alert, Settings.
    static func isOurWindow(_ w: NSWindow?) -> Bool {
        guard let w else { return false }
        if String(describing: type(of: w)).contains("Popover") { return true }
        if w is NSPanel { return false }
        return w.title == Brand.name
    }

    /// The text being edited in the window's focused field; nil = no field has the caret.
    static func editingText(_ w: NSWindow?) -> String? {
        switch w?.firstResponder {
        case let t as NSTextView: return t.string           // a field editor or a text view
        case let f as NSTextField: return f.stringValue
        case let t as NSText: return t.string
        default: return nil
        }
    }

    static func noteName(_ midi: Int) -> String {
        KeyChoice.keyName(((midi % 12) + 12) % 12, minor: false) + String(midi / 12 - 1)
    }

    private var lastIgnore: String?

    private func handle(_ e: NSEvent) -> NSEvent? {
        guard let act = MusicalTyping.action(keyCode: e.keyCode, modifiers: e.modifierFlags) else { return e }
        let d = PlayToFind.decide(action: act, ourWindow: PlayToFind.isOurWindow(e.window),
                                  windowIsKey: e.window?.isKeyWindow ?? false, editingText: PlayToFind.editingText(e.window))
        if case .ignore(let why) = d {
            if why != lastIgnore { AppLog.log("play-to-find: key ignored: \(why)") }   // once per reason in a row
            lastIgnore = why
            return e
        }
        lastIgnore = nil
        let r = shown()
        // a new reading starts the keyboard's root over (the octave stays)
        if let r, lastReading.map({ $0.0 != r.file || $0.1 != r.name }) ?? true {
            lastReading = (r.file, r.name); state.root = nil
        }
        switch act {
        case .sendAutoTune:
            AppLog.log("play-to-find: ⇧⌘A send to auto-tune")
            if !sendAutoTune() { NSSound.beep() }
        case .octaveDown, .octaveUp:
            if e.isARepeat { return nil }
            state.octave(act == .octaveUp)
            AppLog.log("play-to-find: octave \(act == .octaveUp ? "up" : "down"), C = \(PlayToFind.noteName(state.octaveC))")
        case .note(let n):
            if e.isARepeat { return nil }
            // the analyzer's own scores decide major / minor (the raw order: a choice moved to the
            // front at 0 % must not count)
            let keys = (r?.keys ?? []).filter { $0.1 > 0 }
            let midi = state.press(n, keys: keys)
            AppLog.log("play-to-find: note \(PlayToFind.noteName(midi))")
            NoteSynth.shared.play(midi: midi)
            apply(r)
        case .toggleMode:
            guard r != nil else { AppLog.log("play-to-find: space ignored: no reading"); return e }   // let SPACE do what it did
            if e.isARepeat { return nil }
            guard state.toggle(shownKey: r?.keys.first?.0) else { NSSound.beep(); return nil }
            apply(r)
        }
        return nil
    }

    private func apply(_ r: Result?) {
        guard let key = state.key else { return }
        guard let r else { AppLog.log("play-to-find: no reading, key not set (\(key))"); return }   // the notes sound
        SpellingSettings.shared.setManualKey(key, of: r, from: .keyboard)
        AppLog.log("play-to-find: key set to \(key)")
    }
}
