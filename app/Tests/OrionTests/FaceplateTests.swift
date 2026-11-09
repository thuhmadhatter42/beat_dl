import AppKit
import XCTest
@testable import Orion

final class FaceplateTests: XCTestCase {
    // design pass 2026-11-09 (F1, F2, F4, F5): a small set of intentional tokens
    func testDesignTokensStayASmallReadableSet() {
        XCTAssertLessThanOrEqual(Theme.T.all.count, 7)
        XCTAssertEqual(Set(Theme.T.all).count, Theme.T.all.count)
        XCTAssertGreaterThanOrEqual(Theme.T.all.min()!, 10)            // nothing under the macOS floor
        XCTAssertEqual(Theme.T.all, Theme.T.all.sorted(by: >))
        XCTAssertEqual(Theme.A.alphas.count, 5)
        XCTAssertGreaterThanOrEqual(Theme.A.alphas[2], 0.6)            // A3, the floor for any text
        XCTAssertEqual(Theme.A.alphas, Theme.A.alphas.sorted(by: >))
        XCTAssertEqual([Theme.H.lg, Theme.H.md, Theme.H.sm, Theme.H.xs], [36, 28, 20, 16])
        XCTAssertEqual([Theme.R.plate, Theme.R.well, Theme.R.cap], [12, 6, 3])
        for s in [Theme.S.xs, Theme.S.s, Theme.S.m, Theme.S.l, Theme.S.xl, Theme.S.xxl] {
            XCTAssertEqual(s.truncatingRemainder(dividingBy: 4), 0)    // the 4/8 grid
        }
        // the send row lines up with the cap column above it
        XCTAssertEqual(FaceplateView.sendWidth * 2 + FaceplateView.gridGap * 2 + FaceplateView.capWidth,
                       FaceplateView.moduleWidth)
    }

