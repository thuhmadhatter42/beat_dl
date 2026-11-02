import XCTest
@testable import Orion

final class MenuBarTests: XCTestCase {
    func result(bpm: String? = "128.0", exact: Double? = 128.04,
                keys: [(String, Int)] = [("Ebm", 85), ("Gb", 8), ("Bbm", 4)]) -> Result {
        Result(file: URL(fileURLWithPath: "/x/a.wav"), name: "a.wav", bpm: bpm, keys: keys, bpmExact: exact)
    }

    // MARK: 2.1 readout

    func testKeyThenWholeBpm() {
        let r = MenuBarReadout.of(result())
        XCTAssertEqual(r.text, "Ebm 128.0")
        XCTAssertEqual(r.lamp, .locked)
        XCTAssertEqual(r.detail, "Key Ebm · 128.04 BPM · Locked 85%")
    }

    func testUnsureLampAndFactor() {
        let r = MenuBarReadout.of(result(keys: [("Cm", 41), ("Eb", 22), ("Gm", 18)]), factor: .half)
        XCTAssertEqual(r.text, "Cm 64.0")
        XCTAssertEqual(r.lamp, .unsure)
    }

    func testMissingPieces() {
        XCTAssertEqual(MenuBarReadout.of(result(bpm: nil, exact: nil)).text, "Ebm")
        XCTAssertEqual(MenuBarReadout.of(result(keys: [])).text, "128.0")
        XCTAssertNil(MenuBarReadout.of(result(keys: [])).lamp)
        XCTAssertNil(MenuBarReadout.of(result(bpm: nil, exact: nil, keys: [])).text)
    }

    func testFollowsEngineState() {
        XCTAssertEqual(MenuBarReadout.of(.idle, page: 0, factor: .one), .idle)
        XCTAssertEqual(MenuBarReadout.of(.done(result()), page: 0, factor: .one).text, "Ebm 128.0")
        let two = [result(), result(bpm: "90.0", exact: nil, keys: [("Am", 80)])]
        XCTAssertEqual(MenuBarReadout.of(.analyzed(two), page: 1, factor: .one).text, "Am 90.0")
        XCTAssertEqual(MenuBarReadout.of(.analyzed(two), page: 9, factor: .one).text, "Am 90.0")   // clamped
        let w = MenuBarReadout.of(.working(stage: "analyzing"), page: 0, factor: .one)
        XCTAssertEqual(w.lamp, .listening)
        XCTAssertEqual(MenuBarReadout.of(.failed("x"), page: 0, factor: .one), .idle)
    }

    func testAccessibilityLabelSaysTheState() {
        XCTAssertEqual(MenuBarReadout.of(result()).accessibilityLabel, "Beat Key: Key Ebm · 128.04 BPM · Locked 85%, locked")
    }

    func testLampFromKeys() {
        XCTAssertEqual(Lamp.of([("Cm", 70)]), .locked)
        XCTAssertEqual(Lamp.of([("Cm", 69)]), .unsure)
        XCTAssertNil(Lamp.of([]))
    }

    func testMenuBarImageExistsForEveryLamp() {
        for l in [Lamp.locked, .unsure, .listening] {
            XCTAssertNotNil(MenuBarImage.make(l))
        }
    }
}
