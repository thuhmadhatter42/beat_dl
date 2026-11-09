import AppKit
import SwiftUI
import XCTest
@testable import Orion

/// 0.1.45: the borrowed row on the 7-column grid, hover cards at the mouse, Beat Key Mini (pads,
/// keys, MIDI bytes, held-note bookkeeping) and the TUNING meter.
final class MiniTests: XCTestCase {

    // MARK: the borrowed row on the grid

    func testBorrowedSitsUnderTheDegreeItReplaces() {
        let m = Harmony.borrowedRow("Am", quality: .triad)
        XCTAssertEqual(m.count, 7)
        // I under i, ♭II under ii°, IV under iv, V under v; III VI VII empty
        XCTAssertEqual(m.map { $0?.roman }, ["I", "♭II", nil, "IV", "V", nil, nil])
        let c = Harmony.borrowedRow("C", quality: .triad)
        XCTAssertEqual(c.map { $0?.name }, [nil, nil, "E♭", "Fm", nil, "A♭", "B♭"])
        XCTAssertEqual(Harmony.borrowedRow("nonsense", quality: .triad), [])
        // every borrowed chord placed once, in the grid's left-to-right order
        XCTAssertEqual(Harmony.borrowedByColumn("Am", quality: .triad).map(\.column), [0, 1, 3, 4])
        XCTAssertEqual(Set(Harmony.borrowedByColumn("C", quality: .seventh).map(\.chord.name)),
                       Set(Harmony.borrowed("C", quality: .seventh).map(\.name)))
    }

    // MARK: hover cards at the mouse

    private let card = CGSize(width: 212, height: 60)
    private let surface = CGSize(width: 1000, height: 700)

    func testCardSitsDownRightOfThePointer() {
        let p = CGPoint(x: 300, y: 200)
        let o = HelpTipLogic.cardOrigin(cursor: p, card: card, in: surface)
        XCTAssertEqual(o.x, p.x + HelpTipLogic.cursorOffset.width)
        XCTAssertEqual(o.y, p.y + HelpTipLogic.cursorOffset.height)
        XCTAssertTrue((12...16).contains(HelpTipLogic.cursorOffset.width))
        XCTAssertTrue((12...16).contains(HelpTipLogic.cursorOffset.height))
    }

    func testCardFlipsAtTheEdgesAndStaysInside() {
        let m = HelpTipLogic.margin
        // right edge: flips left of the pointer
        let r = HelpTipLogic.cardOrigin(cursor: CGPoint(x: 950, y: 200), card: card, in: surface)
        XCTAssertLessThan(r.x + card.width, 950)
        // bottom edge: flips above
        let b = HelpTipLogic.cardOrigin(cursor: CGPoint(x: 300, y: 680), card: card, in: surface)
        XCTAssertLessThan(b.y + card.height, 680)
        // every pointer position on a grid: inside the margins, never over the pointer
        for x in stride(from: 0.0, through: 1000.0, by: 25) {
            for y in stride(from: 0.0, through: 700.0, by: 25) {
                let p = CGPoint(x: x, y: y)
                let o = HelpTipLogic.cardOrigin(cursor: p, card: card, in: surface)
                let rect = CGRect(origin: o, size: card)
                XCTAssertGreaterThanOrEqual(o.x, m - 0.001); XCTAssertGreaterThanOrEqual(o.y, m - 0.001)
                XCTAssertLessThanOrEqual(rect.maxX, surface.width - m + 0.001, "\(p)")
                XCTAssertLessThanOrEqual(rect.maxY, surface.height - m + 0.001, "\(p)")
                XCTAssertFalse(rect.intersects(HelpTipLogic.cursorRect(p)), "card covers the pointer at \(p)")
            }
        }
    }

    func testCardInThePocketSizedSurface() {
        // the pocket is 376 wide: a 212 card still never lands on the pointer
        let s = CGSize(width: 376, height: 620)
        for x in stride(from: 0.0, through: 376.0, by: 8) {
            let p = CGPoint(x: x, y: 300)
            let o = HelpTipLogic.cardOrigin(cursor: p, card: card, in: s)
            XCTAssertFalse(CGRect(origin: o, size: card).intersects(HelpTipLogic.cursorRect(p)), "\(p)")
        }
    }

