import XCTest
@testable import Orion

final class KeyChoiceTests: XCTestCase {
    let r = Result(file: URL(fileURLWithPath: "/tmp/beat.mp3"), name: "beat", bpm: "140",
                   keys: [("Fm", 60), ("Ab", 25), ("Cm", 10)])

    func testChosenKeyMovesToFront() {
        let c = KeyChoice(file: r.file, name: r.name, pitchClass: 8, minor: false)
        let s = r.respelled(choice: c)
        XCTAssertEqual(s.keys.map { $0.0 }, ["Ab", "Fm", "Cm"])
        XCTAssertEqual(s.keys.map { $0.1 }, [25, 60, 10])            // percentages travel with the key
    }

    func testChoiceForAnotherReadingIsIgnored() {
        let c = KeyChoice(file: URL(fileURLWithPath: "/tmp/other.mp3"), name: "other", pitchClass: 8, minor: false)
        XCTAssertEqual(r.respelled(choice: c).keys.first?.0, "Fm")
    }

    func testChoiceOutsideTopThreeGoesFirstAtZero() {
        let c = KeyChoice(file: r.file, name: r.name, pitchClass: 2, minor: false)
        let s = r.respelled(choice: c)
        XCTAssertEqual(s.keys.map { $0.0 }, ["D", "Fm", "Ab"])
        XCTAssertEqual(s.keys.first?.1, 0)
    }

    func testAllKeysAreSpelledLikeAutoTune() {
        XCTAssertEqual(KeyChoice.allKeys.count, 24)
        XCTAssertEqual(Array(KeyChoice.allKeys.prefix(12)), ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"])
        XCTAssertEqual(Array(KeyChoice.allKeys.suffix(12)),
                       ["Cm", "C#m", "Dm", "Ebm", "Em", "Fm", "F#m", "Gm", "G#m", "Am", "Bbm", "Bm"])
        for (i, k) in KeyChoice.allKeys.enumerated() {
            let kc = AutoTuneSend.keyClass(k)
            XCTAssertEqual(kc?.pitchClass, i % 12, k)
            XCTAssertEqual(kc?.minor, i >= 12, k)
        }
    }

    /// The 24 names every readout shows, pinned before click-to-respell was taken out (2026-11-10)
    /// and held after: whichever way the analyzer (or an old saved reading) spells a key, the
    /// dial / top 3, the menu-bar item, the window's readout, the key a send acts on and the key
    /// wheel all show Auto-Tune's name.
    func testDisplayedNamesForAll24KeysArePinned() {
        let shown = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B",
                     "Cm", "C#m", "Dm", "Ebm", "Em", "Fm", "F#m", "Gm", "G#m", "Am", "Bbm", "Bm"]
        let sharp = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let flat = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        XCTAssertEqual(KeyChoice.allKeys, shown)
        var p = Pager()
        p.reset(count: 1)
        for i in 0..<24 {
            let pc = i % 12, minor = i >= 12, m = minor ? "m" : ""
            let want = shown[i]
            XCTAssertEqual(KeyWheel(keys: []).name(pc, minor: minor), want, "wheel \(want)")
            for given in [sharp[pc] + m, flat[pc] + m] {
                let read = Result(file: URL(fileURLWithPath: "/tmp/\(given).wav"), name: "\(given).wav", bpm: "120",
                                  keys: [(given, 80), ("C", 10)], bpmExact: 120)
                XCTAssertEqual(MenuBarReadout.of(read, choice: nil).text, "\(want) 120.0", given)
                XCTAssertEqual(PocketState.shown(.done(read), live: .off, page: p)?.keys.first?.0, want, given)
                XCTAssertEqual(MidiExport.current(.done(read))?.keys.first?.0, want, given)
                guard case .result(let r, _, _, _, _) = Faceplate.readout(
                    .done(read), live: .off, liveSource: "", page: p, factor: .one, lastAction: .download,
                    note: nil, reference: 440, onCycleTempo: nil) else { return XCTFail(given) }
                XCTAssertEqual(r.keys.first?.0, want, given)
                guard case .result(let l, _, _, _, _)? = Faceplate.liveReadout(.locked(read), source: "x", factor: .one)
                else { return XCTFail(given) }
                XCTAssertEqual(l.keys.first?.0, want, given)
                XCTAssertEqual(KeyWheel(keys: r.keys).name(pc, minor: minor), want, "wheel from \(given)")
            }
        }
    }

    func testChooseRecordsTheReading() {
        let s = SpellingSettings()
        s.setManualKey("G#", of: r, from: .topKeys)
        XCTAssertEqual(s.manualKey, KeyChoice(file: r.file, name: r.name, pitchClass: 8, minor: false))
    }
}
