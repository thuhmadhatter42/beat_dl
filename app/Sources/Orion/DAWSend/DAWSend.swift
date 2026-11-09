import AppKit
import SwiftUI

// Reading › Send to DAW (⌃⌥⌘S), Send to All DAWs (⌃⌥⌘D), Analyze Selection (no default keys; set in Settings › Shortcuts, global). Plan §4.2, §4.3.
// One driver per DAW; what each DAW can really take is in docs/research/send-to-daw.md.

/// The DAWs Beat Key knows, in the order "Send to All" walks them.
enum DAW: String, CaseIterable {
    case proTools, ableton, logic, reaper, bitwig, studioOne, flStudio, reason, cubase

    var name: String {
        switch self {
        case .proTools: return "Pro Tools"
        case .ableton: return "Ableton Live"
        case .logic: return "Logic Pro"
        case .reaper: return "REAPER"
        case .bitwig: return "Bitwig Studio"
        case .studioOne: return "Studio One"
        case .flStudio: return "FL Studio"
        case .reason: return "Reason"
        case .cubase: return "Cubase"
        }
    }

    /// Bundle-id prefixes, then app-name prefixes (versions put numbers in both).
    var bundlePrefixes: [String] {
        switch self {
        case .proTools: return ["com.avid.ProTools"]
        case .ableton: return ["com.ableton.live"]
        case .logic: return ["com.apple.logic"]
        case .reaper: return ["com.cockos.reaper"]
        case .bitwig: return ["com.bitwig."]
        case .studioOne: return ["com.presonus.studioone", "com.fender.studiopro"]
        case .flStudio: return ["com.image-line.flstudio"]
        case .reason: return ["com.propellerheads.reason", "com.reasonstudios.reason"]
        case .cubase: return ["com.steinberg.cubase", "com.steinberg.nuendo"]
        }
    }
    var namePrefixes: [String] {
        switch self {
        case .proTools: return ["Pro Tools"]
        case .ableton: return ["Ableton Live", "Live"]
        case .logic: return ["Logic Pro"]
        case .reaper: return ["REAPER"]
        case .bitwig: return ["Bitwig Studio"]
        case .studioOne: return ["Studio One", "Studio Pro"]
        case .flStudio: return ["FL Studio"]
        case .reason: return ["Reason"]
        case .cubase: return ["Cubase", "Nuendo"]
        }
    }

    static func from(bundleID: String?, name: String?) -> DAW? {
        if let b = bundleID?.lowercased(), let d = allCases.first(where: { $0.bundlePrefixes.contains { b.hasPrefix($0.lowercased()) } }) { return d }
        if let n = name, let d = allCases.first(where: { $0.namePrefixes.contains { n == $0 || n.hasPrefix($0 + " ") } }) { return d }
        return nil
    }

    /// What Send gives this DAW, said plainly in the menu's tooltip and the result.
    var gets: String {
        switch self {
        case .proTools: return "tempo and key, typed into its Tempo Change and Key Change dialogs through Accessibility (PTSL has no tempo or key command)"
        case .logic, .studioOne: return "tempo and key, set in its transport through Accessibility"
        case .ableton: return "tempo and key (Live 12; Live 11 tempo only), through Beat Key's Remote Script"
        case .reaper: return "tempo, through Beat Key's ReaScript (REAPER has no project key)"
        case .bitwig: return "tempo, through Beat Key's controller script (Bitwig has no project key)"
        case .flStudio, .reason, .cubase: return "a MIDI file with tempo and key to import (no outside control of tempo)"
        }
    }

    var canAnalyzeSelection: Bool { self == .proTools || self == .ableton || self == .reaper }
}

/// What gets sent: the reading's decimal BPM and top key.
struct SendPayload: Equatable {
    let bpm: Double?
    let key: String?          // the analyzer's name: "Cm", "F#", "Ebm"
    var trackName: String = "Beat Key"

    init(bpm: Double?, key: String?, trackName: String = "Beat Key") {
        self.bpm = bpm.flatMap { $0 > 0 ? $0 : nil }
        self.key = key
        self.trackName = trackName
    }

    init(_ r: Result) {
        self.init(bpm: MidiExport.bpmValue(r), key: r.keys.first?.0,
                  trackName: (r.name as NSString).deletingPathExtension)
    }

    /// Pitch class of the tonic (C = 0 … B = 11) and minor, from the key name; nil = no key.
    var tonic: (pc: Int, minor: Bool)? { key.flatMap(SendPayload.parseKey) }

    static func parseKey(_ name: String) -> (pc: Int, minor: Bool)? {
        var s = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
        var minor = false
        if s.hasSuffix("m") { minor = true; s.removeLast() }
        let letters: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let first = s.first, var pc = letters[first] else { return nil }
        for c in s.dropFirst() {
            switch c {
            case "#": pc += 1
            case "b": pc -= 1
            default: return nil
            }
        }
        return ((pc % 12 + 12) % 12, minor)
    }

