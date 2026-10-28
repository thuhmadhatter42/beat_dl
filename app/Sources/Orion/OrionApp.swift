import AppKit
import SwiftUI

@main
struct OrionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var login: YouTubeSession
    @StateObject private var engine: Engine
    @StateObject private var model = FaceplateModel()

    init() {
        let session = YouTubeSession()
        _login = StateObject(wrappedValue: session)
        _engine = StateObject(wrappedValue: Engine(downloadsProbe: Engine.defaultProbe(),
                                                   savedLogin: { session.savedLogin },
                                                   dropLogin: { session.file.delete() }))
    }

    var body: some Scene {
        WindowGroup {
            FaceplateView(engine: engine, model: model, login: login)
                .background(WindowConfigurator())
                .onAppear(perform: launch)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandGroup(replacing: .newItem) {}   // one window: no File > New
            // The app menu says Beat Key whatever the process is called (swift run = "Orion").
            CommandGroup(replacing: .appInfo) {
                Button(Brand.about) {
                    NSApp.orderFrontStandardAboutPanel(options: [.applicationName: Brand.name])
                }
                Button(Brand.runDoctor) { engine.runDoctor() }
                    .disabled(engine.state.isBusy)
                Button(Brand.licenses) { Licenses.open() }
                if login.loggedIn && YouTubeLogin.inApp {
                    Button("Log Out of YouTube") { login.logOut() }
                        .disabled(engine.state.isBusy)
                }
            }
            CommandGroup(replacing: .appVisibility) {
                Button(Brand.hide) { NSApp.hide(nil) }.keyboardShortcut("h")
                Button("Hide Others") { NSApp.hideOtherApplications(nil) }.keyboardShortcut("h", modifiers: [.command, .option])
                Button("Show All") { NSApp.unhideAllApplications(nil) }
            }
            CommandGroup(replacing: .appTermination) {
                Button(Brand.quit) { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
    }

    private func launch() {
        let env = ProcessInfo.processInfo.environment
        if let fake = env["ORION_FAKE_STATE"], !fake.isEmpty {
            FakeState.apply(fake, engine: engine, model: model)
            if fake != "idle" {   // the mockup shows the field unfocused in every other state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NSApp.windows.forEach { $0.makeFirstResponder(nil) }
                }
            }
            if fake == "login-window" {   // the window LOG IN TO YOUTUBE opens (videos); saves nowhere real
                let scratch = CookieFile(url: FileManager.default.temporaryDirectory
                    .appendingPathComponent("orion-fake-\(CookieFile.fileName)"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    LoginWindow.open(saving: scratch) { scratch.delete() }
                }
            }
            return
        }
        // Debug: open the real login window straight away (a login test). Saves the real cookie file.
        if env["ORION_OPEN_LOGIN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [login] in
                LoginLog.write("login window opened (ORION_OPEN_LOGIN)")
                LoginWindow.open(saving: login.file) { login.refresh() }
            }
        }
        // Seed yt-dlp into Application Support, then the weekly self-update, on the shared
        // maintenance queue. The Engine stays idle; downloads and Run Doctor wait their turn.
        Runtime.appDefault().launchMaintenance()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        // `swift run` has no bundle: make it a regular, frontmost app all the same.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

/// The window tweaks SwiftUI on macOS 11 cannot express: fixed size, dragged by its plate,
/// dark title area, no tabs.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.styleMask.remove(.resizable)
            w.styleMask.insert(.fullSizeContentView)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(srgbRed: 8 / 255, green: 8 / 255, blue: 10 / 255, alpha: 1)
            w.appearance = NSAppearance(named: .darkAqua)
            w.tabbingMode = .disallowed
            w.collectionBehavior.insert(.fullScreenNone)
            w.standardWindowButton(.zoomButton)?.isEnabled = false
            w.title = Brand.name
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// App menu › Licenses: opens the bundled THIRD-PARTY-LICENSES.md (open-source notices and the
/// source-code offer) in TextEdit, so it needs no screen of its own.
enum Licenses {
    /// The bundled file, or nil when running unbundled (`swift run`).
    static func fileURL(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: Brand.licensesFile, withExtension: Brand.licensesExt)
    }

    static func open(bundle: Bundle = .main) {
        guard let url = fileURL(bundle: bundle) else { NSSound.beep(); return }
        let ws = NSWorkspace.shared
        // .md has no default app on a clean Mac; TextEdit always exists.
        if let edit = ws.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            ws.open([url], withApplicationAt: edit, configuration: NSWorkspace.OpenConfiguration())
        } else {
            ws.open(url)
        }
    }
}
