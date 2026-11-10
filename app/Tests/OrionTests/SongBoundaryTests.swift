import XCTest
@testable import Orion

final class SongBoundaryTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func reading(_ key: String = "Ebm", _ pct: Int = 85, bpm: String? = "128.0") -> Result {
        Result(file: LiveSession.songFile(1), name: "LIVE", bpm: bpm,
               keys: [(key, pct), ("Gb", 8), ("Bbm", 4)], bpmExact: bpm == nil ? nil : 128.02)
    }
    func store() -> RecentStore {
        let name = "orion-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return RecentStore(defaults: d)
    }

    final class FakeSignal: SongSignal { var count = 0; func newSong() { count += 1 } }
    final class FakeWatcher: NowPlayingWatching {
        var current: ((String) -> Void)?
        var change: ((String) -> Void)?
        var stopped = false
        func start(onCurrent: @escaping (String) -> Void, onChange: @escaping (String) -> Void) {
            current = onCurrent; change = onChange
        }
        func stop() { stopped = true }
    }

    // MARK: the analyzer's line

    func testParsesBoundaryLines() {
        XCTAssertEqual(LiveEvent.parse(line: #"{"event":"boundary","reason":"audio","scores":{"disappeared":0.8,"grid":"phase"}}"#, song: LiveSession.songFile(1)),
                       .boundary(LiveBoundary(reason: .audio)))
        XCTAssertEqual(LiveEvent.parse(line: #"{"event":"boundary","reason":"title"}"#, song: LiveSession.songFile(1)),
                       .boundary(LiveBoundary(reason: .title)))
        XCTAssertEqual(LiveEvent.parse(line: #"{"event":"boundary"}"#, song: LiveSession.songFile(1)), .boundary(LiveBoundary(reason: .audio)))
    }

    func testBoundaryStartsTheReadingOver() {
        var s = LiveSession()
        s.begin(why: "test")
        s.feed(.reading(reading()), now: t0)
        s.feed(.boundary(LiveBoundary(reason: .audio)), now: t0 + 2)
        XCTAssertEqual(s.state, .listening)
    }

    // MARK: one entry per song

    func testEachSongIsItsOwnRecentReading() {
        var clock = t0
        let tracker = SongTracker(makeWatcher: { nil }, now: { clock })
        let recents = store()
        tracker.recents = recents
        tracker.begin(signal: nil)
        tracker.observe(.reading(reading("Ebm", 85)))            // green
        clock += 30
        tracker.observe(.boundary(LiveBoundary(reason: .audio)))
        XCTAssertEqual(tracker.lastBoundary, LiveBoundary(reason: .audio))
        tracker.observe(.reading(reading("Am", 90, bpm: "140.0")))
        clock += 40
        tracker.end()
        XCTAssertEqual(recents.readings.count, 2)
        XCTAssertEqual(recents.readings[0].keys.first?.name, "Am")
        XCTAssertEqual(recents.readings[1].keys.first?.name, "Ebm")
        XCTAssertTrue(recents.readings[1].name.hasPrefix("Live "))
        XCTAssertNotEqual(recents.readings[0].path, recents.readings[1].path)
    }

    func testShortUnsureSongIsNotKept() {
        var clock = t0
        let tracker = SongTracker(makeWatcher: { nil }, now: { clock })
        let recents = store()
        tracker.recents = recents
        tracker.begin(signal: nil)
        clock += 4
        tracker.observe(.reading(reading("Ebm", 50)))            // amber, 4 s in
        clock += 6
        tracker.observe(.boundary(LiveBoundary(reason: .audio)))
        XCTAssertTrue(recents.readings.isEmpty)
        clock += 16
        tracker.observe(.reading(reading("Ebm", 50)))            // amber but 16 s long: kept
        tracker.end()
        XCTAssertEqual(recents.readings.count, 1)
    }

    func testLastGreenReadingWins() {
        var log = SongLog(started: t0)
        log.feed(reading("Ebm", 50), secs: 6)
        log.feed(reading("Ebm", 88), secs: 10)
        log.feed(reading("Gb", 40), secs: 20)                   // unsure later: the green one stands
        XCTAssertEqual(log.entry()?.keys.first?.0, "Ebm")
        XCTAssertEqual(log.entry()?.keys.first?.1, 88)
    }

    // MARK: player titles

    func testTitleChangeClosesTheSongAndFlushesTheAnalyzer() {
        var clock = t0
        let w = FakeWatcher()
        let sig = FakeSignal()
        let tracker = SongTracker(makeWatcher: { w }, now: { clock })
        let recents = store()
        tracker.recents = recents
        tracker.begin(signal: sig)
        tracker.observe(.ready)
        w.current?("Artist - First Beat")
        XCTAssertEqual(tracker.title, "Artist - First Beat")
        tracker.observe(.reading(reading("Ebm", 85)))
        clock += 60
        w.change?("Artist - Second Beat")
        XCTAssertEqual(sig.count, 1)
        XCTAssertEqual(recents.readings.first?.name, "Artist - First Beat")
        // old-buffer readings until the analyzer's own flush comes back are ignored
        tracker.observe(.reading(reading("Ebm", 85)))
        XCTAssertNil(tracker.song?.best)
        tracker.observe(.boundary(LiveBoundary(reason: .title)))
        XCTAssertEqual(tracker.lastBoundary, LiveBoundary(reason: .title, title: "Artist - Second Beat"))
        XCTAssertEqual(recents.readings.count, 1)                // the flush echo closes nothing
        tracker.observe(.reading(reading("Am", 90)))
        clock += 30
        tracker.end()
        XCTAssertTrue(w.stopped)
        XCTAssertEqual(recents.readings.first?.name, "Artist - Second Beat")
        XCTAssertEqual(recents.readings.first?.keys.first?.name, "Am")
    }

    func testTitleRightAfterAnAudioBoundaryNamesThatSong() {
        var clock = t0
        let w = FakeWatcher()
        let sig = FakeSignal()
        let tracker = SongTracker(makeWatcher: { w }, now: { clock })
        tracker.begin(signal: sig)
        tracker.observe(.ready)
        clock += 60
        tracker.observe(.boundary(LiveBoundary(reason: .audio)))
        clock += 3
        w.change?("Next Beat")
        XCTAssertEqual(sig.count, 0)                             // no second flush
        XCTAssertEqual(tracker.song?.title, "Next Beat")
        XCTAssertEqual(tracker.lastBoundary, LiveBoundary(reason: .audio, title: "Next Beat"))
    }

    func testTitleTrackerSeesOnlyASlotChangingTrack() {
        var t = TitleTracker()
        let a = NowPlayingEntry(key: "brave:1", identity: "Beat A", title: "Beat A")
        let other = NowPlayingEntry(key: "brave:2", identity: "Other", title: "Other")
        XCTAssertNil(t.update([a]))
        XCTAssertNil(t.update([a, other]))                       // a new tab is not a new song
        XCTAssertNil(t.update([other]))                          // a slot gone (closed / paused)
        XCTAssertNil(t.update([a, other]))                       // and back with the same track
        XCTAssertEqual(t.update([NowPlayingEntry(key: "brave:1", identity: "Beat B", title: "Beat B"), other]), "Beat B")
        let s1 = NowPlayingEntry(key: "spotify", identity: "id1", title: "X - One")
        XCTAssertNil(t.update([s1]))
        XCTAssertEqual(t.update([NowPlayingEntry(key: "spotify", identity: "id2", title: "X - Two")]), "X - Two")
    }

    func testCurrentTitleAndTabTitleCleanup() {
        XCTAssertEqual(TitleTracker.cleanTabTitle("(3) Dark Beat | 140 BPM - YouTube"), "Dark Beat | 140 BPM")
        XCTAssertEqual(TitleTracker.cleanTabTitle("Song - YouTube Music"), "Song")
        let tabs = TitleTracker.parse("12\t-\t(1) Beat One - YouTube\n13\t-\tYouTube\n", prefix: "brave")
        XCTAssertEqual(tabs, [NowPlayingEntry(key: "brave:12", identity: "Beat One", title: "Beat One")])
        let sp = TitleTracker.parse("spotify\tspotify:track:9\tArtist - Song", prefix: "spotify")
        XCTAssertEqual(sp, [NowPlayingEntry(key: "spotify", identity: "spotify:track:9", title: "Artist - Song")])
        XCTAssertEqual(TitleTracker.current(tabs + sp), "Artist - Song")
        XCTAssertEqual(TitleTracker.current(tabs), "Beat One")
        XCTAssertNil(TitleTracker.current(tabs + [NowPlayingEntry(key: "brave:14", identity: "B", title: "B")]))
    }

    func testWatcherOnlyRunsInTheApp() {
        XCTAssertFalse(NowPlayingWatcher.inApp)                  // swift test: never asks the players
    }
}