    /// "140.82 BPM · C minor" for results.
    var text: String {
        [bpm.map { String(format: "%.2f BPM", $0) }, keyText].compactMap { $0 }.joined(separator: " · ")
    }
    var keyText: String? {
        guard let k = key, let t = tonic else { return nil }
        let root = k.hasSuffix("m") ? String(k.dropLast()) : k
        return "\(root) \(t.minor ? "minor" : "major")"
    }
}

/// What one DAW did with a send.
struct SendOutcome {
    let daw: DAW
    let ok: Bool
    let message: String
    /// Accessibility not allowed yet: nothing sent; `promptShown` = the system prompt is up.
    var permission: AXPermissionPending? = nil
}

/// A step only the person can take (install a script, pick it in the DAW). The driver throws it;
/// the controller shows it, runs `install` on OK, and tries once more.
struct SetupNeeded: Error {
    let title: String
    let message: String
    let button: String
    let install: (() throws -> Void)?
}

struct DAWError: Error, CustomStringConvertible {
    let description: String
    init(_ s: String) { description = s }
}

protocol DAWDriver {
    var daw: DAW { get }
    /// Sends tempo / key; the one-line result. Throws SetupNeeded or an error.
    func send(_ p: SendPayload) throws -> String
    /// The audio of the selected clip, ready to analyse.
    func selectionAudio() throws -> [URL]
}

extension DAWDriver {
    func selectionAudio() throws -> [URL] {
        throw DAWError("\(daw.name) does not tell other apps what is selected. Export the clip and drop it on Beat Key.")
    }
}

enum DAWDrivers {
    static func driver(_ d: DAW) -> DAWDriver {
        switch d {
        case .proTools: return ProToolsDriver()
        case .ableton: return AbletonDriver()
        case .reaper: return ReaperDriver()
        case .bitwig: return BitwigDriver()
        case .logic, .studioOne: return AXDAWDriver(daw: d)   // Accessibility, MIDI fallback (AXRoutes.swift)
        case .flStudio, .reason, .cubase: return MidiFileDriver(daw: d)
        }
    }
}

/// Which DAWs are open, and the one the person used last (Beat Key itself is frontmost while
/// its menu is open, so "frontmost DAW" = the DAW most recently brought forward).
final class DAWWatcher: ObservableObject {
    static let shared = DAWWatcher()
    @Published private(set) var last: DAW?
    private var token: NSObjectProtocol?

    private init() {
        let ws = NSWorkspace.shared
        if let f = ws.frontmostApplication, let d = DAW.from(bundleID: f.bundleIdentifier, name: f.localizedName) { last = d }
        token = ws.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let d = DAW.from(bundleID: app.bundleIdentifier, name: app.localizedName) else { return }
            self?.last = d
        }
    }

    var running: [DAW] {
        let apps = NSWorkspace.shared.runningApplications
        return DAW.allCases.filter { d in apps.contains { DAW.from(bundleID: $0.bundleIdentifier, name: $0.localizedName) == d } }
    }

    /// The DAW to send to: the last one used if it is still open, else the first open one.
    var target: DAW? { DAWWatcher.pick(last: last, running: running) }

    static func pick(last: DAW?, running: [DAW]) -> DAW? {
        if let l = last, running.contains(l) { return l }
        return running.first
    }
}

/// The menu actions. Work runs off the main thread; alerts come back on it.
enum DAWSendController {
    private static let queue = DispatchQueue(label: "beatkey.dawsend")

    /// One send at a time (main thread only): a second press while one runs is ignored.
    private static var busy = false

    /// What a send would do with this reading; nil = nothing to send (no BPM and no key).
    static func plan(_ p: SendPayload) -> String? {
        if p.bpm == nil && p.tonic == nil { return nil }
        return p.bpm == nil ? "key only (no BPM yet)" : (p.tonic == nil ? "tempo only (no key)" : "tempo and key")
    }

