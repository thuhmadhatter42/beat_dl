import Foundation

/// Every name a user sees. Public name = "Beat Key"; the code, module, executable, bundle ID,
/// Application Support folder and ORION_* env vars stay "Orion" (internal).
/// app/Info.plist (CFBundleName / CFBundleDisplayName) and app/build.sh (APP_NAME) carry the same
/// string; FaceplateTests checks the plist against `Brand.name`.
enum Brand {
    static let name = "Beat Key"
    static let wordmark = name.uppercased()           // "BEAT KEY" on the rail

    static let about = "About \(name)"
    static let hide = "Hide \(name)"
    static let quit = "Quit \(name)"
    static let runDoctor = "Run Doctor"
    static let checkForUpdates = "Check for Updates…"
    static let licenses = "Licenses"
    /// Bundled in Contents/Resources by app/build.sh (copied from the repo root).
    static let licensesFile = "THIRD-PARTY-LICENSES"
    static let licensesExt = "md"

    /// The last line of every red FAILED readout. One line on the LCD.
    static let doctorHint = "TRY \(wordmark) › RUN DOCTOR"
    static let downloadHint = "\(doctorHint) OR CHECK THE LINK"
}
