import AppKit

// Per-DAW Accessibility routes for tempo and key (plan §4.2). Each job has routes tried in order;
// the first that runs to the end wins. Names come from the DAWs' own documentation:
// - Pro Tools 2026.4 Reference Guide (in the app: Contents/PTHelp/.../Part7_Arranging/Tempo.htm,
//   Key_Signatures.htm, Part4.../Setting_the_Session_Meter_and_Tempo_.htm) and its dialog pictures
//   (Resources/Images/TempoChangeDialog.png, KeyChangeDialog.png).
// - Logic Pro 12.3 Quick Help (Contents/Resources/en.lproj/QuickHelp.plist: TRA_028_TempoDisplay
//   "Tempo display", TRA_030_KeySignatureDisplay "Key Signature display", TRA_002 Go to Beginning).
// - Studio One / Studio Pro: no manual reachable; labels are the transport's ("Tempo", "Key") and
//   Song › Song Setup…; unverified, so it falls back to the MIDI file when they are not found.

/// Key names as DAWs print them, preferred spelling first.
enum AXKeyNames {
    static let major = [["C"], ["Db", "C#"], ["D"], ["Eb", "D#"], ["E"], ["F"], ["F#", "Gb"], ["G"], ["Ab", "G#"], ["A"], ["Bb", "A#"], ["B", "Cb"]]
    static let minor = [["C"], ["C#", "Db"], ["D"], ["Eb", "D#"], ["E"], ["F"], ["F#", "Gb"], ["G"], ["G#", "Ab"], ["A"], ["Bb", "A#"], ["B"]]

    static func roots(_ pc: Int, minor m: Bool) -> [String] { (m ? minor : major)[((pc % 12) + 12) % 12] }

    /// "Eb minor", "D# minor", plus the short forms some menus use ("Ebm", "Eb min").
    static func names(_ pc: Int, minor m: Bool) -> [String] {
        let r = roots(pc, minor: m)
        return r.map { "\($0) \(m ? "minor" : "major")" } + r.map { m ? "\($0) min" : "\($0) maj" } + r.map { m ? "\($0)m" : $0 }
    }

    /// Unicode-accidental spellings (Logic prints ♭/♯); AXText.norm folds them, kept for clarity.
    static func pretty(_ s: String) -> String { s.replacingOccurrences(of: "b", with: "♭").replacingOccurrences(of: "#", with: "♯") }
}

/// A DAW's routes: each an alternative list of steps.
struct AXPlan {
    var tempo: [[AXStep]] = []
    var key: [[AXStep]] = []
}

enum AXPlans {
    static func bpmText(_ bpm: Double) -> String {
        let s = String(format: "%.2f", bpm)
        return s.hasSuffix(".00") ? String(s.dropLast(3)) : s
    }

    static func plan(_ d: DAW, bpm: Double?, tonic: (pc: Int, minor: Bool)?) -> AXPlan {
        switch d {
        case .proTools: return proTools(bpm: bpm, tonic: tonic)
        case .logic: return logic(bpm: bpm, tonic: tonic)
        case .studioOne: return studioOne(bpm: bpm, tonic: tonic)
        default: return AXPlan()
        }
    }

    static let ok = AXMatch(roles: ["AXButton"], labels: ["OK"])

    /// Pro Tools. Tempo: the Tempo ruler's "Add Tempo Change" button opens "Tempo Change"
    /// (Snap To Bar, Location, BPM, Resolution); Location 1|1|000 replaces the default tempo
    /// (Reference Guide, "Setting the Session Tempo"). Second route: Manual Tempo mode's Tempo
    /// field in the Transport window. Key: Event › Add Key Change → "Key Change" (Major Keys /
    /// Minor Keys, Sharps / Flats lists of "C major"…, From, Edit Pitched Tracks, OK). Edit
    /// Pitched Tracks is forced off so no MIDI notes move.
    static func proTools(bpm: Double?, tonic: (pc: Int, minor: Bool)?) -> AXPlan {
        var p = AXPlan()
        if let bpm {
            let v = bpmText(bpm)
            p.tempo = [
                [.press(AXMatch(roles: ["AXButton"], labels: ["Add Tempo Change"]).helped("Add Tempo Change")),
                 .window(["Tempo Change"]),
                 .set(["Location"], "1|1|000"),
                 .set(["BPM"], v),
                 .press(ok), .waitClosed],
                [.set(["Tempo", "Manual Tempo"], v)],
            ]
        }
        if let t = tonic {
            p.key = [[
                .menu([["Event"], ["Add Key Change…", "Add Key Change"]]),
                .window(["Key Change"]),
                .choose([t.minor ? "Minor Keys" : "Major Keys"]),
                .choose(AXKeyNames.names(t.pc, minor: t.minor)),
                .optional(.set(["From"], "1|1|000")),
                .optional(.check(["Edit Pitched Tracks"], false)),
                .press(ok), .waitClosed,
            ]]
        }
        return p
    }

