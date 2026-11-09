import AppKit
import Foundation

// The menu-bar popover ("the pocket faceplate"): its logic, kept out of the views so it can be
// tested. The views are in PocketView.swift; the status item and popover in MenuBar.swift.

/// The notes of a key's scale for the 12-note keyboard: tonic pitch class (C = 0), the seven
/// pitch classes of the major / natural minor scale, and whether the key is spelled with sharps.
struct Scale: Equatable {
    let tonic: Int
    let minor: Bool
    let notes: Set<Int>
    let sharps: Bool
    /// The tonic as the key is written ("E♭", "D♯"); the scale line spells from it.
    let tonicName: String

    static let major = [0, 2, 4, 5, 7, 9, 11]
    static let naturalMinor = [0, 2, 3, 5, 7, 8, 10]
    static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
    static let letters = Array("CDEFGAB")
    private static let letterPC = [0, 2, 4, 5, 7, 9, 11]

    /// Pitch class `pc` written on letter `letter` (0 = C ... 6 = B), with the accidentals that
    /// takes: pc 3 on E = "E♭", pc 6 on E = "E♯", pc 5 on G = "G♭♭". The one speller for scales,
    /// chord roots and relative keys.
    static func spell(_ pc: Int, letter: Int) -> String {
        let li = ((letter % 7) + 7) % 7
        var diff = (((pc - letterPC[li]) % 12) + 12) % 12
        if diff > 6 { diff -= 12 }
        let acc = diff > 0 ? String(repeating: "♯", count: diff) : String(repeating: "♭", count: -diff)
        return String(letters[li]) + acc
    }

    /// The tonic's letter (0 = C ... 6 = B).
    var tonicLetter: Int { tonicName.first.flatMap { Scale.letters.firstIndex(of: $0) } ?? 0 }

    /// "Ebm", "F#", "Bb" → its scale; nil = not a key name.
    static func of(_ key: String) -> Scale? {
        guard let k = AutoTuneSend.keyClass(key) else { return nil }
        let steps = k.minor ? naturalMinor : major
        let t = key.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
        let root = t.hasSuffix("m") ? String(t.dropLast()) : t
        let sharps = root.contains("#") ? true : root.contains("b") ? false : (MidiExport.keySignature(key)?.sharps ?? 0) > 0
        return Scale(tonic: k.pitchClass, minor: k.minor,
                     notes: Set(steps.map { ($0 + k.pitchClass) % 12 }), sharps: sharps,
                     tonicName: root.replacingOccurrences(of: "#", with: "♯").replacingOccurrences(of: "b", with: "♭"))
    }

    /// The name of pitch class `pc` as this key spells it (for the keyboard's black keys).
    func name(_ pc: Int) -> String { (sharps ? Scale.sharpNames : Scale.flatNames)[((pc % 12) + 12) % 12] }

    /// The scale's notes from the tonic up, one letter per degree, so the spelling is the written
    /// one: E♭ minor is E♭ F G♭ A♭ B♭ C♭ D♭, D♯ minor is D♯ E♯ F♯ G♯ A♯ B C♯ (double accidentals
    /// where the key needs them, as in G♯ major's F♯♯).
    var spelled: [String] {
        let steps = minor ? Scale.naturalMinor : Scale.major
        return steps.enumerated().map { i, step in Scale.spell((tonic + step) % 12, letter: tonicLetter + i) }
    }
}

/// The input meter: a peak sample (0...1 linear) on a -54...0 dB scale, as 0...1.
enum LevelMeter {
    static let floorDB: Float = -54

    static func scale(_ peak: Float) -> Float {
        guard peak > 0 else { return 0 }
        let db = 20 * log10(min(peak, 1))
        return max(0, min(1, (db - floorDB) / -floorDB))
    }

    /// How many of `count` segments are lit for `level`.
    static func lit(_ level: Float, count: Int) -> Int {
        Int((max(0, min(1, level)) * Float(count)).rounded())
    }
}

/// The clipboard holds a link to download: an http(s) URL on its own (whitespace trimmed).
enum Clipboard {
    static func link(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
              !t.contains(where: { $0.isWhitespace }),
              let u = URL(string: t), let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https", u.host != nil else { return nil }
        return t
    }

    static func currentLink(_ pb: NSPasteboard = .general) -> String? { link(pb.string(forType: .string)) }
}

