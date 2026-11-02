import AppKit
import Combine

/// What the menu-bar item says: "Ebm 128" and the confidence lamp, for the reading on the LCD.
/// nil text = no reading (the key glyph alone).
struct MenuBarReadout: Equatable {
    var text: String?
    var lamp: Lamp?
    /// The full line for the menu's first row and VoiceOver.
    var detail: String

    static let idle = MenuBarReadout(text: nil, lamp: nil, detail: "No reading yet")

    /// The reading `r` as the menu bar shows it: top key, then the whole-number BPM at `factor`.
    static func of(_ r: Result, factor: TempoFactor = .one, lamp: Lamp? = nil, status: String? = nil) -> MenuBarReadout {
        let bpm = Tempo.text(r, factor: factor).flatMap(Double.init).map { String(Int($0.rounded())) }
        let key = r.keys.first?.0
        let parts = [key, bpm].compactMap { $0 }
        guard !parts.isEmpty else { return MenuBarReadout(text: nil, lamp: nil, detail: "Nothing read") }
        let lampNow = lamp ?? Lamp.of(r.keys)
        var detail = [key.map { "Key \($0)" }, Tempo.text(r, factor: factor).map { "\($0) BPM" }].compactMap { $0 }
        if let s = status ?? Faceplate.confidenceLine(r.keys) { detail.append(s.capitalized) }
        return MenuBarReadout(text: parts.joined(separator: " "), lamp: lampNow,
                              detail: detail.joined(separator: " · "))
    }

    /// The engine's reading: the finished download, or the file paged to on the LCD.
    static func of(_ state: ViewState, page: Int, factor: TempoFactor) -> MenuBarReadout {
        switch state {
        case .done(let r):
            return of(r, factor: factor)
        case .analyzed(let rs) where !rs.isEmpty:
            return of(rs[min(max(page, 0), rs.count - 1)], factor: factor)
        case .working(let s):
            return MenuBarReadout(text: "…", lamp: .listening, detail: Faceplate.stageText(s).capitalized)
        default:
            return .idle
        }
    }

    /// Spoken by VoiceOver for the status item.
    var accessibilityLabel: String {
        "\(Brand.name): \(detail)" + (lamp.map { ", \($0.spoken)" } ?? "")
    }
}

/// The menu-bar item (NSStatusItem: one mechanism on macOS 12 and later; MenuBarExtra is 13+ and
/// would need a second, fallback path for 12). The title follows the LCD's reading; the menu
/// starts / stops listening, analyzes a file, and brings the window back.
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()

    private var item: NSStatusItem?
    private var bag = Set<AnyCancellable>()
    private(set) var readout = MenuBarReadout.idle
    private let menu = NSMenu()
    private let detailRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    /// Called once the window is up (OrionApp.launch).
    func install(engine: Engine, model: FaceplateModel) {
        guard item == nil else { return }
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item = it
        menu.delegate = self
        menu.autoenablesItems = false
        it.menu = menu
        Publishers.CombineLatest3(engine.$state, model.$pager, model.$tempoFactor)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, pager, factor in
                self?.show(MenuBarReadout.of(state, page: pager.index, factor: factor))
            }
            .store(in: &bag)
        self.engine = engine
    }

    private weak var engine: Engine?

    func show(_ r: MenuBarReadout) {
        readout = r
        guard let button = item?.button else { return }
        button.image = MenuBarImage.make(r.lamp)
        button.imagePosition = r.text == nil ? .imageOnly : .imageLeading
        button.title = r.text.map { " \($0)" } ?? ""
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.setAccessibilityLabel(r.accessibilityLabel)
        button.toolTip = r.detail
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        detailRow.title = readout.detail
        detailRow.isEnabled = false
        menu.addItem(detailRow)
        menu.addItem(.separator())
        let analyze = NSMenuItem(title: "Analyze a File…", action: #selector(analyzeFile), keyEquivalent: "")
        analyze.target = self
        analyze.isEnabled = !(engine?.state.isBusy ?? false)
        menu.addItem(analyze)
        menu.addItem(.separator())
        let show = NSMenuItem(title: "Show \(Brand.name)", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
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

/// The small picture left of the menu-bar text: the key glyph with no reading, else the lamp.
enum MenuBarImage {
    static let side: CGFloat = 10

    static func make(_ lamp: Lamp?) -> NSImage? {
        guard let lamp = lamp else {
            let img = NSImage(systemSymbolName: "key.fill", accessibilityDescription: Brand.name)
            img?.isTemplate = true
            return img
        }
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            lamp.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        img.isTemplate = false
        return img
    }
}
