import XCTest
@testable import Orion

final class WavesTuneSendTests: XCTestCase {
    func testEbMinorPreset() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wt-\(UUID()).xps")
        XCTAssertTrue(WavesTuneSend.write(key: "Ebm", to: url))
        let x = try XMLDocument(contentsOf: url)
        XCTAssertEqual(try x.nodes(forXPath: "//Scale/@Name").first?.stringValue, "Natural Minor")
        XCTAssertEqual(try x.nodes(forXPath: "//Root").first?.stringValue, "3")
        let st = try x.nodes(forXPath: "//NoteStatus").map { $0.stringValue ?? "" }
        XCTAssertEqual(st, ["0", "x", "0", "0", "x", "0", "x", "0", "0", "x", "0", "x"])   // root-relative natural minor
        let params = try x.nodes(forXPath: "//Parameters").first?.stringValue ?? ""
        XCTAssertEqual(params.split(separator: " ").filter { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "R" }.count, 83)
        XCTAssertEqual(try x.nodes(forXPath: "//Preset/@Name").first?.stringValue, "Beat Key - Ebm")
    }

    func testMajor() throws {
        let s = WavesTuneSend.contents(pitchClass: 7, minor: false, keyName: "G")
        XCTAssertTrue(s.contains("<Scale Name=\"Major\">"))
        XCTAssertTrue(s.contains("<Root>7</Root>"))
    }
}
