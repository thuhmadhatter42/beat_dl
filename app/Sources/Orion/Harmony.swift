import Foundation

// Advanced mode's music logic (docs/plans/orra-parity.md §2): the Camelot code, the chord strip
// (diatonic + borrowed chords, triads / 7ths / 9ths, four voicings), the MATCH TO transpose
// shift and the chord's MIDI clip. Pure, so it can be tested; the views are in HarmonyView.swift.

/// The DJ wheel's code: 1...12 round the circle of fifths, A = minor, B = major. C = 8B, Am = 8A.
enum Camelot {
    /// "8B" for C major, "5A" for C minor.
    static func code(pitchClass pc: Int, minor: Bool) -> String {
        // a minor key shares its relative major's number
        let majorPC = minor ? (pc + 3) % 12 : ((pc % 12) + 12) % 12
        let n = (majorPC * 7 % 12 + 7) % 12 + 1
        return "\(n)\(minor ? "A" : "B")"
    }

    /// The code for a key name as shown ("Ebm" → "2A"); nil = not a key name.
    static func code(_ key: String) -> String? {
        guard let k = AutoTuneSend.keyClass(key) else { return nil }
        return code(pitchClass: k.pitchClass, minor: k.minor)
    }

    /// The relative key, spelled from the key's own letters: Ebm → "Gb", D#m → "F#", C → "Am".
    static func relative(_ key: String) -> String? {
        guard let s = Scale.of(key) else { return nil }
        // relative major = the minor scale's 3rd degree; relative minor = the major scale's 6th
        let degree = s.minor ? 2 : 5
        let pc = (s.tonic + (s.minor ? Scale.naturalMinor : Scale.major)[degree]) % 12
        let name = Scale.spell(pc, letter: s.tonicLetter + degree)
            .replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
        return name + (s.minor ? "" : "m")
    }
}

/// A key as the wheel holds it: pitch class 0...11 and major / minor.
struct WheelKey: Hashable {
    let pc: Int
    let minor: Bool
    init(_ pc: Int, minor: Bool) { self.pc = ((pc % 12) + 12) % 12; self.minor = minor }
}

/// The keys that fit a pick (J 2026-11-09, design pass): its two neighbours on the circle of
/// fifths (same ring, a fifth up and down: one note apart) and its relative (other ring, the same
/// seven notes). The key wheel outlines them faintly.
enum KeyFit {
    static func keys(_ k: WheelKey) -> Set<WheelKey> {
        let relative = k.minor ? WheelKey(k.pc + 3, minor: false) : WheelKey(k.pc + 9, minor: true)
        return [WheelKey(k.pc + 7, minor: k.minor), WheelKey(k.pc + 5, minor: k.minor), relative]
    }

    /// The fits for a key name as shown ("Cm"); empty = not a key name.
    static func keys(_ name: String) -> Set<WheelKey> {
        guard let c = AutoTuneSend.keyClass(name) else { return [] }
        return keys(WheelKey(c.pitchClass, minor: c.minor))
    }
}

/// How many notes each chord stacks.
enum ChordQuality: String, CaseIterable {
    case triad, seventh, ninth
    var size: Int { self == .triad ? 3 : self == .seventh ? 4 : 5 }
    var label: String { self == .triad ? "TRIAD" : self == .seventh ? "7TH" : "9TH" }
    var spoken: String { self == .triad ? "triads" : self == .seventh ? "sevenths" : "ninths" }
}

/// Which chord tone is in the bass, or the open spread.
enum Voicing: String, CaseIterable {
    case root, first, second, open
    var label: String {
        switch self {
        case .root: return "ROOT"
        case .first: return "1ST"
        case .second: return "2ND"
        case .open: return "OPEN"
        }
    }
    var spoken: String {
        switch self {
        case .root: return "root position"
        case .first: return "first inversion"
        case .second: return "second inversion"
        case .open: return "open voicing"
        }
    }
}

/// One chord of the strip.
struct Chord: Equatable {
    /// The root's pitch class (C = 0).
    let root: Int
    /// Semitones above the root, ascending (C maj7 = 0 4 7 11; a 9th is 13 or 14).
    let intervals: [Int]
    /// "Cm7", "E♭maj7", "B♭7(♭9)".
    let name: String
    /// "i", "♭VII", "ii°": the degree in the detected key.
    let roman: String
    /// Borrowed from the parallel key (or the Neapolitan), not in the key's own scale.
    let borrowed: Bool

    /// The bass octave's C: roots sit in C3...B3 (MIDI 48...59).
    static let baseC = 48

