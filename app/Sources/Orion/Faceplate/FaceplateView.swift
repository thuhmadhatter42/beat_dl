import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// The whole window: observes the app's objects and hands FaceplateFace plain values (the
/// popover's PocketState and PocketActions: one state source, one wiring for both surfaces).
struct FaceplateView: View {
    @ObservedObject var engine: Engine
    @ObservedObject var model: FaceplateModel
    @ObservedObject var login: YouTubeSession
    @ObservedObject var tuning: TuningSettings
    @ObservedObject var live: LiveController
    @ObservedObject var display: DisplaySettings
    @ObservedObject var recents: RecentStore
    @ObservedObject var shortcuts: ShortcutStore
    @ObservedObject var extras: PocketExtras
    /// PocketActions.wired: the popover's controls, wired the same way.
    let actions: PocketActions
    @ObservedObject private var spelling = SpellingSettings.shared
    @ObservedObject private var watcher = DAWWatcher.shared
    @ObservedObject private var help = HelpSettings.shared
    @State private var keyMonitor: Any?
    @State private var pasteboardCount = NSPasteboard.general.changeCount
    private let clipboardTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        FaceplateFace(state: state, picked: model.picked, url: $model.url, fieldFocused: $model.fieldFocused,
                      pickFocused: $model.pickFocused, actions: windowActions,
                      files: FaceplateFace.FileActions(openAudio: openAudio, find: find))
        .onDrop(of: ["public.file-url"], isTargeted: dropBinding, perform: drop)
        .onReceive(engine.$state) { s in
            // a download, an analysis, Run Doctor or a recent reading takes the LCD back from Listen
            if s != .idle && live.state != .off { live.stop() }
            switch s {
            case .done: model.url = ""; model.tempoFactor = .one
            case .analyzed(let rs): model.pager.reset(count: rs.count); model.picked = []; model.tempoFactor = .one
            default: break
            }
            login.refresh()   // a stale login was just dropped, or a new one saved
        }
        .onReceive(model.$url) { u in
            // changing the link drops a pending login prompt (it belongs to the old link)
            let t = u.trimmingCharacters(in: .whitespacesAndNewlines)
            if case .needsLogin(let p) = engine.state, t != p.url { engine.clearLogin() }
        }
        .onReceive(model.$pager) { _ in model.tempoFactor = .one }   // each file reads at x1
        // the clipboard line and the source name: on show, on coming to the front, on a new copy
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            extras.refresh(live: live)
        }
        .onReceive(clipboardTick) { _ in
            let n = NSPasteboard.general.changeCount
            if n != pasteboardCount { pasteboardCount = n; extras.refresh(live: live) }
        }
        .onAppear { extras.refresh(live: live) }
        .onAppear(perform: installKeys)
        .onAppear(perform: installIntake)
        .onDisappear { if let m = keyMonitor { NSEvent.removeMonitor(m) }; Intake.handler = nil }
    }

    /// The content below the title bar (the window adds the 28 pt bar): the plate with the
    /// rail, the readout (dial, BPM, top keys, keyboard), the link / audio / listen rows, the
    /// send caps and the footer links. Advanced mode adds the harmony column to the right: the
    /// window grows wider, never taller (laptop screens have width to spare, not height).
    static func size(advanced: Bool) -> CGSize {
        CGSize(width: plateWidth(advanced: advanced) + 32, height: 732)
    }
    static let size = size(advanced: false)
    /// The module column inside the plate's 12 pt padding (the default plate is 520).
    static let moduleWidth: CGFloat = 520 - 24
    static let columnGap: CGFloat = 12
    /// The plate: the module, plus the gap and the harmony column in Advanced mode.
    static func plateWidth(advanced: Bool) -> CGFloat {
        advanced ? 520 + columnGap + HarmonyPanel.width : 520
    }
    /// Every cap on the right of a field shares one width so the fields line up; it fits the
    /// longest legend in that column (PASTE + DOWNLOAD).
    static let capWidth: CGFloat = 152
    /// The scale keyboard in the window's readout (J 2026-11-09: taller, same width).
    static let keyboardHeight: CGFloat = 84

    // MARK: derived state

    /// The popover's state (PocketState.make), with the window's drag-hover readout.
    private var state: PocketState {
        var s = PocketState.make(engine: engine, model: model, live: live, tuning: tuning, recents: recents,
                                 display: display, shortcuts: shortcuts, extras: extras, spelling: spelling,
                                 daw: watcher.target?.name)
        if showDrop { s.readout = .drop }
        return s
    }

    /// The shared wiring; the window runs the YouTube login itself (the popover sends it here)
    /// and owns Advanced mode's harmony column (the pocket has none).
    private var windowActions: PocketActions {
        var a = actions
        a.openLogin = openLogin
        let (e, m, l, d) = (engine, model, live, display)
        let shown = { PocketState.shown(e.state, live: l.state, page: m.pager) }
        a.playChord = { chord in
            let bpm = ChordClip.bpm(shown(), factor: m.tempoFactor)
            AppLog.log("window: chord \(chord.asciiName) played (\(d.chordVoicing.rawValue), \(d.chordBars) bar)")
            NoteSynth.shared.play(chord.notes(d.chordVoicing), seconds: ChordClip.hearSeconds(bars: d.chordBars, bpm: bpm))
        }
        a.chordFile = { chord in
            let r = shown()
            let bpm = ChordClip.bpm(r, factor: m.tempoFactor)
            let url = ChordClip.write(chord, voicing: d.chordVoicing, bars: d.chordBars, bpm: bpm, key: r?.keys.first?.0)
            if url != nil { AppLog.log("window: chord \(chord.asciiName) dragged as a MIDI clip") }
            return url
        }
        a.setHarmony = { p in
            AppLog.log("window: chords \(p.quality.rawValue) \(p.voicing.rawValue) \(p.bars) bar")
            p.apply(to: d)
        }
        a.pickMatchKey = {
            AppLog.log("window: match to menu")
            let items = KeyChoice.allKeys.enumerated().flatMap { i, k -> [PopupMenu.Item] in
                let item = PopupMenu.Item(title: k, checked: d.matchKey == k) {
                    AppLog.log("window: match to \(k)")
                    d.matchKey = k
                }
                return i == 12 ? [.separator, item] : [item]
            }
            PopupMenu.show(items + [.separator, PopupMenu.Item(title: "None", checked: d.matchKey == nil) { d.matchKey = nil }])
        }
        return a
    }

    private var loginPrompt: LoginPrompt? { Faceplate.loginPrompt(engine.state, url: model.url) }
    private var findLit: Bool { Faceplate.isFindLit(model.picked, busy: engine.state.isBusy) }
    private var showDrop: Bool { model.pinnedDrop || (model.dropTargeted && !engine.state.isBusy) }

    private var dropBinding: Binding<Bool> {
        Binding(get: { model.dropTargeted }, set: { model.dropTargeted = $0 })
    }

    // MARK: actions

    /// LOG IN TO YOUTUBE: Beat Key's own login window. Once it has the login, the same link runs
    /// again with it (if that link is still the one waiting).
    private func openLogin() {
        guard let p = loginPrompt, !engine.state.isBusy, YouTubeLogin.inApp else { return }
        AppLog.log("window: log in to YouTube")
        LoginWindow.open(saving: login.file) { [engine, model, login] in
            login.refresh()
            guard Faceplate.loginPrompt(engine.state, url: model.url)?.url == p.url else { return }
            model.lastAction = .download
            engine.download(p.url, useLogin: true)
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// The audio-only open panel (the drop filter's allowlist), several files allowed.
    private func openAudio() {
        guard !engine.state.isBusy else { return }
        AppLog.log("window: open audio")
        let panel = Intake.makePanel()
        let pick = { (resp: NSApplication.ModalResponse) in
            guard resp == .OK else { return }
            let files = Faceplate.audioFiles(panel.urls)
            if !files.isEmpty { model.picked = files }
        }
        if let w = NSApp.keyWindow ?? NSApp.windows.first { panel.beginSheetModal(for: w, completionHandler: pick) }
        else { pick(panel.runModal()) }
    }

    /// Analyze a File…, the Finder service and Open With all arrive here and read at once.
    private func installIntake() {
        Intake.handler = { [engine, model] files in
            guard !engine.state.isBusy else { return false }
            model.lastAction = .analyze
            engine.analyze(files)
            return true
        }
    }

    private func find() {
        guard findLit else { return }
        AppLog.log("window: find key/bpm (\(model.picked.count) files)")
        model.lastAction = .analyze
        engine.analyze(model.picked)
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard !engine.state.isBusy else { return false }
        let group = DispatchGroup()
        var urls: [Int: URL] = [:]
        let lock = NSLock()
        for (i, p) in providers.enumerated() where p.hasItemConformingToTypeIdentifier("public.file-url") {
            group.enter()
            p.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                var u: URL?
                if let d = item as? Data { u = URL(dataRepresentation: d, relativeTo: nil) }
                else if let x = item as? URL { u = x }
                if let u = u, u.isFileURL { lock.lock(); urls[i] = u; lock.unlock() }
            }
        }
        group.notify(queue: .main) {
            // audio files only; a drop with none (folder, PDF...) changes nothing
            let files = Faceplate.audioFiles(urls.keys.sorted().compactMap { urls[$0] })
            guard !files.isEmpty else { return }
            model.lastAction = .analyze
            engine.analyze(files)
        }
        return true
    }

    /// Left/right arrows page through several dropped files (unless the caret is in a link).
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.keyCode == 123 || e.keyCode == 124, case .analyzed = engine.state,
                  model.pager.count > 1 else { return e }
            if let tv = e.window?.firstResponder as? NSTextView, !tv.string.isEmpty { return e }
            if e.keyCode == 123 { model.pager.previous() } else { model.pager.next() }
            return nil
        }
    }
}

