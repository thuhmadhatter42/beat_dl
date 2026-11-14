import AppKit

/// The one way Beat Key quits and opens itself again. Used by the permission walkthrough's
/// Quit & Reopen and by the install guard's Relaunch Now.
enum AppRelaunch {
    /// Schedules `open -n` of this bundle one second from now, then quits. False = could not
    /// (an unbundled `swift run`, or the helper would not start); the app stays running.
    static func now(why: String) -> Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        // wait for this process to quit, then open the same bundle again
        p.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", bundle.path]
        do { try p.run() } catch {
            AppLog.log("\(why): relaunch could not start: \(error)")
            return false
        }
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
    }
}
