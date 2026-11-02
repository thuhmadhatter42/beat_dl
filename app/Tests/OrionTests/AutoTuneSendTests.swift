import XCTest
@testable import Orion

final class AutoTuneSendTests: XCTestCase {
    func testOriginalSampleBytes() {
        let want = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n\r\n<PROPERTIES>\r\n  <VALUE name=\"KeyClass\" val=\"11\"/>\r\n  <VALUE name=\"KeyType\" val=\"1\"/>\r\n  <VALUE name=\"ReferencePitch\" val=\"450\"/>\r\n  <VALUE name=\"TempoBPM\" val=\"-1\"/>\r\n</PROPERTIES>\r\n"
        XCTAssertEqual(AutoTuneSend.contents(pitchClass: 11, minor: true, referencePitch: 450), want)
        XCTAssertEqual(want.utf8.count, 224)
    }

    func testAll24Keys() {
        let names = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        for (i, n) in names.enumerated() {
            for minor in [false, true] {
                let k = AutoTuneSend.keyClass(n + (minor ? "m" : ""))
                XCTAssertEqual(k?.pitchClass, i, n)
                XCTAssertEqual(k?.minor, minor, n)
                let s = AutoTuneSend.contents(pitchClass: i, minor: minor, referencePitch: 440)
                XCTAssertTrue(s.contains("name=\"KeyClass\" val=\"\(i)\""))
                XCTAssertTrue(s.contains("name=\"KeyType\" val=\"\(minor ? 1 : 0)\""))
            }
        }
        XCTAssertEqual(AutoTuneSend.keyClass("C#m")?.pitchClass, 1)
        XCTAssertEqual(AutoTuneSend.keyClass("G#m")?.pitchClass, 8)
        XCTAssertNil(AutoTuneSend.keyClass("H"))
    }

    func testWriteAtomicCreatesDirAndCRLF() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("atk-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("Temp")
        let url = dir.appendingPathComponent("Auto-Key.handoff")
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(AutoTuneSend.write(key: "Ebm", referencePitch: 442.5, to: url))
        XCTAssertTrue(AutoTuneSend.write(key: "F#", referencePitch: 440, to: url))
        let s = try String(contentsOf: url)
        XCTAssertTrue(s.contains("name=\"KeyClass\" val=\"6\"") && s.contains("name=\"KeyType\" val=\"0\""))
        XCTAssertTrue(s.contains("\r\n"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["Auto-Key.handoff"])
        XCTAssertFalse(AutoTuneSend.write(key: "nope", referencePitch: 440, to: url))
    }
}
