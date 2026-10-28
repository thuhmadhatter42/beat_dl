import AppKit
import SwiftUI

/// Artemis's tokens (artemis/app/src/faceplate/shared.css), as used by orion-v1-mockup.html.
/// CSS sizes are in points; `em` letter-spacing becomes tracking = em * font size.
enum Theme {
    static let amberRGB = (255.0, 176.0, 32.0)
    static let amber = rgb(255, 176, 32)
    static func amber(_ a: Double) -> Color { rgb(255, 176, 32, a) }
    static let amberGlow = amber(0.6)
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
    static func nsFace(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "HelveticaNeue-Bold" : "HelveticaNeue", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

/// The two textures from app/tools/textures.py. A packaged .app may carry them in
/// Contents/Resources (directly or inside the SwiftPM resource bundle); `swift run` finds
/// the SwiftPM bundle through Bundle.module.
enum Textures {
    static let noise = load("noise")
    static let brushed = load("brushed")

    private static func load(_ name: String) -> NSImage? {
        if let u = Bundle.main.url(forResource: name, withExtension: "png") { return NSImage(contentsOf: u) }
        if let res = Bundle.main.resourceURL,
           let b = Bundle(url: res.appendingPathComponent("Orion_Orion.bundle")),
           let u = b.url(forResource: name, withExtension: "png") { return NSImage(contentsOf: u) }
        if let u = Bundle.module.url(forResource: name, withExtension: "png") { return NSImage(contentsOf: u) }
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
    func amberGlow() -> some View {
        shadow(color: Theme.amberGlow, radius: 3).shadow(color: Theme.amber(0.4), radius: 8)
    }
}

extension Text {
    /// A caption in the LCD's 8 pt, .3em amber style.
    static func cap(_ s: String) -> some View {
        Text(s).font(Theme.face(8)).tracking(2.4).foregroundColor(Theme.amber(0.7))
            .shadow(color: Theme.amber(0.35), radius: 2)
    }
}
