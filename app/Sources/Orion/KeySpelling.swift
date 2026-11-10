import Combine
import Foundation

/// One of the top 3 keys the user clicked to make it THE key (shown big, sent to Auto-Tune, the
/// DAW and the MIDI file) for one reading. Matched by the reading's file + name, so the next file
/// or song shows the analyzer's own order again.
struct KeyChoice: Equatable {
    let file: URL
    let name: String
    let pitchClass: Int
    let minor: Bool

    /// A key as Auto-Tune's Key menu spells it: major C Db D Eb E F F# G Ab A Bb B, minor
    /// C C# D Eb E F F# G G# A Bb B (+ "m"). The analyzer's own spelling.
    static func keyName(_ pitchClass: Int, minor: Bool) -> String {
        AXKeyNames.roots(pitchClass, minor: minor)[0] + (minor ? "m" : "")
    }

    /// Any spelling of a key ("Gb", "D#m", "E♭") as Auto-Tune names it; a non-key comes back as given.
    static func autoTuneName(_ name: String) -> String {
        guard let k = AutoTuneSend.keyClass(name) else { return name }
        return keyName(k.pitchClass, minor: k.minor)
    }

    /// All 24 keys in that spelling: the 12 majors from C, then the 12 minors from C.
    static let allKeys: [String] = (0..<12).map { keyName($0, minor: false) } + (0..<12).map { keyName($0, minor: true) }

    /// This choice belongs to reading `r` (same file and name).
    func matches(_ r: Result) -> Bool { file == r.file && name == r.name }

    /// This choice is key `name` (any spelling).
    func isKey(_ name: String) -> Bool {
        AutoTuneSend.keyClass(name).map { $0.pitchClass == pitchClass && $0.minor == minor } ?? false
    }
}

extension Result {
    /// The reading as shown: the chosen key (if any) moved to the front, then every key name as
    /// Auto-Tune's Key menu spells it (J 2026-11-09), so readings saved before that rule match too.
    /// A chosen key the analyzer did not list (taught with "Wrong, it's X" or played on the
    /// keyboard) goes in front at 0 %, and the list keeps its length.
    func respelled(choice: KeyChoice? = SpellingSettings.shared.manualKey) -> Result {
        var ks = keys
        if let c = choice, c.matches(self) {
            if let i = ks.firstIndex(where: { AutoTuneSend.keyClass($0.0).map { $0.pitchClass == c.pitchClass && $0.minor == c.minor } ?? false }) {
                if i > 0 { ks.insert(ks.remove(at: i), at: 0) }
            } else {
                ks.insert((KeyChoice.keyName(c.pitchClass, minor: c.minor), 0), at: 0)
                ks = Array(ks.prefix(max(3, keys.count)))
            }
        }
        ks = ks.map { (KeyChoice.autoTuneName($0.0), $0.1) }
        return Result(file: file, name: name, bpm: bpm, keys: ks,
                      readError: readError, bpmExact: bpmExact, tuningCents: tuningCents, chroma: chroma)
    }
}

/// Manual Key Selection's one state (ManualKeySelection.swift sets and clears it). Key names
/// themselves have one rule and no setting: Auto-Tune's Key menu (KeyChoice.keyName; J's
/// rock-solid rule, 2026-11-09 16:15: "We go off of what Auto-Tune shows. That's it.").
final class SpellingSettings: ObservableObject {
    static let shared = SpellingSettings()

    /// Manual Key Selection: the key the user forced for the reading on show (a key wheel click,
    /// a top-3 click, the MANUAL menu, play-to-find on the keyboard). The one state every path
    /// sets and clears (ManualKeySelection.swift); nil = Beat Key's own detection.
    @Published var manualKey: KeyChoice?
}