    // J 2026-11-09: the narrower left column stays on the grid and its legends fit at full size
    func testNarrowModuleStaysOnTheGridAndFits() {
        for v in [FaceplateView.moduleWidth, FaceplateView.plateWidth(advanced: false),
                  FaceplateView.size.width, FaceplateView.size.height, FaceplateView.keyboardHeight,
                  FaceplateView.sendWidth, FaceplateView.capWidth, ResultReadout.bpmWidth] {
            XCTAssertEqual(v.truncatingRemainder(dividingBy: 4), 0, "\(v) is off the 4/8 grid")
        }
        let label = NSFont(name: "HelveticaNeue-Bold", size: Theme.T.labelSize)!
        func width(_ s: String) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: label, .kern: Theme.T.labelTracking]).width
        }
        for s in ["SEND TO PRO TOOLS", "SEND TO AUTO-TUNE", "SEND TO LOGIC PRO"] {
            XCTAssertLessThanOrEqual(width(s), FaceplateView.sendWidth - FaceplateView.sendPadding * 2, s)
        }
        XCTAssertLessThanOrEqual(width("PASTE + DOWNLOAD"), FaceplateView.capWidth - SSLCapStyle.sidePadding * 2)
        // the keyboard: taller for its width than the 456 x 84 it was
        let keys = FaceplateView.moduleWidth - Theme.S.lcd * 2
        XCTAssertLessThan(keys / FaceplateView.keyboardHeight, 456.0 / 84.0)
    }

    // J 2026-11-09: "put that line in the middle of the tuning in the center" (of the panel)
    func testTuningTrackCentreIsThePanelCentre() {
        let strip = FaceplateView.moduleWidth - Theme.S.lcd * 2       // the window's LCD inside its padding
        let l = TuningMeterRow.layout(width: strip)
        // the glass pads both sides alike, so the strip's centre is the panel's centre
        XCTAssertEqual(Theme.S.lcd + l.trackCentre, FaceplateView.moduleWidth / 2)
        XCTAssertEqual(l.trackCentre, strip / 2)
        XCTAssertGreaterThan(l.trackWidth, 160)
        for w: CGFloat in [strip, 312, 344, 401] {                     // the pocket's strip too
            let m = TuningMeterRow.layout(width: w)
            XCTAssertEqual(m.trackCentre, w / 2, "width \(w)")
            XCTAssertGreaterThanOrEqual(m.labelRight, TuningMeterRow.labelWidth)   // TUNING fits on the left
            XCTAssertLessThanOrEqual(m.textX + TuningMeterRow.textWidth, w)       // the reading on the right
            XCTAssertEqual(m.trackX - m.labelRight, TuningMeterRow.gap)
            XCTAssertEqual(m.textX - (m.trackX + m.trackWidth), TuningMeterRow.gap)
        }
        // the reserved widths hold the widest reading and the label
        let caption = NSFont(name: "HelveticaNeue-Medium", size: Theme.T.captionSize)!
        let reading = TuningMeter(cents: -49.96, reference: 445).text
        XCTAssertLessThanOrEqual((reading as NSString).size(withAttributes: [.font: caption]).width,
                                 TuningMeterRow.textWidth, reading)
        XCTAssertLessThanOrEqual(("TUNING" as NSString).size(withAttributes: [.font: caption, .kern: Theme.T.captionTracking]).width,
                                 TuningMeterRow.labelWidth)
    }

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
        // your file in its own case (design pass F6), not a tracked caps label
        XCTAssertEqual(Faceplate.fileLine(r), "a (90.0 BPM Am).mp3 · Downloads")
        XCTAssertEqual(Faceplate.fileParts(r).name, "a (90.0 BPM Am).mp3")
        XCTAssertEqual(Faceplate.fileParts(r).folder, "Downloads")
    }

    func testDropKeepsOnlyAudioFiles() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("orion-drop-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let names = ["a.wav", "b.pdf", "c.MP3", "d.aiff", "e.txt", "f.opus"]
        for n in names { fm.createFile(atPath: dir.appendingPathComponent(n).path, contents: Data([0])) }
        let folder = dir.appendingPathComponent("beats.wav")      // a folder named like audio
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let missing = dir.appendingPathComponent("gone.mp3")
        let input = names.map { dir.appendingPathComponent($0) } + [folder, missing,
                    URL(string: "https://example.com/x.mp3")!]
        let kept = Faceplate.audioFiles(input).map { $0.lastPathComponent }
        XCTAssertEqual(kept, ["a.wav", "c.MP3", "d.aiff", "f.opus"])   // opus via UTType .audio
        XCTAssertEqual(Faceplate.audioFiles([folder, dir.appendingPathComponent("b.pdf")]), [])
    }

    func testDropAcceptsEveryContainerBeatKeyReads() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("orion-formats-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let names = ["a.flac", "b.OGG", "c.caf", "d.m4a", "e.aac", "f.mp4", "g.m4v", "h.MOV", "i.mid", "j.midi",
                     "k.mp3", "l.wav", "m.aif", "n.aiff", "o.mkv", "p.zip", "q.png"]
        for n in names { fm.createFile(atPath: dir.appendingPathComponent(n).path, contents: Data([0])) }
        let kept = Faceplate.audioFiles(names.map { dir.appendingPathComponent($0) }).map { $0.lastPathComponent }
        XCTAssertEqual(kept, Array(names.prefix(14)))
    }

    func testTextureBundleCandidatesNeverNeedBundleModule() {
        let c = Textures.bundleCandidates()
        XCTAssertFalse(c.isEmpty)
        XCTAssertTrue(c.allSatisfy { $0.lastPathComponent == "Orion_Orion.bundle" })
    }

    func testRuntimeRootOverride() {
        let rt = Runtime.appDefault(env: ["ORION_RUNTIME_ROOT": "/tmp/rt"])
        XCTAssertEqual(rt.root.path, "/tmp/rt")
        XCTAssertNotEqual(Runtime.appDefault(env: [:]).root.path, "/tmp/rt")
        XCTAssertEqual(rt.environment(passing: ["ORION_DOWNLOADS": "/tmp/dl"])["ORION_DOWNLOADS"], "/tmp/dl")
        XCTAssertNil(rt.environment(passing: [:])["ORION_DOWNLOADS"])
    }
}
