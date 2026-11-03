import XCTest
@testable import Orion

final class ReadingTests: XCTestCase {
    func result(_ name: String = "a.wav", bpm: String? = "140.0", exact: Double? = 140.82,
                keys: [(String, Int)] = [("Cm", 85), ("Eb", 8), ("Gm", 4)], tuning: Double? = nil) -> Result {
        Result(file: URL(fileURLWithPath: "/Users/x/\(name)"), name: name, bpm: bpm, keys: keys,
               bpmExact: exact, tuningCents: tuning)
    }
    func defaults() -> UserDefaults {
        let name = "orion-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    // MARK: 1.1 decimal BPM

    func testEventCarriesDecimalBpmAndTuning() {
        let line = #"{"stage":"analyzed","file":"/x/a.wav","name":"a.wav","bpm":"140.0","keys":[["Cm",80]],"bpm_exact":140.82,"tuning_cents":-12.0}"#
        guard case .analyzed(let r)? = Event.parse(line: line) else { return XCTFail() }
        XCTAssertEqual(r.bpm, "140.0")
        XCTAssertEqual(r.bpmExact, 140.82)
        XCTAssertEqual(r.tuningCents, -12.0)
    }

    func testOldEventsStillParse() {
        let line = #"{"stage":"done","file":"/x/a.mp3","name":"a.mp3","bpm":"90.0","keys":[["Am",50]]}"#
        guard case .done(let r)? = Event.parse(line: line) else { return XCTFail() }
        XCTAssertNil(r.bpmExact); XCTAssertNil(r.tuningCents)
    }

    func testTempoTextShowsDecimalWhenMeasured() {
        XCTAssertEqual(Tempo.text(result()), "140.82")
        XCTAssertEqual(Tempo.text(result(exact: nil)), "140.0")     // the analyzer's own text, untouched
        XCTAssertNil(Tempo.text(result(bpm: nil, exact: nil)))
        XCTAssertEqual(Tempo.rounded(result()), "141")
        XCTAssertNil(Tempo.rounded(result(exact: nil)))             // nothing decimal to put it beside
    }

    // MARK: 1.2 half / double

    func testClickCyclesOneDoubleHalf() {
        var f = TempoFactor.one
        f = f.next; XCTAssertEqual(f, .double)
        f = f.next; XCTAssertEqual(f, .half)
        f = f.next; XCTAssertEqual(f, .one)
        XCTAssertNil(TempoFactor.one.label)
        XCTAssertEqual(TempoFactor.double.label, "×2")
        XCTAssertEqual(TempoFactor.half.label, "×0.5")
    }

    func testFactorScalesTheTempo() {
        XCTAssertEqual(Tempo.text(result(), factor: .double), "281.64")
        XCTAssertEqual(Tempo.text(result(), factor: .half), "70.41")
        XCTAssertEqual(Tempo.text(result(exact: nil), factor: .double), "280.0")
        XCTAssertEqual(Tempo.text(result(exact: nil), factor: .half), "70.0")
        XCTAssertEqual(Tempo.rounded(result(), factor: .double), "282")
        // the TEMPO light follows the shown tempo
        XCTAssertEqual(Faceplate.tempoPeriod(Tempo.text(result(), factor: .double))!, 60 / 281.64, accuracy: 1e-9)
    }

    // MARK: 1.3 tuning

    func testOffsetAgainstReference() {
        XCTAssertEqual(Tuning.offset(trackCents: 0, reference: 440), 0, accuracy: 1e-9)
        XCTAssertEqual(Tuning.offset(trackCents: -31.77, reference: 432), 0, accuracy: 0.05)   // a 432 track
        XCTAssertEqual(Tuning.offset(trackCents: 20, reference: 440), 20, accuracy: 1e-9)
        XCTAssertEqual(Tuning.offset(trackCents: 20, reference: 442), 20 - 7.85, accuracy: 0.05)
        // folded to the nearest semitone grid: -30 against 450 (+39) is +31, not -69
        XCTAssertEqual(Tuning.offset(trackCents: -30, reference: 450), 31.1, accuracy: 0.1)
    }

    func testTuningLine() {
        XCTAssertEqual(Tuning.line(12, reference: 440), "TUNING +12¢ · A=440")
        XCTAssertEqual(Tuning.line(-7.4, reference: 440), "TUNING −7¢ · A=440")
        XCTAssertEqual(Tuning.line(0.2, reference: 440), "TUNING 0¢ · A=440")
        XCTAssertEqual(Tuning.line(-31.8, reference: 432), "TUNING 0¢ · A=432")
        XCTAssertEqual(Tuning.line(15, reference: 441.5), "TUNING +9¢ · A=441.5")
        XCTAssertNil(Tuning.line(nil, reference: 440))
    }

    func testTuningHiddenFrom45Cents() {
        XCTAssertNotNil(Tuning.line(44, reference: 440))
        XCTAssertNotNil(Tuning.line(-44.4, reference: 440))
        XCTAssertNil(Tuning.line(45, reference: 440))
        XCTAssertNil(Tuning.line(-48, reference: 440))
        XCTAssertNil(Tuning.line(50, reference: 440))
        // the same track against another reference can come back into range
        XCTAssertNil(Tuning.line(-45, reference: 440))
        XCTAssertNotNil(Tuning.line(-45, reference: 432))
    }

    func testPresetsAndCustomRange() {
        XCTAssertEqual(Tuning.presets, [432, 436, 438, 440, 442, 444, 450])
        XCTAssertEqual(Tuning.defaultReference, 440)
        XCTAssertEqual(Tuning.parse("432"), 432)
        XCTAssertEqual(Tuning.parse(" 441,5 "), 441.5)
        XCTAssertEqual(Tuning.parse("400"), 400)
        XCTAssertEqual(Tuning.parse("480"), 480)
        XCTAssertNil(Tuning.parse("399.9"))
        XCTAssertNil(Tuning.parse("481"))
        XCTAssertNil(Tuning.parse("abc"))
        XCTAssertEqual(Tuning.clamp(300), 400)
        XCTAssertEqual(Tuning.clamp(900), 480)
    }

    func testReferenceIsRemembered() {
        let d = defaults()
        XCTAssertEqual(TuningSettings(defaults: d).reference, 440)          // default
        let a = TuningSettings(defaults: d)
        a.reference = 432
        XCTAssertEqual(TuningSettings(defaults: d).reference, 432)
        a.reference = 9999                                                  // clamped, then saved
        XCTAssertEqual(a.reference, 480)
        XCTAssertEqual(TuningSettings(defaults: d).reference, 480)
        d.set(12.0, forKey: TuningSettings.key)                             // a bad saved value
        XCTAssertEqual(TuningSettings(defaults: d).reference, 400)
    }

    // MARK: 1.8 confidence

    func testConfidenceStates() {
        XCTAssertEqual(KeyConfidence.of([("Cm", 85), ("Eb", 8), ("Gm", 4)]), .locked)
        XCTAssertEqual(KeyConfidence.of([("Cm", 70), ("Eb", 20)]), .locked)
        XCTAssertEqual(KeyConfidence.of([("Cm", 69), ("Eb", 20)]), .unsure)
        XCTAssertEqual(KeyConfidence.of([("Cm", 41), ("Eb", 22), ("Gm", 18)]), .unsure)
        XCTAssertEqual(KeyConfidence.of([]), .none)
    }

    func testConfidenceLine() {
        XCTAssertEqual(Faceplate.confidenceLine([("Cm", 85), ("Eb", 8), ("Gm", 4)]), "LOCKED 85%")
        XCTAssertEqual(Faceplate.confidenceLine([("Cm", 41), ("Eb", 22), ("Gm", 18)]),
                       "UNSURE · Cm 41 · Eb 22 · Gm 18")
        XCTAssertEqual(Faceplate.confidenceLine([("Cm", 40)]), "UNSURE · Cm 40")
        XCTAssertNil(Faceplate.confidenceLine([]))
    }

    func testAnalyzingLampIsTheAnalyzeStage() {
        // the red lamp sits on the working readout only while the analyzer runs
        XCTAssertEqual(Faceplate.stageText("analyzing"), "FINDING BPM AND KEY")
    }

    // MARK: 1.6 recent readings

    func testRecordsNewestFirstAndKeepsThirty() {
        let store = RecentStore(defaults: defaults())
        for i in 0..<35 { store.record(result("f\(i).wav")) }
        XCTAssertEqual(store.readings.count, 30)
        XCTAssertEqual(store.readings.first?.name, "f34.wav")
        XCTAssertEqual(store.readings.last?.name, "f5.wav")
    }

    func testReadAgainMovesToTopWithoutDuplicate() {
        let store = RecentStore(defaults: defaults())
        store.record(result("a.wav")); store.record(result("b.wav")); store.record(result("a.wav", exact: 141.0))
        XCTAssertEqual(store.readings.map { $0.name }, ["a.wav", "b.wav"])
        XCTAssertEqual(store.readings[0].bpmExact, 141.0)
    }

    func testUnreadableFilesAreNotReadings() {
        let store = RecentStore(defaults: defaults())
        store.record(result(bpm: nil, exact: nil, keys: []))
        XCTAssertTrue(store.readings.isEmpty)
    }

    func testPersistsAcrossLaunches() {
        let d = defaults()
        let a = RecentStore(defaults: d)
        a.record(result("a.wav", tuning: -12)); a.record(result("b.wav"))
        let b = RecentStore(defaults: d)
        XCTAssertEqual(b.readings.map { $0.name }, ["b.wav", "a.wav"])
        XCTAssertEqual(b.readings[1].tuningCents, -12)
        b.clear()
        XCTAssertTrue(RecentStore(defaults: d).readings.isEmpty)
    }

    func testReadingRoundTripsToTheSameResult() {
        let r = result("a.wav", tuning: 7)
        XCTAssertEqual(Reading(r).result, r)
        XCTAssertEqual(Reading(r).title, "a.wav · 140.82 BPM · Cm")
    }

    func testCorruptStoreStartsEmpty() {
        let d = defaults()
        d.set(Data("not json".utf8), forKey: RecentStore.key)
        XCTAssertTrue(RecentStore(defaults: d).readings.isEmpty)
    }

    func testEngineRecordsDoneAndAnalyzedAndShowsAgain() {
        let store = RecentStore(defaults: defaults())
        let f = FakeLauncher()
        let rt = Runtime(root: URL(fileURLWithPath: "/R/runtime"), arch: "arm64",
                         support: URL(fileURLWithPath: "/S/Orion"), osMajor: 14)
        let e = Engine(runtime: rt, launcher: f, recents: store)
        e.analyze([URL(fileURLWithPath: "/a.mp3"), URL(fileURLWithPath: "/b.mp3")])
        let deadline = Date().addingTimeInterval(5)
        while f.launches.isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        f.onLine?(#"{"stage":"analyzed","file":"/a.mp3","name":"a.mp3","bpm":"100.0","keys":[["Am",80]],"bpm_exact":100.25}"#)
        f.onLine?(#"{"stage":"analyzed","file":"/b.mp3","name":"b.mp3","bpm":null,"keys":[]}"#)
        f.onExit?(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(store.readings.map { $0.name }, ["a.mp3"])           // the unreadable one is skipped
        e.show(store.readings[0].result)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        if case .analyzed(let rs) = e.state {
            XCTAssertEqual(rs.count, 1); XCTAssertEqual(rs[0].bpmExact, 100.25)
        } else { XCTFail("\(e.state)") }
    }

    func testShowIsIgnoredWhileBusy() {
        let e = Engine(runtime: Runtime(root: URL(fileURLWithPath: "/R/runtime"), arch: "arm64",
                                        support: URL(fileURLWithPath: "/S/Orion"), osMajor: 14),
                       launcher: FakeLauncher())
        e.download("u")
        e.show(result())
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(e.state.isBusy)
    }

    // MARK: 1.7 Analyze a File… / Finder service

    func testInfoPlistDeclaresTheFinderService() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()      // app/
        let plist = try XCTUnwrap(NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")))
        let svc = try XCTUnwrap((plist["NSServices"] as? [[String: Any]])?.first)
        XCTAssertEqual((svc["NSMenuItem"] as? [String: String])?["default"], "Analyze with Beat Key")
        XCTAssertEqual(svc["NSMessage"] as? String, "analyzeWithBeatKey")
        XCTAssertEqual(svc["NSPortName"] as? String, Brand.name)
        // Without NSRequiredContext (even empty) macOS registers the service but never shows it in the menu.
        XCTAssertNotNil(svc["NSRequiredContext"] as? [String: Any], "NSRequiredContext must be present")
        let types = try XCTUnwrap(svc["NSSendFileTypes"] as? [String])
        XCTAssertTrue(types.contains("public.audio") && types.contains("public.movie"))
        // the provider really answers to that message
        XCTAssertTrue(ServiceProvider().responds(to: Selector(("analyzeWithBeatKey:userData:error:"))))
    }

    func testIntakeKeepsAudioOnlyAndHandsItToTheFaceplate() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("orion-intake-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir); Intake.handler = nil }
        for n in ["a.wav", "b.pdf", "c.mov"] { fm.createFile(atPath: dir.appendingPathComponent(n).path, contents: Data([0])) }
        var got: [String] = []
        Intake.handler = { files in got = files.map { $0.lastPathComponent }; return true }
        XCTAssertTrue(Intake.receive(["a.wav", "b.pdf", "c.mov"].map { dir.appendingPathComponent($0) }))
        XCTAssertEqual(got, ["a.wav", "c.mov"])
        Intake.handler = { _ in false }                       // busy: refused
        XCTAssertFalse(Intake.receive([dir.appendingPathComponent("a.wav")]))
    }
}