    // MARK: Beat Key Mini: keys, layout

    func testKeyMapping() {
        for (i, k) in ["1", "2", "3", "4", "5", "6", "7"].enumerated() { XCTAssertEqual(MiniKeys.pad(for: k), .diatonic(i)) }
        for (i, k) in ["q", "w", "e", "r"].enumerated() {
            XCTAssertEqual(MiniKeys.pad(for: k), .borrowed(i))
            XCTAssertEqual(MiniKeys.pad(for: k.uppercased()), .borrowed(i), "caps lock / shift still plays")
        }
        for k in ["8", "0", "t", "a", " ", "", "11"] { XCTAssertNil(MiniKeys.pad(for: k)) }
        XCTAssertEqual(MiniKeys.hint(.diatonic(0)), "1")
        XCTAssertEqual(MiniKeys.hint(.borrowed(3)), "R")
    }

    func testLayoutFollowsTheKey() {
        let l = MiniLayout(key: "Am", quality: .triad)
        XCTAssertEqual(l.diatonic.map(\.name), Harmony.diatonic("Am", quality: .triad).map(\.name))
        XCTAssertEqual(l.chord(.diatonic(0))?.name, "Am")
        // Q W E R = the borrowed chords left to right: I, ♭II, IV, V
        XCTAssertEqual([0, 1, 2, 3].map { l.chord(.borrowed($0))?.roman }, ["I", "♭II", "IV", "V"])
        XCTAssertNil(l.chord(.borrowed(4)))
        XCTAssertNil(l.chord(.diatonic(7)))
        XCTAssertEqual(l.borrowedPad(column: 3), .borrowed(2))
        XCTAssertNil(l.borrowedPad(column: 2))
        XCTAssertTrue(MiniLayout(key: nil, quality: .triad).isEmpty)
        XCTAssertNil(MiniLayout(key: nil, quality: .triad).chord(.diatonic(0)))
    }

    // MARK: MIDI bytes

    func testNoteOnOffBytes() {
        XCTAssertEqual(MidiMessage.bytes(.on(60)), [0x90, 60, 100], "note on, channel 1, velocity 100")
        XCTAssertEqual(MidiMessage.bytes(.off(60)), [0x80, 60, 0])
        XCTAssertEqual(MidiMessage.bytes(.on(64), velocity: 127, channel: 9), [0x99, 64, 127])
        XCTAssertEqual(MidiMessage.bytes(.on(200)), [0x90, 127, 100], "notes clamp into 0...127")
        XCTAssertEqual(MidiMessage.bytes(.off(-3)), [0x80, 0, 0])
        XCTAssertEqual(MidiMessage.ump([0x90, 60, 100]), 0x2090_3C64, "UMP type 2, group 0")
        XCTAssertEqual(MidiMessage.ump([0x80, 60, 0]), 0x2080_3C00)
    }

    func testChordBytes() {
        // C minor triad, root position: C3 E♭3 G3
        let cm = Harmony.diatonic("Cm", quality: .triad)[0]
        var h = HeldNotes()
        let on = h.press(.diatonic(0), notes: cm.notes(.root)).map { MidiMessage.bytes($0) }
        XCTAssertEqual(on, [[0x90, 48, 100], [0x90, 51, 100], [0x90, 55, 100]])
        let off = h.release(.diatonic(0)).map { MidiMessage.bytes($0) }
        XCTAssertEqual(off, [[0x80, 48, 0], [0x80, 51, 0], [0x80, 55, 0]])
    }

    // MARK: held-note bookkeeping

