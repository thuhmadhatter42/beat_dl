import AppKit
import SwiftUI

/// The display colour (J 2026-11-09: "a Color button ... pops up a color wheel that lets you change
/// the amber color to whatever you want"). sRGB 0...255. Amber is the default; every step of
/// Theme.A, the glow, the lit-fill ink and the Mini derive from the one in use.
struct Accent: Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = min(255, max(0, r)); self.g = min(255, max(0, g)); self.b = min(255, max(0, b))
    }

    static let amber = Accent(255, 176, 32)
    /// The LCD glass behind the text (#0c0a06).
    static let lcd = Accent(12, 10, 6)
    /// The reading (A1) keeps at least this contrast on the LCD: amber has 10.8:1. A pick under it
    /// is lifted (brighter first, then paler) until it reaches it.
    static let minContrast = 7.0
    /// Ink on a lit amber fill: the design's #1a1206.
    static let amberInk = Accent(26, 18, 6)
    /// Ink on a dark lit fill (only a pick that was not clamped can be that dark).
    static let lightInk = Accent(246, 244, 238)

    var rgb: (Double, Double, Double) { (r, g, b) }
    var color: Color { Theme.rgb(r, g, b) }
    var nsColor: NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

    /// WCAG relative luminance, 0...1.
    var luminance: Double {
        func lin(_ c: Double) -> Double {
            let s = c / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG contrast ratio, 1...21.
    func contrast(with o: Accent) -> Double {
        let (a, b) = (luminance, o.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Ink for text on a fill of this colour: the darker or the lighter one, whichever reads better.
    /// Dark ink is the colour taken down to a tenth (amber keeps the design's exact #1a1206).
    var ink: Accent {
        let dark = self == .amber ? Accent.amberInk : Accent(r * 0.1, g * 0.1, b * 0.1)
        return contrast(with: dark) >= contrast(with: Accent.lightInk) ? dark : Accent.lightInk
    }

    /// A lit key cap (LISTEN, DOWNLOAD...): its gradient top / middle / bottom and its legend.
    /// Amber keeps the design's hexes (#ffe4a6 / #f7b32b / #c07f12, legend #3a2a06); another colour
    /// gets the same shape: lighter on top, the colour, three quarters at the bottom.
    var litCap: (top: Accent, mid: Accent, bottom: Accent, legend: Accent) {
        if self == .amber {
            return (Accent(255, 228, 166), Accent(247, 179, 43), Accent(192, 127, 18), Accent(58, 42, 6))
        }
        let top = Accent(r + (255 - r) * 0.6, g + (255 - g) * 0.6, b + (255 - b) * 0.6)
        let legend = ink == Accent.lightInk ? Accent.lightInk : Accent(r * 0.23, g * 0.23, b * 0.23)
        return (top, self, Accent(r * 0.75, g * 0.75, b * 0.75), legend)
    }

    /// The colour as the LCD shows it: unchanged when it reads on the glass, else lifted to
    /// `minContrast` (HSB brightness up first, keeping its hue and strength; then less saturated).
    /// `clamped` says whether it had to be lifted.
    func readable() -> (accent: Accent, clamped: Bool) {
        if contrast(with: .lcd) >= Accent.minContrast { return (self, false) }
        var (h, s, v) = hsb
        func at(_ s: Double, _ v: Double) -> Accent { Accent.fromHSB(h, s, v) }
        func ok(_ a: Accent) -> Bool { a.contrast(with: .lcd) >= Accent.minContrast }
        if ok(at(s, 1)) {
            var lo = v, hi = 1.0
            for _ in 0..<24 { let m = (lo + hi) / 2; if ok(at(s, m)) { hi = m } else { lo = m } }
            v = hi
        } else {
            v = 1
            var lo = 0.0, hi = s
            for _ in 0..<24 { let m = (lo + hi) / 2; if ok(at(m, 1)) { lo = m } else { hi = m } }
            s = lo
        }
        if h.isNaN { h = 0 }
        return (at(s, v), true)
    }

    /// Hue 0...1, saturation 0...1, brightness 0...1.
    var hsb: (Double, Double, Double) {
        let (R, G, B) = (r / 255, g / 255, b / 255)
        let mx = max(R, G, B), mn = min(R, G, B), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == R { h = ((G - B) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == G { h = (B - R) / d + 2 }
            else { h = (R - G) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    static func fromHSB(_ h: Double, _ s: Double, _ v: Double) -> Accent {
        let i = floor(h * 6), f = h * 6 - i
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let (R, G, B): (Double, Double, Double)
        switch Int(i) % 6 {
        case 0: (R, G, B) = (v, t, p)
        case 1: (R, G, B) = (q, v, p)
        case 2: (R, G, B) = (p, v, t)
        case 3: (R, G, B) = (p, q, v)
        case 4: (R, G, B) = (t, p, v)
        default: (R, G, B) = (v, p, q)
        }
        return Accent(R * 255, G * 255, B * 255)
    }

    /// From any NSColor (the panel may hand back a catalogue or generic colour); nil = no sRGB form.
    init?(_ ns: NSColor) {
        guard let c = ns.usingColorSpace(.sRGB) else { return nil }
        self.init(Double(c.redComponent) * 255, Double(c.greenComponent) * 255, Double(c.blueComponent) * 255)
    }

    var described: String { "rgb(\(Int(r.rounded())),\(Int(g.rounded())),\(Int(b.rounded())))" }
}

/// The chosen colour, remembered between launches (UserDefaults `accentColor`: [r, g, b] sRGB 0...255).
/// Theme reads the colour in use through `Theme.accent`; the window, the pocket and the Mini observe
/// this object and redraw their face when it changes (nothing else does: Listen's meter, ticking at
/// 20 Hz, never touches it).
final class AccentSettings: ObservableObject {
    static let key = "accentColor"
    static let shared = AccentSettings()
    private let defaults: UserDefaults
    /// While the colour wheel drags, updates are drawn at most this often (the face redraws whole).
    static let minInterval = 1.0 / 30

    /// What J picked (the wheel shows this).
    @Published private(set) var picked: Accent = .amber
    /// What the faceplate shows: `picked`, lifted if it would not read on the LCD.
    @Published private(set) var effective: Accent = .amber
    /// The colour panel is open (the COLOR chip lights).
    @Published var panelOpen = false
    private(set) var clamped = false

    private var pending: Accent?
    private var lastApply = Date.distantPast

    init(defaults: UserDefaults = .standard, applyToTheme: Bool = true) {
        self.defaults = defaults
        let stored = AccentSettings.load(defaults)
        apply(stored ?? .amber, persist: false, applyToTheme: applyToTheme)
    }

    static func load(_ d: UserDefaults) -> Accent? {
        guard let raw = d.object(forKey: key) else { return nil }
        guard let a = raw as? [Double], a.count == 3, a.allSatisfy({ $0.isFinite }) else {
            AppLog.log("accent: stored \(key) unreadable (\(raw)), using amber")
            return nil
        }
        return Accent(a[0], a[1], a[2])
    }

    /// A new colour, now (Reset, tests, launch).
    func set(_ a: Accent) { pending = nil; apply(a, persist: true, applyToTheme: true) }

    /// Back to amber; the stored pick is removed.
    func reset() {
        pending = nil
        apply(.amber, persist: false, applyToTheme: true)
        defaults.removeObject(forKey: AccentSettings.key)
        AppLog.log("accent: reset to amber")
    }

    /// From the colour wheel while it drags: coalesced to `minInterval`, the last one always lands.
    func drag(_ a: Accent) {
        let wait = AccentSettings.minInterval - Date().timeIntervalSince(lastApply)
        if wait <= 0 { set(a); return }
        let scheduled = pending != nil
        pending = a
        if !scheduled {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self = self, let p = self.pending else { return }
                self.set(p)
            }
        }
    }

    private func apply(_ a: Accent, persist: Bool, applyToTheme: Bool) {
        let (shown, wasClamped) = a.readable()
        // logged once each time a pick crosses into too-dark (not on every drag step); the
        // panel's close line names the final pick and what is shown
        if wasClamped && !clamped {
            AppLog.log("accent: \(a.described) too dark for the LCD (\(String(format: "%.1f", a.contrast(with: .lcd))):1), shown as \(shown.described)")
        }
        clamped = wasClamped
        lastApply = Date()
        if applyToTheme { Theme.accent = shown }
        if picked != a { picked = a }
        if effective != shown { effective = shown }
        if persist {
            defaults.set([a.r, a.g, a.b], forKey: AccentSettings.key)
        }
    }
}

/// The macOS colour wheel (the shared NSColorPanel, wheel mode, no opacity), with Reset to Amber
/// under it. Opened by the COLOR chip; the face recolours live while the wheel drags.
final class AccentPanel: NSObject {
    static let shared = AccentPanel()
    private var closeObserver: Any?
    private let settings: AccentSettings

    init(settings: AccentSettings = .shared) { self.settings = settings }

    func toggle() {
        if settings.panelOpen { NSColorPanel.shared.close() } else { open() }
    }

    func open() {
        let p = NSColorPanel.shared
        p.mode = .wheel
        p.showsAlpha = false
        p.isContinuous = true
        p.setTarget(nil); p.setAction(nil)        // setting the colour must not echo back as a pick
        p.color = settings.picked.nsColor
        p.setTarget(self)
        p.setAction(#selector(changed(_:)))
        p.accessoryView = resetView()
        p.title = "\(Brand.name) Colour"
        if closeObserver == nil {
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p,
                                                                   queue: .main) { [weak self] _ in self?.closed() }
        }
        NSApp.activate(ignoringOtherApps: true)
        p.orderFront(nil)
        settings.panelOpen = true
        AppLog.log("accent: colour panel open (\(settings.picked.described))")
    }

    @objc private func changed(_ sender: NSColorPanel) {
        guard let a = Accent(sender.color) else {
            AppLog.log("accent: panel colour \(sender.color) has no sRGB form, ignored")
            return
        }
        settings.drag(a)
    }

    @objc private func resetPressed(_ sender: Any?) {
        let p = NSColorPanel.shared
        p.setTarget(nil); p.setAction(nil)
        p.color = Accent.amber.nsColor
        p.setTarget(self); p.setAction(#selector(changed(_:)))
        settings.reset()
    }

    private func closed() {
        let p = NSColorPanel.shared
        p.setTarget(nil); p.setAction(nil)
        p.accessoryView = nil
        if let o = closeObserver { NotificationCenter.default.removeObserver(o); closeObserver = nil }
        settings.panelOpen = false
        AppLog.log("accent: colour panel closed, \(settings.picked.described)"
                   + (settings.clamped ? " (shown as \(settings.effective.described))" : ""))
    }

    private func resetView() -> NSView {
        let b = NSButton(title: "Reset to Amber", target: self, action: #selector(resetPressed(_:)))
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.sizeToFit()
        let v = NSView(frame: NSRect(x: 0, y: 0, width: b.frame.width + 16, height: b.frame.height + 12))
        b.setFrameOrigin(NSPoint(x: 8, y: 6))
        v.addSubview(b)
        return v
    }
}

/// COLOR in the window's footer, between SETTINGS and HELP: the HELP chip's look, a swatch of the
/// colour in use, lit while the colour wheel is open.
struct ColorChip: View {
    @ObservedObject var accent = AccentSettings.shared
    var action: () -> Void = { AccentPanel.shared.toggle() }

    var body: some View {
        let on = accent.panelOpen
        // the footer's one chip (FooterChip) with the swatch, lit while the wheel is open
        FooterChip(title: "COLOR", label: "Display colour", on: on, swatch: true, action: action)
            .nativeHelp("Pick the display colour")
            .helpTip(HelpText.color)
            .accessibility(hint: Text(on ? "Closes the colour wheel" : "Opens a colour wheel to change the display colour"))
    }
}
