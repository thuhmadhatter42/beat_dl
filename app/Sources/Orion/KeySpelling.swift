import Combine
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

/// One of the top 3 keys the user clicked to make it THE key (shown big, sent to Auto-Tune, the
/// DAW and the MIDI file) for one reading. Matched by the reading's file + name, so the next file
/// or song shows the analyzer's own order again.
struct KeyChoice: Equatable {
    let file: URL
    let name: String
    let pitchClass: Int
    let minor: Bool
}

extension Result {
    /// The reading as shown: the chosen key (if any, and still in the list) moved to the front,
    /// then every key name in `spelling` (nil = untouched).
    func respelled(_ spelling: KeySpelling?, choice: KeyChoice? = SpellingSettings.shared.chosen) -> Result {
        var ks = keys
        if let c = choice, c.file == file, c.name == name,
           let i = ks.firstIndex(where: { AutoTuneSend.keyClass($0.0).map { $0.pitchClass == c.pitchClass && $0.minor == c.minor } ?? false }),
           i > 0 {
            ks.insert(ks.remove(at: i), at: 0)
        }
        if let spelling = spelling { ks = ks.map { (KeySpelling.respell($0.0, to: spelling), $0.1) } }
        return Result(file: file, name: name, bpm: bpm, keys: ks,
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

    /// The key clicked in the top 3 for the reading on show; nil = the analyzer's order.
    @Published var chosen: KeyChoice?

    /// Fires on a spelling change or a key choice (both change what every readout shows).
    var changes: AnyPublisher<KeySpelling?, Never> {
        $preference.combineLatest($chosen).map { $0.0 }.eraseToAnyPublisher()
    }

    /// A click on one of the top 3 (`key` as shown) of `result`: it becomes the key.
    func choose(_ key: String, of result: Result) {
        guard let k = AutoTuneSend.keyClass(key) else { return }
        chosen = KeyChoice(file: result.file, name: result.name, pitchClass: k.pitchClass, minor: k.minor)
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
