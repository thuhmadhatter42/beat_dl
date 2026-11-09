import AppKit
import Combine
import SwiftUI

/// What the menu-bar item says: "Ebm 128.0" and the confidence lamp, for the reading on the LCD.
/// nil text = no reading (the key glyph and a dash).
struct MenuBarReadout: Equatable {
    var text: String?
    var lamp: Lamp?
    /// The last reading shown while nothing is on the readout: drawn dimmed.
    var dim = false
    /// The full line for the menu's first row and VoiceOver.
    var detail: String

    static let idle = MenuBarReadout(text: nil, lamp: nil, detail: "No reading yet")

    /// The reading `r` as the menu bar shows it: top key, then the BPM to one decimal at `factor`.
    static func of(_ r0: Result, factor: TempoFactor = .one, lamp: Lamp? = nil, status: String? = nil,
                   held: Bool = false, spelling: KeySpelling? = nil) -> MenuBarReadout {
        let r = r0.respelled(spelling)
        let bpm = Tempo.text(r, factor: factor).flatMap(Double.init).map { String(format: "%.1f", $0) }
        let key = r.keys.first?.0
        let parts = [key, bpm].compactMap { $0 }
        guard !parts.isEmpty else { return MenuBarReadout(text: nil, lamp: nil, detail: "Nothing read") }
        let lampNow = lamp ?? Lamp.of(r.keys)
        var detail = [key.map { "Key \($0)" }, Tempo.text(r, factor: factor).map { "\($0) BPM" }].compactMap { $0 }
        if let s = status ?? Faceplate.confidenceLine(r.keys) { detail.append(s.capitalized) }
        let line = parts.joined(separator: " ")
        return MenuBarReadout(text: held ? "⏸ " + line : line, lamp: lampNow,
                              detail: (held ? "Held · " : "") + detail.joined(separator: " · "))
    }

    /// The engine's reading: the finished download, or the file paged to on the LCD.
    static func of(_ state: ViewState, page: Int, factor: TempoFactor, spelling: KeySpelling? = nil) -> MenuBarReadout {
        switch state {
        case .done(let r):
            return of(r, factor: factor, spelling: spelling)
        case .analyzed(let rs) where !rs.isEmpty:
            return of(rs[min(max(page, 0), rs.count - 1)], factor: factor, spelling: spelling)
        case .working(let s):
            return MenuBarReadout(text: nil, lamp: .listening, detail: Faceplate.stageText(s).capitalized)
        default:
            return .idle
        }
    }

    /// Listen's reading; nil when Listen is off (the engine's reading shows).
    static func of(live: LiveState, source: String, factor: TempoFactor, held: Bool = false,
                   spelling: KeySpelling? = nil) -> MenuBarReadout? {
        switch live {
        case .off:
            return nil
        case .failed:
            return MenuBarReadout(text: nil, lamp: nil, detail: "Listening stopped")
        case .listening:
            return MenuBarReadout(text: nil, lamp: .listening, detail: "Listening · \(source)")
        case .reading(let r), .locked(let r):
            let m = of(r, factor: factor, lamp: live.lamp, status: live.status(source: source), held: held,
                       spelling: spelling)
            // No key in the menu bar until Beat Key is sure (green): an unsure guess is not a key.
            // The coloured key says how far along it is; the popover still shows the top 3.
            guard m.text != nil, live.lamp == .locked || held else {
                return MenuBarReadout(text: nil, lamp: live.lamp ?? .listening, detail: m.detail)
            }
            return m
        }
    }

    /// Spoken by VoiceOver for the status item.
    var accessibilityLabel: String {
        "\(Brand.name): \(detail)" + (lamp.map { ", \($0.spoken)" } ?? "")
    }
}

