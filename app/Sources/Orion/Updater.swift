import Combine
import Foundation
import Sparkle
import SwiftUI

/// Beat Key › Check for Updates… and the check Run Doctor ends with. Sparkle's standard UI
/// (SPUStandardUpdaterController); feed, key and the daily automatic check are in Info.plist
/// (SUFeedURL, SUPublicEDKey, SUEnableAutomaticChecks, SUScheduledCheckInterval).
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheck = false
    private let controller: SPUStandardUpdaterController?

    /// No updater when the process is not a bundled app that carries a feed (`swift run`, tests):
    /// Sparkle would only show an error there.
    init(bundle: Bundle = .main) {
        guard AppUpdater.isUpdatable(bundle: bundle) else { controller = nil; return }
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller = c
        c.updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main).assign(to: &$canCheck)
    }

    static func isUpdatable(bundle: Bundle) -> Bool {
        bundle.bundleURL.pathExtension == "app" && bundle.object(forInfoDictionaryKey: "SUFeedURL") is String
    }

    private var checkedAtLaunch = false

    /// Once per launch: Sparkle's silent check (Sparkle's own scheduled check waits out its 24 h
    /// interval, so a Beat Key opened an hour after the last check would not look). Shows a window
    /// only when a newer Beat Key exists; "up to date" and errors stay silent. Same updater as the menu item.
    func checkInBackgroundAtLaunch() {
        guard !checkedAtLaunch else { return }
        checkedAtLaunch = true
        guard let c = controller else {
            AppLog.log("update check: no updater (not a bundled app with a feed); launch check skipped")
            return
        }
        AppLog.log("update check: launch check (Sparkle, in the background)")
        c.updater.checkForUpdatesInBackground()
    }

    /// A user-initiated check: Sparkle shows "up to date", the update offer, or the error.
    func checkForUpdates() {
        DispatchQueue.main.async {
            guard let c = self.controller, c.updater.canCheckForUpdates else { return }
            c.checkForUpdates(nil)
        }
    }
}

/// The menu item; its own view so the disabled state follows the updater.
struct CheckForUpdatesButton: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        Button(Brand.checkForUpdates) { updater.checkForUpdates() }
            .disabled(!updater.canCheck)
    }
}
