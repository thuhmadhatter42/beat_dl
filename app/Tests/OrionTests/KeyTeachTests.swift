import AppKit
import XCTest
@testable import Orion

final class TeachStoreTests: XCTestCase {
    var root: URL!
    let raw = Result(file: URL(fileURLWithPath: "/tmp/beat.mp3"), name: "beat", bpm: "140",
                     keys: [("Fm", 60), ("Ab", 25), ("Cm", 10)], bpmExact: 140.02)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("teach-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.trashItem(at: root, resultingItemURL: nil)
    }

    private func label(_ dir: URL) throws -> TeachLabel {
        try JSONDecoder().decode(TeachLabel.self, from: Data(contentsOf: dir.appendingPathComponent("label.json")))
    }

    func testSmallFileIsCopiedWithItsLabel() throws {
        let src = root.appendingPathComponent("src/song.MP3")
        try FileManager.default.createDirectory(at: src.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 1000).write(to: src)
        let dir = try TeachStore.save(chosen: "G#", raw: raw, source: .file, audio: .file(src, link: nil),
                                      root: root.appendingPathComponent("teach"), now: now, version: "9.9.9")
        let l = try label(dir)
        XCTAssertEqual(l.chosen, "Ab")                           // Auto-Tune's spelling
        XCTAssertEqual(l.chosenPitchClass, 8)
        XCTAssertFalse(l.chosenMinor)
        XCTAssertEqual(l.analyzerTop3, [.init(name: "Fm", score: 60), .init(name: "Ab", score: 25), .init(name: "Cm", score: 10)])
        XCTAssertEqual(l.bpm, "140")
        XCTAssertEqual(l.bpmExact, 140.02)
        XCTAssertEqual(l.source, .file)
        XCTAssertEqual(l.appVersion, "9.9.9")
        XCTAssertEqual(l.audio.kind, "copy")
        XCTAssertEqual(l.audio.file, "audio.mp3")
        XCTAssertEqual(l.audio.bytes, 1000)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("audio.mp3")).count, 1000)
        XCTAssertEqual(dir.lastPathComponent, TeachStore.folderName(now))
    }

    func testBigFileKeepsOnlyItsPath() throws {
        let src = root.appendingPathComponent("src/big.wav")
        try FileManager.default.createDirectory(at: src.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: src.path, contents: nil)
        let h = try FileHandle(forWritingTo: src)
        try h.truncate(atOffset: UInt64(TeachStore.copyLimit))   // sparse: 50 MB, nothing written
        try h.close()
        let dir = try TeachStore.save(chosen: "Fm", raw: raw, source: .youtube,
                                      audio: .file(src, link: "https://youtu.be/x"), root: root, now: now)
        let l = try label(dir)
        XCTAssertEqual(l.audio.kind, "path")
        XCTAssertEqual(l.audio.sourcePath, src.path)
        XCTAssertEqual(l.audio.link, "https://youtu.be/x")
        XCTAssertNil(l.audio.file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("audio.wav").path))
    }

    func testLiveClipIsAWav() throws {
        let samples = [Float](repeating: 0.5, count: 44100)
        let dir = try TeachStore.save(chosen: "Ebm", raw: raw, source: .live, audio: .clip(samples, sampleRate: 44100),
                                      root: root, now: now)
        let l = try label(dir)
        XCTAssertEqual(l.source, .live)
        XCTAssertEqual(l.audio.kind, "clip")
        XCTAssertEqual(l.audio.seconds, 1)
        let wav = try Data(contentsOf: dir.appendingPathComponent("clip.wav"))
        XCTAssertEqual(wav.count, 44 + 44100 * 2)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
    }

    func testTwoSavesInTheSameMillisecondDoNotCollide() throws {
        let a = try TeachStore.save(chosen: "C", raw: raw, source: .file, audio: .none(link: nil), root: root, now: now)
        let b = try TeachStore.save(chosen: "C", raw: raw, source: .file, audio: .none(link: nil), root: root, now: now)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(try label(b).audio.kind, "none")
    }

    func testNotAKeyThrows() {
        XCTAssertThrowsError(try TeachStore.save(chosen: "H#", raw: raw, source: .file, audio: .none(link: nil), root: root))
    }

    func testClipRingKeepsTheLastSeconds() {
        var c = ClipRing(seconds: 1, sampleRate: 10)
        for i in 0..<5 { c.append([Float](repeating: Float(i), count: 4)) }
        XCTAssertEqual(c.last.count, 10)
        XCTAssertEqual(c.last.last, 4)
        XCTAssertEqual(c.last.first, 2)
    }
}

