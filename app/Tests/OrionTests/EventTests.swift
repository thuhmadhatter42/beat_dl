import XCTest
@testable import Orion

final class EventTests: XCTestCase {
    func testParseDone() {
        let line = #"{"stage":"done","file":"/tmp/a (142.0 BPM Cm Dm).mp3","name":"a (142.0 BPM Cm Dm).mp3","bpm":"142.0","keys":[["Cm",73],["Dm",20]]}"#
        guard case .done(let r)? = Event.parse(line: line) else { return XCTFail("not done") }
        XCTAssertEqual(r.bpm, "142.0")
        XCTAssertEqual(r.keys.count, 2)
        XCTAssertEqual(r.keys[0].0, "Cm"); XCTAssertEqual(r.keys[0].1, 73)
        XCTAssertEqual(r.file.path, "/tmp/a (142.0 BPM Cm Dm).mp3")
    }
    func testParseEventKeyForm() {
        XCTAssertEqual(Event.parse(line: #"{"event":"stage","stage":"renaming"}"#), .stage("renaming"))
        XCTAssertEqual(Event.parse(line: #"{"stage":"error","message":"x"}"#), .error("x"))
    }
    func testParseStage() {
        XCTAssertEqual(Event.parse(line: #"{"stage":"analyzing"}"#), .stage("analyzing"))
    }
    func testParseGarbage() {
        XCTAssertNil(Event.parse(line: "Analyzing..."))
        XCTAssertNil(Event.parse(line: #"{"stage":"weird"}"#))
    }
    func testParseNeedsLogin() {
        XCTAssertEqual(Event.parse(line: #"{"stage":"needs_login","reason":"age","message":"m"}"#),
                       .needsLogin(reason: "age", message: "m"))
        XCTAssertEqual(Event.parse(line: #"{"stage":"needs_login","reason":"bot","message":"m","tried":"brave"}"#),
                       .needsLogin(reason: "bot", message: "m"))
        // the Full Disk Access event is gone
        XCTAssertNil(Event.parse(line: #"{"stage":"needs_access","browser":"brave","message":"m"}"#))
    }
    func testParseNullBpm() {
        let line = #"{"stage":"analyzed","file":"/x/a.mp3","name":"a.mp3","bpm":null,"keys":[]}"#
        guard case .analyzed(let r)? = Event.parse(line: line) else { return XCTFail() }
        XCTAssertNil(r.bpm); XCTAssertTrue(r.keys.isEmpty)
    }
}