    static func send(_ r: Result, toAll: Bool) {
        let p = SendPayload(r)
        guard let what = plan(p) else {
            AppLog.log("send to DAW: no BPM and no key yet; nothing sent")
            NSSound.beep()
            alert("No BPM or key yet; nothing sent", "")
            return
        }
        guard !busy else { AppLog.log("send to DAW: already sending; ignored"); NSSound.beep(); return }
        let w = DAWWatcher.shared
        let targets = toAll ? w.running : w.target.map { [$0] } ?? []
        guard !targets.isEmpty else {
            AppLog.log("send to DAW: no DAW open")
            alert("No DAW is open", "Open Pro Tools, Ableton Live, Logic, REAPER, Bitwig, Studio One, FL Studio, Reason or Cubase, then send again.")
            return
        }
        AppLog.log("send to DAW: \(what) [\(p.text)] to \(targets.map(\.name).joined(separator: ", "))")
        busy = true
        queue.async {
            var outcomes: [SendOutcome] = []
            for d in targets { outcomes.append(run(d) { try DAWDrivers.driver(d).send(p) }) }
            DispatchQueue.main.async {
                busy = false
                for o in outcomes { AppLog.log("send to DAW: \(o.daw.name) \(o.ok ? "ok" : o.permission != nil ? "needs Accessibility" : "failed"): \(o.message)") }
                // Accessibility not allowed: the system prompt says it; else one line, no failure alert.
                if outcomes.allSatisfy({ $0.permission != nil }) {
                    if !outcomes.contains(where: { $0.permission?.promptShown ?? false }) {
                        alert("Allow Beat Key in Accessibility, then send again", "")
                    }
                    return
                }
                let title = outcomes.count == 1 ? (outcomes[0].ok ? "Sent to \(outcomes[0].daw.name)" : "\(outcomes[0].daw.name) did not take it")
                                                : "Sent to \(outcomes.filter(\.ok).count) of \(outcomes.count) DAWs"
                let body = outcomes.count == 1 ? outcomes[0].message
                    : outcomes.map { "\($0.ok ? "✓" : "✗") \($0.daw.name): \($0.message)" }.joined(separator: "\n\n")
                alert(title, p.text + "\n\n" + body)
            }
        }
    }

    static func analyzeSelection() {
        guard let d = DAWWatcher.shared.target else {
            alert("No DAW is open", "Analyze Selection reads the selected clip in Pro Tools, Ableton Live or REAPER.")
            return
        }
        queue.async {
            var files: [URL] = []
            let o = run(d) { files = try DAWDrivers.driver(d).selectionAudio(); return "" }
            DispatchQueue.main.async {
                if o.ok, !files.isEmpty { Intake.receive(files, via: "daw selection") }
                else { alert("Could not read the selection in \(d.name)", o.ok ? "Nothing came back." : o.message) }
            }
        }
    }

    /// Runs one driver call; a SetupNeeded is shown (on main, waiting) and the call retried once.
    private static func run(_ d: DAW, _ body: () throws -> String) -> SendOutcome {
        for attempt in 0..<2 {
            do { return SendOutcome(daw: d, ok: true, message: try body()) }
            catch let a as AXPermissionPending {
                return SendOutcome(daw: d, ok: false, message: a.description, permission: a)
            } catch let s as SetupNeeded {
                guard attempt == 0 else { return SendOutcome(daw: d, ok: false, message: s.message) }
                var go = false
                DispatchQueue.main.sync { go = confirm(s.title, s.message, button: s.button) }
                guard go else { return SendOutcome(daw: d, ok: false, message: "Not set up yet.") }
                do { try s.install?() } catch { return SendOutcome(daw: d, ok: false, message: "\(error)") }
            } catch {
                return SendOutcome(daw: d, ok: false, message: "\(error)")
            }
        }
        return SendOutcome(daw: d, ok: false, message: "Not set up yet.")
    }

    static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    static func confirm(_ title: String, _ text: String, button: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: button)
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }
}

/// The three Reading-menu items. Disabled until there is a reading (send) / a DAW that can say
/// what is selected (analyze).
struct DAWSendMenuItems: View {
    @ObservedObject var engine: Engine
    @ObservedObject var shortcuts: ShortcutStore
    @ObservedObject private var watcher = DAWWatcher.shared

    var body: some View {
        let r = MidiExport.current(engine.state)
        let usable = r.map { $0.bpm != nil || !$0.keys.isEmpty } ?? false
        let target = watcher.target
        Divider()
        Button(target.map { "Send to \($0.name)" } ?? "Send to DAW") { if let r { DAWSendController.send(r, toAll: false) } }
            .keyboardShortcut("s", modifiers: [.control, .option, .command])
            .disabled(!usable)
        Button("Send to All DAWs") { if let r { DAWSendController.send(r, toAll: true) } }
            .keyboardShortcut("d", modifiers: [.control, .option, .command])
            .disabled(!usable)
        Button(target.map { "Analyze Selection in \($0.name)" } ?? "Analyze Selection") { DAWSendController.analyzeSelection() }
            .optionalShortcut(shortcuts.shortcut(.analyzeSelection)?.menuShortcut)
            .disabled(engine.state.isBusy || !(target?.canAnalyzeSelection ?? false))
    }
}

/// Where Beat Key writes its DAW files (MIDI hand-offs, the REAPER mailbox, script sources).
enum DAWFiles {
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Beat Key/DAW", isDirectory: true)
    }

    /// A bundled script (Resources/DAWScripts), looked up like the textures.
    static func script(_ name: String, ext: String) -> String? {
        let main = Bundle.main
        var urls: [URL?] = [main.url(forResource: name, withExtension: ext)]
        urls += Textures.bundleCandidates().map { Bundle(url: $0)?.url(forResource: name, withExtension: ext) }
        for case let u? in urls { if let s = try? String(contentsOf: u, encoding: .utf8) { return s } }
        return nil
    }

    /// Writes `text` to `url`, making folders, atomically.
    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
