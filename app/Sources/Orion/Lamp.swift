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

    /// sRGB 0...255, shared by the SwiftUI and AppKit colours.
    var rgb: (Double, Double, Double) {
        switch self {
        case .locked: return (61, 220, 122)       // Theme.green
        case .unsure: return Theme.amberRGB
        case .listening: return (226, 55, 44)     // Theme.red
        }
    }

    var color: Color { Theme.rgb(rgb.0, rgb.1, rgb.2) }
    var textColor: Color {
        switch self {
        case .locked: return Theme.greenText
        case .unsure: return Theme.amber(0.8)
        case .listening: return Theme.redText
        }
    }
    var nsColor: NSColor { NSColor(srgbRed: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1) }

    /// Spoken with the reading (VoiceOver, the menu-bar item's label).
    var spoken: String {
        switch self {
        case .locked: return "locked"
        case .unsure: return "unsure"
        case .listening: return "listening"
        }
    }
}
