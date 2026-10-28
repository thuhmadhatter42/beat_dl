import AppKit
import Foundation
import WebKit

/// The YouTube login, only for a video that asks for one. Beat Key never reads a browser's data:
/// the user signs in to YouTube in Beat Key's own window, and the login cookies for youtube.com
/// and google.com go to one owner-only file that yt-dlp reads with `--cookies`.
enum YouTubeLogin {
    /// THE switch. true = LOG IN TO YOUTUBE opens Beat Key's login window. false = the fallback:
    /// a video that needs a login just says Beat Key can't download it (no button, no file).
    static var inApp = true

    static let startURL = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/")!

    /// A desktop Safari user agent. WKWebView's own one has no "Version/... Safari/..." part, which
    /// is what Google's embedded-browser check looks for.
    static func userAgent(osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(max(osMajor, 15)).0 Safari/605.1.15"
    }

    /// yt-dlp's own logged-in test (YoutubeBaseInfoExtractor._has_auth_cookies): LOGIN_INFO plus
    /// one of the SAPISID cookies on youtube.com.
    static func isLoggedIn(_ cookies: [HTTPCookie]) -> Bool {
        let yt = Set(cookies.filter { domainIs($0.domain, "youtube.com") }.map(\.name))
        return yt.contains("LOGIN_INFO")
            && !yt.isDisjoint(with: ["SAPISID", "__Secure-1PAPISID", "__Secure-3PAPISID"])
    }

    /// youtube.com / google.com or one of their subdomains, with or without the leading dot.
    static func domainIs(_ domain: String, _ base: String) -> Bool {
        var d = domain.lowercased()
        if d.hasPrefix(".") { d.removeFirst() }
        return d == base || d.hasSuffix("." + base)
    }
}

/// ~/Library/Application Support/Orion/youtube-cookies.txt: Netscape format, mode 600, only
/// youtube.com and google.com cookies. Its values are never logged or printed.
struct CookieFile {
    let url: URL

    static let fileName = "youtube-cookies.txt"
    static func appDefault() -> CookieFile {
        CookieFile(url: Runtime.appDefault().support.appendingPathComponent(fileName))
    }

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func keeps(_ c: HTTPCookie) -> Bool {
        YouTubeLogin.domainIs(c.domain, "youtube.com") || YouTubeLogin.domainIs(c.domain, "google.com")
    }

    /// The cookies.txt yt-dlp loads (yt_dlp/cookies.py YoutubeDLCookieJar): domain, subdomains,
    /// path, secure, expiry (0 = session), name, value; HttpOnly ones carry the #HttpOnly_ prefix.
    static func netscape(_ cookies: [HTTPCookie]) -> String {
        var out = "# Netscape HTTP Cookie File\n# Written by Beat Key from its YouTube login window.\n\n"
        let bad = CharacterSet(charactersIn: "\t\r\n")
        for c in cookies where keeps(c) {
            let fields = [c.domain, c.path, c.name, c.value]
            guard !c.name.isEmpty, fields.allSatisfy({ $0.rangeOfCharacter(from: bad) == nil }) else { continue }
            let expires = c.expiresDate.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
            let line = [c.domain, c.domain.hasPrefix(".") ? "TRUE" : "FALSE", c.path.isEmpty ? "/" : c.path,
                        c.isSecure ? "TRUE" : "FALSE", expires, c.name, c.value].joined(separator: "\t")
            out += (c.isHTTPOnly ? "#HttpOnly_" : "") + line + "\n"
        }
        return out
    }

