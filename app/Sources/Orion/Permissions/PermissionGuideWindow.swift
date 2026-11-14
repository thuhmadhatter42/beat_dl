import AppKit
import SwiftUI

/// The permission walkthrough's window and its one entry point. Everything that needs a permission
/// (launch, Listen, Send to DAW, Run Doctor, the menu) calls `PermissionGuide.shared`.
final class PermissionGuide: NSObject, NSWindowDelegate {
    static let shared = PermissionGuide()

    let model: PermissionGuideModel
    private var window: NSWindow?
    private var timer: Timer?

    /// Unit tests never open a window.
    private static let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil

    init(model: PermissionGuideModel = PermissionGuideModel()) {
        self.model = model
    }

    /// At launch: only when something is missing and not skipped, or a Quit & Reopen was pending.
    func openAtLaunch() {
        let resume = model.resumePending
        model.resumePending = false
        if resume { AppLog.log("permissions: resuming after relaunch") }
        guard resume || model.hasMissing else {
            AppLog.log("permissions: nothing missing at launch")
            return
        }
        open(at: nil, why: resume ? "relaunch resume" : "launch")
    }

    /// A feature hit a permission error (or the menu / Doctor asked): open the guide at that step.
    /// Safe from any queue.
    func need(_ kind: PermissionKind?, why: String) {
        guard !PermissionGuide.testing else { return }
        DispatchQueue.main.async { self.open(at: kind, why: why) }
    }

    /// Set Up Permissions…: always opens, even when everything is granted.
    func open(at kind: PermissionKind?, why: String) {
        guard !PermissionGuide.testing else { return }
        _ = model.begin(at: kind, why: why)
        show()
        startPolling()
    }

    private func show() {
        if window == nil {
            let size = NSSize(width: 460, height: 440)
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.title = "Set Up Permissions"
            w.titlebarAppearsTransparent = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(srgbRed: 8 / 255, green: 8 / 255, blue: 10 / 255, alpha: 1)
            w.tabbingMode = .disallowed
            w.delegate = self
            w.contentView = NSHostingView(rootView: PermissionGuideView(model: model, close: { [weak self] in self?.close() }))
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startPolling() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.model.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        AppLog.log("permissions: guide closed")
    }
}

private struct PermissionGuideView: View {
    @ObservedObject var model: PermissionGuideModel
    let close: () -> Void
    private var palette: Palette { Palette(accent: AccentSettings.shared.effective) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.S.l) {
            Text("Set up Beat Key")
                .font(Theme.T.title).foregroundColor(palette.a1)
            Text(model.current == nil && model.confirming == nil
                 ? "Everything Beat Key needs is set."
                 : "A few macOS permissions. One at a time; this window checks each for you.")
                .font(Theme.T.note).foregroundColor(Theme.textLo)
            ForEach(PermissionGuideModel.order, id: \.self) { k in row(k) }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(action: close) { SSLCapStyle.label(model.current == nil ? "DONE" : "CLOSE") }
                    .buttonStyle(SSLCapStyle(lit: false, ready: true))
            }
        }
        .padding(Theme.S.xl)
        .frame(width: 460, height: 440, alignment: .topLeading)
        .environment(\.palette, palette)
    }

    @ViewBuilder private func row(_ k: PermissionKind) -> some View {
        let isCurrent = model.current == k || model.confirming == k
        VStack(alignment: .leading, spacing: Theme.S.s) {
            HStack(spacing: Theme.S.s) {
                Text(icon(k)).font(Theme.T.value).foregroundColor(color(k))
                Text(k.title).font(Theme.T.value).foregroundColor(Theme.textHi)
                Spacer()
                Text(model.rowText(k).uppercased()).captionStyle().foregroundColor(color(k))
            }
            if isCurrent, model.confirming != k {
                Text(k.why).font(Theme.T.note).foregroundColor(Theme.textLo)
                if model.awaitingPrompt {
                    Text("Click Allow in the macOS pop-up.").font(Theme.T.note).foregroundColor(Theme.textHi)
                } else {
                    Text(k.instruction).font(Theme.T.note).foregroundColor(Theme.textHi)
                    HStack(spacing: Theme.S.s) {
                        Button(action: model.openSettings) { SSLCapStyle.label("OPEN SYSTEM SETTINGS") }
                            .buttonStyle(SSLCapStyle(lit: true))
                        if model.offersRelaunch {
                            Button(action: model.relaunch) { SSLCapStyle.label("QUIT & REOPEN BEAT KEY") }
                                .buttonStyle(SSLCapStyle(lit: false, ready: true))
                        }
                    }
                    if model.offersRelaunch {
                        Text("Turned it on and still waiting? macOS may need Beat Key to reopen first.")
                            .font(Theme.T.note).foregroundColor(Theme.textLo)
                    }
                }
                if model.openFailed {
                    Text("Could not open System Settings. Open it yourself: Privacy & Security › \(k.title).")
                        .font(Theme.T.note).foregroundColor(Theme.redText)
                }
                Button(action: model.skip) { SSLCapStyle.label(k.skipLabel.uppercased()) }
                    .buttonStyle(SSLCapStyle(lit: false, ready: true))
            }
        }
        .padding(Theme.S.m)
        .background(RoundedRectangle(cornerRadius: Theme.R.well, style: .continuous)
            .fill(isCurrent ? palette.a5 : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: Theme.R.well, style: .continuous)
            .stroke(isCurrent ? palette.a4 : Theme.textFaint.opacity(0.4), lineWidth: 1))
    }

    private func icon(_ k: PermissionKind) -> String {
        switch model.status[k] {
        case .granted?: return "✓"
        case .skipped?: return "–"
        default: return "○"
        }
    }

    private func color(_ k: PermissionKind) -> Color {
        switch model.status[k] {
        case .granted?: return Theme.greenText
        case .skipped?: return Theme.textLo
        default: return model.current == k ? palette.a1 : Theme.textLo
        }
    }
}
