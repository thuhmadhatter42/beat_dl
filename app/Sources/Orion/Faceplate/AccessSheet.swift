import AppKit
import SwiftUI

/// The words on the permission sheet, kept out of the view so they can be tested.
enum AccessCopy {
    static let title = "Let \(Brand.name) read your YouTube login"
    static func sentence(_ browser: String) -> String {
        let name = LoginBrowser.named(browser)?.display ?? browser.capitalized
        return "macOS keeps other apps' data private. To use your \(name) login, turn on Full Disk Access for \(Brand.name)."
    }
    static let steps = ["Click Open System Settings", "Turn on \(Brand.name)", "Come back here"]
    static let notListed = "If it's not in the list: click +, choose \(Brand.name) in Applications"
    static let waiting = "WAITING FOR FULL DISK ACCESS"

    static let doneTitle = "All set"
    static func doneSentence(_ browser: String) -> String {
        let name = LoginBrowser.named(browser)?.display ?? browser.capitalized
        return "macOS now lets \(Brand.name) read your \(name) login. \(Brand.name) restarts to use it, then tries the link again."
    }
    static let restarting = "RESTARTING"

    static let openSettings = "OPEN SYSTEM SETTINGS"
    static let showInFinder = "SHOW \(Brand.wordmark) IN FINDER ›"
    static let notNow = "NOT NOW"
    static let restart = "RESTART & TRY AGAIN"

    /// The LCD while the sheet is up.
    static let lcdFirst = "NEEDS PERMISSION"
    static let lcdSecond = "TURN ON FULL DISK ACCESS FOR \(Brand.wordmark)"
}

/// The sheet over the faceplate: dark, amber, SSL caps; not a stock alert.
struct AccessSheet: View {
    @ObservedObject var access: AccessController

    var body: some View {
        let browser = access.phase.browser ?? "brave"
        let done: Bool = { if case .asking = access.phase { return false } else { return true } }()
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(done ? Theme.green : Theme.amber)
                    .frame(width: 7, height: 7)
                    .shadow(color: done ? Theme.greenGlow : Theme.amberGlow, radius: 4)
                Text.cap("PRIVACY & SECURITY · FULL DISK ACCESS")
            }
            Text(done ? AccessCopy.doneTitle : AccessCopy.title)
                .font(Theme.face(19)).foregroundColor(Theme.textHi)
                .padding(.top, 14)
            Text(done ? AccessCopy.doneSentence(browser) : AccessCopy.sentence(browser))
                .font(Theme.face(12, bold: false)).foregroundColor(Theme.textLo)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Group {
                if done { granted } else { steps }
            }
            .padding(.top, 18)

            HStack(spacing: 14) {
                Spacer(minLength: 0)
                Button(action: { access.dismiss() }) { SSLCapStyle.label(AccessCopy.notNow).fixedSize() }
                    .buttonStyle(SSLCapStyle(lit: false))
                    .keyboardShortcut(.cancelAction)
                    .accessibility(label: Text("Not now"))
                if done {
                    Button(action: { access.restart() }) { SSLCapStyle.label(AccessCopy.restart).fixedSize() }
                        .buttonStyle(SSLCapStyle(lit: isGranted))
                        .keyboardShortcut(.defaultAction)
                        .accessibility(label: Text("Restart and try again"))
                } else {
                    Button(action: { FullDiskAccessPane.open() }) { SSLCapStyle.label(AccessCopy.openSettings).fixedSize() }
                        .buttonStyle(SSLCapStyle(lit: true))
                        .keyboardShortcut(.defaultAction)
                        .accessibility(label: Text("Open System Settings"))
                }
            }
            .padding(.top, 22)
        }
        .padding(EdgeInsets(top: 34, leading: 26, bottom: 18, trailing: 26))
        .frame(width: 470)
        .background(Theme.vertical([(Theme.hex(0x1d1d20), 0), (Theme.hex(0x111113), 1)])
            .edgesIgnoringSafeArea(.all))
    }

    private var isGranted: Bool { if case .granted = access.phase { return true } else { return false } }

    /// The three steps in the recessed well, the app icon beside "Turn on Beat Key".
    private var steps: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            StepRow(n: 1, text: AccessCopy.steps[0])
            StepRow(n: 2, text: AccessCopy.steps[1], note: AccessCopy.notListed, icon: true)
            // drag Beat Key from Finder into the list, if it is not there
            Button(action: showInFinder) {
                Text(AccessCopy.showInFinder).font(Theme.face(9)).tracking(1.8)
                    .foregroundColor(Theme.amber).shadow(color: Theme.amberGlow, radius: 2.5)
                    .fixedSize()
            }
            .buttonStyle(PlainButtonStyle())
            .pointingHand()
            .accessibility(label: Text("Show \(Brand.name) in Finder"))
            .padding(.leading, 32 + 28)
            .padding(.top, -4)
            StepRow(n: 3, text: AccessCopy.steps[2])
            HStack(spacing: 10) {
                RunningBar().frame(width: 60)
                Text(AccessCopy.waiting).font(Theme.face(8)).tracking(2.4).foregroundColor(Theme.amber(0.7))
            }
            .padding(.top, 4)
            .accessibility(hidden: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelDeep.clipShape(shape))
        .innerShadow(shape, Color.black.opacity(0.9), blur: 5, y: 2)
        .ring(radius: 5, spread: 1, Theme.black)
    }

    private var granted: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return HStack(spacing: 14) {
            AppIcon(size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("FULL DISK ACCESS ON").font(Theme.face(15)).tracking(0.8)
                    .foregroundColor(Theme.amber).amberGlow()
                Text(isGranted ? "\(Brand.wordmark) WILL REOPEN BY ITSELF" : AccessCopy.restarting)
                    .font(Theme.face(8)).tracking(2.4).foregroundColor(Theme.amber(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelDeep.clipShape(shape))
        .innerShadow(shape, Color.black.opacity(0.9), blur: 5, y: 2)
        .ring(radius: 5, spread: 1, Theme.black)
    }

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

private struct StepRow: View {
    let n: Int
    let text: String
    var note: String? = nil
    var icon = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(Theme.face(11)).foregroundColor(Theme.hex(0x3a2a06))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.vertical([(Theme.hex(0xffe4a6), 0), (Theme.hex(0xf7b32b), 0.5),
                                                          (Theme.hex(0xc07f12), 1)])))
                .shadow(color: Theme.amberGlow, radius: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if icon { AppIcon(size: 20) }
                    Text(text).font(Theme.face(13)).foregroundColor(Theme.textHi)
                }
                if let note = note {
                    Text(note).font(Theme.face(11, bold: false)).foregroundColor(Theme.textLo)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AppIcon: View {
    let size: CGFloat
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
            .resizable().interpolation(.high)
            .frame(width: size, height: size)
            .accessibility(hidden: true)
    }
}
