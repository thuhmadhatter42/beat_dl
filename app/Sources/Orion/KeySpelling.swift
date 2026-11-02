import Foundation

/// Enharmonic spelling of key names: Ebm <-> D#m, Gb <-> F#, ... A click on the big key flips
/// it; the choice is remembered. nil = the analyzer's own spelling (Eb, Bb, Ab, Db, F#, C#, G#).
enum KeySpelling: String {
    case sharps, flats

    var opposite: KeySpelling { self == .sharps ? .flats : .sharps }

    private static let sharpRoots = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flatRoots = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    /// The key name in this spelling ("Ebm" > "D#m"). Natural keys and non-keys come back as given.
    static func respell(_ name: String, to spelling: KeySpelling?) -> String {
        guard let spelling = spelling, let k = AutoTuneSend.keyClass(name), isBlack(name) else { return name }
        let roots = spelling == .sharps ? sharpRoots : flatRoots
        return roots[k.pitchClass] + (k.minor ? "m" : "")
    }

    /// A black-key tonic (the only ones that have two spellings).
    static func isBlack(_ name: String) -> Bool {
        guard let k = AutoTuneSend.keyClass(name) else { return false }
        return [1, 3, 6, 8, 10].contains(k.pitchClass)
    }

    /// What a click on this key name should switch to; nil = a natural key, nothing to switch.
    static func clickTarget(for name: String) -> KeySpelling? {
        guard isBlack(name) else { return nil }
        let t = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "♭", with: "b")
        return t.dropFirst().hasPrefix("b") ? .sharps : .flats
    }
}

extension Result {
    /// The same reading with every key name in `spelling` (nil = untouched).
    func respelled(_ spelling: KeySpelling?) -> Result {
        guard let spelling = spelling else { return self }
        return Result(file: file, name: name, bpm: bpm, keys: keys.map { (KeySpelling.respell($0.0, to: spelling), $0.1) },
                      readError: readError, bpmExact: bpmExact, tuningCents: tuningCents)
    }
}

/// The remembered choice (Reading > Spell Keys with Sharps, or a click on the key).
final class SpellingSettings: ObservableObject {
    static let key = "keySpelling"
    static let shared = SpellingSettings()
    private let defaults: UserDefaults

    @Published var preference: KeySpelling? {
        didSet {
            if let p = preference { defaults.set(p.rawValue, forKey: SpellingSettings.key) }
            else { defaults.removeObject(forKey: SpellingSettings.key) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preference = defaults.string(forKey: SpellingSettings.key).flatMap(KeySpelling.init(rawValue:))
    }

    /// A click on the key as shown (`name`): switch to the other spelling. False = natural key.
    @discardableResult
    func click(on name: String) -> Bool {
        guard let t = KeySpelling.clickTarget(for: name) else { return false }
        preference = t
        return true
    }

    /// The menu checkbox: on = sharps, off = flats.
    var sharps: Bool {
        get { preference == .sharps }
        set { preference = newValue ? .sharps : .flats }
    }
}
