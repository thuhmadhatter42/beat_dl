import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The whole window: the plate on the desk, with the rail, the LCD and the link row.
struct FaceplateView: View {
    @ObservedObject var engine: Engine
    @ObservedObject var model: FaceplateModel
    @ObservedObject var login: YouTubeSession
    @ObservedObject var tuning: TuningSettings
    @ObservedObject var live: LiveController
    @ObservedObject var display: DisplaySettings
    @ObservedObject private var spelling = SpellingSettings.shared
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            Plate {
                VStack(spacing: 0) {
                    Rail(status: railStatus)
                    module.padding(.top, 10)
                }
            }
            .padding(.top, 6)          // + the 28 pt title bar above = the mockup's traffic-light gap
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: FaceplateView.size.width, height: FaceplateView.size.height)
        // the desk runs up under the hidden title bar; SwiftUI adds the bar's 28 pt to the window
        .background(Theme.desk.edgesIgnoringSafeArea(.all))
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
        .onAppear(perform: installKeys)
        .onAppear(perform: installIntake)
        .onDisappear { if let m = keyMonitor { NSEvent.removeMonitor(m) }; Intake.handler = nil }
    }

    /// The content below the title bar; the window is 552 x 438 with the bar.
    /// (One 36 pt row + its 10 pt gap more than the mockup's 552 x 392.)
    static let size = CGSize(width: 552, height: 410)
    /// Both caps share one width so the two fields line up.
    static let capLegendWidth: CGFloat = 92
    /// The login cap's longer legend (8 pt) needs a wider cap.
    static let loginLegendWidth: CGFloat = 170

    // MARK: module: LCD + row

    private var module: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return VStack(spacing: 0) {
            LCD(readout: readout, highlighted: showDrop) { step in
                if step < 0 { model.pager.previous() } else { model.pager.next() }
            }
            .id(display.highContrast)   // Theme.highContrast is read while drawing: redraw the readout
            HStack(spacing: 12) {
                LinkField(text: $model.url, focused: $model.fieldFocused, onSubmit: download)
                if loginPrompt != nil, let cap = Faceplate.loginCap(busy: engine.state.isBusy) {
                    Button(action: openLogin) {
                        SSLCapStyle.label(cap.label, size: 8).lineLimit(1).fixedSize().frame(width: FaceplateView.loginLegendWidth)
                    }
                    .buttonStyle(SSLCapStyle(lit: cap.lit))
                    .accessibility(label: Text(cap.label.capitalized))
                } else {
                    Button(action: download) { SSLCapStyle.label("DOWNLOAD").frame(width: FaceplateView.capLegendWidth) }
                        // not .disabled(): AppKit would grey the legend; download() ignores an unlit cap
                        .buttonStyle(SSLCapStyle(lit: lit))
                        .accessibility(label: Text("Download"))
                        .accessibility(hint: Text(lit ? "Downloads the link as an MP3 into Downloads" : "Paste a YouTube link first"))
                }
            }
            .padding(.top, 14)
            HStack(spacing: 12) {
                AudioPickField(label: Faceplate.pickLabel(model.picked), focused: $model.pickFocused,
                               onOpen: openAudio, onSubmit: { findLit ? find() : openAudio() })
                Button(action: find) { SSLCapStyle.label("FIND KEY/BPM").frame(width: FaceplateView.capLegendWidth) }
                    .buttonStyle(SSLCapStyle(lit: findLit))
                    .accessibility(label: Text("Find key and BPM"))
                    .accessibility(hint: Text(findLit ? "Finds the BPM and key of the chosen audio" : "Open an audio file first"))
            }
            .padding(.top, 10)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        .background(Theme.vertical([(Theme.hex(0x1d1d20), 0), (Theme.hex(0x151517), 1)]).clipShape(shape))
        .innerShadow(shape, Color.white.opacity(0.06), blur: 0, y: 1)
        .ring(radius: 7, spread: 1, Theme.black)
        .dropShadow(radius: 7, Color.black.opacity(0.7), blur: 3, y: 1)
    }

    // MARK: derived state

    private var loginPrompt: LoginPrompt? { Faceplate.loginPrompt(engine.state, url: model.url) }

    /// Unlit while the link is one that needs a login (the fallback readout): a re-try would only fail again.
    private var lit: Bool { Faceplate.isLit(model.url, busy: engine.state.isBusy) && loginPrompt == nil }
    private var findLit: Bool { Faceplate.isFindLit(model.picked, busy: engine.state.isBusy) }
    private var showDrop: Bool { model.pinnedDrop || (model.dropTargeted && !engine.state.isBusy) }

    private var railStatus: Rail.Status {
        switch engine.state {
        case .working: return .working
        case .failed: return .failed
        case .doctor(let r): return r.outcome == .failed ? .failed : .ready
        default: return .ready
        }
    }

    private var readout: Readout {
        if showDrop { return .drop }
        return Faceplate.readout(engine.state, live: live.state, liveSource: live.sourceName, page: model.pager,
                                 factor: model.tempoFactor, lastAction: model.lastAction, note: engine.note,
                                 reference: tuning.reference,
                                 onCycleTempo: { model.tempoFactor = model.tempoFactor.next },
                                 held: live.isHeld, spelling: spelling.preference,
                                 onToggleSpelling: toggleSpelling)
    }

    /// A click on the key: switch it between sharp and flat (the reading as shown decides which way).
    private func toggleSpelling() {
        if case .result(let r, _, _, _, _) = readout, let k = r.keys.first?.0 { spelling.click(on: k) }
    }

    private var dropBinding: Binding<Bool> {
        Binding(get: { model.dropTargeted }, set: { model.dropTargeted = $0 })
    }

    // MARK: actions

    /// LOG IN TO YOUTUBE: Beat Key's own login window. Once it has the login, the same link runs
    /// again with it (if that link is still the one waiting).
    private func openLogin() {
        guard let p = loginPrompt, !engine.state.isBusy, YouTubeLogin.inApp else { return }
        LoginWindow.open(saving: login.file) { [engine, model, login] in
            login.refresh()
            guard Faceplate.loginPrompt(engine.state, url: model.url)?.url == p.url else { return }
            model.lastAction = .download
            engine.download(p.url, useLogin: true)
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func download() {
        if loginPrompt != nil { if YouTubeLogin.inApp { openLogin() }; return }
        guard lit else { return }
        model.lastAction = .download
        engine.download(model.url.trimmingCharacters(in: .whitespacesAndNewlines))
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// The audio-only open panel (the drop filter's allowlist), several files allowed.
    private func openAudio() {
        guard !engine.state.isBusy else { return }
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

extension Faceplate {
    /// What the readout shows for the engine and Listen: one derivation for the window's LCD and
    /// the menu-bar popover. Listen's reading wins while it is on; else the engine's state.
    static func readout(_ state: ViewState, live: LiveState, liveSource: String, page: Pager,
                        factor: TempoFactor, lastAction: LastAction, note: String?, reference: Double,
                        onCycleTempo: (() -> Void)?, held: Bool = false, spelling: KeySpelling? = nil,
                        onToggleSpelling: (() -> Void)? = nil) -> Readout {
        if let l = liveReadout(live, source: liveSource, factor: factor, onCycleTempo: onCycleTempo, held: held,
                               spelling: spelling, onToggleSpelling: onToggleSpelling) { return l }
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