    /// Writes the file owner-only from its first byte (a 0600 temp file, then renamed over).
    func write(_ cookies: [HTTPCookie]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(CookieFile.fileName).\(getpid()).tmp")
        unlink(tmp.path)
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        let data = Array(CookieFile.netscape(cookies).utf8)
        let n = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        fchmod(fd, 0o600)
        close(fd)
        guard n == data.count, rename(tmp.path, url.path) == 0 else {
            unlink(tmp.path)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// Log Out / a stale login. Removed outright, not to the Trash: a login in the Trash is still a login.
    func delete() { try? FileManager.default.removeItem(at: url) }
}

/// Whether a saved login exists (the app menu's Log Out of YouTube), and logging out.
final class YouTubeSession: ObservableObject {
    @Published private(set) var loggedIn: Bool
    let file: CookieFile

    init(file: CookieFile = .appDefault()) {
        self.file = file
        loggedIn = file.exists
    }

    /// The saved login's path for yt-dlp, nil = none (or the switch is off).
    var savedLogin: URL? { YouTubeLogin.inApp && file.exists ? file.url : nil }

    func refresh() { loggedIn = file.exists }

    /// Deletes the file and anything WebKit kept, closes an open login window.
    func logOut() {
        file.delete()
        LoginWindow.close()
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        refresh()
    }
}

/// The login window: a normal, movable, closable window with a web view on a throwaway
/// (non-persistent) data store. Once youtube.com shows a logged-in session it saves the cookies,
/// closes and calls onLogin. One at a time: opening it again brings the open one forward.
final class LoginWindow: NSObject, NSWindowDelegate, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    private static var current: LoginWindow?

    static var isOpen: Bool { current != nil }

    static func open(saving file: CookieFile, onLogin: @escaping () -> Void) {
        if let c = current { c.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let c = LoginWindow(file: file, onLogin: onLogin)
        current = c
        c.show()
    }

    static func close() { current?.window.close() }

    static let size = NSSize(width: 460, height: 620)

    private let file: CookieFile
    private let onLogin: () -> Void
    private let window: NSWindow
    private let web: WKWebView
    private var saved = false

    private init(file: CookieFile, onLogin: @escaping () -> Void) {
        self.file = file
        self.onLogin = onLogin
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(origin: .zero, size: LoginWindow.size), configuration: config)
        web.customUserAgent = YouTubeLogin.userAgent()
        window = NSWindow(contentRect: NSRect(origin: .zero, size: LoginWindow.size),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")   // the desk color while a page loads
        config.websiteDataStore.httpCookieStore.add(self)
        window.isReleasedWhenClosed = false
        window.title = "Log In to YouTube"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 8 / 255, green: 8 / 255, blue: 10 / 255, alpha: 1)
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.contentView = web
        window.delegate = self
    }

    private func show() {
        // beside the faceplate when there is room, else centered
        if let main = NSApp.windows.first(where: { $0 !== window && $0.isVisible && $0.title == Brand.name }),
           let screen = main.screen?.visibleFrame {
            var o = NSPoint(x: main.frame.maxX + 12, y: main.frame.maxY - LoginWindow.size.height - 28)
            if o.x + LoginWindow.size.width > screen.maxX { o.x = main.frame.minX - LoginWindow.size.width - 40 }
            if o.x < screen.minX { window.center() } else {
                o.y = max(screen.minY, o.y)
                window.setFrameOrigin(o)
            }
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        web.load(URLRequest(url: YouTubeLogin.startURL))
    }

    func webView(_ v: WKWebView, didFinish navigation: WKNavigation!) { check() }
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { check() }

    /// Logged in = on youtube.com with yt-dlp's login cookies present.
    private func check() {
        guard !saved, let host = web.url?.host, YouTubeLogin.domainIs(host, "youtube.com") else { return }
        web.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self, !self.saved, YouTubeLogin.isLoggedIn(cookies) else { return }
            self.saved = true
            do { try self.file.write(cookies) } catch { self.saved = false; return }
            self.window.close()
            self.onLogin()
        }
    }

    func windowWillClose(_ n: Notification) {
        web.stopLoading()
        web.configuration.websiteDataStore.httpCookieStore.remove(self)
        web.navigationDelegate = nil
        if LoginWindow.current === self { LoginWindow.current = nil }
    }
}