/// Everything the popover draws, as plain values (so it can be rendered offscreen and tested).
struct PocketState {
    var readout: Readout = .idle
    /// Listen is on (listening, reading or locked).
    var listening = false
    /// "System Audio", "Scarlett 4i4 · Ch 3".
    var source = "System Audio"
    var level: Float = 0
    var url = ""
    /// A download or an analysis is running (the caps go dark).
    var busy = false
    /// The YouTube link waiting needs a login (the window's LOG IN cap takes over).
    var needsLogin = false
    /// The clipboard holds a link (PASTE + GO lights).
    var clipboardLink: String? = nil
    /// The DAW Send to DAW would go to; nil = none open.
    var daw: String? = nil
    var recents: [Reading] = []
    var highContrast = false
    /// New Song's global shortcut as printed ("⌃⌥⌘R"); nil = none set.
    var newSongKeys: String? = nil
    /// Hold is on: the reading is frozen (a button, never automatic).
    var held = false
    /// Hold's global shortcut as printed; nil = none set.
    var holdKeys: String? = nil
    /// Advanced mode of the surface drawn: the window's harmony column, or the pocket's harmony
    /// pieces (PocketContainer puts the pocket's own setting in).
    var advanced = false
    /// Advanced mode's chord and MATCH TO choices.
    var harmony = HarmonyPrefs()
    /// Beat Key Mini's panel is open (the MINI chip lights).
    var miniOpen = false
    /// Help mode: hovering a control explains it (HelpSettings; the HELP chip lights).
    var help = false
    /// Manual Key Selection on the reading shown (it is `result`'s first key); nil = detection.
    var manualKey: ManualKey? = nil
    /// A click on the key's name switches sharp / flat; nil = no action wired.
    var canRespell: Bool { result?.keys.first.map { KeySpelling.isBlack($0.0) } ?? false }

    /// The reading on the readout, if there is one.
    var result: Result? {
        if case .result(let r, _, _, _, _) = readout { return r }
        return nil
    }
    var options: ResultOptions? {
        if case .result(_, _, _, _, let o) = readout { return o }
        return nil
    }

    /// DOWNLOAD lights for a link while nothing runs (the window's rule).
    var downloadLit: Bool { Faceplate.isLit(url, busy: busy) && !needsLogin }
    /// The field is empty and the clipboard holds a link: DOWNLOAD lights and takes that link.
    var clipboardReady: Bool {
        !busy && !needsLogin && clipboardLink != nil && url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// A reading with a tempo or a key: the send / export caps light.
    /// Hold has a reading to freeze (or is on and can be released).
    var canHold: Bool { listening && (held || result != nil) }
    var canSend: Bool { result.map { $0.bpm != nil || !$0.keys.isEmpty } ?? false }
    var canAutoTune: Bool { result?.keys.first.flatMap { AutoTuneSend.keyClass($0.0) } != nil }

    /// The lamp beside the hero key: Listen's own choice, else the key's confidence.
    var lamp: Lamp? {
        guard let r = result else {
            if case .listening = readout { return .listening }
            if case .working = readout { return .listening }
            return nil
        }
        return options?.live?.lamp ?? Lamp.of(r.keys)
    }

    /// The top key's confidence as 0...1 for the ring (nil = no key).
    var confidence: Double? { result?.keys.first.map { Double(max(0, min(100, $0.1))) / 100 } }

    var scale: Scale? { result?.keys.first.flatMap { Scale.of($0.0) } }

    /// The lamp's word: LOCKED / UNSURE / LISTENING.
    var lampWord: String? {
        guard let l = lamp else { return nil }
        return (held ? "HELD · " : "") + l.spoken.uppercased()
    }
}

extension PocketState {
    /// The reading the popover acts on (send, export, Auto-Tune): Listen's while it is on, else
    /// the finished download or the file paged to (what the readout shows).
    static func shown(_ state: ViewState, live: LiveState, page: Pager,
                      spelling: KeySpelling? = SpellingSettings.shared.preference) -> Result? {
        if live.isActive, let r = live.result { return r.respelled(spelling) }
        switch state {
        case .done(let r): return r.respelled(spelling)
        case .analyzed(let rs) where !rs.isEmpty: return rs[min(max(page.index, 0), rs.count - 1)].respelled(spelling)
        default: return nil
        }
    }
}