    /// MIDI notes, low to high. Inversions lift the bottom tone an octave once (1st) or twice
    /// (2nd), so the 3rd or the 5th is in the bass; open lifts the 3rd an octave (C: C G E, the
    /// spread piano voicing).
    func notes(_ v: Voicing) -> [Int] {
        var n = intervals.map { Chord.baseC + root + $0 }
        switch v {
        case .root: break
        case .first, .second:
            for _ in 0..<(v == .first ? 1 : 2) { n.append(n.removeFirst() + 12) }
        case .open:
            if n.count > 1 { n[1] += 12 }
        }
        return n.sorted()   // a ninth's lifted root lands among its upper tones
    }

    /// The chord name in plain ASCII ("Ebmaj7", "Bb7(b9)"), for file names.
    var asciiName: String {
        name.replacingOccurrences(of: "♭", with: "b").replacingOccurrences(of: "♯", with: "#")
    }
}

enum Harmony {
    static let phrygian = [0, 1, 3, 5, 7, 8, 10]
    private static let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]

    /// The seven chords built on the key's own scale, I to VII.
    static func diatonic(_ key: String, quality: ChordQuality) -> [Chord] {
        guard let s = Scale.of(key) else { return [] }
        let steps = s.minor ? Scale.naturalMinor : Scale.major
        return (0..<7).map { chord(in: s, steps: steps, degree: $0, quality: quality, borrowed: false) }
    }

    /// The four colour chords borrowed from outside the key (plan §2.3, the choice documented):
    /// a major key takes ♭III, iv, ♭VI and ♭VII from its parallel minor (the four standard
    /// modal-mixture chords of pop and film writing). A minor key takes I (the Picardy third),
    /// IV and V from its parallel major (dorian IV, the harmonic-minor dominant), and ♭II, the
    /// Neapolitan (from Phrygian), the fourth colour chord minor-key writers reach for.
    static func borrowed(_ key: String, quality: ChordQuality) -> [Chord] {
        guard let s = Scale.of(key) else { return [] }
        return borrowedPicks(minor: s.minor).map {
            chord(in: s, steps: $0.steps, degree: $0.degree, quality: quality, borrowed: true)
        }
    }

    private static func borrowedPicks(minor: Bool) -> [(steps: [Int], degree: Int)] {
        minor
            ? [(Scale.major, 0), (Scale.major, 3), (Scale.major, 4), (phrygian, 1)]
            : [(Scale.naturalMinor, 2), (Scale.naturalMinor, 3), (Scale.naturalMinor, 5), (Scale.naturalMinor, 6)]
    }

    /// The chord grid's second row (J 2026-11-09, design audit F10): seven columns like the
    /// diatonic row, each borrowed chord under the degree it stands in for (C minor: I under i,
    /// ♭II under ii°, IV under iv, V under v), the other columns empty (nil). Empty for no key.
    static func borrowedRow(_ key: String, quality: ChordQuality) -> [Chord?] {
        guard let s = Scale.of(key) else { return [] }
        var row = [Chord?](repeating: nil, count: 7)
        for (c, pick) in zip(borrowed(key, quality: quality), borrowedPicks(minor: s.minor)) { row[pick.degree] = c }
        return row
    }

    /// The borrowed chords left to right as the grid shows them, with their column (0...6).
    static func borrowedByColumn(_ key: String, quality: ChordQuality) -> [(column: Int, chord: Chord)] {
        borrowedRow(key, quality: quality).enumerated().compactMap { i, c in c.map { (i, $0) } }
    }

    /// The chord on `degree` of `steps` (a 7-note scale on the key's tonic), stacked in thirds
    /// within that scale: triad 1 3 5, seventh + 7, ninth + 9.
    static func chord(in key: Scale, steps: [Int], degree: Int, quality: ChordQuality, borrowed: Bool) -> Chord {
        let intervals = (0..<quality.size).map { k -> Int in
            let i = degree + 2 * k
            return steps[i % 7] + 12 * (i / 7) - steps[degree]
        }
        let root = (key.tonic + steps[degree]) % 12
        let rootName = Scale.spell(root, letter: key.tonicLetter + degree)
        // the numeral's accidental against the key's own scale (diatonic chords have none)
        let own = key.minor ? Scale.naturalMinor : Scale.major
        var off = ((steps[degree] - own[degree]) % 12 + 12) % 12
        if off > 6 { off -= 12 }
        let acc = off < 0 ? "♭" : off > 0 ? "♯" : ""
        let third = intervals[1], fifth = intervals[2]
        var numeral = numerals[degree]
        if third == 3 { numeral = numeral.lowercased() }
        if third == 3 && fifth == 6 { numeral += "°" }
        if third == 4 && fifth == 8 { numeral += "+" }
        return Chord(root: root, intervals: intervals, name: rootName + suffix(intervals),
                     roman: acc + numeral, borrowed: borrowed)
    }

    /// The chord symbol after the root, from its intervals.
    static func suffix(_ iv: [Int]) -> String {
        let third = iv[1], fifth = iv[2]
        let triad: String
        switch (third, fifth) {
        case (4, 7): triad = ""
        case (3, 7): triad = "m"
        case (3, 6): triad = "dim"
        case (4, 8): triad = "aug"
        default: triad = "?"
        }
        guard iv.count >= 4 else { return triad }
        let seventh: String
        switch (third, fifth, iv[3]) {
        case (4, 7, 11): seventh = "maj7"
        case (4, 7, 10): seventh = "7"
        case (3, 7, 10): seventh = "m7"
        case (3, 6, 10): seventh = "m7♭5"
        case (3, 6, 9): seventh = "dim7"
        case (3, 7, 11): seventh = "m(maj7)"
        case (4, 8, 11): seventh = "maj7♯5"
        case (4, 8, 10): seventh = "7♯5"
        default: seventh = triad + "7"
        }
        guard iv.count >= 5 else { return seventh }
        switch iv[4] {
        case 14:   // a major 9th: the 7 becomes a 9 (maj9, 9, m9, m9♭5)
            return seventh.replacingOccurrences(of: "7", with: "9")
        case 13:
            return seventh + "(♭9)"
        default:
            return seventh + "(♯9)"
        }
    }
}

