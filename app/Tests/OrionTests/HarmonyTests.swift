import AppKit
import AVFoundation
import AudioToolbox
import SwiftUI
import XCTest
@testable import Orion

/// Advanced mode (orra-parity §2.7): Camelot, chord spelling per key / quality / voicing, the
/// borrowed set, MATCH TO, the chord's MIDI clip, and the analyzer's chroma / tuning fields.
final class HarmonyTests: XCTestCase {
    func defaults() -> UserDefaults {
        let name = "orion-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    // MARK: Camelot

    func testCamelotAll24Keys() {
        let majors = ["C": "8B", "G": "9B", "D": "10B", "A": "11B", "E": "12B", "B": "1B", "F#": "2B",
                      "Db": "3B", "Ab": "4B", "Eb": "5B", "Bb": "6B", "F": "7B"]
        let minors = ["Am": "8A", "Em": "9A", "Bm": "10A", "F#m": "11A", "C#m": "12A", "G#m": "1A",
                      "Ebm": "2A", "Bbm": "3A", "Fm": "4A", "Cm": "5A", "Gm": "6A", "Dm": "7A"]
        for (k, c) in majors.merging(minors, uniquingKeysWith: { a, _ in a }) {
            XCTAssertEqual(Camelot.code(k), c, k)
        }
        XCTAssertEqual(Set(KeyChoice.allKeys.compactMap { Camelot.code($0) }).count, 24)
        // the other spelling of a black key is the same slot
        XCTAssertEqual(Camelot.code("D#m"), "2A")
        XCTAssertEqual(Camelot.code("Gb"), "2B")
        XCTAssertNil(Camelot.code("nope"))
    }

    func testRelativeKeyKeepsTheKeysSpelling() {
        XCTAssertEqual(Camelot.relative("C"), "Am")
        XCTAssertEqual(Camelot.relative("Am"), "C")
        XCTAssertEqual(Camelot.relative("Ebm"), "Gb")
        XCTAssertEqual(Camelot.relative("D#m"), "F#")
        XCTAssertEqual(Camelot.relative("F#"), "D#m")
        XCTAssertEqual(Camelot.relative("Gb"), "Ebm")
        XCTAssertEqual(Camelot.relative("Cm"), "Eb")
    }

    // MARK: chords

    func testDiatonicTriadsMajorAndMinor() {
        let c = Harmony.diatonic("C", quality: .triad)
        XCTAssertEqual(c.map(\.name), ["C", "Dm", "Em", "F", "G", "Am", "Bdim"])
        XCTAssertEqual(c.map(\.roman), ["I", "ii", "iii", "IV", "V", "vi", "vii°"])
        XCTAssertFalse(c.contains { $0.borrowed })
        let cm = Harmony.diatonic("Cm", quality: .triad)
        XCTAssertEqual(cm.map(\.name), ["Cm", "Ddim", "E♭", "Fm", "Gm", "A♭", "B♭"])
        XCTAssertEqual(cm.map(\.roman), ["i", "ii°", "III", "iv", "v", "VI", "VII"])
    }

    func testSeventhsAndNinths() {
        XCTAssertEqual(Harmony.diatonic("C", quality: .seventh).map(\.name),
                       ["Cmaj7", "Dm7", "Em7", "Fmaj7", "G7", "Am7", "Bm7♭5"])
        XCTAssertEqual(Harmony.diatonic("C", quality: .ninth).map(\.name),
                       ["Cmaj9", "Dm9", "Em7(♭9)", "Fmaj9", "G9", "Am9", "Bm7♭5(♭9)"])
        XCTAssertEqual(Harmony.diatonic("Am", quality: .seventh).map(\.name),
                       ["Am7", "Bm7♭5", "Cmaj7", "Dm7", "Em7", "Fmaj7", "G7"])
        XCTAssertEqual(Harmony.diatonic("C", quality: .ninth)[0].intervals, [0, 4, 7, 11, 14])
    }

    func testChordRootsSpelledFromTheKey() {
        XCTAssertEqual(Harmony.diatonic("Ebm", quality: .triad).map(\.name),
                       ["E♭m", "Fdim", "G♭", "A♭m", "B♭m", "C♭", "D♭"])
        XCTAssertEqual(Harmony.diatonic("D#m", quality: .triad).map(\.name),
                       ["D♯m", "E♯dim", "F♯", "G♯m", "A♯m", "B", "C♯"])
        XCTAssertEqual(Harmony.diatonic("F#", quality: .triad).map(\.name),
                       ["F♯", "G♯m", "A♯m", "B", "C♯", "D♯m", "E♯dim"])
        XCTAssertTrue(Harmony.diatonic("H", quality: .triad).isEmpty)
    }

    func testBorrowedSet() {
        // major key: bIII iv bVI bVII from the parallel minor
        let b = Harmony.borrowed("C", quality: .triad)
        XCTAssertEqual(b.map(\.name), ["E♭", "Fm", "A♭", "B♭"])
        XCTAssertEqual(b.map(\.roman), ["♭III", "iv", "♭VI", "♭VII"])
        XCTAssertTrue(b.allSatisfy { $0.borrowed })
        XCTAssertEqual(Harmony.borrowed("C", quality: .seventh).map(\.name), ["E♭maj7", "Fm7", "A♭maj7", "B♭7"])
        // minor key: I IV V from the parallel major, bII the Neapolitan
        let m = Harmony.borrowed("Am", quality: .triad)
        XCTAssertEqual(m.map(\.name), ["A", "D", "E", "B♭"])
        XCTAssertEqual(m.map(\.roman), ["I", "IV", "V", "♭II"])
        XCTAssertEqual(Harmony.borrowed("Am", quality: .seventh).map(\.name), ["Amaj7", "Dmaj7", "E7", "B♭maj7"])
        XCTAssertEqual(Harmony.borrowed("A", quality: .triad).map(\.name), ["C", "Dm", "F", "G"])
    }

    func testVoicings() {
        let c = Harmony.diatonic("C", quality: .triad)[0]
        XCTAssertEqual(c.notes(.root), [48, 52, 55])
        XCTAssertEqual(c.notes(.first), [52, 55, 60])
        XCTAssertEqual(c.notes(.second), [55, 60, 64])
        XCTAssertEqual(c.notes(.open), [48, 55, 64])
        let g7 = Harmony.diatonic("C", quality: .seventh)[4]
        XCTAssertEqual(g7.notes(.root), [55, 59, 62, 65])
        XCTAssertEqual(g7.notes(.first), [59, 62, 65, 67])
        XCTAssertEqual(g7.notes(.open), [55, 62, 65, 71])
        for v in Voicing.allCases {
            let n = Harmony.diatonic("B", quality: .ninth)[6].notes(v)
            XCTAssertEqual(n, n.sorted(), "\(v) is low to high")
            XCTAssertTrue(n.allSatisfy { (0...127).contains($0) })
        }
    }

    // MARK: MATCH TO

    func testTransposeShift() {
        XCTAssertEqual(Transpose.shift(from: "Cm", to: "Eb"), 0)       // relative counts
        XCTAssertEqual(Transpose.shift(from: "Cm", to: "Cm"), 0)
        XCTAssertEqual(Transpose.shift(from: "Cm", to: "Am"), -3)
        XCTAssertEqual(Transpose.shift(from: "C", to: "D"), 2)
        XCTAssertEqual(Transpose.shift(from: "C", to: "Bm"), 2)        // C's relative Am up 2 = Bm
        XCTAssertEqual(Transpose.shift(from: "C", to: "F#"), 6)
        XCTAssertEqual(Transpose.shift(from: "D#m", to: "Ebm"), 0)
        XCTAssertEqual(Transpose.shift(from: "Am", to: "F#m"), -3)
        XCTAssertEqual(Transpose.shift(from: "F", to: "E"), -1)
        XCTAssertNil(Transpose.shift(from: "x", to: "C"))
        for a in KeyChoice.allKeys { for b in KeyChoice.allKeys {
            XCTAssertTrue((-5...6).contains(Transpose.shift(from: a, to: b)!))
        } }
        XCTAssertTrue(Transpose.lit(6, shift: 6))
        XCTAssertTrue(Transpose.lit(-6, shift: 6))
        XCTAssertTrue(Transpose.lit(-3, shift: -3))
        XCTAssertFalse(Transpose.lit(3, shift: -3))
        XCTAssertFalse(Transpose.lit(0, shift: nil))
        XCTAssertEqual(Transpose.label(-2), "−2")
        XCTAssertEqual(Transpose.label(3), "+3")
    }

    // MARK: the MIDI clip

    func testVarLen() {
        XCTAssertEqual(MidiExport.varLen(0), [0x00])
        XCTAssertEqual(MidiExport.varLen(127), [0x7F])
        XCTAssertEqual(MidiExport.varLen(128), [0x81, 0x00])
        XCTAssertEqual(MidiExport.varLen(3840), [0x9E, 0x00])
        XCTAssertEqual(MidiExport.varLen(0x0FFFFFFF), [0xFF, 0xFF, 0xFF, 0x7F])
    }

    func testChordClipBytes() {
        let c = Harmony.diatonic("C", quality: .triad)[0]
        let d = [UInt8](ChordClip.data(c, voicing: .root, bars: 2, bpm: 120, key: "C"))
        XCTAssertEqual(Array(d[0..<4]), Array("MThd".utf8))
        XCTAssertEqual(Array(d[12..<14]), [0x01, 0xE0])                     // 480 ticks a quarter
        XCTAssertEqual(Array(d[14..<18]), Array("MTrk".utf8))
        let len = Int(d[18]) << 24 | Int(d[19]) << 16 | Int(d[20]) << 8 | Int(d[21])
        let track = Array(d[22...])
        XCTAssertEqual(track.count, len)
        func find(_ seq: [UInt8]) -> Bool {
            guard track.count >= seq.count else { return false }
            return (0...(track.count - seq.count)).contains { Array(track[$0..<$0 + seq.count]) == seq }
        }
        XCTAssertTrue(find([0xFF, 0x03, 0x01, UInt8(ascii: "C")]))         // track name = the chord
        XCTAssertTrue(find([0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]))          // 120 BPM = 500000 µs
        XCTAssertTrue(find([0xFF, 0x58, 0x04, 4, 2, 24, 8]))               // 4/4
        XCTAssertTrue(find([0xFF, 0x59, 0x02, 0x00, 0x00]))                // C major
        // all three notes on at tick 0, all off together after 2 bars (3840 ticks)
        XCTAssertTrue(find([0x00, 0x90, 48, 96, 0x00, 0x90, 52, 96, 0x00, 0x90, 55, 96,
                            0x9E, 0x00, 0x80, 48, 0x00, 0x00, 0x80, 52, 0x00, 0x00, 0x80, 55, 0x00,
                            0x00, 0xFF, 0x2F, 0x00]))
        XCTAssertEqual(Array(track.suffix(3)), [0xFF, 0x2F, 0x00])
        // 4 bars of the first inversion
        let four = [UInt8](ChordClip.data(c, voicing: .first, bars: 4, bpm: 90, key: nil))
        XCTAssertTrue(four.count > 22)
        XCTAssertEqual(ChordClip.ticks(bars: 4), 7680)
        XCTAssertEqual(MidiExport.varLen(ChordClip.ticks(bars: 1)), [0x8F, 0x00])
    }

    func testTempoKeyFileUnchangedWithoutNotes() {
        // the Export MIDI Tempo/Key file still carries no notes
        let d = [UInt8](MidiExport.data(bpm: 120, key: "Cm"))
        XCTAssertFalse(d.contains(0x90))
    }

    func testChordClipFileAndTempo() throws {
        let c = Harmony.diatonic("Eb", quality: .seventh)[0]
        XCTAssertEqual(c.asciiName, "Ebmaj7")
        XCTAssertEqual(ChordClip.fileName(c, voicing: .open, bars: 2, bpm: 140), "Ebmaj7 open 2 bars 140 BPM.mid")
        XCTAssertEqual(ChordClip.fileName(c, voicing: .root, bars: 1, bpm: 92.97), "Ebmaj7 root 1 bar 92.97 BPM.mid")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("orion-test-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = try XCTUnwrap(ChordClip.write(c, voicing: .open, bars: 2, bpm: 140, key: "Eb", in: dir))
        XCTAssertEqual(try Data(contentsOf: url), ChordClip.data(c, voicing: .open, bars: 2, bpm: 140, key: "Eb"))
        // the clip's tempo is the BPM on show, with its x2 / x0.5
        let r = Result(file: URL(fileURLWithPath: "/x/a.wav"), name: "a.wav", bpm: "70.0", keys: [("Eb", 80)], bpmExact: 70.0)
        XCTAssertEqual(ChordClip.bpm(r, factor: .one), 70)
        XCTAssertEqual(ChordClip.bpm(r, factor: .double), 140)
        XCTAssertEqual(ChordClip.bpm(nil, factor: .one), 120)
        XCTAssertEqual(ChordClip.hearSeconds(bars: 1, bpm: 120), 2, accuracy: 1e-9)
        XCTAssertEqual(ChordClip.hearSeconds(bars: 4, bpm: 70), ChordClip.maxHearSeconds)
    }

    // MARK: the analyzer's chroma and tuning

    func testParseChromaAndTuningFromAFile() {
        let line = #"{"stage":"analyzed","file":"/x/a.wav","name":"a.wav","bpm":"90.0","keys":[["Am",80]],"tuning_cents":14.5,"chroma":[0.1,0,0.2,0,0.5,0.1,0,0.3,0,1,0,0.2]}"#
        guard case .analyzed(let r)? = Event.parse(line: line) else { return XCTFail("not analyzed") }
        XCTAssertEqual(r.tuningCents, 14.5)
        XCTAssertEqual(r.chroma?.count, 12)
        XCTAssertEqual(r.chroma?[9], 1)
    }

    func testStreamReadingFieldsShareTheParser() throws {
        // bpm.py --stream's reading line, through the parser LiveEvent.parse uses
        let line = #"{"event":"reading","bpm":"128.0","bpm_exact":128.02,"keys":[["F#m",77]],"tuning_cents":-30.0,"chroma":[0,1,0,0,0.2,0,0.9,0,0.1,0.6,0,0]}"#
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let r = try XCTUnwrap(Event.reading(obj, file: LiveSession.placeholderFile, name: "LIVE"))
        XCTAssertEqual(r.tuningCents, -30)
        XCTAssertEqual(r.bpmExact, 128.02)
        XCTAssertEqual(r.chroma?[6], 0.9)
        XCTAssertEqual(r.keys.first?.0, "F#m")
    }

    func testChromaMissingOrMalformedKeepsTheReading() {
        for c in ["", #","chroma":null"#, #","chroma":[1,2,3]"#, #","chroma":[0,0,0,0,0,0,0,0,0,0,0,"x"]"#] {
            let line = #"{"stage":"analyzed","file":"/x/a.wav","name":"a.wav","bpm":"90.0","keys":[["Am",80]]"# + c + "}"
            guard case .analyzed(let r)? = Event.parse(line: line) else { return XCTFail("dropped: \(c)") }
            XCTAssertNil(r.chroma, c)
            XCTAssertEqual(r.keys.count, 1)
        }
    }

    func testChromaSurvivesRespellAndRecents() throws {
        let ch = [1.0, 0, 0.5, 0, 0, 0.2, 0, 0.8, 0, 0, 0.1, 0]
        let r = Result(file: URL(fileURLWithPath: "/x/a.wav"), name: "a.wav", bpm: "90.0", keys: [("Ebm", 80)], chroma: ch)
        XCTAssertEqual(r.respelled(.sharps, choice: nil).chroma, ch)
        let saved = try JSONDecoder().decode(Reading.self, from: JSONEncoder().encode(Reading(r)))
        XCTAssertEqual(saved.result.chroma, ch)
        // a reading saved before chroma existed still loads
        let old = #"{"path":"/x/a.wav","name":"a.wav","bpm":"90.0","keys":[{"name":"Am","percent":80}],"date":0}"#
        XCTAssertNil(try JSONDecoder().decode(Reading.self, from: Data(old.utf8)).chroma)
    }

    func testNotesHeardLevels() {
        XCTAssertEqual(NotesHeard.levels([0.5, 0.25] + Array(repeating: 0, count: 10)).prefix(2), [1, 0.5])
        XCTAssertEqual(NotesHeard.levels(Array(repeating: 0, count: 12)), Array(repeating: 0, count: 12))
        XCTAssertEqual(NotesHeard.levels([-1, 2] + Array(repeating: 0, count: 10)).prefix(2), [0, 1])
    }

    // MARK: the wheel

    // J 2026-11-09 design pass: the wheel outlines the keys that fit the pick
    func testKeysThatFitAreTheFifthsNeighboursAndTheRelative() {
        // C major: G and F beside it, Am inside
        XCTAssertEqual(KeyFit.keys(WheelKey(0, minor: false)),
                       [WheelKey(7, minor: false), WheelKey(5, minor: false), WheelKey(9, minor: true)])
        // A minor: Em and Dm beside it, C outside
        XCTAssertEqual(KeyFit.keys(WheelKey(9, minor: true)),
                       [WheelKey(4, minor: true), WheelKey(2, minor: true), WheelKey(0, minor: false)])
        // by name, and wrapping round the circle: Cm → Gm, Fm, Eb; F# → C#, B, D#m
        XCTAssertEqual(KeyFit.keys("Cm"), [WheelKey(7, minor: true), WheelKey(5, minor: true), WheelKey(3, minor: false)])
        XCTAssertEqual(KeyFit.keys("F#"), [WheelKey(1, minor: false), WheelKey(11, minor: false), WheelKey(3, minor: true)])
        XCTAssertEqual(KeyFit.keys("Ebm"), KeyFit.keys("D#m"))
        XCTAssertEqual(KeyFit.keys("not a key"), [])
        XCTAssertEqual(WheelKey(-1, minor: false), WheelKey(11, minor: false))
        // every fit is next to the pick on the wheel: same slot (relative) or one slot either side
        for pc in 0..<12 {
            for minor in [false, true] {
                let fits = KeyFit.keys(WheelKey(pc, minor: minor))
                XCTAssertEqual(fits.count, 3)
                XCTAssertFalse(fits.contains(WheelKey(pc, minor: minor)))
                let slot = { (k: WheelKey) in (0..<12).first { KeyWheel.slot($0, minor: k.minor).pc == k.pc }! }
                let me = slot(WheelKey(pc, minor: minor))
                for f in fits {
                    let d = (slot(f) - me + 12) % 12
                    XCTAssertTrue(f.minor == minor ? (d == 1 || d == 11) : d == 0, "\(pc) \(minor) → \(f)")
                }
            }
        }
        // the wheel's own set follows the key on show
        XCTAssertEqual(KeyWheel(keys: [("Cm", 64), ("Eb", 18)]).fits, KeyFit.keys("Cm"))
        XCTAssertEqual(KeyWheel(keys: []).fits, [])
    }

    func testMatchToLineIsASentenceOrNothing() {
        XCTAssertEqual(MatchToRow.line(target: "Am", shift: -3), "Pitch the beat −3 to fit Am")
        XCTAssertEqual(MatchToRow.line(target: "F#m", shift: 2), "Pitch the beat +2 to fit F#m")
        XCTAssertEqual(MatchToRow.line(target: "Am", shift: 0), "Already fits Am")
        XCTAssertNil(MatchToRow.line(target: nil, shift: nil))     // the picker says PICK KEY
        XCTAssertNil(MatchToRow.line(target: "Am", shift: nil))    // no reading yet
    }

    func testWheelSlotsAndRanks() {
        XCTAssertTrue(KeyWheel.slot(0, minor: false) == (0, false))   // C at the top
        XCTAssertTrue(KeyWheel.slot(0, minor: true) == (9, true))     // Am inside it
        XCTAssertTrue(KeyWheel.slot(1, minor: false) == (7, false))   // G clockwise
        XCTAssertTrue(KeyWheel.slot(6, minor: true) == (3, true))     // D#m / Ebm opposite Am
        XCTAssertEqual(Set((0..<12).map { KeyWheel.slot($0, minor: false).pc }).count, 12)
        let w = KeyWheel(keys: [("Cm", 64), ("Eb", 18), ("Gm", 9)])
        XCTAssertEqual(w.rank(0, minor: true), 0)
        XCTAssertEqual(w.rank(3, minor: false), 1)
        XCTAssertEqual(w.rank(7, minor: true), 1)
        XCTAssertNil(w.rank(0, minor: false))
    }

    func testKeyWheelSectionUnderTheMouse() {
        let c = KeyWheel.side / 2
        XCTAssertNil(KeyWheel.section(at: CGPoint(x: c, y: c)))                                   // centre
        XCTAssertNil(KeyWheel.section(at: CGPoint(x: 0, y: 0)))                                   // corner, outside
        XCTAssertEqual(KeyWheel.section(at: CGPoint(x: c, y: c - 80)), 0)                         // C, top, outer
        XCTAssertEqual(KeyWheel.section(at: CGPoint(x: c, y: c - 48)), 1)                         // Am, top, inner
        XCTAssertEqual(KeyWheel.section(at: CGPoint(x: c + 80, y: c)), 6)                         // A, 3 o'clock = slot 3
        XCTAssertEqual(KeyWheel.section(at: CGPoint(x: c, y: c + 80)), 12)                        // F#, bottom = slot 6
        XCTAssertEqual(KeyWheel.section(at: CGPoint(x: c - 48, y: c)), 19)                        // Fm? slot 9 inner
    }

    func testKeyWheelHoverExplainsEachLitKey() {
        let w = KeyWheel(keys: [("Cm", 64), ("Eb", 18), ("Gm", 9)])
        let pick = w.info(0, minor: true)
        XCTAssertTrue(pick.title.hasSuffix("64% SURE"))
        XCTAssertTrue(pick.why.contains("pick"))
        let rel = w.info(3, minor: false)                       // Eb: relative major
        XCTAssertTrue(rel.title.hasSuffix("18% SURE"))
        XCTAssertTrue(rel.why.contains("relative major") && rel.why.contains("seven notes"))
        let nb = w.info(7, minor: true)                         // Gm: neighbour
        XCTAssertTrue(nb.why.contains("circle of fifths") && nb.why.contains("one note"))
        let par = w.info(0, minor: false)                       // C major: parallel, not in the reading
        XCTAssertFalse(par.title.contains("%"))
        XCTAssertTrue(par.why.contains("Same root"))
        XCTAssertTrue(w.info(6, minor: false).why.contains("clashes"))   // F#/Gb: far side
        XCTAssertTrue(KeyWheel(keys: []).info(0, minor: false).why.contains("Click"))
    }

    // MARK: the mode and its settings

    func testAdvancedModeAndChoicesAreRemembered() {
        let d = defaults()
        let s = DisplaySettings(defaults: d)
        XCTAssertFalse(s.advanced)                         // default = the minimal window
        XCTAssertEqual(HarmonyPrefs(s), HarmonyPrefs())
        s.advanced = true
        HarmonyPrefs(quality: .ninth, voicing: .open, bars: 4, matchKey: "F#m").apply(to: s)
        let again = DisplaySettings(defaults: d)
        XCTAssertTrue(again.advanced)
        XCTAssertEqual(HarmonyPrefs(again), HarmonyPrefs(quality: .ninth, voicing: .open, bars: 4, matchKey: "F#m"))
        again.chordBars = 3                                // not a choice: back to 1
        XCTAssertEqual(again.chordBars, 1)
        d.set("garbage", forKey: DisplaySettings.matchKeyKey)
        XCTAssertNil(DisplaySettings(defaults: d).matchKey)
    }

    func testAdvancedWindowIsWiderNotTaller() {
        let a = FaceplateView.size(advanced: true), b = FaceplateView.size(advanced: false)
        XCTAssertEqual(b, FaceplateView.size)
        XCTAssertEqual(b.width, 528)                       // J 2026-11-09: the left side 24 narrower
        XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.width, b.width + FaceplateView.columnGap + HarmonyPanel.width)
    }

    func testAdvancedShortcutIsFree() {
        // ⌥⌘A: not a global shortcut's default, not a play-to-find key (⇧⌘A is)
        let optCmd = Shortcut(keyCode: 0, modifiers: UInt32(2048 | 256), key: "A")
        XCTAssertFalse(HotkeyAction.allCases.contains { $0.defaultShortcut?.keyCode == optCmd.keyCode
            && $0.defaultShortcut?.modifiers == optCmd.modifiers })
        XCTAssertNil(MusicalTyping.action(keyCode: 0, modifiers: [.option, .command]))
    }

    // MARK: click to hear

    func testSystemPianoLoadsIntoTheSampler() throws {
        // the GM bank every Mac ships; loaded without starting an engine (no sound in tests)
        XCTAssertTrue(FileManager.default.fileExists(atPath: NoteSynth.bankURL.path))
        let e = AVAudioEngine()
        let s = AVAudioUnitSampler()
        e.attach(s)
        e.connect(s, to: e.mainMixerNode, format: nil)
        XCTAssertNoThrow(try s.loadSoundBankInstrument(at: NoteSynth.bankURL, program: 0,
                                                       bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                                       bankLSB: UInt8(kAUSampler_DefaultBankLSB)))
    }

    // MARK: offscreen renders (ORION_SNAPSHOT_DIR=<dir> swift test --filter HarmonyTests/testRender)

    @MainActor
    func testRenderBothModes() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORION_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ORION_SNAPSHOT_DIR to write the window PNGs")
        }
        guard #available(macOS 13.0, *) else { throw XCTSkip("ImageRenderer is macOS 13+") }
        Pocket.snapshot = true
        defer { Pocket.snapshot = false }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let r = Result(file: URL(fileURLWithPath: "/x/Beats/Beat A.wav"), name: "Beat A.wav", bpm: "142.0",
                       keys: [("Cm", 64), ("Eb", 18), ("Gm", 9)], bpmExact: 141.98, tuningCents: 12,
                       chroma: [1.0, 0.08, 0.42, 0.81, 0.06, 0.37, 0.1, 0.93, 0.62, 0.05, 0.48, 0.12])
        var s = PocketState()
        s.source = "System Audio"
        s.daw = "Pro Tools"
        s.readout = .result(r, page: nil, download: false, options: ResultOptions(
            factor: .one, tuning: Tuning.meter(12, reference: 440), onCycleTempo: {}))
        var adv = s
        adv.advanced = true
        adv.harmony = HarmonyPrefs(quality: .seventh, voicing: .root, bars: 2, matchKey: "Am")
        var noChroma = adv
        noChroma.readout = .result(Result(file: r.file, name: r.name, bpm: r.bpm, keys: r.keys, bpmExact: 141.98),
                                   page: nil, download: false, options: ResultOptions())
        var empty = PocketState()
        empty.advanced = true
        for (name, st) in [("default", s), ("advanced", adv), ("advanced-no-chroma", noChroma), ("advanced-idle", empty)] {
            let view = FaceplateFace(state: st, picked: [], url: .constant(""), fieldFocused: .constant(false),
                                     pickFocused: .constant(false))
                .environment(\.colorScheme, .dark)
            let rr = ImageRenderer(content: view)
            rr.scale = 2
            guard let cg = rr.cgImage else { return XCTFail("no image for \(name)") }
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
            try png.write(to: out.appendingPathComponent("render-\(name).png"))
        }
    }
}
