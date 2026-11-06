import AppKit

// Per-DAW Accessibility routes for tempo and key (plan §4.2). Each job has routes tried in order;
// the first that runs to the end wins. Names come from the DAWs' own documentation:
// - Pro Tools 2026.4 Reference Guide (in the app: Contents/PTHelp/.../Part7_Arranging/Tempo.htm,
//   Key_Signatures.htm, Part4.../Setting_the_Session_Meter_and_Tempo_.htm) and its dialog pictures
//   (Resources/Images/TempoChangeDialog.png, KeyChangeDialog.png).
// - Logic Pro 12.3 Quick Help (Contents/Resources/en.lproj/QuickHelp.plist: TRA_028_TempoDisplay
//   "Tempo display", TRA_030_KeySignatureDisplay "Key Signature display", TRA_002 Go to Beginning).
// - Studio One / Studio Pro: no manual reachable; labels are the transport's ("Tempo", "Key") and
//   Song › Song Setup…; unverified, so a miss is reported, nothing else sent.

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
                 .set(["Location"], "1|1|000", .time),
                 .set(["BPM"], v, .tempo(bpm)),
                 .press(ok), .waitClosed],
                [.set(["Tempo", "Manual Tempo"], v, .tempo(bpm))],
            ]
        }
        if let t = tonic {
            p.key = [[
                .menu([["Event"], ["Add Key Change…", "Add Key Change"]]),
                .window(["Key Change"]),
                .choose([t.minor ? "Minor Keys" : "Major Keys"]),
                .choose(AXKeyNames.names(t.pc, minor: t.minor)),
                .optional(.set(["From"], "1|1|000", .time)),
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
                [.set(["Tempo"], v, .tempo(bpm))],
                [.menu([["Song"], ["Song Setup…", "Song Setup"]]), .window(["Song Setup"]), .set(["Tempo"], v, .tempo(bpm)), .press(ok), .waitClosed],
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
    /// The dialogs a plan opens (its .window steps).
    static func dialogs(_ plan: AXPlan) -> [String] {
        (plan.tempo + plan.key).flatMap { $0 }.flatMap { step -> [String] in
            if case .window(let t) = step { return t }
            return []
        }
    }

    /// Runs a plan: for each job, routes in order until one finishes. A failed route cancels the
    /// dialog it opened (Cancel, else Escape) so the DAW is never left inside it; if that dialog
    /// will not close, nothing more runs. A plan whose dialog is already open (left from before)
    /// does not run at all: nothing is pressed or typed.
    static func run(_ plan: AXPlan, runner: () -> AXRunner) -> AXResult {
        var r = AXResult()
        var stuck: String?
        let probe = runner()
        let titles = dialogs(plan)
        if let open = probe.app.windows.first(where: { w in titles.contains { AXText.same(w.title, $0) } }) {
            stuck = "the \(open.title ?? "dialog") dialog is already open; close it first"
            probe.note("not started: \(stuck!)")
        }
        func job(_ name: String, _ routes: [[AXStep]]) -> (Bool, String?) {
            if let s = stuck { return (false, s) }
            var errors: [String] = []
            for (i, steps) in routes.enumerated() {
                let x = runner()
                x.note("\(name) route \(i + 1) of \(routes.count)")
                do { try x.run(steps); r.log += x.log; x.note("\(name) set"); return (true, nil) }
                catch {
                    x.note("\(name) route \(i + 1) failed: \(error)")
                    errors.append("\(error)")
                    if !x.cancelDialog() { stuck = "\(x.scope.title ?? "a dialog") would not close" }
                    r.log += x.log
                    if let s = stuck { errors.append(s); break }
                }
            }
            return (false, errors.joined(separator: "; "))
        }
        if !plan.tempo.isEmpty { (r.tempoSet, r.tempoError) = job("tempo", plan.tempo) }
        if !plan.key.isEmpty { (r.keySet, r.keyError) = job("key", plan.key) }
        return r
    }
}

/// Pro Tools, Logic Pro and Studio One / Studio Pro through Accessibility. No MIDI-file fallback
/// (J, 2026-11-05: File › Export MIDI is its own button); a miss is said in one line.
struct AXDAWDriver: DAWDriver {
    let daw: DAW

    func send(_ p: SendPayload) throws -> String {
        try AXDAWDriver.sendAX(daw, p, readBack: nil)
    }

    /// Shared by Pro Tools: run the AX plan and report what happened. `readBack` confirms the
    /// tempo where the DAW can say it. Accessibility not allowed yet: the system prompt (once),
    /// nothing sent, no failure alert.
    static func sendAX(_ d: DAW, _ p: SendPayload, readBack: (() -> Double?)?) throws -> String {
        let wantTempo = p.bpm != nil, wantKey = p.tonic != nil
        guard wantTempo || wantKey else { throw DAWError("No BPM or key yet; nothing sent.") }
        if let b = p.bpm, !AXFieldKind.tempoRange.contains(b) {
            throw DAWError(String(format: "Tempo %.2f is outside 20-999 BPM; nothing sent.", b))
        }
        guard AXIsProcessTrusted() else {
            let shown = AXTrust.promptOnce()
            AppLog.log("daw send: accessibility not allowed (system prompt \(shown ? "shown" : "already shown")); nothing sent")
            throw AXPermissionPending(promptShown: shown)
        }
        guard let app = AXApps.running(d) else { throw DAWError("\(d.name) is not open.") }
        let tree = AXElement.app(pid: app.processIdentifier)
        let focus = AXFocus.begin(app, app: tree)
        let r = AXSend.run(AXPlans.plan(d, bpm: p.bpm, tonic: p.tonic)) { AXRunner(app: tree, pid: app.processIdentifier) }
        focus.end(app)
        let back = r.tempoSet ? readBack?() : nil
        if r.tempoSet { AppLog.log("daw send: tempo read back \(back.map { String(format: "%.2f", $0) } ?? "unavailable")") }
        return try report(d, p, r, readBack: back)
    }

    /// The result text: which values went in, which did not and why. Nothing went in = throws.
    static func report(_ d: DAW, _ p: SendPayload, _ r: AXResult, readBack: Double?) throws -> String {
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
        var out = done.isEmpty ? "" : "Set in \(d.name): " + done.joined(separator: ", ") + "."
        if p.bpm == nil { out += (out.isEmpty ? "" : " ") + "No BPM yet; tempo left alone." }
        if !missed.isEmpty {
            out += (out.isEmpty ? "" : " ") + "Could not set " + missed.joined(separator: "; ") + "."
        }
        AppLog.log("daw send: result \(out)")
        if done.isEmpty { throw DAWError(out) }
        return out
    }
}