    func testEveryNoteOnGetsOneNoteOff() {
        var h = HeldNotes()
        // C (48 52 55) and Am (57 60 64) share nothing; C and Em (52 55 59) share E and G
        XCTAssertEqual(h.press(.diatonic(0), notes: [48, 52, 55]), [.on(48), .on(52), .on(55)])
        XCTAssertEqual(h.press(.diatonic(2), notes: [52, 55, 59]), [.on(59)], "shared notes are already sounding")
        XCTAssertEqual(h.release(.diatonic(0)), [.off(48)], "E and G still held by the other pad")
        XCTAssertEqual(h.sounding, [52, 55, 59])
        XCTAssertEqual(h.release(.diatonic(2)), [.off(52), .off(55), .off(59)])
        XCTAssertTrue(h.isEmpty)
        XCTAssertEqual(h.release(.diatonic(2)), [], "a second release sends nothing")
    }

    func testAllNotesOff() {
        var h = HeldNotes()
        _ = h.press(.diatonic(0), notes: [48, 52, 55])
        _ = h.press(.borrowed(1), notes: [49, 53, 56])
        XCTAssertEqual(h.allOff(), [48, 49, 52, 53, 55, 56].map { NoteEvent.off($0) })
        XCTAssertTrue(h.isEmpty)
        XCTAssertEqual(h.allOff(), [], "nothing left to stop")
        // pressing a held pad again restarts it without leaking a note
        XCTAssertEqual(h.press(.diatonic(0), notes: [48, 52, 55]), [.on(48), .on(52), .on(55)])
        XCTAssertEqual(h.press(.diatonic(0), notes: [48, 52, 55]), [.off(48), .off(52), .off(55), .on(48), .on(52), .on(55)])
        XCTAssertEqual(h.allOff().count, 3)
    }

    func testEventsBalance() {
        // random presses and releases: ons and offs always pair up per note
        var h = HeldNotes()
        var g = SystemRandomNumberGenerator()
        var level: [Int: Int] = [:]
        func apply(_ es: [NoteEvent]) {
            for e in es {
                switch e {
                case .on(let n): level[n, default: 0] += 1; XCTAssertEqual(level[n], 1, "double note-on \(n)")
                case .off(let n): level[n, default: 0] -= 1; XCTAssertEqual(level[n], 0, "stray note-off \(n)")
                }
            }
        }
        let chords = Harmony.diatonic("Eb", quality: .ninth).map { $0.notes(.open) }
        for _ in 0..<500 {
            let i = Int.random(in: 0..<7, using: &g)
            if Bool.random(using: &g) { apply(h.press(.diatonic(i), notes: chords[i])) } else { apply(h.release(.diatonic(i))) }
        }
        apply(h.allOff())
        XCTAssertTrue(level.values.allSatisfy { $0 == 0 })
    }

    func testSoundDefaultsOffAndPersists() {
        let name = "mini-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        let a = MiniController(defaults: d)
        XCTAssertFalse(a.view.sound, "MIDI is the point: the built-in piano starts off")
        a.toggleSound()
        XCTAssertTrue(d.bool(forKey: MiniController.soundKey))
        XCTAssertTrue(MiniController(defaults: d).view.sound)
        a.toggleSound()
        XCTAssertFalse(MiniController(defaults: d).view.sound)
    }

    func testMiniHelpLines() {
        XCTAssertTrue(HelpText.all.contains(HelpText.mini))
        XCTAssertTrue(HelpText.all.contains(HelpText.miniPanel))
        XCTAssertTrue(HelpText.all.contains(HelpText.miniSound))
        XCTAssertTrue(HelpText.miniPanel.body.contains("1-7"))
        XCTAssertTrue(HelpText.miniPanel.body.contains("Q W E R"))
        XCTAssertEqual(HelpText.problems(), [])
    }

    // MARK: the TUNING meter

    func testMeterMarkerPosition() {
        XCTAssertEqual(TuningMeter.fraction(0), 0.5)
        XCTAssertEqual(TuningMeter.fraction(-50), 0)
        XCTAssertEqual(TuningMeter.fraction(50), 1)
        XCTAssertEqual(TuningMeter.fraction(25), 0.75)
        XCTAssertEqual(TuningMeter.fraction(-80), 0, "clamped at −50")
        XCTAssertEqual(TuningMeter.fraction(120), 1, "clamped at +50")
        XCTAssertEqual(TuningMeter.fraction(.nan), 0.5)
        // the marker stays on the track at both ends
        XCTAssertEqual(TuningMeterRow.markerX(0, width: 100), 0)
        XCTAssertEqual(TuningMeterRow.markerX(1, width: 100), 100 - TuningMeterRow.markerWidth)
        XCTAssertEqual(TuningMeterRow.markerX(0.5, width: 100), 50 - TuningMeterRow.markerWidth / 2)
    }

