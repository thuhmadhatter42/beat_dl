import AppKit
import SwiftUI
import XCTest
@testable import Orion

/// 0.1.48: live readings move instead of snap (J 2026-11-09: "it's all very clicky"). The shared
/// Motion tokens, the Reduce Motion switch, and the counting-number helper.
final class MotionTests: XCTestCase {

    override func tearDown() {
        Theme.Motion.reduceMotionOverride = nil
        Pocket.snapshot = false
        super.tearDown()
    }

    // MARK: the counting number

    func testInterpolateRunsFromAToB() {
        XCTAssertEqual(NumberTween.interpolate(40, 60, 0), 40)
        XCTAssertEqual(NumberTween.interpolate(40, 60, 1), 60)
        XCTAssertEqual(NumberTween.interpolate(40, 60, 0.5), 50)
        XCTAssertEqual(NumberTween.interpolate(60, 40, 0.25), 55)
        // clamped: an overshooting curve never shows a number past the target
        XCTAssertEqual(NumberTween.interpolate(40, 60, 1.3), 60)
        XCTAssertEqual(NumberTween.interpolate(40, 60, -0.2), 40)
    }

    func testCountingNumberShowsTheNearestWholeNumber() {
        XCTAssertEqual(NumberTween.text(41.6, suffix: "%"), "42%")
        XCTAssertEqual(NumberTween.text(41.4, suffix: "%"), "41%")
        XCTAssertEqual(NumberTween.text(-0.3), "0")          // no "-0"
        XCTAssertEqual(NumberTween.text(.nan, suffix: "%"), "0%")
        XCTAssertEqual(NumberTween.text(.infinity), "0")
        XCTAssertEqual(NumberTween.text(100), "100")
    }

    func testCountingNumberAnimatesItsValue() {
        var m = CountingNumber(value: 64, suffix: "%")
        XCTAssertEqual(m.animatableData, 64)
        // SwiftUI sets animatableData every frame; the shown text follows it
        m.animatableData = NumberTween.interpolate(64, 71, 0.5)
        XCTAssertEqual(m.value, 67.5)
        XCTAssertEqual(NumberTween.text(m.value, suffix: m.suffix), "68%")
    }

    /// Every frame between two readings reads as a whole number on the way, in order, never jumping
    /// past the target (what the percentages do between 64 % and 71 %).
    func testFramesBetweenTwoReadingsCountInOrder() {
        let frames = stride(from: 0.0, through: 1.0, by: 0.1).map { NumberTween.whole(NumberTween.interpolate(64, 71, $0)) }
        XCTAssertEqual(frames.first, 64)
        XCTAssertEqual(frames.last, 71)
        XCTAssertEqual(frames, frames.sorted())
        XCTAssertTrue(frames.allSatisfy { (64...71).contains($0) })
    }

    // MARK: the tokens

    func testTokens() {
        // (the literals are asserted once, in testDurations, through duration(_:reduce:))
        // a swap is quicker than a value move, a hover quicker still; nothing runs past a second
        // reading (readings land about once a second)
        XCTAssertLessThan(Theme.Motion.hoverDuration, Theme.Motion.swapDuration)
        XCTAssertLessThan(Theme.Motion.swapDuration, Theme.Motion.valueDuration)
        XCTAssertLessThan(Theme.Motion.valueDuration, 0.6)
    }

    func testDurations() {
        XCTAssertEqual(Theme.Motion.duration(.value, reduce: false), 0.45)
        XCTAssertEqual(Theme.Motion.duration(.swap, reduce: false), 0.25)
        XCTAssertEqual(Theme.Motion.duration(.hover, reduce: false), 0.12)
    }

    func testReduceMotionKeepsCrossfadesAndDropsMovement() {
        XCTAssertNil(Theme.Motion.duration(.value, reduce: true))      // bars, arcs, numbers jump
        XCTAssertEqual(Theme.Motion.duration(.swap, reduce: true), 0.25) // opacity is not motion
        XCTAssertEqual(Theme.Motion.duration(.hover, reduce: true), 0.12)
        XCTAssertNil(Theme.Motion.animation(.value, reduce: true))
        XCTAssertNotNil(Theme.Motion.animation(.swap, reduce: true))
    }

    func testOffscreenRendersAreInstant() {
        for k in Theme.Motion.Kind.allCases {
            XCTAssertNil(Theme.Motion.duration(k, reduce: false, snapshot: true))
            XCTAssertNil(Theme.Motion.animation(k, reduce: false, snapshot: true))
        }
    }

    func testTheSwitchFollowsReduceMotion() {
        Theme.Motion.reduceMotionOverride = true
        XCTAssertTrue(Theme.Motion.reduceMotion)
        XCTAssertNil(Theme.Motion.value)
        XCTAssertNotNil(Theme.Motion.swap)
        Theme.Motion.reduceMotionOverride = false
        XCTAssertFalse(Theme.Motion.reduceMotion)
        XCTAssertNotNil(Theme.Motion.value)
        XCTAssertEqual(Theme.Motion.value, Theme.Motion.animation(.value, reduce: false))
        // no override = the system setting
        Theme.Motion.reduceMotionOverride = nil
        XCTAssertEqual(Theme.Motion.reduceMotion, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func testSnapshotSwitchesEverythingOff() {
        Theme.Motion.reduceMotionOverride = false
        Pocket.snapshot = true
        XCTAssertNil(Theme.Motion.value)
        XCTAssertNil(Theme.Motion.swap)
        XCTAssertNil(Theme.Motion.hover)
    }

    // MARK: the live modules still draw (two readings, the second a new key)

    @MainActor
    func testLiveModulesRender() throws {
        guard #available(macOS 13.0, *) else { throw XCTSkip("ImageRenderer is macOS 13+") }
        Pocket.snapshot = true
        let a = Result(file: URL(fileURLWithPath: "/x/a.wav"), name: "a.wav", bpm: "120.4",
                       keys: [("Cm", 64), ("Eb", 18), ("Gm", 9)], bpmExact: 120.4, tuningCents: 3,
                       chroma: [1.0, 0.08, 0.42, 0.81, 0.06, 0.37, 0.1, 0.93, 0.62, 0.05, 0.48, 0.12])
        let b = Result(file: a.file, name: a.name, bpm: "121.0", keys: [("Eb", 52), ("Cm", 30)],
                       bpmExact: 121, chroma: Array(repeating: 0.5, count: 12))
        for r in [a, b] {
            var s = PocketState()
            s.advanced = true
            s.readout = .result(r, page: nil, download: false, options: ResultOptions(tuning: Tuning.meter(3, reference: 440)))
            let v = VStack {
                Dial(state: s).frame(width: Dial.side, height: Dial.side)
                BPMNumber(text: r.bpm, whole: Theme.T.heroSize, fraction: Theme.T.keySize)
                KeyStrip(state: s).frame(width: 300)
                HarmonyPanel(state: s).frame(width: HarmonyPanel.width, height: 640)
            }
            .environment(\.colorScheme, .dark)
            let rr = ImageRenderer(content: v)
            XCTAssertNotNil(rr.cgImage, "no image for \(r.keys.first?.0 ?? "-")")
        }
        // a counting number mid-flight draws its whole number
        let mid = ImageRenderer(content: Color.clear.modifier(CountingNumber(value: 67.5, suffix: "%")))
        XCTAssertNotNil(mid.cgImage)
    }
}