/// The menu-bar item (NSStatusItem: one mechanism on macOS 12 and later; MenuBarExtra is 13+ and
/// would need a second, fallback path for 12). The title follows the LCD's reading. A click opens
/// the pocket faceplate (an NSPopover holding PocketView); a right-click or Control-click opens
/// the short menu (listen, analyze, window, settings, quit).
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()

    private var item: NSStatusItem?
    private var bag = Set<AnyCancellable>()
    private(set) var readout = MenuBarReadout.idle
    private let menu = NSMenu()
    private let detailRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let popover = NSPopover()
    /// The clipboard link and source name, shared with the window (OrionApp owns it).
    private var extras = PocketExtras()

    private weak var engine: Engine?
    private weak var live: LiveController?
    private var toggleListening: (() -> Void)?
    private var newSong: (() -> Void)?
    private var toggleHold: (() -> Void)?

    /// Called once the window is up (OrionApp.launch).
    func install(engine: Engine, model: FaceplateModel, live: LiveController, tuning: TuningSettings,
                 recents: RecentStore, display: DisplaySettings, shortcuts: ShortcutStore, extras: PocketExtras,
                 toggleListening: @escaping () -> Void, newSong: @escaping () -> Void,
                 toggleHold: @escaping () -> Void = {}, showAgain: @escaping (Reading) -> Void) {
        guard item == nil else { return }
        self.extras = extras
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item = it
        menu.delegate = self
        menu.autoenablesItems = false
        if let b = it.button {
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.engine = engine
        self.live = live
        self.toggleListening = toggleListening
        self.newSong = newSong
        self.toggleHold = toggleHold
        Publishers.CombineLatest(
            Publishers.CombineLatest4(engine.$state, model.$pager, model.$tempoFactor,
                                      live.$state.combineLatest(live.$sourceName)),
            recents.$readings.combineLatest(live.$isHeld, SpellingSettings.shared.changes))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] a, b in
                let (state, pager, factor, l) = a
                let (readings, held, spelling) = b
                let r = MenuBarReadout.of(live: l.0, source: l.1, factor: factor, held: held, spelling: spelling)
                    ?? MenuBarReadout.of(state, page: pager.index, factor: factor, spelling: spelling)
                _ = readings; self?.show(r)
            }
            .store(in: &bag)

        let actions = PocketActions.wired(surface: "pocket", engine: engine, model: model, live: live, tuning: tuning,
                                          recents: recents, extras: extras, toggleListening: toggleListening,
                                          newSong: newSong, toggleHold: toggleHold, showAgain: showAgain,
                                          close: { [weak self] in self?.closePopover() })
        let root = PocketContainer(engine: engine, model: model, live: live, tuning: tuning, recents: recents,
                                   display: display, shortcuts: shortcuts, extras: extras, actions: actions) { [weak self] size in
            guard let self = self, size.width > 0, size.height > 0 else { return }
            if self.popover.contentSize != size { self.popover.contentSize = size }
        }
        let host = NSHostingController(rootView: root)
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentSize = host.view.fittingSize
    }

    func show(_ r: MenuBarReadout) {
        readout = r
        guard let button = item?.button else { return }
        // The key (gold = no reading, else the lamp's colour) sits AFTER the reading, and the item
        // is one fixed width, so nothing in the menu bar shifts as readings change.
        button.image = MenuBarImage.make(r.lamp)
        button.imagePosition = .imageTrailing
        button.alignment = .center
        let quiet = r.dim || r.text == nil
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.attributedTitle = NSAttributedString(string: r.text.map { $0 + " " } ?? "", attributes: [
            .font: font,
            .foregroundColor: quiet ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ])
        // ONE width in every state (idle, "…", analyzing, a reading): the item never changes size,
        // so the popover hanging under it never slides.
        let w = StatusItemController.fixedWidth(font: font)
        if item?.length != w { item?.length = w }
        button.setAccessibilityLabel(r.accessibilityLabel)
        button.toolTip = r.detail
        if let f = button.window?.frame, f != lastItemFrame {
            AppLog.log("menu-bar item frame \(NSStringFromRect(f)) showing \(r.text ?? "-")")
            lastItemFrame = f
        }
    }

    private var lastItemFrame: NSRect = .zero

    /// Wide enough for the longest reading ("G#m 188.8" + the key), so the item never resizes.
    static func fixedWidth(font: NSFont) -> CGFloat {
        let text = ("⏸ G#m 888.8 " as NSString).size(withAttributes: [.font: font]).width
        return (text + MenuBarImage.key().size.width + 6).rounded(.up)
    }

    // MARK: click = popover, right-click = menu

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true { showMenu() } else { togglePopover() }
    }

    private func showMenu() {
        popover.performClose(nil)
        guard let it = item else { return }
        it.menu = menu
        it.button?.performClick(nil)
        it.menu = nil
    }

    func togglePopover() {
        guard let button = item?.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        extras.refresh(live: live)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() { popover.performClose(nil) }

    // MARK: menu (right-click)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        detailRow.title = readout.detail
        detailRow.isEnabled = false
        menu.addItem(detailRow)
        menu.addItem(.separator())
        let active = live?.state.isActive ?? false
        let source = live?.settings.sourceName(devices: InputDevice.all()) ?? ""
        let listen = NSMenuItem(title: active ? "Stop Listening" : "Start Listening · \(source)",
                                action: #selector(listenToggled), keyEquivalent: "")
        listen.target = self
        listen.isEnabled = active || !(engine?.state.isBusy ?? false)
        menu.addItem(listen)
        let reset = NSMenuItem(title: "New Song (Reset Listening)", action: #selector(newSongChosen), keyEquivalent: "")
        reset.target = self
        reset.isEnabled = active
        menu.addItem(reset)
        let hold = NSMenuItem(title: "Hold Reading", action: #selector(holdChosen), keyEquivalent: "")
        hold.target = self
        hold.state = (live?.isHeld ?? false) ? .on : .off
        hold.isEnabled = (live?.isHeld ?? false) || (active && live?.state.result != nil)
        menu.addItem(hold)
        let analyze = NSMenuItem(title: "Analyze a File…", action: #selector(analyzeFile), keyEquivalent: "")
        analyze.target = self
        analyze.isEnabled = !(engine?.state.isBusy ?? false)
        menu.addItem(analyze)
        menu.addItem(.separator())
        let show = NSMenuItem(title: "Show \(Brand.name)", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: Brand.quit, action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func analyzeFile() {
        StatusItemController.bringWindowForward()
        Intake.analyzeAFile()
    }

    @objc private func showWindow() { StatusItemController.bringWindowForward() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openSettings() { SettingsOpener.open() }
    @objc private func listenToggled() { toggleListening?() }
    @objc private func newSongChosen() { newSong?() }
    @objc private func holdChosen() { toggleHold?() }

    /// The faceplate window to the front (it may be minimised or behind other apps).
    static func bringWindowForward() {
        NSApp.activate(ignoringOtherApps: true)
        let w = NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }
        if let w = w {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        }
    }
}

/// The controls of both surfaces (the popover and the window), wired once to the same calls the
/// menus make. `close` hides the surface first where it is a popover (the window passes nothing).
extension PocketActions {
    static func wired(surface: String, engine: Engine, model: FaceplateModel, live: LiveController,
                      tuning: TuningSettings, recents: RecentStore, extras: PocketExtras,
                      toggleListening: @escaping () -> Void, newSong: @escaping () -> Void,
                      toggleHold: @escaping () -> Void, showAgain: @escaping (Reading) -> Void,
                      close: @escaping () -> Void = {}) -> PocketActions {
        func log(_ s: String) { AppLog.log("\(surface): \(s)") }
        var a = PocketActions()
        let shown = { PocketState.shown(engine.state, live: live.state, page: model.pager) }
        a.setFactor = { f in log("tempo factor \(f.label ?? "x1")"); model.tempoFactor = f }
        a.page = { step in
            log(step < 0 ? "previous file" : "next file")
            if step < 0 { model.pager.previous() } else { model.pager.next() }
        }
        let download = {
            guard Faceplate.isLit(model.url, busy: engine.state.isBusy),
                  Faceplate.loginPrompt(engine.state, url: model.url) == nil else { NSSound.beep(); return }
            log("download")
            model.lastAction = .download
            engine.download(model.url.trimmingCharacters(in: .whitespacesAndNewlines))
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        a.download = download
        a.pasteAndDownload = { link in log("paste + download from the clipboard"); model.url = link; download() }
        // the window's LOG IN TO YOUTUBE cap runs the login (one login path); the window overrides this
        a.openLogin = { log("log in: to the window"); close(); StatusItemController.bringWindowForward() }
        a.toggleListen = { log(live.state.isActive ? "stop listening" : "start listening"); toggleListening() }
        a.newSong = { log("new song (reset listening)"); newSong() }
        a.toggleHold = { log(live.isHeld ? "release hold" : "hold reading"); toggleHold() }
        a.respellKey = {
            guard let k = shown()?.keys.first?.0 else { return }
            log("respell key")
            SpellingSettings.shared.click(on: k)
        }
        a.teachKey = {
            guard let r = shown() else { NSSound.beep(); return }
            log("wrong key menu")
            let now = r.keys.first.flatMap { AutoTuneSend.keyClass($0.0) }
            PopupMenu.show(KeyChoice.allKeys.enumerated().flatMap { i, k -> [PopupMenu.Item] in
                let kc = AutoTuneSend.keyClass(k)
                let item = PopupMenu.Item(title: k, checked: kc?.pitchClass == now?.pitchClass && kc?.minor == now?.minor) {
                    KeyTeach.teach(k, engine: engine, live: live, model: model)
                }
                return i == 12 ? [.separator, item] : [item]
            })
        }
        a.pickSource = { log("source menu"); SourceMenu.show(live: live, extras: extras, close: close) }
        a.analyzeFile = {
            log("analyze a file")
            close()
            StatusItemController.bringWindowForward()
            Intake.analyzeAFile()
        }
        a.sendDAW = {
            guard let r = shown() else { NSSound.beep(); return }
            log("send to DAW")
            close()
            DAWSendController.send(r, toAll: false)
        }
        a.sendAutoTune = {
            log("send to auto-tune")
            guard let key = shown()?.keys.first?.0, AutoTuneSend.sendAll(key: key, referencePitch: tuning.reference)
            else { NSSound.beep(); return false }
            return true
        }
        a.exportMidi = {
            guard let r = shown() else { NSSound.beep(); return }
            log("export MIDI")
            close()
            NSApp.activate(ignoringOtherApps: true)
            MidiExport.runPanel(for: r)
        }
        a.showRecents = {
            log("recent readings menu")
            PopupMenu.show(recents.readings.map { r in PopupMenu.Item(title: r.title) { showAgain(r) } }
                           + [.separator, PopupMenu.Item(title: "Clear Menu") { recents.clear() }])
        }
        a.openWindow = { log("show window"); close(); StatusItemController.bringWindowForward() }
        a.settings = { log("settings"); close(); SettingsOpener.open() }
        a.quit = { log("quit"); NSApp.terminate(nil) }
        return a
    }
}

/// Listen to: System Audio (13+), the default input, or a device; a change while listening
/// starts over on the new source. The popover's and the window's SOURCE field.
enum SourceMenu {
    static func show(live: LiveController, extras: PocketExtras, close: @escaping () -> Void = {}) {
        let s = live.settings
        func pick(_ src: LiveSource) {
            AppLog.log("listen source picked")
            s.source = src
            extras.refresh(live: live)
            if live.state.isActive { live.start() }
        }
        var items: [PopupMenu.Item] = []
        if LiveSource.systemAvailable {
            items.append(PopupMenu.Item(title: "System Audio", checked: s.source == .system) { pick(.system) })
        }
        items.append(PopupMenu.Item(title: "Default Input", checked: s.source == .input(uid: nil, channel: 0)) {
            pick(.input(uid: nil, channel: 0))
        })
        for d in InputDevice.all() {
            var on = false
            if case .input(let uid, _) = s.source, uid == d.uid { on = true }
            items.append(PopupMenu.Item(title: d.name, checked: on) { pick(.input(uid: d.uid, channel: 0)) })
        }
        items += [.separator, PopupMenu.Item(title: "Channels and More…") { close(); SettingsOpener.open() }]
        PopupMenu.show(items)
    }
}

/// The small picture left of the menu-bar text: Beat Key's golden key with no reading, else the lamp.
enum MenuBarImage {
    static let side: CGFloat = 11

    /// The menu-bar key: gold with no reading, else the confidence lamp's colour (green locked,
    /// amber unsure, ...). `side` is kept for callers sizing it; the key is 12 pt tall by default.
    static func make(_ lamp: Lamp?, side: CGFloat = 12) -> NSImage? {
        guard let lamp = lamp else { return key(height: side) }
        return key(height: side, color: lamp.nsColor)
    }

    /// Beat Key's golden key (KeyGlyphShape: the app icon's dial head and toothed shaft): amber on
    /// a dark menu bar, a deeper gold on a light one, so it is findable either way.
    static func key(height: CGFloat = 12, color: NSColor? = nil) -> NSImage {
        let size = NSSize(width: (height * 1.75).rounded(), height: height)
        let img = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let gold = color ?? (dark ? NSColor(srgbRed: 1, green: 176 / 255, blue: 32 / 255, alpha: 1)
                            : NSColor(srgbRed: 168 / 255, green: 104 / 255, blue: 0, alpha: 1))
            ctx.addPath(KeyGlyphShape().path(in: rect.insetBy(dx: 0.25, dy: 0.25)).cgPath)
            ctx.setFillColor(gold.cgColor)
            ctx.fillPath(using: .evenOdd)
            return true
        }
        img.isTemplate = false
        img.accessibilityDescription = Brand.name
        return img
    }
}

/// The popover's own live values: the clipboard link and the source name (Core Audio is asked
/// when the popover opens, not on every redraw).
final class PocketExtras: ObservableObject {
    @Published var clipboardLink: String?
    @Published var sourceName = ""

    func refresh(live: LiveController?) {
        clipboardLink = Clipboard.currentLink()
        if let l = live { sourceName = l.state.isActive ? l.sourceName : l.settings.sourceName(devices: InputDevice.all()) }
    }
}

/// The popover's root: observes the app's objects and hands PocketView plain values.
struct PocketContainer: View {
    @ObservedObject var engine: Engine
    @ObservedObject var model: FaceplateModel
    @ObservedObject var live: LiveController
    @ObservedObject var tuning: TuningSettings
    @ObservedObject var recents: RecentStore
    @ObservedObject var display: DisplaySettings
    @ObservedObject var shortcuts: ShortcutStore
    @ObservedObject var extras: PocketExtras
    @ObservedObject private var spelling = SpellingSettings.shared
    @ObservedObject private var watcher = DAWWatcher.shared
    let actions: PocketActions
    let onSize: (CGSize) -> Void

    var body: some View {
        PocketView(state: state, url: $model.url, actions: actions)
            .fixedSize()
            .background(GeometryReader { g in Color.clear.preference(key: PocketSizeKey.self, value: g.size) })
            .onPreferenceChange(PocketSizeKey.self, perform: onSize)
    }

    private var state: PocketState {
        PocketState.make(engine: engine, model: model, live: live, tuning: tuning, recents: recents, display: display,
                         shortcuts: shortcuts, extras: extras, spelling: spelling, daw: watcher.target?.name)
    }
}

extension PocketState {
    /// Everything both surfaces draw, from the app's objects: one derivation for the popover and
    /// the window (the window then puts its own readout in, for the drag-hover highlight).
    static func make(engine: Engine, model: FaceplateModel, live: LiveController, tuning: TuningSettings,
                     recents: RecentStore, display: DisplaySettings, shortcuts: ShortcutStore, extras: PocketExtras,
                     spelling: SpellingSettings, daw: String?) -> PocketState {
        var s = PocketState()
        s.readout = Faceplate.readout(engine.state, live: live.state, liveSource: live.sourceName, page: model.pager,
                                      factor: model.tempoFactor, lastAction: model.lastAction, note: engine.note,
                                      reference: tuning.reference,
                                      onCycleTempo: { [model] in model.tempoFactor = model.tempoFactor.next },
                                      held: live.isHeld, spelling: spelling.preference)
        s.listening = live.state.isActive
        s.source = live.state.isActive ? live.sourceName : extras.sourceName
        s.level = live.level
        s.url = model.url
        s.busy = engine.state.isBusy
        s.needsLogin = Faceplate.loginPrompt(engine.state, url: model.url) != nil
        s.clipboardLink = extras.clipboardLink
        s.daw = daw
        s.recents = recents.readings
        s.highContrast = display.highContrast
        s.newSongKeys = shortcuts.shortcut(.newSong)?.display
        s.held = live.isHeld
        s.holdKeys = shortcuts.shortcut(.hold)?.display
        s.advanced = display.advanced
        s.harmony = HarmonyPrefs(display)
        return s
    }
}

private struct PocketSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// A small NSMenu popped up at the mouse, for pickers inside the popover (a SwiftUI Menu on
/// macOS 12 flattens its label to plain text).
enum PopupMenu {
    struct Item {
        var title: String
        var checked = false
        var action: (() -> Void)?
        static let separator = Item(title: "", action: nil)
        init(title: String, checked: Bool = false, action: (() -> Void)?) {
            self.title = title; self.checked = checked; self.action = action
        }
    }

    private final class Target: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    static func show(_ items: [Item]) {
        let m = NSMenu()
        m.autoenablesItems = false
        for it in items {
            guard let act = it.action else { m.addItem(.separator()); continue }
            let mi = NSMenuItem(title: it.title, action: #selector(Target.fire), keyEquivalent: "")
            let t = Target(act)
            mi.target = t
            mi.representedObject = t   // the item keeps its target alive
            mi.state = it.checked ? .on : .off
            m.addItem(mi)
        }
        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
