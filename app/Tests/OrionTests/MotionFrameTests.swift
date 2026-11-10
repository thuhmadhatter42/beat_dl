import AppKit
import Combine
import SwiftUI
import XCTest
@testable import Orion

/// 0.1.50 (J 2026-11-09 04:09: "it needs to be smooth. it has very jerky clicky movements").
/// Two separate facts, each proved without a clock:
///   1. the CURVE (how far a value has got t ms after a reading lands) is a pure function,
///      `Theme.Motion.valueProgress(elapsed:)`, sampled here at fixed times;
///   2. the VIEWS attach that motion: hosting the real window face / menu-bar pocket resolves
///      `Theme.Motion.value` (bars, arc, counting numbers) and `.swap` (key crossfades).
/// Earlier versions grabbed rendered frames on a wall-clock schedule (80 ms per grab against a
/// 450 ms animation) and failed under load with no bug; see git history.
final class MotionFrameTests: XCTestCase {

    /// The window's view model stand-in: one published PocketState, as PocketState.make hands
    /// FaceplateView / PocketContainer a fresh value.
    final class Box: ObservableObject {
        @Published var state: PocketState
        /// Listen's level, as LiveController.meter hands it to both surfaces.
        let meter = LiveLevel()
        init(_ s: PocketState) { state = s }
    }

    /// The real window face (FaceplateView's body hands FaceplateFace the derived state).
    struct WindowReadout: View {
        @ObservedObject var box: Box
        var body: some View {
            FaceplateFace(state: box.state, picked: [], url: .constant(""), fieldFocused: .constant(false),
                          pickFocused: .constant(false))
                .environment(\.liveLevel, box.meter)
                .environment(\.colorScheme, .dark)
        }
    }

    struct PocketReadout: View {
        @ObservedObject var box: Box
        var body: some View {
            PocketView(state: box.state, url: .constant(""))
                .background(Color.black)
                .environment(\.liveLevel, box.meter)
                .environment(\.colorScheme, .dark)
        }
    }

    // A live reading from J's own live.log (2026-11-09 04:10:58), with chroma and tuning so the
    // dial arc, the percentages, the bars and Notes Heard are all on the face.
    static let chromaA: [Double] = [0.3, 0.05, 0.62, 0.2, 0.08, 0.4, 0.1, 1.0, 0.1, 0.45, 0.85, 0.1]
    static func reading(_ keys: [(String, Int)], bpm: String?, cents: Double, chroma: [Double]) -> Result {
        Result(file: LiveSession.songFile(1), name: "LIVE", bpm: bpm, keys: keys,
               bpmExact: bpm.flatMap(Double.init), tuningCents: cents, chroma: chroma)
    }
    static let a = reading([("Gm", 90), ("Cm", 4), ("C", 1)], bpm: "90.0", cents: -4, chroma: chromaA)

    /// The state both surfaces draw for a live state: the same derivation PocketState.make runs.
    static func state(_ live: LiveState, advanced: Bool = true) -> PocketState {
        var s = PocketState()
        s.readout = Faceplate.readout(.idle, live: live, liveSource: "System Audio", page: Pager(), factor: .one,
                                      lastAction: .download, note: nil, reference: 440, onCycleTempo: {})
        s.listening = live.isActive
        s.source = "System Audio"
        s.advanced = advanced
        return s
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        Pocket.snapshot = false
        Theme.Motion.reduceMotionOverride = false
    }

    override func tearDown() {
        Theme.Motion.onResolve = nil
        Theme.Motion.reduceMotionOverride = nil
        Pocket.snapshot = false
        super.tearDown()
    }

    // MARK: the curve: a pure function of elapsed time

    /// The value curve starts gently (no click) and still lands within the reading's gap.
    func testValueCurveGlidesInsteadOfClicking() {
        let p = Theme.Motion.valueProgress(elapsed:)
        XCTAssertEqual(p(-1), 0)
        XCTAssertEqual(p(0), 0)
        XCTAssertLessThan(p(0.050), 0.3, "half the move in the first 50 ms reads as a click")
        XCTAssertGreaterThan(p(0.200), 0.5, "too slow: not halfway at 200 ms")
        XCTAssertGreaterThan(p(0.600), 0.97, "not settled by 600 ms")
        // every 60 Hz frame from 0 to 600 ms: never back, never past the target, and no single
        // frame covers 15 % or more of the move
        let frames = (0...36).map { p(Double($0) / 60) }
        XCTAssertEqual(frames, frames.sorted())
        XCTAssertLessThanOrEqual(frames.max() ?? 0, 1.0)
        let step = zip(frames.dropFirst(), frames).map { $0 - $1 }.max() ?? 1
        XCTAssertLessThan(step, 0.15, "one frame jumps \(step) of the way: reads as a click")
    }

    /// The curve is the one the views are given: Motion.value is a critically damped spring with
    /// the same response, and about 98 % of the move is done at valueDuration.
    func testValueCurveIsTheSpringTheViewsGet() {
        XCTAssertEqual(Theme.Motion.value,
                       .spring(response: Theme.Motion.valueDuration, dampingFraction: 1, blendDuration: 0))
        XCTAssertEqual(Theme.Motion.valueDamping, 1)
        XCTAssertGreaterThan(Theme.Motion.valueProgress(elapsed: Theme.Motion.valueDuration), 0.98)
        XCTAssertLessThan(Theme.Motion.valueProgress(elapsed: Theme.Motion.valueDuration), 1)
    }

    // MARK: the views: they attach the motion tokens

    /// Hosts `view` and returns which motion tokens its body asked for while laid out.
    @MainActor
    static func motionKinds<V: View>(_ view: V) -> Set<Theme.Motion.Kind> {
        var seen = Set<Theme.Motion.Kind>()
        Theme.Motion.onResolve = { seen.insert($0) }
        defer { Theme.Motion.onResolve = nil }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: host.frame.size),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        defer { win.contentView = nil }
        host.layoutSubtreeIfNeeded()
        // the body runs on layout; if SwiftUI defers it, wait for the tokens (a condition, not a duration)
        let deadline = Date().addingTimeInterval(30)
        while !(seen.contains(.value) && seen.contains(.swap)) && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return seen
    }

    /// The window readout moves its values (Motion.value) and crossfades its names (Motion.swap).
    @MainActor
    func testWindowReadoutAttachesValueAndSwapMotion() {
        let box = Box(MotionFrameTests.state(.locked(MotionFrameTests.a)))
        let kinds = MotionFrameTests.motionKinds(WindowReadout(box: box))
        XCTAssertTrue(kinds.contains(.value), "the window readout does not animate its values")
        XCTAssertTrue(kinds.contains(.swap), "the window readout does not crossfade its names")
    }

    /// The menu-bar pocket likewise.
    @MainActor
    func testPocketReadoutAttachesValueAndSwapMotion() {
        let box = Box(MotionFrameTests.state(.locked(MotionFrameTests.a), advanced: false))
        let kinds = MotionFrameTests.motionKinds(PocketReadout(box: box))
        XCTAssertTrue(kinds.contains(.value), "the pocket does not animate its values")
        XCTAssertTrue(kinds.contains(.swap), "the pocket does not crossfade its names")
    }
}
