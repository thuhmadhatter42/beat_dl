import AppKit
import Foundation

/// A browser yt-dlp can read a YouTube login from.
struct LoginBrowser: Equatable {
    let name: String        // yt-dlp's --cookies-from-browser name
    let display: String     // "Brave"
    let bundleID: String

    static let all: [LoginBrowser] = [
        LoginBrowser(name: "brave", display: "Brave", bundleID: "com.brave.Browser"),
        LoginBrowser(name: "chrome", display: "Chrome", bundleID: "com.google.Chrome"),
        LoginBrowser(name: "chromium", display: "Chromium", bundleID: "org.chromium.Chromium"),
        LoginBrowser(name: "edge", display: "Edge", bundleID: "com.microsoft.edgemac"),
        LoginBrowser(name: "firefox", display: "Firefox", bundleID: "org.mozilla.firefox"),
        LoginBrowser(name: "opera", display: "Opera", bundleID: "com.operasoftware.Opera"),
        LoginBrowser(name: "safari", display: "Safari", bundleID: "com.apple.Safari"),
        LoginBrowser(name: "vivaldi", display: "Vivaldi", bundleID: "com.vivaldi.Vivaldi"),
        LoginBrowser(name: "whale", display: "Whale", bundleID: "com.naver.Whale"),
    ]

    /// When the default browser is not supported: the first installed one of these.
    static let fallbackOrder = ["chrome", "brave", "edge", "firefox", "safari"]

    static func forBundle(_ id: String?) -> LoginBrowser? { all.first { $0.bundleID == id } }
    static func named(_ name: String?) -> LoginBrowser? { all.first { $0.name == name } }

    /// The default browser if supported, else the first installed fallback, else nil.
    static func resolve(defaultBundleID: String?, isInstalled: (String) -> Bool) -> LoginBrowser? {
        if let b = forBundle(defaultBundleID) { return b }
        for n in fallbackOrder {
            if let b = named(n), isInstalled(b.bundleID) { return b }
        }
        return nil
    }

    /// The Mac's default browser for https links (or a fallback), looked up now.
    static func current() -> LoginBrowser? {
        let ws = NSWorkspace.shared
        let id = ws.urlForApplication(toOpen: URL(string: "https://www.youtube.com")!)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
        return resolve(defaultBundleID: id) { ws.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    /// Opens youtube.com in this browser so the user can sign in (or is already signed in).
    func openYouTube() {
        let ws = NSWorkspace.shared
        guard let app = ws.urlForApplication(withBundleIdentifier: bundleID) else { return }
        ws.open([URL(string: "https://www.youtube.com")!], withApplicationAt: app,
                configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}
