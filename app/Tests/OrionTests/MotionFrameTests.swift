import AppKit
import Combine
import SwiftUI
import XCTest
@testable import Orion

/// 0.1.50 (J 2026-11-09 04:09: "it needs to be smooth. it has very jerky clicky movements"): the
/// readout is hosted for real (an NSHostingView in an offscreen window, the run loop spinning) and
/// fed two live readings the way LiveController publishes them; frames are captured while it
/// moves. A value that snaps has no frame between the two readings; a value that moves does.
///
/// MOTION_FRAMES_DIR=<dir> also writes every captured frame and a contact sheet there.
final class MotionFrameTests: XCTestCase {

    /// The window's view model stand-in: one published PocketState, replaced whole on each
    /// reading, as PocketState.make hands FaceplateView / PocketContainer a fresh value.
    final class Box: ObservableObject {
        @Published var state: PocketState
        /// Bumped with each new reading (the frame probe animates on it).
        @Published var tick: Double = 0
        /// Listen's level, as LiveController.meter hands it to both surfaces.
        let meter = LiveLevel()
        init(_ s: PocketState) { state = s }
    }

    /// One live meter tick (LiveController.updateLevel, 20 Hz). `whole` = the 0.1.49 path, where
    /// the level was a @Published of the controller and each tick republished the whole state.
    static func tick(_ box: Box, _ n: Int, whole: Bool = false) {
        let v = Float(n % 7) / 7
        if whole { var s = box.state; s.level = v; box.state = s } else { box.meter.value = v }
    }

    /// The real window face (FaceplateView's body hands FaceplateFace the derived state).
    struct WindowReadout: View {
        @ObservedObject var box: Box
        var body: some View {
            ZStack(alignment: .topLeading) {
                FaceplateFace(state: box.state, picked: [], url: .constant(""), fieldFocused: .constant(false),
                              pickFocused: .constant(false))
                // a frame counter beside the face (never inside it): animates with Motion.value
                // whenever a reading lands, and stamps every frame SwiftUI draws for it
                Color.clear.frame(width: 1, height: 1)
                    .modifier(FrameProbe(v: box.tick))
                    .animation(Theme.Motion.value, value: box.tick)
            }
            .environment(\.liveLevel, box.meter)
            .environment(\.colorScheme, .dark)
        }
    }

    /// Records every frame SwiftUI draws for the Motion.value animation: its time and how far the
    /// value has got (SwiftUI sets animatableData for each frame).
    struct FrameProbe: AnimatableModifier {
        static var stamps: [(t: CFTimeInterval, v: Double)] = []
        var v: Double
        var animatableData: Double {
            get { v }
            set { v = newValue; FrameProbe.stamps.append((CACurrentMediaTime(), newValue)) }
        }
        func body(content: Content) -> some View { content }
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

    // Two of J's own live readings from live.log (2026-11-09 04:10:58 -> 04:11:00), with chroma
    // and tuning so the dial arc, the percentages, the bars and Notes Heard all have to move.
    static let chromaA: [Double] = [0.3, 0.05, 0.62, 0.2, 0.08, 0.4, 0.1, 1.0, 0.1, 0.45, 0.85, 0.1]
    static let chromaB: [Double] = [0.7, 0.05, 0.3, 0.55, 0.08, 0.2, 0.1, 0.8, 0.1, 0.25, 1.0, 0.1]
    static func reading(_ keys: [(String, Int)], bpm: String?, cents: Double, chroma: [Double]) -> Result {
        Result(file: LiveSession.placeholderFile, name: "LIVE", bpm: bpm, keys: keys,
               bpmExact: bpm.flatMap(Double.init), tuningCents: cents, chroma: chroma)
    }
    static let a = reading([("Gm", 90), ("Cm", 4), ("C", 1)], bpm: "90.0", cents: -4, chroma: chromaA)
    static let b = reading([("Gm", 52), ("Cm", 30), ("C", 12)], bpm: "91.0", cents: 9, chroma: chromaB)

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
        Theme.flatInsetForCapture = true
    }

    override func tearDown() {
        Theme.Motion.reduceMotionOverride = nil
        Pocket.snapshot = false
        Theme.flatInsetForCapture = false
        super.tearDown()
    }

    // MARK: the harness

    struct Frame { let t: Double; let rep: NSBitmapImageRep }