    /// Logic Pro. The control bar LCD (Beats & Project) shows "Tempo display" (double-click and
    /// enter a value) and "Key Signature display" (pick a major or minor key from its pop-up).
    /// The key set at the project start is the project key, so the playhead goes to the start first.
    static func logic(bpm: Double?, tonic: (pc: Int, minor: Bool)?) -> AXPlan {
        var p = AXPlan()
        let tempo = AXMatch(labels: ["Tempo", "Tempo display"]).helped("Indicates the playback or recording speed")
        if let bpm { p.tempo = [[.typeInto(tempo, bpmText(bpm))]] }
        if let t = tonic {
            let keyDisplay = AXMatch(labels: ["Key Signature", "Key Signature display", "Key"]).helped("Indicates the key signature of the project")
            let names = AXKeyNames.names(t.pc, minor: t.minor)
            p.key = [[
                .optional(.press(AXMatch(roles: ["AXButton"], labels: ["Go to Beginning"]).helped("Move the playhead to the start of the project"))),
                .popup(keyDisplay, names),
            ]]
        }
        return p
    }

    /// Studio One / Studio Pro: the transport's Tempo field and Key pop-up; Song › Song Setup… as
    /// a second tempo route.
    static func studioOne(bpm: Double?, tonic: (pc: Int, minor: Bool)?) -> AXPlan {
        var p = AXPlan()
        if let bpm {
            let v = bpmText(bpm)
            p.tempo = [
                [.set(["Tempo"], v)],
                [.menu([["Song"], ["Song Setup…", "Song Setup"]]), .window(["Song Setup"]), .set(["Tempo"], v), .press(ok), .waitClosed],
            ]
        }
        if let t = tonic {
            p.key = [[.popup(AXMatch(labels: ["Key", "Key Signature", "Song Key"]), AXKeyNames.names(t.pc, minor: t.minor))]]
        }
        return p
    }
}

/// What a route run did, per job.
struct AXResult: Equatable {
    var tempoSet = false
    var keySet = false
    var tempoError: String?
    var keyError: String?
    var log: [String] = []
}

enum AXSend {
    /// Runs a plan: for each job, routes in order until one finishes. A failed route presses
    /// Escape in case it left a dialog open, so the next route starts clean.
    static func run(_ plan: AXPlan, runner: () -> AXRunner) -> AXResult {
        var r = AXResult()
        func job(_ routes: [[AXStep]]) -> (Bool, String?) {
            var last: String?
            for steps in routes {
                let x = runner()
                do { try x.run(steps); r.log += x.log; return (true, nil) }
                catch {
                    r.log += x.log + ["failed: \(error)"]
                    last = "\(error)"
                    if x.scope !== x.start { x.keys.key(KeyCode.escape, flags: [], pid: x.pid) }   // a dialog it opened
                }
            }
            return (false, last)
        }
        if !plan.tempo.isEmpty { (r.tempoSet, r.tempoError) = job(plan.tempo) }
        if !plan.key.isEmpty { (r.keySet, r.keyError) = job(plan.key) }
        return r
    }
}

/// Logic Pro and Studio One / Studio Pro: Accessibility first, the MIDI file when it fails.
struct AXDAWDriver: DAWDriver {
    let daw: DAW
    var midi: MidiFileDriver? = nil

    func send(_ p: SendPayload) throws -> String {
        try AXDAWDriver.sendWithFallback(daw, p, midi: midi ?? MidiFileDriver(daw: daw), readBack: nil)
    }

    /// Shared by Pro Tools: run the AX plan, report what happened, and hand over the MIDI file
    /// for whatever AX could not set. `readBack` confirms the tempo where the DAW can say it.
    static func sendWithFallback(_ d: DAW, _ p: SendPayload, midi: MidiFileDriver, readBack: (() -> Double?)?) throws -> String {
        let wantTempo = p.bpm != nil, wantKey = p.tonic != nil
        guard wantTempo || wantKey else { return try midi.send(p) }
        guard AXTrust.isTrusted(prompt: true) else {
            return "Beat Key could not set it directly: allow Beat Key in System Settings › Privacy & Security › Accessibility, then send again. For now: " + (try midi.send(p))
        }
        guard let app = AXApps.running(d) else { return try midi.send(p) }
        let tree = AXElement.app(pid: app.processIdentifier)
        let focus = AXFocus.begin(app, app: tree)
        let r = AXSend.run(AXPlans.plan(d, bpm: p.bpm, tonic: p.tonic)) { AXRunner(app: tree, pid: app.processIdentifier) }
        focus.end(app)
        return try report(d, p, r, readBack: readBack?(), midi: midi)
    }

    /// The alert text: which values went in by Accessibility, which by the MIDI file, and why.
    static func report(_ d: DAW, _ p: SendPayload, _ r: AXResult, readBack: Double?, midi: MidiFileDriver) throws -> String {
        var done: [String] = [], missed: [String] = []
        if let bpm = p.bpm {
            if r.tempoSet {
                if let got = readBack, abs(got - bpm) > 0.05 {
                    missed.append(String(format: "tempo (\(d.name) reads %.2f after the change)", got))
                } else {
                    done.append(String(format: "tempo %.2f", bpm) + (readBack != nil ? " (read back)" : ""))
                }
            } else { missed.append("tempo (\(r.tempoError ?? "not found"))") }
        }
        if let k = p.keyText {
            if r.keySet { done.append("key \(k)") } else { missed.append("key (\(r.keyError ?? "not found"))") }
        }
        var out = done.isEmpty ? "" : "Set directly in \(d.name): " + done.joined(separator: ", ") + "."
        if !missed.isEmpty {
            let lead = "Could not set " + missed.joined(separator: "; ") + " through Accessibility."
            out += (out.isEmpty ? "" : " ") + lead + " " + (try midi.send(p))
        }
        return out
    }
}
