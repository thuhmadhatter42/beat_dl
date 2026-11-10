import XCTest
@testable import Orion

/// Each live song has its own identity (0.1.60): a key picked by hand, the tempo factor and the
/// keyboard's root belong to the song they were set in. Every route to a new song (gap reset,
/// audio boundary, the player's title, New Song, a fresh Listen) starts them over; within one
/// song they hold.
final class SongIdentityTests: XCTestCase {
    final class FakePipe: LivePipe {
        func write(_ samples: [Float]) {}
        func close() {}
    }
    final class FakeCapture: AudioCapture {
        func start(onSamples: @escaping ([Float]) -> Void, onError: @escaping (String) -> Void) {}
        func stop() {}
    }

    private func defaults() -> UserDefaults {
        let name = "orion-song-identity-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    private func controller() -> LiveController {
        let c = LiveController(settings: LiveSettings(defaults: defaults(), systemAvailable: false),
                               launch: { _, _, _ in FakePipe() }, makeCapture: { _ in FakeCapture() })
        addTeardownBlock { c.stop() }
        return c
    }

    private func settings() -> SpellingSettings { SpellingSettings(defaults: defaults()) }

    static let reading = #"{"event":"reading","bpm":"128.0","bpm_exact":128.02,"keys":[["Ebm",85],["F#",8],["Bbm",4]]}"#
    static let reset = #"{"event":"reset"}"#
    static let audio = #"{"event":"boundary","reason":"audio"}"#
    static let title = #"{"event":"boundary","reason":"title"}"#

    /// The reading on show after the analyzer prints `line`.
    private func heard(_ c: LiveController, _ line: String = SongIdentityTests.reading) -> Result? {
        c.receive(line)
        return c.state.result
    }

    // (a) (b) a key picked in song A is not song B's, by every automatic route

    func testPickedKeyDoesNotOutliveASongChange() throws {
        for change in [SongIdentityTests.audio, SongIdentityTests.reset, SongIdentityTests.title] {
            let c = controller(), s = settings()
            c.start()
            let a = try XCTUnwrap(heard(c))
            XCTAssertTrue(s.setManualKey("Am", of: a, from: .wheel))
            XCTAssertEqual(a.respelled(nil, choice: s.manualKey).keys.first?.0, "Am", change)
            c.receive(change)
            let b = try XCTUnwrap(heard(c))
            XCTAssertFalse(s.manualKey!.matches(b), "the key picked in song A applies to song B after \(change)")
            XCTAssertEqual(b.respelled(nil, choice: s.manualKey).keys.first?.0, "Ebm", change)
            XCTAssertNil(ManualKey.of(s.manualKey, raw: b), change)
        }
    }

    /// New Song and a fresh Listen start a new song too (no clear of their own).
    func testNewSongAndAFreshListenStartANewSong() throws {
        let c = controller(), s = settings()
        c.start()
        let a = try XCTUnwrap(heard(c))
        s.setManualKey("Am", of: a, from: .topKeys)
        c.reset()                                                     // New Song
        let b = try XCTUnwrap(heard(c))
        XCTAssertFalse(s.manualKey!.matches(b))
        s.setManualKey("G", of: b, from: .keyboard)
        c.stop()
        c.start()                                                     // Listen again
        let d = try XCTUnwrap(heard(c))
        XCTAssertFalse(s.manualKey!.matches(d))
    }

    // (c) within one song the pick holds

    func testPickedKeyHoldsForTheSameSong() throws {
        let c = controller(), s = settings()
        c.start()
        let a = try XCTUnwrap(heard(c))
        s.setManualKey("Am", of: a, from: .dropdown)
        for _ in 0..<3 {
            let next = try XCTUnwrap(heard(c))
            XCTAssertTrue(s.manualKey!.matches(next))
            XCTAssertEqual(next.respelled(nil, choice: s.manualKey).keys.first?.0, "Am")
        }
        c.receive(#"{"event":"ready"}"#)                              // not a song change
        XCTAssertTrue(s.manualKey!.matches(try XCTUnwrap(heard(c))))
    }

    // (d) the tempo factor: x1 at every song change, held within a song

    func testTempoFactorFollowsTheSong() {
        let c = controller(), m = FaceplateModel()
        m.follow(c)
        m.tempoFactor = .double
        c.start()
        XCTAssertEqual(m.tempoFactor, .one, "Listen started")
        m.tempoFactor = .double
        _ = heard(c); _ = heard(c)
        c.setHold(true); c.setHold(false)
        XCTAssertEqual(m.tempoFactor, .double, "changed within one song")
        for change in [SongIdentityTests.audio, SongIdentityTests.reset, SongIdentityTests.title] {
            m.tempoFactor = .half
            c.receive(change)
            XCTAssertEqual(m.tempoFactor, .one, change)
        }
        m.tempoFactor = .double
        c.reset()
        XCTAssertEqual(m.tempoFactor, .one, "New Song")
        m.tempoFactor = .double
        c.stop()
        XCTAssertEqual(m.tempoFactor, .one, "Listen stopped")
    }

    /// One log line per song change: what changed it and what it cleared.
    func testEverySongChangeLogsWhatItCleared() throws {
        var lines: [String] = []
        AppLog.sink = { lines.append($0) }
        defer { AppLog.sink = nil }
        let c = controller(), m = FaceplateModel(), s = settings()
        c.start()
        let a = try XCTUnwrap(heard(c))
        s.setManualKey("Am", of: a, from: .wheel)
        m.tempoFactor = .double
        let from = c.songChange.to
        c.receive(SongIdentityTests.audio)
        XCTAssertEqual(c.songChange.from, from)
        XCTAssertNotEqual(c.songChange.to, from)
        lines.removeAll()
        m.songChanged(c.songChange, choice: s.manualKey)
        XCTAssertEqual(lines.count, 1)
        let line = try XCTUnwrap(lines.first)
        XCTAssertTrue(line.contains("(audio boundary)"), line)
        XCTAssertTrue(line.contains("manual key Am cleared"), line)
        XCTAssertTrue(line.contains("tempo factor ×2 back to x1"), line)
        c.stop(reason: "user stop")
        lines.removeAll()
        m.songChanged(c.songChange, choice: s.manualKey)               // song B ends: nothing set in it
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("-> off (user stop)"), lines[0])
        XCTAssertFalse(lines[0].contains("cleared") || lines[0].contains("back to"), lines[0])
    }

    // (e) the keyboard's root starts over on a new live song

    func testKeyboardRootStartsOverOnANewSong() throws {
        let c = controller()
        c.start()
        var p = PlayState()
        let a = try XCTUnwrap(heard(c))
        p.show(a)
        _ = p.press(9, keys: a.keys)
        XCTAssertEqual(p.root, 9)
        p.show(try XCTUnwrap(heard(c)))                               // same song
        XCTAssertEqual(p.root, 9)
        c.receive(SongIdentityTests.audio)
        p.show(try XCTUnwrap(heard(c)))
        XCTAssertNil(p.root, "the root played over song A carried into song B")
    }
}
