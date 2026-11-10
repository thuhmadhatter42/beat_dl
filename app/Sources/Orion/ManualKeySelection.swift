import SwiftUI

// Manual Key Selection (J, 2026-11-09 15:19): a key the user forced, from the key wheel, a top-3
// click, the MANUAL menu or play-to-find on the keyboard. One state holds it
// (SpellingSettings.manualKey); every path sets it with setManualKey and clears it with
// clearManualKey, and every set / clear goes to beatkey.log with where it came from.
//
// How it shows: WHITE instead of the display colour. The wheel's section is lit white; the top-3
// slot shows the name in white and MANUAL in place of a % (the detected keys keep their real %);
// the dial's key, ring and status line (MANUAL, no lamp, no %) go white. Hovering the wheel's
// white section or the dial swaps the key name for the reset arrow (NEW SONG's glyph), and a click
// clears the selection: detection takes over again.

/// Where a Manual Key Selection was set or cleared (the log names it).
enum ManualKeySource: String, CaseIterable {
    case wheel = "key wheel"
    case topKeys = "top-3"
    case dropdown = "MANUAL menu"
    case keyboard = "keyboard"
    /// A click on the white section of the wheel: clears.
    case wheelReset = "key wheel re-click"
    /// A click on the dial while manual: clears.
    case dialReset = "dial reset"
    // A new live song needs no clear: the selection holds the song's identity (LiveSession.song).
}

extension SpellingSettings {
    /// Manual Key Selection: `key` (any spelling) becomes THE key of `result`. The one override
    /// path. A key name that does not resolve leaves the state as it was and is logged as an
    /// error (no alert: the click simply does nothing). False = not set.
    @discardableResult
    func setManualKey(_ key: String, of result: Result, from source: ManualKeySource) -> Bool {
        guard let k = AutoTuneSend.keyClass(key) else {
            AppLog.log("ERROR manual key selection: could not resolve \"\(key)\" (from \(source.rawValue)); unchanged")
            return false
        }
        let was = manualKey.flatMap { $0.matches(result) ? KeyChoice.keyName($0.pitchClass, minor: $0.minor) : nil }
        manualKey = KeyChoice(file: result.file, name: result.name, pitchClass: k.pitchClass, minor: k.minor)
        AppLog.log("manual key selection set: \(KeyChoice.keyName(k.pitchClass, minor: k.minor)) from \(source.rawValue)"
                   + (was.map { " (was \($0))" } ?? ""))
        return true
    }

    /// Clears Manual Key Selection: detection takes over again. `result` = the reading on show; a
    /// selection that belongs to another reading is still cleared, but logged as an error (the view
    /// and the state disagreed). False = there was nothing to clear (logged as an error).
    @discardableResult
    func clearManualKey(of result: Result?, from source: ManualKeySource) -> Bool {
        guard let m = manualKey else {
            AppLog.log("ERROR manual key selection: clear from \(source.rawValue), but none is set")
            return false
        }
        let name = KeyChoice.keyName(m.pitchClass, minor: m.minor)
        if let r = result, !m.matches(r) {
            AppLog.log("ERROR manual key selection: \(name) no longer matches the reading on show (clear from \(source.rawValue))")
        }
        manualKey = nil
        AppLog.log("manual key selection cleared: \(name) from \(source.rawValue); detection resumes")
        return true
    }
}

/// The Manual Key Selection on show, as a plain value for the views (PocketState.manualKey).
struct ManualKey: Equatable {
    let pitchClass: Int
    let minor: Bool
    /// The analyzer's own % for this key; nil = it was not in the analyzer's list (never a
    /// made-up number: the views show MANUAL, not a %).
    let detected: Int?

    /// This is key `name` (any spelling).
    func isKey(_ name: String) -> Bool {
        AutoTuneSend.keyClass(name).map { $0.pitchClass == pitchClass && $0.minor == minor } ?? false
    }

    func isKey(_ pc: Int, minor m: Bool) -> Bool { pc == pitchClass && m == minor }

    /// The selection `choice` as shown on reading `raw` (the analyzer's own, before the choice
    /// moved to the front); nil = no selection, or it belongs to another reading.
    static func of(_ choice: KeyChoice?, raw: Result?) -> ManualKey? {
        guard let c = choice, let r = raw, c.matches(r) else { return nil }
        let pct = r.keys.first(where: { c.isKey($0.0) })?.1
        return ManualKey(pitchClass: c.pitchClass, minor: c.minor, detected: pct)
    }
}

/// The colours of a Manual Key Selection: white instead of the display colour, the same in every
/// accent. High Contrast: pure white, no glow (white is already the most contrast the LCD has).
enum ManualLook {
    static var white: Color { Theme.highContrast ? Theme.rgb(255, 255, 255) : Theme.rgb(244, 244, 247) }
    /// Ink on a white fill (the wheel's lit section): near black in every accent.
    static let ink = Theme.hex(0x111113)
    static var glow: Color { Theme.highContrast ? .clear : Theme.rgb(255, 255, 255, 0.55) }
    /// The reset arrow: NEW SONG's glyph (the reset key beside HOLD).
    static let resetSymbol = "arrow.counterclockwise"
    /// The status line under the dial's key, and the top-3 slot's label.
    static let word = "MANUAL"
}

private struct ManualHoverForcedKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// Offscreen renders: "dial" = the dial hovered, "wheel" = the wheel's manual section hovered.
    var manualHoverForced: String? {
        get { self[ManualHoverForcedKey.self] }
        set { self[ManualHoverForcedKey.self] = newValue }
    }
}