/// MATCH TO: how far to pitch the beat so its key lands on the project's key.
enum Transpose {
    /// Semitones (-5...+6) that move `from` onto `to`. A relative major / minor counts as a
    /// match: Cm onto Eb is 0. nil = a name that is not a key.
    static func shift(from: String, to: String) -> Int? {
        guard let a = AutoTuneSend.keyClass(from), let b = AutoTuneSend.keyClass(to) else { return nil }
        // compare in the target's mode: the detected key, or its relative
        var pc = a.pitchClass
        if a.minor != b.minor { pc = a.minor ? (pc + 3) % 12 : (pc + 9) % 12 }
        var s = ((b.pitchClass - pc) % 12 + 12) % 12
        if s > 6 { s -= 12 }
        return s
    }

    /// The row's cells.
    static let range = -6...6

    /// Whether the row's cell `cell` is the shift (a tritone lights both ends, -6 and +6).
    static func lit(_ cell: Int, shift: Int?) -> Bool {
        guard let s = shift else { return false }
        return ((cell - s) % 12 + 12) % 12 == 0
    }

    /// "+3", "−2", "0".
    static func label(_ n: Int) -> String { n > 0 ? "+\(n)" : n < 0 ? "−\(-n)" : "0" }
}

/// A chord as a MIDI clip: the reading's tempo, the chord held for 1, 2 or 4 bars of 4/4.
enum ChordClip {
    static let barChoices = [1, 2, 4]
    /// A click plays the chord this long at most, so a 4-bar slow chord does not drone.
    static let maxHearSeconds = 6.0
    static let velocity: UInt8 = 96

    static func ticks(bars: Int) -> UInt32 { UInt32(max(1, bars) * 4) * UInt32(MidiExport.ticksPerQuarter) }

    /// The tempo the clip and the click use: the BPM on show (with its ×2 / ×0.5), else 120.
    static func bpm(_ r: Result?, factor: TempoFactor) -> Double {
        if let r, let v = Tempo.text(r, factor: factor).flatMap(Double.init), (1...1000).contains(v) { return v }
        return 120
    }

    /// How long a click sounds: the clip's length at `bpm`, at most maxHearSeconds.
    static func hearSeconds(bars: Int, bpm: Double) -> Double {
        min(maxHearSeconds, Double(max(1, bars) * 4) * 60 / max(1, bpm))
    }

    /// The .mid bytes (MidiExport's one writer): tempo, 4/4, the key, the chord held `bars`.
    static func data(_ chord: Chord, voicing: Voicing, bars: Int, bpm: Double, key: String?) -> Data {
        MidiExport.data(bpm: bpm, key: key, trackName: chord.asciiName,
                        notes: chord.notes(voicing), noteTicks: ticks(bars: bars), velocity: velocity)
    }

    /// "Cm7 root 2 bars 140 BPM.mid" (ASCII: every DAW takes it).
    static func fileName(_ chord: Chord, voicing: Voicing, bars: Int, bpm: Double) -> String {
        let b = bpm == bpm.rounded() ? String(Int(bpm)) : String(format: "%.2f", bpm)
        return "\(chord.asciiName) \(voicing.rawValue) \(bars) bar\(bars == 1 ? "" : "s") \(b) BPM.mid"
    }

    /// Where dragged clips are written (the system temp folder; macOS clears it).
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Beat Key Chords", isDirectory: true)
    }

    /// Writes the clip for a drag; nil (and a log line) when it could not be written.
    static func write(_ chord: Chord, voicing: Voicing, bars: Int, bpm: Double, key: String?,
                      in dir: URL = ChordClip.directory) -> URL? {
        let url = dir.appendingPathComponent(fileName(chord, voicing: voicing, bars: bars, bpm: bpm))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data(chord, voicing: voicing, bars: bars, bpm: bpm, key: key).write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.log("chord clip: could not write \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
}
