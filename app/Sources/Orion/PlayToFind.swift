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

/// A small, quiet synth: a sine with a little second harmonic and a fast decay, through one
/// AVAudioEngine that starts on the first note and stops after a few idle seconds.
final class NoteSynth {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    private var idle: Timer?
    private var failedOnce = false
    static let gain: Float = 0.12
    static let seconds = 0.45

    func play(midi: Int) {
        guard ensureRunning(), let player, let format else { return }
        let hz = 440 * pow(2, Double(midi - 69) / 12)
        let rate = format.sampleRate
        let n = AVAudioFrameCount(rate * NoteSynth.seconds)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n) else { return }
        buf.frameLength = n
        let attack = rate * 0.005
        for ch in 0..<Int(format.channelCount) {
            guard let p = buf.floatChannelData?[ch] else { continue }
            for i in 0..<Int(n) {
                let t = Double(i) / rate
                let env = min(1, Double(i) / attack) * exp(-t * 7)
                let v = sin(2 * .pi * hz * t) + 0.3 * sin(4 * .pi * hz * t)
                p[i] = Float(v * env) * NoteSynth.gain
            }
        }
        player.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
        idle?.invalidate()
        idle = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in self?.stop() }
    }

    private func ensureRunning() -> Bool {
        if let e = engine, e.isRunning { return true }
        let e = AVAudioEngine()
        let p = AVAudioPlayerNode()
        let out = e.outputNode.inputFormat(forBus: 0)
        let rate = out.sampleRate > 0 ? out.sampleRate : 44100
        guard let f = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return false }
        e.attach(p)
        e.connect(p, to: e.mainMixerNode, format: f)
        do {
            try e.start()
        } catch {
            if !failedOnce { AppLog.log("play-to-find: synth would not start: \(error.localizedDescription)") }
            failedOnce = true
            return false
        }
        engine = e; player = p; format = f
        return true
    }

    func stop() {
        idle?.invalidate(); idle = nil
        player?.stop()
        engine?.stop()
        engine = nil; player = nil; format = nil
    }
}

/// The key monitor: one local monitor for the window and the popover.
final class PlayToFind {
    static let shared = PlayToFind()
    private(set) var state = PlayState()
    private let synth = NoteSynth()
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

    /// Beat Key's own window or its popover, with no text being edited.
    static func isOurs(_ e: NSEvent) -> Bool {
        guard let w = e.window else { return false }
        let popover = String(describing: type(of: w)).contains("Popover")
        guard popover || w.title == Brand.name else { return false }
        if let r = w.firstResponder, r is NSText || r is NSTextField || r is NSTextView { return false }
        return true
    }

    private func handle(_ e: NSEvent) -> NSEvent? {
        guard PlayToFind.isOurs(e),
              let act = MusicalTyping.action(keyCode: e.keyCode, modifiers: e.modifierFlags) else { return e }
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
        case .note(let n):
            if e.isARepeat { return nil }
            // the analyzer's own scores decide major / minor (the raw order: a choice moved to the
            // front at 0 % must not count)
            let keys = (r?.keys ?? []).filter { $0.1 > 0 }
            synth.play(midi: state.press(n, keys: keys))
            apply(r)
        case .toggleMode:
            guard r != nil else { return e }   // nothing to set: let SPACE do what it did
            if e.isARepeat { return nil }
            guard state.toggle(shownKey: r?.keys.first?.0) else { NSSound.beep(); return nil }
            apply(r)
        }
        return nil
    }

    private func apply(_ r: Result?) {
        guard let key = state.key else { return }
        guard let r else { return }   // no reading: the notes sound, nothing to set
        SpellingSettings.shared.choose(key, of: r)
        AppLog.log("play-to-find: key set to \(key)")
    }
}