    static func spin(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.004))) }
    }

    /// The view's layer tree as drawn right now (cacheDisplay(in:to:) asks SwiftUI to redraw
    /// from scratch and comes back blank for the glass; the layers hold what is on screen).
    static func grab(_ v: NSView) -> NSBitmapImageRep {
        let w = Int(v.bounds.width), h = Int(v.bounds.height)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 32)!
        guard let layer = v.layer, let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return rep }
        let cg = ctx.cgContext
        cg.setFillColor(NSColor.black.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if v.isFlipped { cg.translateBy(x: 0, y: CGFloat(h)); cg.scaleBy(x: 1, y: -1) }
        layer.render(in: cg)
        cg.flush()
        return rep
    }

    /// Hosts `view`, shows `from`, lets it settle, then hands it `to` and captures `count` frames
    /// over `seconds`. Returns [settled start] + frames; the last frame is taken after a long settle.
    static func capture<V: View>(_ make: (Box) -> V, from: PocketState, to: PocketState,
                                 count: Int = 12, seconds: Double = 0.6,
                                 level: Bool = false) -> (start: NSBitmapImageRep, frames: [Frame], end: NSBitmapImageRep) {
        let box = Box(from)
        let host = NSHostingView(rootView: make(box))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let win = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: host.frame.width, height: host.frame.height),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.orderFrontRegardless()
        defer { win.orderOut(nil) }
        spin(0.4)
        // the readout before: let the first reading land and anything it started finish
        box.state = from
        spin(0.8)
        let start = grab(host)
        // live meter ticks (LiveController's level, 20 Hz) keep coming while it moves
        var timer: Timer?
        if level {
            var n = 0
            timer = Timer(timeInterval: 1.0 / 20, repeats: true) { _ in
                n += 1
                MotionFrameTests.tick(box, n)
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
        let t0 = Date()
        box.tick += 1
        box.state = to   // LiveController.publish(): a plain @Published set on the main thread
        var frames: [Frame] = []
        for i in 1...count {
            let due = Double(i) * seconds / Double(count)
            // a grab blocks the main thread (~80 ms for the whole face): always let SwiftUI run
            // a few frames between two grabs, or the capture itself freezes the animation
            spin(max(0.03, due - Date().timeIntervalSince(t0)))
            frames.append(Frame(t: Date().timeIntervalSince(t0), rep: grab(host)))
        }
        spin(1.0)
        timer?.invalidate()
        let end = grab(host)
        return (start, frames, end)
    }

    /// Sum of absolute RGB differences over `rect` (in the image's pixels), 0 = identical.
    static func distance(_ x: NSBitmapImageRep, _ y: NSBitmapImageRep, _ rect: NSRect? = nil) -> Double {
        let w = min(x.pixelsWide, y.pixelsWide), h = min(x.pixelsHigh, y.pixelsHigh)
        let r = rect.map { $0.intersection(NSRect(x: 0, y: 0, width: w, height: h)) } ?? NSRect(x: 0, y: 0, width: w, height: h)
        guard let pa = x.bitmapData, let pb = y.bitmapData, x.bitsPerSample == 8, y.bitsPerSample == 8 else { return 0 }
        let sa = x.bitsPerPixel / 8, sb = y.bitsPerPixel / 8
        var d = 0
        for py in Int(r.minY)..<Int(r.maxY) {
            let ra = pa + py * x.bytesPerRow, rb = pb + py * y.bytesPerRow
            for px in Int(r.minX)..<Int(r.maxX) {
                let ia = px * sa, ib = px * sb
                d += abs(Int(ra[ia]) - Int(rb[ib])) + abs(Int(ra[ia + 1]) - Int(rb[ib + 1]))
                    + abs(Int(ra[ia + 2]) - Int(rb[ib + 2]))
            }
        }
        return Double(d)
    }

    /// For each frame, how far from the start toward the end it is (0 = still the start, 1 = the
    /// end): d(start, f) / (d(start, f) + d(f, end)).
    static func progress(_ c: (start: NSBitmapImageRep, frames: [Frame], end: NSBitmapImageRep), _ rect: NSRect? = nil) -> [Double] {
        c.frames.map { f in
            let s = distance(c.start, f.rep, rect), e = distance(f.rep, c.end, rect)
            return s + e == 0 ? 1 : s / (s + e)
        }
    }

    /// Frames strictly between the two readings (neither ~the start nor ~the end).
    static func inBetween(_ p: [Double]) -> Int { p.filter { $0 > 0.03 && $0 < 0.97 }.count }

    static func write(_ c: (start: NSBitmapImageRep, frames: [Frame], end: NSBitmapImageRep), name: String) {
        guard let dir = ProcessInfo.processInfo.environment["MOTION_FRAMES_DIR"] else { return }
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // contact sheet: start, the frames, end, in a grid of 4 columns, each with its time
        let reps = [("start", c.start)] + c.frames.map { (String(format: "%.0f ms", $0.t * 1000), $0.rep) } + [("end", c.end)]
        let w = CGFloat(c.start.pixelsWide), h = CGFloat(c.start.pixelsHigh)
        let cols = 4, rows = (reps.count + cols - 1) / cols, label: CGFloat = 28
        let sheet = NSImage(size: NSSize(width: w * CGFloat(cols), height: (h + label) * CGFloat(rows)))
        sheet.lockFocus()
        NSColor(white: 0.12, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        for (i, (t, rep)) in reps.enumerated() {
            let col = i % cols, row = i / cols
            let y = sheet.size.height - CGFloat(row + 1) * (h + label)
            rep.draw(in: NSRect(x: CGFloat(col) * w, y: y, width: w, height: h))
            (t as NSString).draw(at: NSPoint(x: CGFloat(col) * w + 8, y: y + h + 6),
                                 withAttributes: [.font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.white])
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: out.appendingPathComponent("\(name).png"))
        }
    }

    static func report(_ name: String, _ p: [Double], _ c: (start: NSBitmapImageRep, frames: [Frame], end: NSBitmapImageRep)) -> String {
        let times = c.frames.map { String(format: "%3.0f", $0.t * 1000) }.joined(separator: " ")
        let prog = p.map { String(format: "%.2f", $0) }.joined(separator: " ")
        return "\(name): in-between \(inBetween(p))/\(p.count)\n  t(ms) \(times)\n  prog  \(prog)"
    }

    static func log(_ s: String) {
        print(s)
        if let dir = ProcessInfo.processInfo.environment["MOTION_FRAMES_DIR"] {
            let u = URL(fileURLWithPath: dir).appendingPathComponent("numbers.txt")
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            let line = s + "\n"
            if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
            else { try? line.write(to: u, atomically: true, encoding: .utf8) }
        }
    }

    // MARK: the checks

    /// The window readout, reading -> reading (locked both times): the arc, the percentages, the
    /// bars and Notes Heard move through frames between the two readings.
    @MainActor
    func testWindowReadingToReadingMoves() {
        let c = MotionFrameTests.capture({ WindowReadout(box: $0) },
                                         from: MotionFrameTests.state(.locked(MotionFrameTests.a)),
                                         to: MotionFrameTests.state(.locked(MotionFrameTests.b)), level: true)
        MotionFrameTests.write(c, name: "window-locked-to-locked")
        let p = MotionFrameTests.progress(c)
        MotionFrameTests.log(MotionFrameTests.report("window locked->locked", p, c))
        XCTAssertGreaterThan(MotionFrameTests.distance(c.start, c.end), 0, "the two readings draw the same")
        XCTAssertGreaterThanOrEqual(MotionFrameTests.inBetween(p), 2, "snapped: \(p)")
    }

    /// reading -> locked (the lamp turns green as the numbers change): still moves.
    @MainActor
    func testWindowReadingToLockedMoves() {
        let c = MotionFrameTests.capture({ WindowReadout(box: $0) },
                                         from: MotionFrameTests.state(.reading(MotionFrameTests.a)),
                                         to: MotionFrameTests.state(.locked(MotionFrameTests.b)), level: true)
        MotionFrameTests.write(c, name: "window-reading-to-locked")
        let p = MotionFrameTests.progress(c)
        MotionFrameTests.log(MotionFrameTests.report("window reading->locked", p, c))
        XCTAssertGreaterThanOrEqual(MotionFrameTests.inBetween(p), 2, "snapped: \(p)")
    }

    /// The menu-bar pocket, reading -> reading.
    @MainActor
    func testPocketReadingToReadingMoves() {
        let c = MotionFrameTests.capture({ PocketReadout(box: $0) },
                                         from: MotionFrameTests.state(.locked(MotionFrameTests.a), advanced: false),
                                         to: MotionFrameTests.state(.locked(MotionFrameTests.b), advanced: false), level: true)
        MotionFrameTests.write(c, name: "pocket-locked-to-locked")
        let p = MotionFrameTests.progress(c)
        MotionFrameTests.log(MotionFrameTests.report("pocket locked->locked", p, c))
        XCTAssertGreaterThanOrEqual(MotionFrameTests.inBetween(p), 2, "snapped: \(p)")
    }

    // MARK: no captures: grabbing a frame blocks the main thread itself

    static func host<V: View>(_ v: V) -> (NSHostingView<V>, NSWindow) {
        let host = NSHostingView(rootView: v)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let win = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: host.frame.width, height: host.frame.height),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.orderFrontRegardless()
        return (host, win)
    }

    /// The curve SwiftUI really runs for Motion.value in the window, meter ticking: how far
    /// (0...1) a value has got `ms` after a reading lands, read off the probe's frames.
    static func curve(at ms: [Double]) -> [Double] {
        let box = Box(state(.locked(a)))
        let (_, win) = host(WindowReadout(box: box))
        defer { win.orderOut(nil) }
        spin(1.0)
        var n = 0
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { _ in n += 1; MotionFrameTests.tick(box, n) }
        RunLoop.main.add(timer, forMode: .common)
        spin(0.3)
        FrameProbe.stamps = []
        let t0 = CACurrentMediaTime()
        let base = box.tick
        box.tick += 1
        box.state = state(.locked(b))
        spin(Theme.Motion.valueDuration + 0.2)
        timer.invalidate()
        let st = FrameProbe.stamps
        return ms.map { m in
            let last = st.last { ($0.t - t0) * 1000 <= m }
            return (last?.v ?? base) - base
        }
    }

    /// What one live meter tick costs the main thread, median ms over 40 ticks. whole = the 0.1.49
    /// path (the level a @Published of LiveController: the whole state re-derived and redrawn).
    static func meterTickCost<V: View>(_ make: (Box) -> V, _ s: PocketState, whole: Bool) -> Double {
        let box = Box(s)
        let (host, win) = host(make(box))
        defer { win.orderOut(nil) }
        spin(0.8)
        var ms: [Double] = []
        for i in 0..<40 {
            let t = CACurrentMediaTime()
            tick(box, i + 1, whole: whole)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            CATransaction.flush()
            ms.append((CACurrentMediaTime() - t) * 1000)
            spin(0.01)
        }
        return ms.sorted()[ms.count / 2]
    }

    /// A meter tick redraws the meter, not the face: far cheaper than re-deriving everything.
    @MainActor
    func testMeterTickDoesNotRedrawTheFace() {
        let s = MotionFrameTests.state(.locked(MotionFrameTests.a))
        let ps = MotionFrameTests.state(.locked(MotionFrameTests.a), advanced: false)
        let wOld = MotionFrameTests.meterTickCost({ WindowReadout(box: $0) }, s, whole: true)
        let wNew = MotionFrameTests.meterTickCost({ WindowReadout(box: $0) }, s, whole: false)
        let pOld = MotionFrameTests.meterTickCost({ PocketReadout(box: $0) }, ps, whole: true)
        let pNew = MotionFrameTests.meterTickCost({ PocketReadout(box: $0) }, ps, whole: false)
        MotionFrameTests.log(String(format: "meter tick cost (median): window %.1f ms whole-state -> %.1f ms LiveLevel; pocket %.1f -> %.1f ms",
                                    wOld, wNew, pOld, pNew))
        XCTAssertLessThan(wNew, wOld / 2, "a meter tick still redraws the window face")
        // the pocket was light to begin with (its redraw, not its body, is most of a tick): no worse
        XCTAssertLessThan(pNew, pOld * 1.5 + 1, "a meter tick got dearer in the pocket")
    }

    /// The value curve starts gently (no click) and still lands within the reading's gap.
    @MainActor
    func testValueCurveGlidesInsteadOfClicking() {
        let at: [Double] = [17, 33, 50, 100, 200, 300, 450, 600]
        // every 60 Hz frame from 0 to 600 ms after the shown points: the steepest single-frame step
        let frames = (0...36).map { Double($0) * 1000 / 60 }
        let all = MotionFrameTests.curve(at: at + frames)
        let c = Array(all.prefix(at.count)), f = Array(all.dropFirst(at.count))
        let step = zip(f.dropFirst(), f).map { $0 - $1 }.max() ?? 1
        MotionFrameTests.log("value curve (fraction done at ms " + at.map { String(format: "%.0f", $0) }.joined(separator: "/") + "): "
                             + c.map { String(format: "%.2f", $0) }.joined(separator: " ")
                             + String(format: "; biggest step in one 60 Hz frame %.2f", step))
        XCTAssertLessThan(step, 0.15, "one frame jumps \(step) of the way: reads as a click")
        XCTAssertLessThan(c[2], 0.3, "half the move in the first 50 ms reads as a click")
        XCTAssertGreaterThan(c[4], 0.5, "too slow: not halfway at 200 ms")
        XCTAssertGreaterThan(c[7], 0.97, "not settled by 600 ms")
        // monotonic: never back, never past the target
        XCTAssertEqual(c, c.sorted())
        XCTAssertLessThanOrEqual(c.max() ?? 0, 1.0001)
    }
}
