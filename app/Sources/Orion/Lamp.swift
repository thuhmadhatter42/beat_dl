import AppKit
import SwiftUI

/// The one confidence lamp, wherever it shows (the LCD's status line, the working readout, the
/// menu bar): green LOCKED, amber UNSURE, red LISTENING / ANALYZING.
enum Lamp: Equatable {
    case locked, unsure, listening

    /// The lamp for a key reading; nil when there is no key.
    static func of(_ keys: [(String, Int)]) -> Lamp? {
        switch KeyConfidence.of(keys) {
        case .locked: return .locked
        case .unsure: return .unsure
        case .none: return nil
        }
    }

    /// sRGB 0...255, shared by the SwiftUI and AppKit colours. UNSURE is the display colour in use
    /// (`accent`: the view's `\.palette`, or the menu bar's own copy of it).
    func rgb(_ accent: Accent) -> (Double, Double, Double) {
        switch self {
        case .locked: return (61, 220, 122)       // Theme.green
        case .unsure: return accent.rgb
        case .listening: return (226, 55, 44)     // Theme.red
        }
    }

    func color(_ accent: Accent) -> Color { let c = rgb(accent); return Theme.rgb(c.0, c.1, c.2) }
    func textColor(_ accent: Accent) -> Color {
        switch self {
        case .locked: return Theme.greenText
        case .unsure: return accent.color
        case .listening: return Theme.redText
        }
    }
    func nsColor(_ accent: Accent) -> NSColor {
        let c = rgb(accent)
        return NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
    }

    /// Colour-blind safe: each state has its own shape as well as its colour (plan 5.1).
    /// locked = octagon (a stop sign: settled), unsure = triangle (a caution sign),
    /// listening / analyzing = circle.
    var sides: Int? {
        switch self {
        case .locked: return 8
        case .unsure: return 3
        case .listening: return nil
        }
    }

    /// Spoken with the reading (VoiceOver, the menu-bar item's label).
    var spoken: String {
        switch self {
        case .locked: return "locked"
        case .unsure: return "unsure"
        case .listening: return "listening"
        }
    }
}

/// The lamp's outline, one path for the LCD (SwiftUI) and the menu bar (drawn into an NSImage).
struct LampShape: Shape {
    let lamp: Lamp

    func path(in rect: CGRect) -> Path {
        guard let n = lamp.sides else { return Path(ellipseIn: rect) }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        // octagon: flat top (rotated half a side); triangle: point up
        let start: CGFloat = n == 8 ? -.pi / 2 + .pi / 8 : -.pi / 2
        var p = Path()
        for i in 0..<n {
            let a = start + CGFloat(i) * 2 * .pi / CGFloat(n)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        // a triangle's centroid sits low in its circle: centre it in the box
        if n == 3 { p = p.offsetBy(dx: 0, dy: r / 4) }
        return p
    }
}