    func testMeterText() {
        XCTAssertEqual(TuningMeter(cents: 0.1, reference: 440).text, "+0.1 ct  A4 = 440.0 Hz")
        XCTAssertEqual(TuningMeter(cents: 12, reference: 440).text, "+12.0 ct  A4 = 443.1 Hz")
        XCTAssertEqual(TuningMeter(cents: -30, reference: 440).text, "−30.0 ct  A4 = 432.4 Hz")
        XCTAssertEqual(TuningMeter(cents: 0, reference: 432).text, "0.0 ct  A4 = 432.0 Hz")
        XCTAssertEqual(TuningMeter(cents: -0.04, reference: 440).text, "0.0 ct  A4 = 440.0 Hz", "no −0.0")
        XCTAssertEqual(TuningMeter.concertHz(cents: 100, reference: 440), 440 * pow(2, 1.0 / 12), accuracy: 1e-9)
    }

    func testMeterGreenThreshold() {
        XCTAssertTrue(TuningMeter.inTune(0))
        XCTAssertTrue(TuningMeter.inTune(5))
        XCTAssertTrue(TuningMeter.inTune(-5))
        XCTAssertFalse(TuningMeter.inTune(5.1))
        XCTAssertFalse(TuningMeter.inTune(-12))
    }

    func testMeterFromTheReading() {
        XCTAssertNil(Tuning.meter(nil, reference: 440))
        let m = Tuning.meter(12, reference: 440)
        XCTAssertEqual(m?.cents ?? 0, 12, accuracy: 1e-9)
        // the reference moves the offset: a track at +12 against 440 sits about −27 against 444
        XCTAssertEqual(Tuning.meter(12, reference: 444)?.cents ?? 0, 12 - 1200 * log2(444.0 / 440), accuracy: 1e-9)
        // and the concert pitch is the same either way
        XCTAssertEqual(Tuning.meter(12, reference: 444)!.concertHz, Tuning.meter(12, reference: 440)!.concertHz, accuracy: 1e-9)
    }

    // MARK: offscreen renders (ORION_SNAPSHOT_DIR=<dir> swift test --filter MiniTests/testRender)

    @MainActor
    func testRenderMini() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORION_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ORION_SNAPSHOT_DIR to write the Mini PNGs")
        }
        guard #available(macOS 13.0, *) else { throw XCTSkip("ImageRenderer is macOS 13+") }
        Pocket.snapshot = true
        defer { Pocket.snapshot = false }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func write<V: View>(_ v: V, _ name: String) throws {
            let rr = ImageRenderer(content: v.environment(\.colorScheme, .dark))
            rr.scale = 2
            guard let cg = rr.cgImage else { return XCTFail("no image for \(name)") }
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
            try png.write(to: out.appendingPathComponent("\(name).png"))
        }
        let cm = MiniViewState(key: "Cm", layout: MiniLayout(key: "Cm", quality: .seventh))
        var held = cm
        held.lit = [.diatonic(3), .borrowed(2)]
        held.sound = true
        let major = MiniViewState(key: "Eb", layout: MiniLayout(key: "Eb", quality: .triad))
        var failed = MiniViewState(key: nil, layout: MiniLayout(key: nil, quality: .triad))
        failed.midiReady = false
        try write(MiniView(state: cm), "mini-cminor")
        try write(MiniView(state: held), "mini-held")
        try write(MiniView(state: major), "mini-major")
        try write(MiniView(state: failed), "mini-nokey-midi-off")
        var help = cm
        help.help = true
        try write(MiniView(state: help).environment(\.helpTipForced, HelpText.miniPanel.id), "mini-help")
    }
}