final class MusicalTypingTests: XCTestCase {
    func testLogicLayout() {
        // A W S E D F T G Y H U J K (ANSI key codes) = C..B, C above
        let codes: [UInt16] = [0, 13, 1, 14, 2, 3, 17, 5, 16, 4, 32, 38, 40]
        for (i, c) in codes.enumerated() {
            XCTAssertEqual(MusicalTyping.action(keyCode: c, modifiers: []), .note(i))
        }
        XCTAssertEqual(MusicalTyping.action(keyCode: 6, modifiers: []), .octaveDown)
        XCTAssertEqual(MusicalTyping.action(keyCode: 7, modifiers: []), .octaveUp)
        XCTAssertEqual(MusicalTyping.action(keyCode: 49, modifiers: []), .toggleMode)
        XCTAssertNil(MusicalTyping.action(keyCode: 15, modifiers: []))      // R: not a note
    }

    func testShortcutsAreNotNotes() {
        XCTAssertEqual(MusicalTyping.action(keyCode: 0, modifiers: [.command, .shift]), .sendAutoTune)
        XCTAssertNil(MusicalTyping.action(keyCode: 0, modifiers: [.command]))            // ⌘A
        XCTAssertNil(MusicalTyping.action(keyCode: 1, modifiers: [.control]))
        XCTAssertNil(MusicalTyping.action(keyCode: 0, modifiers: [.control, .option, .command]))
        XCTAssertEqual(MusicalTyping.action(keyCode: 0, modifiers: [.capsLock]), .note(0))
    }

    func testModeIsTheAnalyzersHigherScore() {
        let keys = [("Fm", 60), ("Ab", 25), ("Abm", 10)]
        XCTAssertTrue(MusicalTyping.minor(forRoot: 5, keys: keys))     // F: only Fm listed
        XCTAssertFalse(MusicalTyping.minor(forRoot: 8, keys: keys))    // Ab 25 > Abm 10
        XCTAssertTrue(MusicalTyping.minor(forRoot: 2, keys: keys))     // D: not listed, top key is minor
        XCTAssertFalse(MusicalTyping.minor(forRoot: 2, keys: []))
    }

    func testLastNoteIsTheRootAndSpaceFlips() {
        var s = PlayState()
        let keys = [("Fm", 60), ("Ab", 25), ("Cm", 10)]
        XCTAssertEqual(s.press(0, keys: keys), 60)
        XCTAssertEqual(s.press(8, keys: keys), 68)
        XCTAssertEqual(s.key, "Ab")
        XCTAssertTrue(s.toggle(shownKey: "Fm"))
        XCTAssertEqual(s.key, "G#m")
        s.octave(true)
        XCTAssertEqual(s.press(12, keys: keys), 84)    // K in the octave up = C
        XCTAssertEqual(s.key, "Cm")
    }

    func testSpaceWithoutARootFlipsTheShownKey() {
        var s = PlayState()
        XCTAssertFalse(s.toggle(shownKey: nil))
        XCTAssertTrue(s.toggle(shownKey: "Ebm"))
        XCTAssertEqual(s.key, "Eb")
    }

    func testOctaveStaysInRange() {
        var s = PlayState()
        for _ in 0..<10 { s.octave(false) }
        XCTAssertEqual(s.octaveC, PlayState.lowestC)
        for _ in 0..<10 { s.octave(true) }
        XCTAssertEqual(s.octaveC, PlayState.highestC)
    }
}
