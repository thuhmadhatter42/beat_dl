import XCTest
@testable import Orion

final class MidiExportTests: XCTestCase {
    /// Minimal SMF reader: header, then the meta events of the one track.
    private func parse(_ d: Data) -> (fmt: Int, ntrks: Int, div: Int, metas: [UInt8: [UInt8]], endsWithEOT: Bool) {
        let b = [UInt8](d)
        XCTAssertEqual(Array(b[0..<4]), Array("MThd".utf8))
        XCTAssertEqual(Int(b[4]) << 24 | Int(b[5]) << 16 | Int(b[6]) << 8 | Int(b[7]), 6)
        let fmt = Int(b[8]) << 8 | Int(b[9]), n = Int(b[10]) << 8 | Int(b[11]), div = Int(b[12]) << 8 | Int(b[13])
        XCTAssertEqual(Array(b[14..<18]), Array("MTrk".utf8))
        let len = Int(b[18]) << 24 | Int(b[19]) << 16 | Int(b[20]) << 8 | Int(b[21])
        XCTAssertEqual(b.count, 22 + len)
        var i = 22, metas = [UInt8: [UInt8]](), eot = false
        while i < b.count {
            XCTAssertEqual(b[i], 0); i += 1            // delta 0 (all events at tick 0)
            XCTAssertEqual(b[i], 0xFF); i += 1
            let type = b[i], l = Int(b[i + 1]); i += 2
            metas[type] = Array(b[i..<i + l]); i += l
            if type == 0x2F { eot = (i == b.count) }
        }
        return (fmt, n, div, metas, eot)
    }

    func testTempoAndKey() {
        let p = parse(MidiExport.data(bpm: 140.82, key: "Ebm"))
        XCTAssertEqual(p.fmt, 0); XCTAssertEqual(p.ntrks, 1); XCTAssertEqual(p.div, 480)
        let us = p.metas[0x51]!
        let micro = Int(us[0]) << 16 | Int(us[1]) << 8 | Int(us[2])
        XCTAssertEqual(micro, 426_076)                                  // 60e6 / 140.82
        XCTAssertEqual(60_000_000.0 / Double(micro), 140.82, accuracy: 0.001)
        XCTAssertEqual(p.metas[0x59], [UInt8(bitPattern: -6), 1])       // Eb minor: 6 flats
        XCTAssertTrue(p.endsWithEOT)
    }

    func testKeySignatures() {
        XCTAssertTrue(MidiExport.keySignature("C")! == (0, false))
        XCTAssertTrue(MidiExport.keySignature("Am")! == (0, true))
        XCTAssertTrue(MidiExport.keySignature("F#")! == (6, false))
        XCTAssertTrue(MidiExport.keySignature("Bb")! == (-2, false))
        XCTAssertTrue(MidiExport.keySignature("C#m")! == (4, true))
        XCTAssertTrue(MidiExport.keySignature("Gm")! == (-2, true))
        XCTAssertTrue(MidiExport.keySignature("G♯m")! == (5, true))
        XCTAssertNil(MidiExport.keySignature("H"))
        // every name bpm.py can print resolves
        for n in ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"] { XCTAssertNotNil(MidiExport.keySignature(n), n) }
        for n in ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"] { XCTAssertNotNil(MidiExport.keySignature(n + "m"), n + "m") }
    }

    func testMissingPartsAreOmitted() {
        let p = parse(MidiExport.data(bpm: nil, key: "nonsense"))
        XCTAssertNil(p.metas[0x51]); XCTAssertNil(p.metas[0x59]); XCTAssertTrue(p.endsWithEOT)
    }

    func testSuggestedName() {
        XCTAssertEqual(MidiExport.suggestedName(track: "Beat.mp3", bpm: "140.82", key: "Ebm"), "Beat (140.82 BPM Ebm).mid")
        XCTAssertEqual(MidiExport.suggestedName(track: "a (142.0 BPM Cm Dm).mp3", bpm: "142.0", key: "Cm"), "a (142.0 BPM Cm).mid")
        XCTAssertEqual(MidiExport.suggestedName(track: "x/y", bpm: nil, key: nil), "x-y.mid")
    }

    /// Round trip through the repo's own Python SMF parser (midi_analyze.py), when it is present.
    func testRoundTripThroughPythonParser() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("midiexport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("t.mid")
        try MidiExport.data(bpm: 128, key: "Cm").write(to: f)
        let script = """
        import sys, importlib.util
        spec = importlib.util.spec_from_file_location("m", sys.argv[1]); m = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(m)
        except ImportError:
            print("SKIP"); sys.exit(0)
        tpq, notes, tempos, last = m.parse(open(sys.argv[2], "rb").read())
        print(tpq, len(notes), 60e6 / tempos[0][1])
        """
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let py = root.appendingPathComponent("midi_analyze.py")
        guard FileManager.default.fileExists(atPath: py.path) else { throw XCTSkip("midi_analyze.py not in this checkout") }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", "-c", script, py.path, f.path]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if text.hasPrefix("SKIP") { throw XCTSkip("python deps missing") }
        XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "480 0 128.0")
    }
}
