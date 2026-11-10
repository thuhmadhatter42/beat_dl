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

    func testChoiceOutsideTopThreeGoesFirstAtZero() {
        let c = KeyChoice(file: r.file, name: r.name, pitchClass: 2, minor: false)
        let s = r.respelled(nil, choice: c)
        XCTAssertEqual(s.keys.map { $0.0 }, ["D", "Fm", "Ab"])
        XCTAssertEqual(s.keys.first?.1, 0)
    }

    func testAllKeysAreSpelledLikeAutoTune() {
        XCTAssertEqual(KeyChoice.allKeys.count, 24)
        XCTAssertEqual(Array(KeyChoice.allKeys.prefix(12)), ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"])
        XCTAssertEqual(Array(KeyChoice.allKeys.suffix(12)),
                       ["Cm", "C#m", "Dm", "Ebm", "Em", "Fm", "F#m", "Gm", "G#m", "Am", "Bbm", "Bm"])
        for (i, k) in KeyChoice.allKeys.enumerated() {
            let kc = AutoTuneSend.keyClass(k)
            XCTAssertEqual(kc?.pitchClass, i % 12, k)
            XCTAssertEqual(kc?.minor, i >= 12, k)
        }
    }

    func testChooseRecordsTheReading() {
        let s = SpellingSettings(defaults: UserDefaults(suiteName: "KeyChoiceTests")!)
        s.setManualKey("G#", of: r, from: .topKeys)
        XCTAssertEqual(s.manualKey, KeyChoice(file: r.file, name: r.name, pitchClass: 8, minor: false))
    }
}
