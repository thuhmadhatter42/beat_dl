import AppKit
import SwiftUI

@main
struct OrionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var engine = Engine(downloadsProbe: Engine.defaultProbe(),
                                             accessCheck: { AccessProbe().browserData($0) },
                                             noteLogin: { PendingRetryStore().lastLoginBrowser = $0 })
    @StateObject private var model = FaceplateModel()
    @StateObject private var access = AccessController()

    var body: some Scene {
        WindowGroup {
            FaceplateView(engine: engine, model: model, access: access)
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
        access.onClose = { [engine] in engine.clearAccess() }
        if let fake = env["ORION_FAKE_STATE"], !fake.isEmpty {
            FakeState.apply(fake, engine: engine, model: model, access: access)
            if fake != "idle" {   // the mockup shows the field unfocused in every other state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NSApp.windows.forEach { $0.makeFirstResponder(nil) }
                }
            }
            return
        }
        // Seed yt-dlp into Application Support, then the weekly self-update, on the shared
        // maintenance queue. The Engine stays idle; downloads and Run Doctor wait their turn.
        Runtime.appDefault().launchMaintenance()
        // Restart & Try Again: no relaunch to come back from (swift run) = retry in this process
        access.retryHere = { [engine, model] p in
            model.url = p.url
            model.lastAction = .download
            engine.download(p.url, browser: p.browser)
        }
        // Back from Restart & Try Again: run that link once with the browser login.
        if let p = access.store.take() { access.retryHere?(p) }
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