/// The window as plain values (so it can be rendered offscreen and tested, like PocketView):
/// the desk, the plate, the rail, the module and the footer. Every control that the popover has
/// is the popover's own view, fed the same PocketState and PocketActions.
struct FaceplateFace: View {
    let state: PocketState
    /// Audio chosen with the Open Audio... field, waiting for FIND KEY/BPM.
    let picked: [URL]
    @Binding var url: String
    @Binding var fieldFocused: Bool
    @Binding var pickFocused: Bool
    var actions = PocketActions()
    var files = FileActions()

    /// The window's own second row: pick audio into the field, then read it.
    struct FileActions {
        var openAudio: () -> Void = {}
        var find: () -> Void = {}
    }

    var body: some View {
        let size = FaceplateView.size(advanced: state.advanced)
        VStack(spacing: 0) {
            Plate(width: FaceplateView.plateWidth(advanced: state.advanced)) {
                VStack(spacing: 0) {
                    Rail(status: FaceplateFace.railStatus(state))
                    HStack(alignment: .top, spacing: FaceplateView.columnGap) {
                        module.frame(width: FaceplateView.moduleWidth)
                        if state.advanced {
                            HarmonyPanel(state: state, actions: actions).frame(width: HarmonyPanel.width)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    footer.padding(.top, 10)
                }
            }
            .padding(.top, 6)          // + the 28 pt title bar above = the mockup's traffic-light gap
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.helpMode, state.help)
        .helpTipLayer()
        // the desk runs up under the hidden title bar; SwiftUI adds the bar's 28 pt to the window
        .background(Theme.desk.edgesIgnoringSafeArea(.all))
    }

    /// The rail's legend: LIVE · <source> while listening, else the readout's state.
    static func railStatus(_ s: PocketState) -> Rail.Status {
        if s.listening { return .live(s.source.uppercased()) }
        switch s.readout {
        case .working: return .working
        case .error: return .failed
        case .doctor(let r): return r.outcome == .failed ? .failed : .ready
        default: return .ready
        }
    }

    private var highlighted: Bool {
        if case .drop = state.readout { return true }
        return false
    }

    private var findLit: Bool { Faceplate.isFindLit(picked, busy: state.busy) }
    private var capWidth: CGFloat { FaceplateView.capWidth }

    // MARK: module: readout + rows

    private var module: some View {
        VStack(spacing: 0) {
            LCD(state: state, highlighted: highlighted, actions: actions)
                .id(state.highContrast)   // Theme.highContrast is read while drawing: redraw the readout
            HStack(spacing: 12) {
                LinkField(text: $url, focused: $fieldFocused, onSubmit: { actions.downloadPressed(state) })
                if state.needsLogin, let cap = Faceplate.loginCap(busy: state.busy) {
                    Button(action: actions.openLogin) {
                        SSLCapStyle.label(cap.label).lineLimit(1).fixedSize().frame(minWidth: capWidth - SSLCapStyle.sidePadding * 2)
                    }
                    .buttonStyle(SSLCapStyle(lit: cap.lit))
                    .accessibility(label: Text(cap.label.capitalized))
                    .helpTip(HelpText.download)
                } else {
                    DownloadCap(state: state, action: { actions.downloadPressed(state) }).frame(width: capWidth)
                }
            }
            .padding(.top, 14)
            HStack(spacing: 12) {
                AudioPickField(label: Faceplate.pickLabel(picked), focused: $pickFocused,
                               onOpen: files.openAudio, onSubmit: { findLit ? files.find() : files.openAudio() })
                    .helpTip(HelpText.openAudio)
                Button(action: files.find) { SSLCapStyle.label("FIND KEY/BPM").lineLimit(1).frame(maxWidth: .infinity) }
                    .buttonStyle(SSLCapStyle(lit: findLit))
                    .frame(width: capWidth)
                    .accessibility(label: Text("Find key and BPM"))
                    .accessibility(hint: Text(findLit ? "Finds the BPM and key of the chosen audio" : "Open an audio file first"))
                    .helpTip(HelpText.findKey)
            }
            .padding(.top, 10)
            // the window keeps its size: HOLD and the reset key stay put, dim until Listen is on
            HStack(spacing: 10) {
                SourceField(source: state.source, level: state.level, listening: state.listening,
                            action: actions.pickSource)
                HStack(spacing: Pocket.transportGap) {
                    HoldCap(state: state, action: actions.toggleHold).frame(width: 72)
                    NewSongCap(lit: state.listening, keys: state.newSongKeys, action: actions.newSong)
                }
                ListenCap(state: state, action: actions.toggleListen).frame(width: capWidth)
            }
            .padding(.top, 10)
            ModuleRule().padding(.vertical, 14)
            HStack(spacing: 12) {
                SendDAWCap(state: state, action: actions.sendDAW)
                AutoTuneCap(state: state, send: actions.sendAutoTune)
                ExportMidiCap(state: state, action: actions.exportMidi)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        .modulePanel()
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 16) {
            RecentLink(state: state, action: actions.showRecents)
            FooterLink(title: "SETTINGS", label: "Settings", action: actions.settings).helpTip(HelpText.settings)
            HelpChip(on: state.help, action: actions.toggleHelp)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 16)
    }
}

extension Faceplate {
    /// What the readout shows for the engine and Listen: one derivation for the window's LCD and
    /// the menu-bar popover. Listen's reading wins while it is on; else the engine's state.
    static func readout(_ state: ViewState, live: LiveState, liveSource: String, page: Pager,
                        factor: TempoFactor, lastAction: LastAction, note: String?, reference: Double,
                        onCycleTempo: (() -> Void)?, held: Bool = false, spelling: KeySpelling? = nil,
                        onToggleSpelling: (() -> Void)? = nil, liveNotice: String? = nil) -> Readout {
        if let l = liveReadout(live, source: liveSource, factor: factor, onCycleTempo: onCycleTempo, held: held,
                               spelling: spelling, onToggleSpelling: onToggleSpelling,
                               reference: reference, notice: liveNotice) { return l }
        let dl = lastAction == .download
        func options(_ r: Result) -> ResultOptions {
            ResultOptions(factor: factor, tuning: Tuning.line(r.tuningCents, reference: reference),
                          onCycleTempo: onCycleTempo, onToggleSpelling: onToggleSpelling)
        }
        switch state {
        case .idle: return .idle
        case .working(let s): return .working(stage: s, download: dl)
        case .doctor(let r): return .doctor(r)
        case .done(let r0):
            let r = r0.respelled(spelling)
            return .result(r, page: nil, download: true, options: options(r))
        case .analyzed(let rs):
            guard !rs.isEmpty else { return .idle }
            let i = min(page.index, rs.count - 1)
            let r = rs[i].respelled(spelling)
            return .result(r, page: page.caption, download: false, note: note, options: options(r))
        case .failed(let m): return .error(m, download: dl)
        case .needsLogin(let p):
            let (a, b) = loginLines(p)
            return .login(a, b, caption: nil)
        }
    }
}
