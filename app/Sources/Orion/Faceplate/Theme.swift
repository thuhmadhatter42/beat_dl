import AppKit
import SwiftUI

/// Artemis's tokens (artemis/app/src/faceplate/shared.css), as used by orion-v1-mockup.html.
/// CSS sizes are in points; `em` letter-spacing becomes tracking = em * font size.
enum Theme {
    // The display colour ("amber") and High Contrast are not here: they come through the
    // environment as a `Palette` (below), so the views that use them redraw when they change.
    static let green = rgb(61, 220, 122)
    static let greenGlow = rgb(61, 220, 122, 0.7)
    static let greenText = rgb(89, 225, 141)           // #59e18d
    static let red = rgb(226, 55, 44)
    static let redText = rgb(255, 106, 92)             // #ff6a5c
    static let textHi = rgb(238, 238, 242, 0.9)
    static let textLo = rgb(235, 235, 240, 0.5)
    static let textFaint = rgb(235, 235, 240, 0.28)
    static let panelDeep = hex(0x050505)
    static let black = hex(0x000000)                   // rings and shadows only, never a surface

    /// The window around the plate: the mockup page's radial background.
    static let desk = RadialGradient(
        gradient: Gradient(stops: [.init(color: hex(0x131315), location: 0),
                                   .init(color: hex(0x08080a), location: 0.65),
                                   .init(color: hex(0x030304), location: 1)]),
        center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 420)

    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        rgb(Double((v >> 16) & 0xff), Double((v >> 8) & 0xff), Double(v & 0xff), a)
    }

    /// CSS `linear-gradient(180deg, ...)`.
    static func vertical(_ stops: [(Color, CGFloat)]) -> LinearGradient {
        LinearGradient(gradient: Gradient(stops: stops.map { .init(color: $0.0, location: $0.1) }),
                       startPoint: .top, endPoint: .bottom)
    }

    // Helvetica Neue ships with every macOS. Numbers use tabular figures.
    static func face(_ size: CGFloat, bold: Bool = true) -> Font {
        Font.custom(bold ? "HelveticaNeue-Bold" : "HelveticaNeue", size: size)
    }

    // MARK: the design tokens (design pass 2026-11-09, audit F1/F2/F4/F5)
    // Every surface (window, Advanced, pocket, Mini) sets its type, amber, spacing, control
    // heights and corners from these tables; nothing on the faceplate picks its own number.

    /// Six type sizes, nothing under 10 pt (Apple's macOS floor). Each role carries its weight and
    /// tracking. UPPERCASE + tracking only for labels of 1-3 words; names and sentences mixed case.
    enum T {
        /// 68 Bold: the window's BPM (whole number).
        static let heroSize: CGFloat = 68
        /// 34 Bold: the key in the dial, the BPM's decimals, the pocket's BPM, Doctor's title.
        static let keySize: CGFloat = 34
        /// 18 Bold: stage words (WORKING, LISTENING), the top keys, the Mini's key, the idle invitation.
        static let titleSize: CGFloat = 18
        /// 13: values and content. Bold for chord names, wheel majors, percentages; Regular for the
        /// file name, the source, the link field.
        static let valueSize: CGFloat = 13
        /// 11 Bold, +0.08em: cap legends, section heads, the status legend, menus.
        static let labelSize: CGFloat = 11
        /// 10 Medium, +0.10em in caps: small labels, roman numerals, note letters, chips, footer.
        static let captionSize: CGFloat = 10

        static let all: [CGFloat] = [heroSize, keySize, titleSize, valueSize, labelSize, captionSize]

        static var hero: Font { face(heroSize).monospacedDigit() }
        static var key: Font { face(keySize) }
        static var title: Font { face(titleSize) }
        static var value: Font { face(valueSize) }
        static var body: Font { face(valueSize, bold: false) }
        static var label: Font { face(labelSize) }
        /// The help card's sentences: the label size, Regular.
        static var note: Font { face(labelSize, bold: false) }
        static var caption: Font { Font.custom("HelveticaNeue-Medium", size: captionSize) }

        static let labelTracking: CGFloat = labelSize * 0.08
        static let captionTracking: CGFloat = captionSize * 0.10
        /// Large caps (stage words): +0.04em.
        static let titleTracking: CGFloat = titleSize * 0.04
    }

    /// Five amber steps, nothing else (contrast on the LCD's #0c0a06 in brackets):
    /// A1 the reading (10.8:1), A2 labels and secondary values (~6.3:1), A3 tertiary text and the
    /// floor for any text (~4.6:1), A4 structure (rules, outlines, unlit bars), A5 fills.
    /// High Contrast: A2 and A3 go full, A4 to 0.3, A5 to 0.12.
    /// The colours themselves are the palette's (`palette.a1` ... `palette.a5`, `palette.ink`).
    enum A {
        static let alphas: [Double] = [1, 0.75, 0.62, 0.16, 0.06]
        static let highContrastAlphas: [Double] = [1, 1, 1, 0.3, 0.12]
    }

    /// The 4/8 spacing grid: 8 within a group, 16 between groups.
    enum S {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// The LCD glass's inner padding.
        static let lcd: CGFloat = 20
    }

    /// Four control heights, nothing else: fields and the caps beside them, send / action caps,
    /// chips and menus, inline pills.
    enum H {
        static let lg: CGFloat = 36
        static let md: CGFloat = 28
        static let sm: CGFloat = 20
        static let xs: CGFloat = 16
    }

    /// Three corners: the plate, wells (LCD, fields), caps and chips.
    enum R {
        static let plate: CGFloat = 12
        static let well: CGFloat = 6
        static let cap: CGFloat = 3
    }

    /// Motion (J 2026-11-09: "the notes, note count updates, and then the key changing ... it's all
    /// very clicky"). Live readings land about once a second; every value that changes with them
    /// moves on these tokens, and nothing else picks its own timing. Views use `Motion.value` /
    /// `Motion.swap` scoped with `.animation(_, value:)`, so an unrelated state change never
    /// re-animates them. Hover cards keep their own quick `hover` timing.
    enum Motion {
        enum Kind: CaseIterable {
            /// A value moving: bar heights and widths, the dial's arc, counting numbers, the tuning
            /// marker. A critically damped spring, no overshoot.
            case value
            /// One thing replacing another: a key name, LOCKED / UNSURE, lit keys, chords. A crossfade.
            case swap
            /// Hover washes (unchanged: hover feedback stays quick).
            case hover
        }

        /// The value spring's response: about 98 % of the way there after this long.
        static let valueDuration = 0.45
        static let swapDuration = 0.25
        static let hoverDuration = 0.12

        /// Tests set this; nil = ask the system (System Settings › Accessibility › Reduce motion).
        static var reduceMotionOverride: Bool?
        static var reduceMotion: Bool {
            reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        /// How long `kind` runs; nil = instant. Reduce Motion keeps the crossfades (opacity is not
        /// motion) and the hover wash, and makes every moving value jump straight to its new place.
        /// Offscreen renders (Pocket.snapshot) draw the final frame: everything instant.
        static func duration(_ kind: Kind, reduce: Bool, snapshot: Bool = false) -> Double? {
            if snapshot { return nil }
            switch kind {
            case .value: return reduce ? nil : valueDuration
            case .swap: return swapDuration
            case .hover: return hoverDuration
            }
        }

        static func animation(_ kind: Kind, reduce: Bool, snapshot: Bool = false) -> Animation? {
            guard let d = duration(kind, reduce: reduce, snapshot: snapshot) else { return nil }
            switch kind {
            // A critically damped spring: it starts gently, glides, and settles without passing
            // the target. 0.1.48's easeOutExpo curve (0.16, 1, 0.3, 1) did half of every move in
            // the first 45 ms and then crawled, so each reading read as a click (0.1.50, J
            // 2026-11-09). A spring also picks up from its current speed if a reading lands
            // mid-move instead of restarting from rest.
            case .value: return .spring(response: d, dampingFraction: valueDamping, blendDuration: 0)
            case .swap: return .easeInOut(duration: d)
            case .hover: return .easeOut(duration: d)
            }
        }

        /// Damping of the value spring (1 = critically damped). Shared by `animation(.value)` and
        /// `valueProgress`, so the curve the tests sample is the curve the views are given.
        static let valueDamping = 1.0

        /// How far (0...1) a value has got `elapsed` seconds after its reading lands: the closed
        /// form of the critically damped spring `animation(.value)` hands SwiftUI (response =
        /// valueDuration, so omega = 2 pi / response): 1 - (1 + w t) e^(-w t). Pure: time is passed in.
        static func valueProgress(elapsed t: Double) -> Double {
            guard t > 0 else { return 0 }
            let w = 2 * Double.pi / valueDuration
            return 1 - (1 + w * t) * exp(-w * t)
        }

        /// Tests only (MotionFrameTests): called with the kind each time a view's body asks for
        /// a token, to assert which views attach which motion.
        static var onResolve: ((Kind) -> Void)?

        static var value: Animation? { onResolve?(.value); return animation(.value, reduce: reduceMotion, snapshot: Pocket.snapshot) }
        static var swap: Animation? { onResolve?(.swap); return animation(.swap, reduce: reduceMotion, snapshot: Pocket.snapshot) }
        static var hover: Animation? { onResolve?(.hover); return animation(.hover, reduce: reduceMotion, snapshot: Pocket.snapshot) }
    }

    static func nsFace(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "HelveticaNeue-Bold" : "HelveticaNeue", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

/// The display colour and High Contrast Readout as one value: everything "amber" on the faceplate
/// derives from it. Views read it from the SwiftUI environment (`@Environment(\.palette)`), which
/// each surface's root fills from the one owner of each setting (AccentSettings.effective,
/// DisplaySettings.highContrast; see `View.paletteRoot(_:display:)`), so a change redraws exactly the
/// views that read it. Non-view code (the menu-bar key, the link field's caret) is handed the value
/// by its caller.
struct Palette: Equatable {
    /// The display colour in use (amber unless J picked another with COLOR), already lifted to
    /// read on the LCD.
    var accent: Accent = .amber
    /// View › High Contrast Readout: dimmed amber text goes full strength, the faint placeholders
    /// brighten, glows go.
    var highContrast = false

    var amber: Color { accent.color }
    func amber(_ a: Double) -> Color { Theme.rgb(accent.r, accent.g, accent.b, contrast(a)) }
    /// The accent for AppKit (the link field's caret).
    var amberNS: NSColor { accent.nsColor }
    var amberGlow: Color { Theme.rgb(accent.r, accent.g, accent.b, 0.6) }   // a glow, not text: High Contrast leaves it

    /// An amber alpha under High Contrast: text (0.4 and up) full, faint (under 0.2) to 0.3.
    func contrast(_ a: Double) -> Double {
        guard highContrast else { return a }
        if a >= 0.4 { return 1 }
        if a < 0.2 { return 0.3 }
        return a
    }

    // The five amber steps (Theme.A): A1 the reading, A2 labels and secondary values, A3 tertiary
    // text, A4 structure, A5 fills. High Contrast: A2 and A3 go full, A4 to 0.3, A5 to 0.12.
    var a1: Color { amber }
    var a2: Color { step(1) }
    var a3: Color { step(2) }
    var a4: Color { step(3) }
    var a5: Color { step(4) }
    /// Ink on a lit amber fill (selected chip, lit section, lit key): dark or light by the
    /// accent's luminance (#1a1206 on amber).
    var ink: Color { accent.ink.color }
    private func step(_ i: Int) -> Color {
        Theme.rgb(accent.r, accent.g, accent.b, (highContrast ? Theme.A.highContrastAlphas : Theme.A.alphas)[i])
    }

    /// A Manual Key Selection's white (ManualLook): High Contrast pure white, no glow.
    var manualWhite: Color { highContrast ? Theme.rgb(255, 255, 255) : Theme.rgb(244, 244, 247) }
    var manualGlow: Color { highContrast ? .clear : Theme.rgb(255, 255, 255, 0.55) }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette() }

extension EnvironmentValues {
    /// The display colour and High Contrast in use (amber, off unless a surface's root says else).
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// A surface's root (the window, the pocket, the Mini): the one place the two settings enter.
/// Observing them here means a new colour re-runs only this modifier; SwiftUI then redraws the
/// views that read `\.palette`, keeping every view's identity and state.
struct PaletteRoot: ViewModifier {
    @ObservedObject var accent: AccentSettings
    @ObservedObject var display: DisplaySettings

    func body(content: Content) -> some View {
        content.environment(\.palette, Palette(accent: accent.effective, highContrast: display.highContrast))
    }
}

extension View {
    /// Fills `\.palette` for everything below from the two settings objects.
    func paletteRoot(_ accent: AccentSettings = .shared, display: DisplaySettings) -> some View {
        modifier(PaletteRoot(accent: accent, display: display))
    }
}

/// The two textures from app/tools/textures.py. Looked up without Bundle.module (which
/// fatalErrors when its bundle is missing): loose PNGs in Contents/Resources, then the SwiftPM
/// resource bundle in Contents/Resources (.app) or next to the executable (`swift run`).
/// Not found = nil, and the plate simply draws without grain.
enum Textures {
    static let noise = load("noise")
    static let brushed = load("brushed")

    static let bundleName = "Orion_Orion.bundle"

    /// Where the SwiftPM resource bundle may sit, in order.
    static func bundleCandidates(main: Bundle = .main) -> [URL] {
        [main.resourceURL, main.executableURL?.deletingLastPathComponent(), main.bundleURL]
            .compactMap { $0?.appendingPathComponent(bundleName) }
    }

    private static func load(_ name: String) -> NSImage? {
        if let u = Bundle.main.url(forResource: name, withExtension: "png") { return NSImage(contentsOf: u) }
        for c in bundleCandidates() {
            if let u = Bundle(url: c)?.url(forResource: name, withExtension: "png") { return NSImage(contentsOf: u) }
        }
        return nil
    }
}

extension View {
    /// CSS `box-shadow: inset x y blur color` clipped to `shape`.
    func innerShadow<S: Shape>(_ shape: S, _ color: Color, blur: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        let pad = blur * 2 + abs(x) + abs(y) + 2
        return overlay(
            ZStack {
                Rectangle().fill(color).padding(-pad)
                shape.fill(Color.black).offset(x: x, y: y).blendMode(.destinationOut)
            }
            .compositingGroup()
            .blur(radius: blur / 2)
            .mask(shape)
            .allowsHitTesting(false)
        )
    }

    /// CSS `box-shadow: 0 0 0 <spread> color` around a rounded rect of `radius`.
    func ring(radius: CGFloat, spread: CGFloat, _ color: Color) -> some View {
        background(RoundedRectangle(cornerRadius: radius + spread, style: .continuous)
            .fill(color).padding(-spread))
    }

    /// CSS `box-shadow: x y blur [spread] color` (outer) under a rounded rect.
    func dropShadow(radius: CGFloat, _ color: Color, blur: CGFloat, x: CGFloat = 0, y: CGFloat = 0,
                    spread: CGFloat = 0) -> some View {
        background(RoundedRectangle(cornerRadius: radius + spread, style: .continuous)
            .fill(color).padding(-spread).offset(x: x, y: y).blur(radius: blur / 2))
    }

    /// CSS `line-height: <lh>` on a single line: the glyphs keep their size, the box is size * lh.
    func lineBox(_ size: CGFloat, _ lh: CGFloat) -> some View {
        fixedSize().frame(height: size * lh)
    }

    /// The amber glow: `0 0 6px amber-glow, 0 0 16px rgba(amber,.4)`.
    func amberGlow() -> some View { modifier(AmberGlow()) }
}

/// The amber glow in the palette's colour; High Contrast: crisp edges, no halo.
private struct AmberGlow: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.shadow(color: palette.highContrast ? .clear : palette.amberGlow, radius: 3)
            .shadow(color: palette.highContrast ? .clear : palette.amber(0.4), radius: 8)
    }
}

extension Text {
    /// A section head / label on the LCD: T.label (11 Bold, +0.08em) in A2. No glow: the glow is
    /// kept for the reading (BPM, key, the lit wheel section).
    static func cap(_ s: String, _ palette: Palette) -> Text {
        Text(s).labelStyle().foregroundColor(palette.a2)
    }

    /// T.label: 11 Bold, +0.08em (UPPERCASE, 1-3 words).
    func labelStyle() -> Text { font(Theme.T.label).tracking(Theme.T.labelTracking) }
    /// T.caption: 10 Medium, +0.10em (UPPERCASE, 1-3 words).
    func captionStyle() -> Text { font(Theme.T.caption).tracking(Theme.T.captionTracking) }
}
