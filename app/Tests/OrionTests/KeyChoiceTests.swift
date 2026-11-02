import XCTest
@testable import Orion

final class KeyChoiceTests: XCTestCase {
    let r = Result(file: URL(fileURLWithPath: "/tmp/beat.mp3"), name: "beat", bpm: "140",
                   keys: [("Fm", 60), ("Ab", 25), ("Cm", 10)])

    func testChosenKeyMovesToFront() {
        let c = KeyChoice(file: r.file, name: r.name, pitchClass: 8, minor: false)
        let s = r.respelled(nil, choice: c)
        XCTAssertEqual(s.keys.map { $0.0 }, ["Ab", "Fm", "Cm"])
        XCTAssertEqual(s.keys.map { $0.1 }, [25, 60, 10])            // percentages travel with the key
    }

    func testChoiceSurvivesRespelling() {
        let c = KeyChoice(file: r.file, name: r.name, pitchClass: 8, minor: false)
        XCTAssertEqual(r.respelled(.sharps, choice: c).keys.first?.0, "G#")
    }

    func testChoiceForAnotherReadingIsIgnored() {
        let c = KeyChoice(file: URL(fileURLWithPath: "/tmp/other.mp3"), name: "other", pitchClass: 8, minor: false)
        XCTAssertEqual(r.respelled(nil, choice: c).keys.first?.0, "Fm")
    }

    func testChoiceNotInTopThreeIsIgnored() {
        let c = KeyChoice(file: r.file, name: r.name, pitchClass: 2, minor: false)
        XCTAssertEqual(r.respelled(nil, choice: c).keys.map { $0.0 }, ["Fm", "Ab", "Cm"])
    }

    func testChooseRecordsTheReading() {
        let s = SpellingSettings(defaults: UserDefaults(suiteName: "KeyChoiceTests")!)
        s.choose("G#", of: r)
        XCTAssertEqual(s.chosen, KeyChoice(file: r.file, name: r.name, pitchClass: 8, minor: false))
    }
}
