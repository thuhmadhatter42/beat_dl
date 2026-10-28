import XCTest
@testable import Orion

final class FaceplateTests: XCTestCase {
    func testLitNeedsALinkAndIdle() {
        XCTAssertFalse(Faceplate.isLit("", busy: false))
        XCTAssertFalse(Faceplate.isLit("youtube.com/watch?v=x", busy: false))
        XCTAssertTrue(Faceplate.isLit("https://youtu.be/x", busy: false))
        XCTAssertTrue(Faceplate.isLit("  HTTP://youtu.be/x\n", busy: false))
        XCTAssertFalse(Faceplate.isLit("https://youtu.be/x", busy: true))
    }

    func testTempoPeriod() {
        XCTAssertEqual(Faceplate.tempoPeriod("120.0")!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(Faceplate.tempoPeriod("142.0")!, 60 / 142.0, accuracy: 1e-9)
        XCTAssertNil(Faceplate.tempoPeriod(nil))
        XCTAssertNil(Faceplate.tempoPeriod("0"))
        XCTAssertNil(Faceplate.tempoPeriod("-5"))
        XCTAssertNil(Faceplate.tempoPeriod("abc"))
    }

    func testPagerOpensOnLastAndClamps() {
        var p = Pager()
        XCTAssertNil(p.caption)
        p.reset(count: 1)
        XCTAssertNil(p.caption)          // one file: no "1 of N"
        p.reset(count: 3)
        XCTAssertEqual(p.index, 2)
        XCTAssertEqual(p.caption, "3 OF 3")
        p.next()
        XCTAssertEqual(p.index, 2)
        p.previous(); p.previous(); p.previous()
        XCTAssertEqual(p.index, 0)
        XCTAssertEqual(p.caption, "1 OF 3")
        p.reset(count: 0)
        XCTAssertEqual(p.index, 0)
    }

    func testStepsFollowTheStage() {
        let s = Faceplate.steps("analyzing").map { $0.1 }
        XCTAssertEqual(s, [.done, .on, .off])
        XCTAssertEqual(Faceplate.steps("downloading").map { $0.1 }, [.on, .off, .off])
        XCTAssertEqual(Faceplate.steps("renaming").map { $0.1 }, [.done, .done, .on])
    }

    func testErrorAndFileLine() {
        XCTAssertEqual(Faceplate.errorText("That video is private or was removed."),
                       "THAT VIDEO IS PRIVATE OR WAS REMOVED")
        let r = Result(file: URL(fileURLWithPath: "/Users/x/Downloads/a (90.0 BPM Am).mp3"),
                       name: "a (90.0 BPM Am).mp3", bpm: "90.0", keys: [])
        XCTAssertEqual(Faceplate.fileLine(r), "A (90.0 BPM AM).MP3 · DOWNLOADS")
    }

    func testRuntimeRootOverride() {
        let rt = Runtime.appDefault(env: ["ORION_RUNTIME_ROOT": "/tmp/rt"])
        XCTAssertEqual(rt.root.path, "/tmp/rt")
        XCTAssertNotEqual(Runtime.appDefault(env: [:]).root.path, "/tmp/rt")
        XCTAssertEqual(rt.environment(passing: ["ORION_DOWNLOADS": "/tmp/dl"])["ORION_DOWNLOADS"], "/tmp/dl")
        XCTAssertNil(rt.environment(passing: [:])["ORION_DOWNLOADS"])
    }
}
