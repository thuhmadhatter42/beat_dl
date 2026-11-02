import XCTest
@testable import Orion

/// Hold (a button, never automatic) and the sharp / flat respelling of keys (J, 2026-11-01).
final class HoldSpellingTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func reading(_ key: String = "Ebm", _ pct: Int = 85) -> Result {
        Result(file: LiveSession.placeholderFile, name: "LIVE", bpm: "128.0",
               keys: [(key, pct), ("Gb", 8), ("Bbm", 4)], bpmExact: 128.02)
    }

    // MARK: hold

    func testHoldFreezesTheShownReadingAndReleaseJumpsToTheLiveOne() {
        var s = LiveSession()
        s.begin()
        s.feed(.reading(reading("Ebm")), now: t0)
        XCTAssertTrue(s.setHold(true))
        XCTAssertTrue(s.isHeld)
        s.feed(.reading(reading("Am", 90)), now: t0 + 2)
        s.feed(.reading(reading("Am", 90)), now: t0 + 9)       // would lock underneath
        XCTAssertEqual(s.state, .reading(reading("Ebm")))      // still the frozen one
        XCTAssertEqual(s.current, .locked(reading("Am", 90)))  // listening carried on
        XCTAssertTrue(s.setHold(false))
        XCTAssertFalse(s.isHeld)
        XCTAssertEqual(s.state, .locked(reading("Am", 90)))    // straight to the current reading
    }

    func testHoldIsNeverAutomaticAndNeedsAReading() {
        var s = LiveSession()
        XCTAssertFalse(s.setHold(true))                        // not listening
        s.begin()
        XCTAssertFalse(s.setHold(true))                        // nothing to hold yet
        XCTAssertFalse(s.isHeld)
        for i in 0..<5 { s.feed(.reading(reading()), now: t0 + Double(i) * 2) }
        XCTAssertFalse(s.isHeld)                               // a green lock never holds by itself
        XCTAssertTrue(s.toggleHold())
        XCTAssertTrue(s.isHeld)
        XCTAssertTrue(s.toggleHold())                          // a second press releases
        XCTAssertFalse(s.isHeld)
    }

    func testNewSongStopAndFailureTurnHoldOff() {
        var s = LiveSession()
        s.begin()
        s.feed(.reading(reading()), now: t0)
        s.setHold(true)
        s.feed(.reset, now: t0 + 1)                            // silence gap: new song
        XCTAssertFalse(s.isHeld)
        XCTAssertEqual(s.state, .listening)

        s.feed(.reading(reading()), now: t0 + 2)
        s.setHold(true)
        s.begin()                                              // New Song · Reset restarts the session
        XCTAssertFalse(s.isHeld)

        s.feed(.reading(reading()), now: t0 + 3)
        s.setHold(true)
        s.end()                                                // Stop Listening
        XCTAssertFalse(s.isHeld)
        XCTAssertEqual(s.state, .off)

        s.begin()
        s.feed(.reading(reading()), now: t0 + 4)
        s.setHold(true)
        s.fail("x")
        XCTAssertFalse(s.isHeld)
        XCTAssertEqual(s.state, .failed("x"))
    }

    func testHeldCaptionAndReadout() {
        let r = reading()
        XCTAssertEqual(LiveState.reading(r).status(source: "x", held: true), "HELD · LOCKED 85%")
        XCTAssertEqual(LiveState.reading(r).status(source: "x"), "LOCKED 85%")
        XCTAssertEqual(LiveState.listening.status(source: "Mic", held: true), "LISTENING · MIC")   // nothing held
        let m = MenuBarReadout.of(r, held: true)
        XCTAssertEqual(m.text, "⏸ Ebm 128.0")
        XCTAssertTrue(m.detail.hasPrefix("Held · "))
        XCTAssertEqual(MenuBarReadout.of(r).text, "Ebm 128.0")
    }

    func testControllerHoldOnlyWhileListeningWithAReading() {
        let c = LiveController(settings: LiveSettings(defaults: UserDefaults(suiteName: "hold-\(UUID())")!),
                               launch: { _, _, _ in nil }, makeCapture: { _ in nil })
        XCTAssertFalse(c.toggleHold())
        XCTAssertFalse(c.isHeld)
    }

    // MARK: spelling

    /// All 24 keys, both ways: the analyzer's spelling > sharps > flats.
    func testEnharmonicMappingForAll24Keys() {
        let pairs = [("Db", "C#"), ("Eb", "D#"), ("Gb", "F#"), ("Ab", "G#"), ("Bb", "A#")]
        for (flat, sharp) in pairs {
            for m in ["", "m"] {
                XCTAssertEqual(KeySpelling.respell(flat + m, to: .sharps), sharp + m)
                XCTAssertEqual(KeySpelling.respell(sharp + m, to: .flats), flat + m)
                XCTAssertEqual(KeySpelling.respell(flat + m, to: .flats), flat + m)
                XCTAssertEqual(KeySpelling.respell(sharp + m, to: .sharps), sharp + m)
                XCTAssertEqual(KeySpelling.respell(flat + m, to: nil), flat + m)
            }
        }
        for n in ["C", "D", "E", "F", "G", "A", "B"] {
            for m in ["", "m"] {
                XCTAssertEqual(KeySpelling.respell(n + m, to: .sharps), n + m)
                XCTAssertEqual(KeySpelling.respell(n + m, to: .flats), n + m)
                XCTAssertNil(KeySpelling.clickTarget(for: n + m))
                XCTAssertFalse(KeySpelling.isBlack(n + m))
            }
        }
        XCTAssertEqual(KeySpelling.respell("Ebm", to: .sharps), "D#m")
        XCTAssertEqual(KeySpelling.respell("Bbm", to: .sharps), "A#m")
        XCTAssertEqual(KeySpelling.respell("nonsense", to: .sharps), "nonsense")
    }

    func testClickTargetSwitchesToTheOtherSpelling() {
        XCTAssertEqual(KeySpelling.clickTarget(for: "Ebm"), .sharps)
        XCTAssertEqual(KeySpelling.clickTarget(for: "D#m"), .flats)
        XCTAssertEqual(KeySpelling.clickTarget(for: "F#"), .flats)
        XCTAssertEqual(KeySpelling.clickTarget(for: "Gb"), .sharps)
        XCTAssertEqual(KeySpelling.clickTarget(for: "E♭"), .sharps)
    }

    func testRespelledResultCoversTheTopKeyAndTheList() {
        let r = reading("Ebm").respelled(.sharps)
        XCTAssertEqual(r.keys.map { $0.0 }, ["D#m", "F#", "A#m"])
        XCTAssertEqual(r.keys.map { $0.1 }, [85, 8, 4])
        XCTAssertEqual(r.bpm, "128.0")
        XCTAssertEqual(reading("Ebm").respelled(nil), reading("Ebm"))
        XCTAssertEqual(r.respelled(.flats).keys.map { $0.0 }, ["Ebm", "Gb", "Bbm"])
    }

    func testPreferencePersistsAndClickFlipsIt() {
        let d = UserDefaults(suiteName: "spell-\(UUID())")!
        let s = SpellingSettings(defaults: d)
        XCTAssertNil(s.preference)
        XCTAssertFalse(s.click(on: "Am"))                       // natural: nothing
        XCTAssertNil(s.preference)
        XCTAssertTrue(s.click(on: "Ebm"))
        XCTAssertEqual(s.preference, .sharps)
        XCTAssertEqual(SpellingSettings(defaults: d).preference, .sharps)
        XCTAssertTrue(s.click(on: "D#m"))
        XCTAssertEqual(s.preference, .flats)
        s.sharps = true
        XCTAssertEqual(s.preference, .sharps)
        XCTAssertTrue(s.sharps)
    }

    func testScaleSpellingFollowsTheKeyName() {
        XCTAssertEqual(Scale.of("Ebm")!.spelled, ["E♭", "F", "G♭", "A♭", "B♭", "C♭", "D♭"])
        XCTAssertEqual(Scale.of("D#m")!.spelled, ["D♯", "E♯", "F♯", "G♯", "A♯", "B", "C♯"])
        XCTAssertEqual(Scale.of("Gb")!.spelled, ["G♭", "A♭", "B♭", "C♭", "D♭", "E♭", "F"])
        XCTAssertEqual(Scale.of("F#")!.spelled, ["F♯", "G♯", "A♯", "B", "C♯", "D♯", "E♯"])
        XCTAssertEqual(Scale.of("Db")!.spelled, ["D♭", "E♭", "F", "G♭", "A♭", "B♭", "C"])
        XCTAssertEqual(Scale.of("C#")!.spelled, ["C♯", "D♯", "E♯", "F♯", "G♯", "A♯", "B♯"])
        XCTAssertEqual(Scale.of("Bbm")!.spelled, ["B♭", "C", "D♭", "E♭", "F", "G♭", "A♭"])
        XCTAssertEqual(Scale.of("A#m")!.spelled, ["A♯", "B♯", "C♯", "D♯", "E♯", "F♯", "G♯"])
        XCTAssertEqual(Scale.of("Ab")!.spelled, ["A♭", "B♭", "C", "D♭", "E♭", "F", "G"])
        XCTAssertEqual(Scale.of("G#")!.spelled, ["G♯", "A♯", "B♯", "C♯", "D♯", "E♯", "F♯♯"])   // 8 sharps, as written
        XCTAssertEqual(Scale.of("G#m")!.spelled, ["G♯", "A♯", "B", "C♯", "D♯", "E", "F♯"])
        XCTAssertEqual(Scale.of("Abm")!.spelled.first, "A♭")
        XCTAssertEqual(Scale.of("C")!.spelled, ["C", "D", "E", "F", "G", "A", "B"])
        XCTAssertEqual(Scale.of("Am")!.spelled, ["A", "B", "C", "D", "E", "F", "G"])
        XCTAssertEqual(Scale.of("Ebm")!.tonicName, "E♭")
        XCTAssertEqual(Scale.of("D#m")!.tonicName, "D♯")
        XCTAssertTrue(Scale.of("D#m")!.sharps)
        XCTAssertFalse(Scale.of("Ebm")!.sharps)
        XCTAssertEqual(Scale.of("D#m")!.notes, Scale.of("Ebm")!.notes)   // same notes on the keyboard
    }

    func testMidiKeySignatureFollowsTheSpelling() {
        func sig(_ k: String) -> Int? { MidiExport.keySignature(k)?.sharps }
        XCTAssertEqual(sig("Ebm"), -6)
        XCTAssertEqual(sig("D#m"), 6)
        XCTAssertEqual(sig("Bbm"), -5)
        XCTAssertEqual(sig("A#m"), 7)
        XCTAssertEqual(sig("Gb"), -6)
        XCTAssertEqual(sig("F#"), 6)
        XCTAssertEqual(sig("Db"), -5)
        XCTAssertEqual(sig("C#"), 7)
        XCTAssertEqual(sig("Ab"), -4)
        XCTAssertEqual(sig("G#"), -4)   // no 8-sharp signature: written as its equal, A-flat major
        XCTAssertEqual(sig("D#"), -3)
        XCTAssertEqual(sig("A#"), -2)
        XCTAssertEqual(MidiExport.keySignature("G#")?.minor, false)
    }

    func testReadingsShownFollowThePreference() {
        let live = LiveState.reading(reading("Ebm"))
        let r = PocketState.shown(.idle, live: live, page: Pager(), spelling: .sharps)
        XCTAssertEqual(r?.keys.first?.0, "D#m")
        XCTAssertEqual(PocketState.shown(.idle, live: live, page: Pager(), spelling: nil)?.keys.first?.0, "Ebm")
        let m = MenuBarReadout.of(live: live, source: "x", factor: .one, spelling: .sharps)
        XCTAssertEqual(m?.text, "D#m 128.0")
        guard case .result(let shown, _, _, _, _)? = Faceplate.liveReadout(live, source: "x", factor: .one, spelling: .sharps)
        else { return XCTFail() }
        XCTAssertEqual(shown.keys.map { $0.0 }, ["D#m", "F#", "A#m"])
        XCTAssertEqual(MidiExport.current(.done(reading("Ebm")), spelling: .sharps)?.keys.first?.0, "D#m")
    }

    func testHoldHotkeyDefaultsAppended() {
        XCTAssertEqual(HotkeyAction.hold.defaultShortcut.display, "⌃⌥⌘H")
        XCTAssertEqual(HotkeyAction.hold.hotKeyID, 4)
    }
}
